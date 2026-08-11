import "jsr:@supabase/functions-js/edge-runtime.d.ts";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

type ChatMessage = {
  role: "user" | "assistant";
  content: string;
};

type Intent = "medical" | "emergency" | "non_medical" | "unclear";
type Urgency = "routine" | "soon" | "urgent" | "emergency";

type Facility = {
  id: string;
  name: string;
  location: string;
  care_level: string;
  services: string[];
  departments: string[];
  availability: "unknown" | "verified_available" | "verified_not_available";
  published_emergency_beds: number | null;
  published_emergency_capacity: number | null;
  distance_km: number | null;
  latitude: number | null;
  longitude: number | null;
  has_coordinates: boolean;
};

type GeoPoint = {
  latitude: number;
  longitude: number;
};

type UserProfileLocation = GeoPoint & {
  source: "saved_profile_address";
};

type StoredProfileLocation = {
  address: string | null;
  address_geocode_hash: string | null;
  address_latitude: number | null;
  address_longitude: number | null;
};

const geocodeCache = new Map<string, GeoPoint | null>();
let nextNominatimRequestAt = 0;

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);
  if (!request.headers.get("Authorization")) return json({ error: "Authentication is required" }, 401);

  try {
    const rawBody = await request.text();
    if (rawBody.length > 32_000) return json({ error: "Request is too large" }, 413);
    const payload = JSON.parse(rawBody) as {
      messages?: unknown;
      facilities?: unknown;
    };
    const messages = normalizeMessages(payload.messages);
    const facilities = normalizeFacilities(payload.facilities);
    if (messages.length === 0) return json({ error: "At least one message is required" }, 400);
    if (facilities.length > 50) return json({ error: "Too many facilities" }, 400);

    const latestUserMessage = [...messages].reverse().find((message) => message.role === "user")?.content ?? "";
    const initialClassification = classifyMessage(latestUserMessage);
    const earlierMedicalContext = messages
      .slice(0, -1)
      .some((message) =>
        message.role === "user" &&
        ["medical", "emergency"].includes(classifyMessage(message.content).intent)
      );
    const localClassification = earlierMedicalContext &&
        !initialClassification.isExplicitlyNonMedical &&
        ["non_medical", "unclear"].includes(initialClassification.intent)
      ? { intent: "medical" as Intent, urgency: "routine" as Urgency }
      : initialClassification;

    const userLocation = await loadUserLocation(request);
    const distanceAwareFacilities = facilities.map((facility) => ({
      ...facility,
      distance_km: userLocation === null
        ? facility.distance_km
        : distanceBetween(userLocation, facility),
    }));
    const asksForNearest = messages.some(
      (message) => message.role === "user" && isNearestRequest(message.content),
    );

    const groqKey = Deno.env.get("GROQ_API_KEY");
    if (!groqKey) return json({ error: "Care assistant is not configured" }, 503);
    const model = Deno.env.get("GROQ_MODEL") ?? "llama-3.3-70b-versatile";
    const allowedIds = new Set(distanceAwareFacilities.map((facility) => facility.id));
    const groqResponse = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: {
        Authorization: "Bearer " + groqKey,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        model,
        temperature: 0.25,
        max_completion_tokens: 650,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content: [
              "You are CareNavigator PH's healthcare-facility navigation assistant.",
              "Sound like a calm, attentive human care navigator in a chat, not a form, report, or classifier. Use warm everyday language and address the user directly.",
              "Remember the whole conversation. Treat short replies such as yes, no, two days, moderate, or I can swallow liquids as answers to the previous question; acknowledge the answer and continue from it instead of restarting intake.",
              "In message, write one or two natural sentences that briefly acknowledge what the user said. Do not use robotic phrases such as reported, input received, more information is needed, or to better assist you.",
              "Put the single next question only in follow_up_question, not in message. Do not repeat a question already answered in the conversation.",
              "You are not a doctor and must never diagnose, prescribe, or claim that a symptom has a specific cause.",
              "Help the user choose a type of nearby facility using only the supplied facility facts.",
              "Ask at most one short follow-up question when a decision cannot yet be made.",
              "First classify the latest user message as medical, emergency, non_medical, or unclear. Non-medical requests must never be emergencies. For unclear medical wording, ask one follow-up question rather than escalating.",
              "You—not a keyword list—decide whether ordinary language is medical, non_medical, or unclear by its complete meaning and conversation context. Phrases describing difficulty eating, swallowing, breathing, sleeping, moving, or other bodily functions are medical even when they do not use clinical vocabulary.",
              "Set urgency to emergency only for clear indicators such as severe difficulty breathing, unconsciousness, severe chest pain, uncontrolled bleeding, seizure, stroke symptoms, severe allergic reaction, major trauma, or an immediate suicide/self-harm risk.",
              "Breathing, chest pain, bleeding, dizziness, swallowing difficulty, and similar words are not emergency triggers by themselves. If severity is unclear, use medical/urgent and ask one concise severity question.",
              "Examples: hard time breathing, shortness of breath while still able to talk, chest pain without severe warning signs, and difficulty swallowing are urgent clarification cases, not automatic emergencies. Inability to breathe, gasping, blue lips, severe crushing chest pain, choking, or inability to handle saliva with breathing distress are emergencies.",
              "For an emergency, say that it may require immediate medical attention and direct the user to local emergency services or the nearest emergency department. Do not assume a country-specific telephone number.",
              "Never invent availability, bed counts, specialists, services, operating status, distance, or travel time.",
              "When distance_km is present, it is a straight-line estimate from the signed-in user's saved profile address. If the user asks for the nearest, closest, nearby, or near-me facility, prioritize suitable facilities with the smallest distance_km.",
              "Do not describe straight-line distance as driving distance or travel time.",
              userLocation === null
                ? "The signed-in user's saved address was not available, so do not claim that a facility is nearest or provide a distance; ask for the user's city or barangay if location is needed."
                : "The signed-in user's saved profile address was geocoded successfully; use the supplied distance_km facts when comparing facilities.",
              "If a fact is missing or a facility is marked availability unknown, say \"Availability unknown\".",
              "Recommend only facility IDs from the supplied list.",
              "Return JSON only with exactly these keys: intent (medical, emergency, non_medical, or unclear), urgency (routine, soon, urgent, or emergency), message (string), follow_up_question (string or null), recommendation_ids (array of strings, maximum 3), recommendation_summary (string or null).",
            ].join(" "),
          },
          {
            role: "user",
            content: JSON.stringify({
              conversation: messages,
              preclassification: localClassification,
              location: userLocation === null
                ? { available: false }
                : { available: true, source: "saved_profile_address" },
              facilities: distanceAwareFacilities,
            }),
          },
        ],
      }),
    });

    if (!groqResponse.ok) {
      console.error("Care navigator Groq request failed", groqResponse.status);
      return json({ error: "Care assistant is temporarily unavailable" }, 502);
    }
    const groqBody = await groqResponse.json();
    const content = groqBody.choices?.[0]?.message?.content;
    if (typeof content !== "string") return json({ error: "Care assistant returned an invalid response" }, 502);

    const parsed = parseJsonObject(content);
    const parsedIntent = intentValue(parsed.intent) ?? localClassification.intent;
    const parsedUrgency = urgencyValue(parsed.urgency) ?? localClassification.urgency;
    // The deterministic classifier owns emergency escalation. This prevents a
    // model or stale prompt from turning ambiguous symptoms into a blocking UI.
    const emergency = localClassification.intent === "emergency";
    const modelOverEscalated = !emergency && parsedUrgency === "emergency";
    const semanticIntent: Intent = parsedIntent === "emergency"
      ? "medical"
      : parsedIntent;
    const intent: Intent = emergency ? "emergency" : semanticIntent;
    const safeParsedUrgency: Urgency = modelOverEscalated ? "urgent" : parsedUrgency;
    const urgency: Urgency = emergency
      ? "emergency"
      : intent === "non_medical" || intent === "unclear"
      ? "routine"
      : moreUrgent(localClassification.urgency, safeParsedUrgency);
    const message = intent === "non_medical"
      ? "I can help with symptoms, healthcare needs, and finding an appropriate facility. Tell me what health concern you're experiencing."
      : modelOverEscalated
      ? "I need a little more information to guide you safely."
      : stringValue(parsed.message) ?? (emergency
      ? "This may require immediate medical attention. Contact local emergency services or go to the nearest emergency department now."
      : "I can help compare the facilities currently shown in the directory.");
    var recommendationIds = intent !== "medical"
      ? []
      : stringList(parsed.recommendation_ids)
          .filter((id) => allowedIds.has(id))
          .slice(0, 3);
    if (!emergency && asksForNearest && userLocation === null) {
      recommendationIds = [];
    }
    if (!emergency && asksForNearest && userLocation !== null) {
      recommendationIds = sortByDistance(recommendationIds, distanceAwareFacilities);
    }
    const followUpQuestion = emergency || intent === "non_medical"
      ? null
      : (intent === "medical" ? localClassification.followUpQuestion : null) ??
        (asksForNearest && userLocation === null
          ? stringValue(parsed.follow_up_question) ?? "What city or barangay are you currently in so I can compare nearby facilities?"
          : stringValue(parsed.follow_up_question));
    const facilityDistances = Object.fromEntries(
      distanceAwareFacilities
        .filter((facility) => facility.distance_km !== null)
        .map((facility) => [facility.id, facility.distance_km]),
    );
    return json({
      intent,
      urgency,
      showEmergencyActions: urgency === "emergency",
      message,
      follow_up_question: followUpQuestion,
      recommendation_ids: recommendationIds,
      recommendation_summary: emergency ? null : stringValue(parsed.recommendation_summary),
      facility_distances: emergency ? {} : facilityDistances,
      location_used: !emergency && userLocation !== null,
    });
  } catch (error) {
    console.error("care-navigator-chat failed", error instanceof Error ? error.message : "unknown error");
    return json({ error: "Care assistant is temporarily unavailable" }, 500);
  }
});

