import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers": "authorization, x-client-info, apikey, content-type",
};

const emergencyPatterns = [
  /severe (difficulty|trouble) breathing/i,
  /chest pain/i,
  /loss of consciousness|unconscious/i,
  /severe bleeding|heavy bleeding/i,
  /face droop|slurred speech|suspected stroke/i,
  /seizure/i,
  /severe allergic reaction|anaphylaxis/i,
];

type AssessmentRequest = {
  symptoms: string;
  symptom_duration?: string;
  age?: number;
  existing_conditions?: string[];
  allergies?: string[];
  current_medications?: string[];
  guest_request_id?: string;
  patient_id?: string;
};

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  try {
    const authHeader = request.headers.get("Authorization");
    if (!authHeader) return json({ error: "Authentication is required" }, 401);

    const supabaseUrl = mustEnv("SUPABASE_URL");
    const anonKey = mustEnv("SUPABASE_ANON_KEY");
    const client = createClient(supabaseUrl, anonKey, {
      global: { headers: { Authorization: authHeader } },
    });
    const { data: { user }, error: userError } = await client.auth.getUser();
    if (userError || !user) return json({ error: "Invalid session" }, 401);

    const payload = await request.json() as AssessmentRequest;
    if (!payload.symptoms?.trim() || payload.symptoms.trim().length > 4000) {
      return json({ error: "Symptoms must contain between 1 and 4,000 characters" }, 400);
    }
    if (payload.patient_id && payload.guest_request_id) {
      return json({ error: "Choose either a patient or guest request context" }, 400);
    }
    if (payload.patient_id) {
      const { data, error } = await client.from("patients")
        .select("id").eq("id", payload.patient_id).maybeSingle();
      if (error || !data) {
        return json({ error: "You cannot assess symptoms for this patient" }, 403);
      }
    }
    if (payload.guest_request_id) {
      const { data, error } = await client.from("guest_consultation_requests")
        .select("id").eq("id", payload.guest_request_id).maybeSingle();
      if (error || !data) {
        return json({ error: "You cannot assess symptoms for this consultation request" }, 403);
      }
    }

    if (emergencyPatterns.some((pattern) => pattern.test(payload.symptoms))) {
      const emergency = {
        possible_conditions: [],
        urgency_level: "emergency",
        warning_signs: ["The description contains a potentially life-threatening warning sign."],
        recommended_department: "Emergency Department",
        recommended_action: "Call 911 or go to the nearest emergency room now. Do not wait for an online consultation.",
        hospital_requirements: ["Open emergency room"],
        disclaimer: "This safety warning is not a diagnosis.",
      };
      await storeAssessment(client, user.id, payload, emergency, "safety-rule");
      return json(emergency);
    }

    const groqKey = Deno.env.get("GROQ_API_KEY");
    if (!groqKey) return json({ error: "AI assessment is not configured" }, 503);

    const model = Deno.env.get("GROQ_MODEL") ?? "llama-3.3-70b-versatile";
    const groqResponse = await fetch("https://api.groq.com/openai/v1/chat/completions", {
      method: "POST",
      headers: { Authorization: `Bearer ${groqKey}`, "Content-Type": "application/json" },
      body: JSON.stringify({
        model,
        temperature: 0.15,
        response_format: { type: "json_object" },
        messages: [
          {
            role: "system",
            content: `You are the preliminary health navigation assistant for CareNavigator PH. Never diagnose. Return only JSON with possible_conditions (array of {name, rationale}), urgency_level (self_care|routine|urgent|emergency), warning_signs (string array), recommended_department (string), recommended_action (string), hospital_requirements (string array), and disclaimer (string). If emergency warning signs are plausible, set emergency and direct the user to call 911 or immediately visit an ER. Do not prescribe medication.`,
          },
          { role: "user", content: JSON.stringify(payload) },
        ],
      }),
    });
    if (!groqResponse.ok) {
      const detail = await groqResponse.text();
      console.error("Groq request failed", groqResponse.status, detail.slice(0, 500));
      return json({ error: "AI assessment is temporarily unavailable" }, 502);
    }

    const groqBody = await groqResponse.json();
    const content = groqBody.choices?.[0]?.message?.content;
    if (typeof content !== "string") return json({ error: "AI returned an invalid response" }, 502);
    const assessment = JSON.parse(content);
    validateAssessment(assessment);
    await storeAssessment(client, user.id, payload, assessment, model, groqBody);
    return json(assessment);
  } catch (error) {
    console.error("analyze-symptoms", error);
    return json({ error: error instanceof Error ? error.message : "Unexpected server error" }, 500);
  }
});

async function storeAssessment(
  client: ReturnType<typeof createClient>,
  userId: string,
  payload: AssessmentRequest,
  assessment: Record<string, unknown>,
  model: string,
  rawResponse: Record<string, unknown> = {},
) {
  const { error } = await client.from("ai_assessments").insert({
    user_id: userId,
    patient_id: payload.patient_id ?? null,
    guest_request_id: payload.guest_request_id ?? null,
    symptoms: payload.symptoms,
    symptom_duration: payload.symptom_duration ?? null,
    possible_conditions: assessment.possible_conditions ?? [],
    urgency_level: assessment.urgency_level,
    warning_signs: assessment.warning_signs ?? [],
    recommended_action: assessment.recommended_action,
    recommended_department: assessment.recommended_department ?? null,
    groq_response: rawResponse,
    disclaimer: assessment.disclaimer,
    model_name: model,
  });
  if (error) throw new Error(`Could not save assessment: ${error.message}`);
}

function validateAssessment(value: Record<string, unknown>) {
  const urgency = value.urgency_level;
  if (!["self_care", "routine", "urgent", "emergency"].includes(String(urgency))) {
    throw new Error("AI returned an invalid urgency level");
  }
  if (typeof value.recommended_action !== "string" || typeof value.disclaimer !== "string") {
    throw new Error("AI returned an incomplete assessment");
  }
}

function mustEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...corsHeaders, "Content-Type": "application/json" },
  });
}
