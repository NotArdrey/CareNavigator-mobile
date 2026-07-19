import "jsr:@supabase/functions-js/edge-runtime.d.ts";
import { createClient, SupabaseClient } from "jsr:@supabase/supabase-js@2";

const corsHeaders = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type, x-bootstrap-token",
};

type Actor = {
  appUserId: string;
  authUserId: string;
  role: string;
  hospitalId: string | null;
};

Deno.serve(async (request: Request) => {
  if (request.method === "OPTIONS") return new Response("ok", { headers: corsHeaders });
  if (request.method !== "POST") return json({ error: "Method not allowed" }, 405);

  const admin = createClient(mustEnv("SUPABASE_URL"), mustEnv("SUPABASE_SERVICE_ROLE_KEY"), {
    auth: { autoRefreshToken: false, persistSession: false },
  });

  try {
    const body = await request.json() as Record<string, unknown>;
    const action = requiredString(body, "action", 60);

    if (action === "bootstrap_super_admin") {
      return await bootstrapSuperAdmin(request, admin, body);
    }

    const actor = await requireActor(request, admin);
    switch (action) {
      case "create_hospital_admin":
        return await createHospitalAdmin(admin, actor, body);
      case "create_doctor":
        return await createDoctor(admin, actor, body);
      case "update_user_status":
        return await updateUserStatus(admin, actor, body);
      case "update_doctor_status":
        return await updateDoctorStatus(admin, actor, body);
      default:
        return json({ error: "Unknown action" }, 400);
    }
  } catch (error) {
    console.error("admin-users", error);
    const message = error instanceof Error ? error.message : "Unexpected server error";
    const status = message.startsWith("Forbidden")
      ? 403
      : message.startsWith("Authentication")
      ? 401
      : 400;
    return json({ error: message }, status);
  }
});

async function bootstrapSuperAdmin(
  request: Request,
  admin: SupabaseClient,
  body: Record<string, unknown>,
) {
  const expected = mustEnv("ADMIN_BOOTSTRAP_TOKEN");
  const supplied = request.headers.get("x-bootstrap-token") ?? "";
  if (!constantTimeEqual(supplied, expected)) {
    return json({ error: "Invalid bootstrap token" }, 403);
  }

  const superRoleId = await roleId(admin, "super_admin");
  const { count, error: countError } = await admin
    .from("users")
    .select("id", { count: "exact", head: true })
    .eq("role_id", superRoleId);
  if (countError) throw countError;
  if ((count ?? 0) > 0) {
    return json({ error: "Bootstrap is disabled because a super administrator already exists" }, 409);
  }

  const created = await createAuthUser(admin, body);
  try {
    const { error } = await admin.from("users").update({
      role_id: superRoleId,
      account_status: "active",
      first_name: requiredString(body, "first_name", 100),
      last_name: requiredString(body, "last_name", 100),
      email: requiredEmail(body),
      hospital_id: null,
    }).eq("auth_user_id", created.id);
    if (error) throw error;
    return json({ id: created.id, message: "Super administrator created" }, 201);
  } catch (error) {
    await admin.auth.admin.deleteUser(created.id);
    throw error;
  }
}

async function createHospitalAdmin(
  admin: SupabaseClient,
  actor: Actor,
  body: Record<string, unknown>,
) {
  if (actor.role !== "super_admin") throw new Error("Forbidden: super administrator access required");
  const hospitalId = requiredUuid(body, "hospital_id");
  await ensureHospital(admin, hospitalId);
  const hospitalAdminRoleId = await roleId(admin, "hospital_admin");
  const created = await createAuthUser(admin, body);
  try {
    const { error } = await admin.from("users").update({
      role_id: hospitalAdminRoleId,
      account_status: "active",
      first_name: requiredString(body, "first_name", 100),
      last_name: requiredString(body, "last_name", 100),
      email: requiredEmail(body),
      hospital_id: hospitalId,
    }).eq("auth_user_id", created.id);
    if (error) throw error;
    return json({ id: created.id, message: "Hospital administrator created" }, 201);
  } catch (error) {
    await admin.auth.admin.deleteUser(created.id);
    throw error;
  }
}

