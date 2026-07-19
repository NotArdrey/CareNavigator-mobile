import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};
const uuidPattern =
  /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const allowedBuckets = new Set(["laboratory-results", "scanned-medical-results"]);
const analyzableStatuses = new Set([
  "uploaded",
  "ocr_processing",
  "ai_analysis_pending",
  "pending_doctor_review",
]);
const imageMimeTypes = new Set(["image/jpeg", "image/png", "image/webp"]);
const maxFileBytes = 20 * 1024 * 1024;

type Analysis = {
  summary: string;
  possible_findings: Array<{
    finding: string;
    evidence: string;
    confidence: "low" | "moderate" | "high";
  }>;
  abnormal_indicators: string[];
  recommended_follow_up: string[];
  limitations: string[];
  disclaimer: string;
};

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
  }
}

class PdfTextRequiredError extends HttpError {
  constructor() {
    super(422, "PDF text extraction is required before AI analysis");
  }
}

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") {
    return new Response("ok", { headers: corsHeaders });
  }
  if (request.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  let admin: SupabaseClient | null = null;
  let resultId: string | null = null;
  let doctorId: string | null = null;
  let actorAuthUserId: string | null = null;
  let hospitalId: string | null = null;
  let processingJobId: string | null = null;
  let processingStarted = false;

  try {
    admin = serviceClient();
    const actor = await requireAssignedDoctor(request, admin);
    doctorId = actor.doctorId;
    actorAuthUserId = actor.authUserId;
    hospitalId = actor.hospitalId;
    const body = await readBody(request);
    resultId = requiredUuid(body, "laboratory_result_id");

    const { data: result, error: resultError } = await admin
      .from("laboratory_results")
      .select(
        "id, patient_id, doctor_id, hospital_id, test_name, extracted_text, file_path, verification_status, updated_at, ocr_provider",
      )
      .eq("id", resultId)
      .maybeSingle();
    if (resultError) throw resultError;
    if (!result) throw new HttpError(404, "Laboratory result was not found");
    if (result.doctor_id !== actor.doctorId || result.hospital_id !== actor.hospitalId) {
      throw new HttpError(403, "Only the assigned doctor can analyze this result");
    }
    if (!analyzableStatuses.has(result.verification_status)) {
      throw new HttpError(
        409,
        "A confirmed, rejected, or saved result cannot be sent back for preliminary analysis",
      );
    }

    const { data: locked, error: lockError } = await admin
      .from("laboratory_results")
      .update({ verification_status: "ai_analysis_pending" })
      .eq("id", result.id)
      .eq("doctor_id", actor.doctorId)
      .eq("updated_at", result.updated_at)
      .select("id")
      .maybeSingle();
    if (lockError) throw lockError;
    if (!locked) {
      throw new HttpError(409, "The laboratory result changed; refresh and try again");
    }
    processingStarted = true;

    processingJobId = await beginProcessingJob(admin, result, actor.doctorId);

    const storedFile = await downloadResultFile(
      admin,
      result.file_path,
      result.patient_id,
    );
    const input = await prepareGroqInput(
      storedFile.blob,
      storedFile.mimeType,
      result.extracted_text,
      result.test_name,
    );
    const groq = await analyzeWithGroq(input);
    validateAnalysis(groq.analysis);

    await completeProcessingJob(admin, processingJobId, groq.model);

    const { data: saved, error: saveError } = await admin
      .from("laboratory_results")
      .update({
        ai_summary: groq.analysis.summary,
        ai_possible_findings: groq.analysis,
        ai_analyzed_at: new Date().toISOString(),
        verification_status: "pending_doctor_review",
      })
      .eq("id", result.id)
      .eq("doctor_id", actor.doctorId)
      .eq("verification_status", "ai_analysis_pending")
      .select("id")
      .maybeSingle();
    if (saveError) throw saveError;
    if (!saved) throw new Error("The result status changed before analysis was saved");

    await logSecurityEvent(admin, actorAuthUserId, "medical_result_analysis", true, "info", {
      laboratory_result_id: result.id,
      processing_job_id: processingJobId,
      doctor_id: doctorId,
      hospital_id: hospitalId,
      outcome: "pending_doctor_review",
      model: groq.model,
    }, request);

    return json({
      laboratory_result_id: result.id,
      status: "pending_doctor_review",
      analysis: groq.analysis,
      model: groq.model,
    });
  } catch (error) {
    console.error("analyze-medical-result", error);
    if (processingStarted && admin && resultId && doctorId) {
      await recordProcessingFailure(admin, resultId, doctorId, processingJobId, error);
    }
    if (admin) {
      await logSecurityEvent(
        admin,
        actorAuthUserId,
        "medical_result_analysis",
        false,
        error instanceof HttpError && error.status < 500 ? "warning" : "critical",
        {
          laboratory_result_id: resultId,
          processing_job_id: processingJobId,
          doctor_id: doctorId,
          hospital_id: hospitalId,
          failure: error instanceof HttpError ? `http_${error.status}` : "unexpected_error",
        },
        request,
      );
    }
    if (error instanceof HttpError) {
      return json({ error: error.message }, error.status);
    }
    return json({ error: "Preliminary result analysis is temporarily unavailable" }, 502);
  }
});