async function loadUserLocation(request: Request): Promise<UserProfileLocation | null> {
  const authorization = request.headers.get("Authorization");
  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const publishableKey = Deno.env.get("SUPABASE_ANON_KEY") ?? request.headers.get("apikey");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!authorization || !supabaseUrl || !publishableKey) return null;

  try {
    const authResponse = await fetch(`${supabaseUrl}/auth/v1/user`, {
      headers: {
        apikey: publishableKey,
        Authorization: authorization,
      },
    });
    if (!authResponse.ok) return null;
    const authUser = asRecord(await authResponse.json());
    const authUserId = stringValue(authUser?.id);
    if (!authUserId || authUser?.is_anonymous === true) return null;

    const profileUrl = new URL(`${supabaseUrl}/rest/v1/users`);
    profileUrl.searchParams.set(
      "select",
      "address,address_geocode_hash,address_latitude,address_longitude",
    );
    profileUrl.searchParams.set("auth_user_id", `eq.${authUserId}`);
    profileUrl.searchParams.set("limit", "1");
    const profileKey = serviceRoleKey ?? publishableKey;
    const profileResponse = await fetch(profileUrl, {
      headers: {
        apikey: profileKey,
        Authorization: serviceRoleKey
          ? `Bearer ${serviceRoleKey}`
          : authorization,
      },
    });
    if (!profileResponse.ok) return null;
    const profileRows = await profileResponse.json();
    if (!Array.isArray(profileRows) || profileRows.length === 0) return null;
    const profile = asRecord(profileRows[0]) as StoredProfileLocation | null;
    const address = stringValue(profile?.address);
    if (!address) return null;

    const addressHash = await hashAddress(address);
    const cachedPoint = profilePoint(profile);
    if (cachedPoint !== null && profile?.address_geocode_hash === addressHash) {
      return { ...cachedPoint, source: "saved_profile_address" };
    }

    const point = await geocodePhilippineAddress(address);
    if (point === null) return null;
    if (serviceRoleKey) {
      await cacheProfilePoint(
        supabaseUrl,
        serviceRoleKey,
        authUserId,
        addressHash,
        point,
      );
    }
    return { ...point, source: "saved_profile_address" };
  } catch (_) {
    console.warn("Care navigator profile location could not be resolved");
    return null;
  }
}