async function createDoctor(
  admin: SupabaseClient,
  actor: Actor,
  body: Record<string, unknown>,
) {
  if (!["super_admin", "hospital_admin"].includes(actor.role)) {
    throw new Error("Forbidden: hospital administrator access required");
  }
  const hospitalId = requiredUuid(body, "hospital_id");
  if (actor.role === "hospital_admin" && actor.hospitalId !== hospitalId) {
    throw new Error("Forbidden: this hospital is outside your assignment");
  }
  await ensureHospital(admin, hospitalId);

  const departmentId = optionalUuid(body, "department_id");
  if (departmentId) {
    const { data, error } = await admin.from("hospital_departments")
      .select("id").eq("id", departmentId).eq("hospital_id", hospitalId).maybeSingle();
    if (error || !data) throw new Error("The selected department does not belong to this hospital");
  }

  const doctorRoleId = await roleId(admin, "doctor");
  const created = await createAuthUser(admin, body);
  try {
    const firstName = requiredString(body, "first_name", 100);
    const lastName = requiredString(body, "last_name", 100);
    const { data: appUser, error: userError } = await admin.from("users").update({
      role_id: doctorRoleId,
      account_status: "active",
      first_name: firstName,
      last_name: lastName,
      email: requiredEmail(body),
      hospital_id: hospitalId,
    }).eq("auth_user_id", created.id).select("id").single();
    if (userError) throw userError;

    const fee = optionalNumber(body, "consultation_fee");
    const { data: doctor, error: doctorError } = await admin.from("doctors").insert({
      user_id: appUser.id,
      hospital_id: hospitalId,
      department_id: departmentId,
      display_name: `Dr. ${firstName} ${lastName}`.trim(),
      specialization: requiredString(body, "specialization", 160),
      license_number: requiredString(body, "license_number", 100),
      consultation_fee: fee,
      biography: optionalString(body, "biography", 2000),
      created_by_admin: actor.appUserId,
    }).select("id").single();
    if (doctorError) throw doctorError;
    return json({ id: doctor.id, user_id: appUser.id, message: "Doctor account created" }, 201);
  } catch (error) {
    await admin.auth.admin.deleteUser(created.id);
    throw error;
  }
}

async function updateUserStatus(
  admin: SupabaseClient,
  actor: Actor,
  body: Record<string, unknown>,
) {
  const targetId = requiredUuid(body, "user_id");
  const status = requiredEnum(body, "account_status", ["active", "inactive", "suspended"]);
  const { data: target, error } = await admin.from("users")
    .select("id, auth_user_id, hospital_id, roles!inner(role_name)")
    .eq("id", targetId).single();
  if (error) throw error;
  const targetRole = relationName(target.roles);
  if (targetRole === "super_admin") throw new Error("Forbidden: super administrator status cannot be changed here");
  if (actor.role !== "super_admin" &&
      !(actor.role === "hospital_admin" && actor.hospitalId === target.hospital_id)) {
    throw new Error("Forbidden: this account is outside your assignment");
  }

  const { error: updateError } = await admin.from("users")
    .update({ account_status: status }).eq("id", targetId);
  if (updateError) throw updateError;
  const { error: banError } = await admin.auth.admin.updateUserById(target.auth_user_id, {
    ban_duration: status === "active" ? "none" : "876000h",
  });
  if (banError) throw banError;
  return json({ message: `Account marked ${status}` });
}

async function updateDoctorStatus(
  admin: SupabaseClient,
  actor: Actor,
  body: Record<string, unknown>,
) {
  const doctorId = requiredUuid(body, "doctor_id");
  const status = requiredEnum(body, "availability_status", ["available", "limited", "unavailable"]);
  const { data: doctor, error } = await admin.from("doctors")
    .select("id, hospital_id").eq("id", doctorId).single();
  if (error) throw error;
  if (actor.role !== "super_admin" &&
      !(actor.role === "hospital_admin" && actor.hospitalId === doctor.hospital_id)) {
    throw new Error("Forbidden: this doctor is outside your assignment");
  }
  const { error: updateError } = await admin.from("doctors")
    .update({ availability_status: status }).eq("id", doctorId);
  if (updateError) throw updateError;
  return json({ message: `Doctor marked ${status}` });
}