async function requireAssignedDoctor(request: Request, admin: SupabaseClient) {
  const token = bearerToken(request);
  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData.user) {
    throw new HttpError(401, "Authentication session is invalid");
  }

  const { data: appUser, error: appUserError } = await admin
    .from("users")
    .select("id, hospital_id, account_status, roles!inner(role_name)")
    .eq("auth_user_id", authData.user.id)
    .maybeSingle();
  if (appUserError) throw appUserError;
  if (
    !appUser || appUser.account_status !== "active" ||
    relationName(appUser.roles) !== "doctor" || !appUser.hospital_id
  ) {
    throw new HttpError(403, "An active doctor account is required");
  }

  const { data: doctor, error: doctorError } = await admin
    .from("doctors")
    .select("id, hospital_id")
    .eq("user_id", appUser.id)
    .maybeSingle();
  if (doctorError) throw doctorError;
  if (!doctor || doctor.hospital_id !== appUser.hospital_id) {
    throw new HttpError(403, "The doctor profile is not assigned to this hospital");
  }
  return {
    doctorId: doctor.id as string,
    hospitalId: doctor.hospital_id as string,
    authUserId: authData.user.id,
  };
}

async function beginProcessingJob(
  admin: SupabaseClient,
  result: Record<string, unknown>,
  doctorId: string,
) {
  const activeStatuses = [
    "queued",
    "ocr_processing",
    "ai_analysis_pending",
    "pending_doctor_review",
  ];
  const { data: active, error: activeError } = await admin
    .from("document_processing_jobs")
    .select("id, attempt_count")
    .eq("laboratory_result_id", result.id)
    .in("status", activeStatuses)
    .order("created_at", { ascending: false })
    .limit(1)
    .maybeSingle();
  if (activeError) throw activeError;

  const startedAt = new Date().toISOString();
  if (active) {
    const { error } = await admin
      .from("document_processing_jobs")
      .update({
        requested_by: doctorId,
        status: "ai_analysis_pending",
        ocr_provider: result.ocr_provider ?? null,
        ai_provider: "groq",
        attempt_count: Number(active.attempt_count ?? 0) + 1,
        last_error: null,
        started_at: startedAt,
        completed_at: null,
      })
      .eq("id", active.id);
    if (error) throw error;
    return active.id as string;
  }

  const { data: created, error: createError } = await admin
    .from("document_processing_jobs")
    .insert({
      laboratory_result_id: result.id,
      requested_by: doctorId,
      status: "ai_analysis_pending",
      ocr_provider: result.ocr_provider ?? null,
      ai_provider: "groq",
      attempt_count: 1,
      started_at: startedAt,
    })
    .select("id")
    .single();
  if (createError) {
    if (createError.code === "23505") {
      const { data: concurrent, error: concurrentError } = await admin
        .from("document_processing_jobs")
        .select("id")
        .eq("laboratory_result_id", result.id)
        .in("status", activeStatuses)
        .limit(1)
        .single();
      if (concurrentError) throw concurrentError;
      return concurrent.id as string;
    }
    throw createError;
  }
  return created.id as string;
}

async function completeProcessingJob(
  admin: SupabaseClient,
  jobId: string,
  model: string,
) {
  const { data, error } = await admin
    .from("document_processing_jobs")
    .update({
      status: "pending_doctor_review",
      model_name: model,
      last_error: null,
      completed_at: new Date().toISOString(),
    })
    .eq("id", jobId)
    .eq("status", "ai_analysis_pending")
    .select("id")
    .maybeSingle();
  if (error) throw error;
  if (!data) throw new Error("The document processing job changed before completion");
}

async function downloadResultFile(
  admin: SupabaseClient,
  rawFilePath: string,
  patientId: string,
) {
  const candidates = storageCandidates(rawFilePath);
  for (const candidate of candidates) {
    if (!candidate.path.startsWith(`${patientId}/`)) {
      throw new HttpError(403, "The stored result path does not belong to this patient");
    }
    const { data, error } = await admin.storage
      .from(candidate.bucket)
      .download(candidate.path);
    if (error || !data) continue;
    if (data.size > maxFileBytes) {
      throw new HttpError(413, "The medical result exceeds the 20 MB analysis limit");
    }
    return {
      blob: data,
      mimeType: normalizedMimeType(data.type, candidate.path),
    };
  }
  throw new HttpError(404, "The private medical result file could not be downloaded");
}