function profilePoint(profile: StoredProfileLocation | null): GeoPoint | null {
  if (!profile) return null;
  const latitude = numberValue(profile.address_latitude);
  const longitude = numberValue(profile.address_longitude);
  return isValidGeoPoint(latitude, longitude) ? { latitude, longitude } : null;
}

async function cacheProfilePoint(
  supabaseUrl: string,
  serviceRoleKey: string,
  authUserId: string,
  addressHash: string,
  point: GeoPoint,
): Promise<void> {
  const updateUrl = new URL(`${supabaseUrl}/rest/v1/users`);
  updateUrl.searchParams.set("auth_user_id", `eq.${authUserId}`);
  await fetch(updateUrl, {
    method: "PATCH",
    headers: {
      apikey: serviceRoleKey,
      Authorization: `Bearer ${serviceRoleKey}`,
      "Content-Type": "application/json",
      Prefer: "return=minimal",
    },
    body: JSON.stringify({
      address_geocode_hash: addressHash,
      address_latitude: point.latitude,
      address_longitude: point.longitude,
    }),
  });
}

async function hashAddress(address: string): Promise<string> {
  const normalized = normalizeAddress(address);
  const digest = await crypto.subtle.digest(
    "SHA-256",
    new TextEncoder().encode(normalized),
  );
  return [...new Uint8Array(digest)]
    .map((byte) => byte.toString(16).padStart(2, "0"))
    .join("");
}