async function createAuthUser(admin: SupabaseClient, body: Record<string, unknown>) {
  const email = requiredEmail(body);
  const password = requiredString(body, "password", 200);
  if (password.length < 12) throw new Error("Password must contain at least 12 characters");
  const firstName = requiredString(body, "first_name", 100);
  const lastName = requiredString(body, "last_name", 100);
  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: { first_name: firstName, last_name: lastName },
  });
  if (error || !data.user) throw error ?? new Error("Could not create authentication account");
  return data.user;
}

async function requireActor(request: Request, admin: SupabaseClient): Promise<Actor> {
  const authorization = request.headers.get("Authorization") ?? "";
  const token = authorization.replace(/^Bearer\s+/i, "");
  if (!token) throw new Error("Authentication is required");
  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData.user) throw new Error("Authentication session is invalid");
  const { data, error } = await admin.from("users")
    .select("id, auth_user_id, hospital_id, account_status, roles!inner(role_name)")
    .eq("auth_user_id", authData.user.id).single();
  if (error || !data || data.account_status !== "active") {
    throw new Error("Forbidden: active administrator profile required");
  }
  const role = relationName(data.roles);
  if (!["super_admin", "hospital_admin"].includes(role)) {
    throw new Error("Forbidden: administrator access required");
  }
  return {
    appUserId: data.id,
    authUserId: data.auth_user_id,
    role,
    hospitalId: data.hospital_id,
  };
}

async function roleId(admin: SupabaseClient, roleName: string) {
  const { data, error } = await admin.from("roles").select("id").eq("role_name", roleName).single();
  if (error) throw error;
  return data.id;
}

async function ensureHospital(admin: SupabaseClient, hospitalId: string) {
  const { data, error } = await admin.from("hospitals").select("id").eq("id", hospitalId).maybeSingle();
  if (error || !data) throw new Error("Hospital was not found");
}

function relationName(value: unknown) {
  const relation = Array.isArray(value) ? value[0] : value;
  if (!relation || typeof relation !== "object") return "";
  return String((relation as Record<string, unknown>).role_name ?? "");
}

function requiredString(body: Record<string, unknown>, key: string, max: number) {
  const value = typeof body[key] === "string" ? body[key].trim() : "";
  if (!value) throw new Error(`${key} is required`);
  if (value.length > max) throw new Error(`${key} is too long`);
  return value;
}

function optionalString(body: Record<string, unknown>, key: string, max: number) {
  if (body[key] == null || body[key] === "") return null;
  return requiredString(body, key, max);
}

function requiredEmail(body: Record<string, unknown>) {
  const email = requiredString(body, "email", 320).toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) throw new Error("A valid email is required");
  return email;
}

function requiredUuid(body: Record<string, unknown>, key: string) {
  const value = requiredString(body, key, 36);
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(value)) {
    throw new Error(`${key} must be a valid identifier`);
  }
  return value;
}

function optionalUuid(body: Record<string, unknown>, key: string) {
  return body[key] == null || body[key] === "" ? null : requiredUuid(body, key);
}

function optionalNumber(body: Record<string, unknown>, key: string) {
  if (body[key] == null || body[key] === "") return null;
  const value = Number(body[key]);
  if (!Number.isFinite(value) || value < 0) throw new Error(`${key} must be zero or greater`);
  return value;
}

function requiredEnum(body: Record<string, unknown>, key: string, values: string[]) {
  const value = requiredString(body, key, 60);
  if (!values.includes(value)) throw new Error(`${key} is invalid`);
  return value;
}

function constantTimeEqual(left: string, right: string) {
  const encoder = new TextEncoder();
  const a = encoder.encode(left);
  const b = encoder.encode(right);
  let difference = a.length ^ b.length;
  const length = Math.max(a.length, b.length);
  for (let index = 0; index < length; index++) {
    difference |= (a[index % (a.length || 1)] ?? 0) ^ (b[index % (b.length || 1)] ?? 0);
  }
  return difference === 0;
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