function storageCandidates(rawFilePath: string) {
  const clean = rawFilePath.trim().replace(/^\/+/, "");
  if (!clean || clean.includes("..")) {
    throw new HttpError(400, "The stored result path is invalid");
  }
  const [first, ...rest] = clean.split("/");
  if (allowedBuckets.has(first)) {
    const path = rest.join("/");
    if (!path) throw new HttpError(400, "The stored result path is invalid");
    return [{ bucket: first, path }];
  }
  return [
    { bucket: "laboratory-results", path: clean },
    { bucket: "scanned-medical-results", path: clean },
  ];
}

function normalizedMimeType(blobType: string, path: string) {
  const type = blobType.toLowerCase().split(";")[0].trim();
  if (type && type !== "application/octet-stream") return type;
  const extension = path.toLowerCase().split(".").at(-1);
  return ({
    jpg: "image/jpeg",
    jpeg: "image/jpeg",
    png: "image/png",
    webp: "image/webp",
    pdf: "application/pdf",
    txt: "text/plain",
  } as Record<string, string>)[extension ?? ""] ?? "application/octet-stream";
}

async function prepareGroqInput(
  blob: Blob,
  mimeType: string,
  extractedText: string | null,
  testName: string,
) {
  const normalizedText = (extractedText ?? "").trim().slice(0, 30_000);
  if (mimeType === "application/pdf") {
    if (!normalizedText) throw new PdfTextRequiredError();
    return { testName, text: normalizedText, imageDataUrl: null };
  }
  if (mimeType === "text/plain") {
    const fileText = (await blob.text()).trim().slice(0, 30_000);
    const text = normalizedText || fileText;
    if (!text) throw new HttpError(422, "The stored result does not contain readable text");
    return { testName, text, imageDataUrl: null };
  }
  if (imageMimeTypes.has(mimeType)) {
    const base64 = arrayBufferToBase64(await blob.arrayBuffer());
    return {
      testName,
      text: normalizedText || null,
      imageDataUrl: `data:${mimeType};base64,${base64}`,
    };
  }
  throw new HttpError(415, "Only JPEG, PNG, WebP, text, and text-extracted PDF results are supported");
}

async function analyzeWithGroq(input: {
  testName: string;
  text: string | null;
  imageDataUrl: string | null;
}) {
  const key = mustEnv("GROQ_API_KEY");
  const model = input.imageDataUrl
    ? Deno.env.get("GROQ_VISION_MODEL") ??
      "meta-llama/llama-4-scout-17b-16e-instruct"
    : Deno.env.get("GROQ_MODEL") ?? "llama-3.3-70b-versatile";
  const system = `You assist licensed doctors by extracting preliminary observations from medical result documents. Never make an official diagnosis, prescribe treatment, or claim certainty. Return only JSON with: summary (string), possible_findings (array of {finding, evidence, confidence where confidence is low|moderate|high}), abnormal_indicators (string array), recommended_follow_up (string array), limitations (string array), and disclaimer (string). The disclaimer must clearly state that this is preliminary AI assistance requiring review and confirmation by a licensed doctor. Base observations only on visible or supplied values; say when data is unclear.`;

  const userContent: unknown = input.imageDataUrl
    ? [
      {
        type: "text",
        text: `Laboratory test: ${input.testName}. Extracted text, if available: ${input.text ?? "None"}`,
      },
      { type: "image_url", image_url: { url: input.imageDataUrl } },
    ]
    : `Laboratory test: ${input.testName}\nExtracted result text:\n${input.text}`;

  const response = await fetch("https://api.groq.com/openai/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      temperature: 0.1,
      response_format: { type: "json_object" },
      messages: [
        { role: "system", content: system },
        { role: "user", content: userContent },
      ],
    }),
  });
  if (!response.ok) {
    const detail = await response.text();
    console.error("Groq medical-result request failed", response.status, detail.slice(0, 500));
    throw new HttpError(502, "The AI provider could not analyze this result");
  }
  const body = await response.json();
  const content = body.choices?.[0]?.message?.content;
  if (typeof content !== "string") {
    throw new HttpError(502, "The AI provider returned an invalid result");
  }
  try {
    return { analysis: JSON.parse(content) as Analysis, model };
  } catch {
    throw new HttpError(502, "The AI provider returned malformed findings");
  }
}