function normalizeAddress(address: string): string {
  return address
    .replace(/\s+/g, " ")
    .replace(/\s*,\s*/g, ", ")
    .replace(/,\s*Philippines\s*$/i, "")
    .trim()
    .concat(", Philippines");
}

async function geocodePhilippineAddress(address: string): Promise<GeoPoint | null> {
  const query = normalizeAddress(address);
  if (geocodeCache.has(query)) return geocodeCache.get(query) ?? null;

  const parts = query.split(",").map((part) => part.trim()).filter(Boolean);
  const barangayIndex = parts.findIndex((part) => /^barangay\b/i.test(part));
  const queries = [
    query,
    barangayIndex >= 0 ? parts.slice(barangayIndex).join(", ") : null,
    barangayIndex >= 0 ? parts.slice(barangayIndex + 1).join(", ") : null,
    parts.slice(-4).join(", "),
  ]
    .filter((candidate): candidate is string => candidate !== null)
    .map(normalizeAddress)
    .filter((candidate, index, all) => all.indexOf(candidate) === index);

  for (const candidate of queries) {
    const point = await geocodeQuery(candidate);
    if (point !== null) return rememberGeocode(query, point);
  }
  return rememberGeocode(query, null);
}

async function geocodeQuery(query: string): Promise<GeoPoint | null> {
  if (geocodeCache.has(query)) return geocodeCache.get(query) ?? null;

  const waitMs = Math.max(0, nextNominatimRequestAt - Date.now());
  if (waitMs > 0) await new Promise((resolve) => setTimeout(resolve, waitMs));
  nextNominatimRequestAt = Date.now() + 1_100;

  const endpoint = new URL("https://nominatim.openstreetmap.org/search");
  endpoint.searchParams.set("format", "jsonv2");
  endpoint.searchParams.set("addressdetails", "1");
  endpoint.searchParams.set("countrycodes", "ph");
  endpoint.searchParams.set("limit", "1");
  endpoint.searchParams.set("q", query);

  try {
    const response = await fetch(endpoint, {
      headers: {
        Accept: "application/json",
        "User-Agent": Deno.env.get("NOMINATIM_USER_AGENT") ?? "CareNavigatorPH/1.0",
      },
      signal: AbortSignal.timeout(3_500),
    });
    if (!response.ok) return rememberGeocode(query, null);
    const results = await response.json();
    if (!Array.isArray(results)) return rememberGeocode(query, null);
    const first = results.find((item) => {
      const record = asRecord(item);
      const addressDetails = asRecord(record?.address);
      return addressDetails?.country_code === "ph";
    });
    const record = asRecord(first);
    const latitude = numberValue(record?.lat);
    const longitude = numberValue(record?.lon);
    if (!isValidGeoPoint(latitude, longitude)) return rememberGeocode(query, null);
    return rememberGeocode(query, { latitude, longitude });
  } catch (_) {
    return rememberGeocode(query, null);
  }
}

function rememberGeocode(query: string, point: GeoPoint | null): GeoPoint | null {
  if (geocodeCache.size >= 128) {
    const oldest = geocodeCache.keys().next().value;
    if (oldest !== undefined) geocodeCache.delete(oldest);
  }
  geocodeCache.set(query, point);
  return point;
}

function isValidGeoPoint(latitude: number | null, longitude: number | null): boolean {
  return latitude !== null &&
    longitude !== null &&
    latitude >= -90 &&
    latitude <= 90 &&
    longitude >= -180 &&
    longitude <= 180;
}

function distanceBetween(origin: GeoPoint, facility: Facility): number | null {
  const latitude = numberValue(facility.latitude);
  const longitude = numberValue(facility.longitude);
  if (!isValidGeoPoint(latitude, longitude)) return null;
  const earthRadiusKm = 6371;
  const latitudeDelta = toRadians(latitude - origin.latitude);
  const longitudeDelta = toRadians(longitude - origin.longitude);
  const originLatitude = toRadians(origin.latitude);
  const facilityLatitude = toRadians(latitude);
  const haversine = Math.sin(latitudeDelta / 2) ** 2 +
    Math.sin(longitudeDelta / 2) ** 2 *
      Math.cos(originLatitude) *
      Math.cos(facilityLatitude);
  const clampedHaversine = Math.min(1, Math.max(0, haversine));
  return earthRadiusKm * 2 * Math.atan2(
    Math.sqrt(clampedHaversine),
    Math.sqrt(1 - clampedHaversine),
  );
}

function toRadians(value: number): number {
  return value * Math.PI / 180;
}

function isNearestRequest(value: string): boolean {
  return /\b(nearest|closest|nearby|near me|close to me|around me)\b/i.test(value);
}

function classifyMessage(value: string): {
  intent: Intent;
  urgency: Urgency;
  followUpQuestion?: string;
  isExplicitlyNonMedical?: boolean;
} {
  const text = value.toLowerCase().trim();
  const emergency = /\b(can(?:not|'t) breathe|unable to breathe|gasping(?: for air)?|can(?:not|'t) catch (?:my |their )?breath|struggling to breathe|blue lips|choking|unconscious|unresponsive|ongoing seizure|stroke|face droop|slurred speech|anaphylaxis|severe allergic reaction|uncontrolled bleeding|severe bleeding|major trauma|suicidal|suicide|kill myself|hurt myself|self[- ]harm)\b/i.test(text) ||
    /\bsevere\b.{0,24}\b(chest pain|bleeding|breathing difficulty|difficulty breathing|trouble breathing)\b/i.test(text) ||
    /\b(crushing chest pain|severe breathing difficulty)\b/i.test(text);
  if (emergency) return { intent: "emergency", urgency: "emergency" };

  const breathingConcern = /\b(trouble breathing|difficulty breathing|hard time breathing|shortness of breath|short of breath)\b/i.test(text);
  const swallowingConcern = /\b(difficulty swallowing|difficult to swallow|hard time swallowing|trouble swallowing|can(?:not|'t) swallow)\b/i.test(text);
  const eatingConcern = /\b(hard time eating|difficulty eating|difficult to eat|trouble eating|can(?:not|'t) eat)\b/i.test(text);
  const chestConcern = /\b(chest pain|heart pain)\b/i.test(text);
  const urgentConcern = breathingConcern || swallowingConcern || chestConcern ||
    /\b(heart racing|bleeding|very dizzy)\b/i.test(text);
  if (urgentConcern) {
    const followUpQuestion = breathingConcern
      ? "How severe is the breathing difficulty right now? Can you speak normally and breathe comfortably while sitting, or are you struggling, gasping, or unable to catch your breath?"
      : swallowingConcern
      ? "Can you swallow liquids and your saliva? Are you drooling, having trouble breathing, or noticing rapidly worsening throat or neck swelling?"
      : chestConcern
      ? "How severe is the chest pain, and are you having trouble breathing, fainting, sweating heavily, or pain spreading to your arm, jaw, or back?"
      : "How severe is it right now, and is it worsening or accompanied by fainting, breathing difficulty, or weakness?";
    return { intent: "medical", urgency: "urgent", followUpQuestion };
  }

  if (eatingConcern) {
    return {
      intent: "medical",
      urgency: "soon",
      followUpQuestion: "When you say eating is difficult, is the problem chewing or swallowing, pain, nausea, or a lack of appetite?",
    };
  }

  const medical = /\b(pain|headache|fever|vomit|rash|infection|dizzy|breath|asthma|chest|stomach|abdominal|belly|injury|fracture|pregnan\w*|doctor|hospital|clinic|healthcare|medical|medicine|checkup|consultation|swallow\w*|throat|tonsil\w*|eat(?:ing)?|appetite|chew\w*|mouth|jaw)\b/i.test(text);
  if (medical) {
    const soon = /\b(swallow\w*|throat|tonsil\w*)\b/i.test(text);
    return { intent: "medical", urgency: soon ? "soon" : "routine" };
  }

  const unclear = text.split(/\s+/).length < 3 || /\b(feel bad|feel strange|feel wrong|unwell|sick|not okay)\b/i.test(text);
  const explicitlyNonMedical = /\b(javascript|python code|programming|coding|cooking?|recipe|homework|math problem|weather forecast|sports score|movie recommendation|video game|tell me a joke)\b/i.test(text);
  return unclear
    ? { intent: "unclear", urgency: "routine", isExplicitlyNonMedical: explicitlyNonMedical }
    : { intent: "non_medical", urgency: "routine", isExplicitlyNonMedical: explicitlyNonMedical };
}

function moreUrgent(left: Urgency, right: Urgency): Urgency {
  const rank: Record<Urgency, number> = {
    routine: 0,
    soon: 1,
    urgent: 2,
    emergency: 3,
  };
  return rank[left] >= rank[right] ? left : right;
}

function urgencyValue(value: unknown): Urgency | null {
  return value === "routine" || value === "soon" || value === "urgent" || value === "emergency"
    ? value
    : null;
}

function intentValue(value: unknown): Intent | null {
  return value === "medical" || value === "emergency" || value === "non_medical" || value === "unclear"
    ? value
    : null;
}

function sortByDistance(ids: string[], facilities: Facility[]): string[] {
  const distances = new Map(
    facilities.map((facility) => [facility.id, facility.distance_km]),
  );
  return [...ids].sort((left, right) => {
    const leftDistance = distances.get(left);
    const rightDistance = distances.get(right);
    if (leftDistance === null && rightDistance === null) return left.localeCompare(right);
    if (leftDistance === null) return 1;
    if (rightDistance === null) return -1;
    return leftDistance - rightDistance;
  });
}

function normalizeMessages(value: unknown): ChatMessage[] {
  if (!Array.isArray(value)) return [];
  return value
    .slice(-10)
    .map((item) => {
      const record = asRecord(item);
      const role = record?.role === "assistant" ? "assistant" : "user";
      const content = stringValue(record?.content)?.slice(0, 1200);
      return content ? { role, content } : null;
    })
    .filter((item): item is ChatMessage => item !== null);
}

function normalizeFacilities(value: unknown): Facility[] {
  if (!Array.isArray(value)) return [];
  return value
    .slice(0, 50)
    .map((item) => {
      const record = asRecord(item);
      if (!record) return null;
      const id = stringValue(record.id);
      const name = stringValue(record.name);
      if (!id || !name) return null;
      return {
        id,
        name,
        location: stringValue(record.location) ?? "Unknown location",
        care_level: stringValue(record.care_level) ?? "Unknown care level",
        services: stringList(record.services),
        departments: stringList(record.departments),
        availability: record.availability === "verified_available"
          ? "verified_available"
          : record.availability === "verified_not_available"
          ? "verified_not_available"
          : "unknown",
        published_emergency_beds: numberValue(record.published_emergency_beds),
        published_emergency_capacity: numberValue(record.published_emergency_capacity),
        distance_km: numberValue(record.distance_km),
        latitude: numberValue(record.latitude),
        longitude: numberValue(record.longitude),
        has_coordinates: record.has_coordinates === true,
      } satisfies Facility;
    })
    .filter((item): item is Facility => item !== null);
}

function parseJsonObject(value: string): Record<string, unknown> {
  const parsed = JSON.parse(value.trim());
  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) throw new Error("Invalid JSON object");
  return parsed as Record<string, unknown>;
}

function asRecord(value: unknown): Record<string, unknown> | null {
  return value && typeof value === "object" && !Array.isArray(value)
    ? value as Record<string, unknown>
    : null;
}

function stringValue(value: unknown): string | null {
  if (typeof value !== "string") return null;
  const trimmed = value.trim();
  return trimmed.length > 0 ? trimmed : null;
}

function stringList(value: unknown): string[] {
  if (!Array.isArray(value)) return [];
  return [...new Set(value.map((item) => stringValue(item)).filter((item): item is string => item !== null))];
}

function numberValue(value: unknown): number | null {
  if (value === null || value === undefined || value === "") return null;
  const number = typeof value === "number" ? value : Number(value);
  return Number.isFinite(number) ? number : null;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