function validateAnalysis(value: Analysis) {
  if (!value || typeof value !== "object") throw new HttpError(502, "AI findings are invalid");
  if (typeof value.summary !== "string" || !value.summary.trim() || value.summary.length > 8_000) {
    throw new HttpError(502, "AI findings are missing a valid summary");
  }
  if (!Array.isArray(value.possible_findings) || value.possible_findings.length > 20) {
    throw new HttpError(502, "AI findings have an invalid findings list");
  }
  for (const item of value.possible_findings) {
    if (
      !item || typeof item.finding !== "string" || typeof item.evidence !== "string" ||
      !["low", "moderate", "high"].includes(item.confidence)
    ) throw new HttpError(502, "AI findings contain an invalid item");
  }
  for (const key of ["abnormal_indicators", "recommended_follow_up", "limitations"] as const) {
    if (!Array.isArray(value[key]) || value[key].some((item) => typeof item !== "string")) {
      throw new HttpError(502, `AI findings contain invalid ${key}`);
    }
  }
  if (
    typeof value.disclaimer !== "string" ||
    !/preliminary|not a diagnosis|doctor review/i.test(value.disclaimer)
  ) {
    throw new HttpError(502, "AI findings are missing the required clinical disclaimer");
  }
}

async function recordProcessingFailure(
  admin: SupabaseClient,
  resultId: string,
  doctorId: string,
  processingJobId: string | null,
  error: unknown,
) {
  const pdfNeedsText = error instanceof PdfTextRequiredError;
  const message = pdfNeedsText
    ? "PDF text extraction is required before preliminary AI analysis."
    : "Automated preliminary analysis could not be completed. Retry or review the result manually.";
  const { error: updateError } = await admin
    .from("laboratory_results")
    .update({
      verification_status: pdfNeedsText ? "ocr_processing" : "ai_analysis_pending",
      ai_summary: message,
    })
    .eq("id", resultId)
    .eq("doctor_id", doctorId)
    .eq("verification_status", "ai_analysis_pending");
  if (updateError) console.error("Could not record analysis failure", updateError);

  if (processingJobId) {
    const { error: jobError } = await admin
      .from("document_processing_jobs")
      .update({
        status: pdfNeedsText ? "ocr_processing" : "failed",
        last_error: message,
        completed_at: pdfNeedsText ? null : new Date().toISOString(),
      })
      .eq("id", processingJobId);
    if (jobError) console.error("Could not record document processing failure", jobError);
  }
}

function arrayBufferToBase64(buffer: ArrayBuffer) {
  const bytes = new Uint8Array(buffer);
  let binary = "";
  const chunkSize = 0x8000;
  for (let offset = 0; offset < bytes.length; offset += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(offset, offset + chunkSize));
  }
  return btoa(binary);
}

function serviceClient() {
  return createClient(
    mustEnv("SUPABASE_URL"),
    mustEnv("SUPABASE_SERVICE_ROLE_KEY"),
    { auth: { autoRefreshToken: false, persistSession: false } },
  );
}

function bearerToken(request: Request) {
  const authorization = request.headers.get("Authorization") ?? "";
  const match = authorization.match(/^Bearer\s+(.+)$/i);
  if (!match?.[1]) throw new HttpError(401, "Authentication is required");
  return match[1];
}

async function readBody(request: Request) {
  try {
    const value = await request.json();
    if (!value || typeof value !== "object" || Array.isArray(value)) throw new Error();
    return value as Record<string, unknown>;
  } catch {
    throw new HttpError(400, "A valid JSON request body is required");
  }
}

function requiredUuid(body: Record<string, unknown>, key: string) {
  const value = typeof body[key] === "string" ? body[key].trim() : "";
  if (!uuidPattern.test(value)) {
    throw new HttpError(400, `${key} must be a valid identifier`);
  }
  return value;
}

function relationName(value: unknown) {
  const relation = Array.isArray(value) ? value[0] : value;
  if (!relation || typeof relation !== "object") return "";
  return String((relation as Record<string, unknown>).role_name ?? "");
}

function mustEnv(name: string) {
  const value = Deno.env.get(name);
  if (!value) throw new Error(`${name} is not configured`);
  return value;
}

async function logSecurityEvent(
  admin: SupabaseClient,
  actorAuthUserId: string | null,
  eventType: string,
  success: boolean,
  severity: "info" | "warning" | "critical",
  metadata: Record<string, unknown>,
  request: Request,
) {
  try {
    const { error } = await admin.from("security_logs").insert({
      actor_auth_user_id: actorAuthUserId,
      event_type: eventType,
      severity,
      success,
      user_agent: (request.headers.get("user-agent") ?? "").slice(0, 500) || null,
      metadata,
    });
    if (error) console.error("Could not record analysis security event", error);
  } catch (logError) {
    console.error("Could not record analysis security event", logError);
  }
}

function json(body: unknown, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      ...corsHeaders,
      "Content-Type": "application/json",
      "Cache-Control": "no-store",
    },
  });
}
