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
const convertibleStatuses = new Set([
  "approved",
  "temporary_patient_created",
  "account_activation_pending",
  "consultation_scheduled",
  "consultation_completed",
]);

type Actor = {
  appUserId: string;
  authUserId: string;
  role: "doctor" | "hospital_admin";
  hospitalId: string;
  doctorId: string | null;
};

type Compensation = {
  authUserId: string | null;
  createdAuthUser: boolean;
  patientId: string | null;
  createdPatient: boolean;
  activatedPatient: boolean;
  createdAssignmentIds: string[];
  originalAppUser: Record<string, unknown> | null;
  originalPatient: Record<string, unknown> | null;
  originalGuest: Record<string, unknown> | null;
  originalConsultations: Array<Record<string, unknown>>;
};

class HttpError extends Error {
  constructor(public status: number, message: string) {
    super(message);
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
  let actor: Actor | null = null;
  let guestRequestId: string | null = null;
  let eventType = "care_workflow_request";
  try {
    admin = serviceClient();
    actor = await requireActor(request, admin);
    const body = await readBody(request);
    const action = requiredString(body, "action", 60);

    let response: Response;
    if (action === "create_patient_account") {
      eventType = "guest_patient_conversion";
      guestRequestId = requiredUuid(body, "guest_request_id");
      response = await createPatientAccount(admin, actor, body);
    } else if (action === "create_direct_patient_account") {
      eventType = "direct_patient_account_creation";
      if (actor.role !== "doctor" || !actor.doctorId) {
        throw new HttpError(403, "Only an active doctor can create a patient account directly");
      }
      response = await createDirectPatientAccount(admin, actor, body);
    } else {
      throw new HttpError(400, "Unknown action");
    }
    await logSecurityEvent(admin, actor.authUserId, eventType, true, "info", {
      guest_request_id: guestRequestId,
      hospital_id: actor.hospitalId,
      actor_role: actor.role,
    }, request);
    return response;
  } catch (error) {
    console.error("care-workflows", error);
    if (admin) {
      await logSecurityEvent(
        admin,
        actor?.authUserId ?? null,
        eventType,
        false,
        error instanceof HttpError && error.status < 500 ? "warning" : "critical",
        {
          guest_request_id: guestRequestId,
          hospital_id: actor?.hospitalId ?? null,
          actor_role: actor?.role ?? null,
          failure: error instanceof HttpError ? `http_${error.status}` : "unexpected_error",
        },
        request,
      );
    }
    if (error instanceof HttpError) {
      return json({ error: error.message }, error.status);
    }
    return json({ error: "The care workflow could not be completed" }, 500);
  }
});

async function createPatientAccount(
  admin: SupabaseClient,
  actor: Actor,
  body: Record<string, unknown>,
) {
  const guestRequestId = requiredUuid(body, "guest_request_id");
  const email = requiredEmail(body);
  const password = requiredPassword(body);

  const { data: guest, error: guestError } = await admin
    .from("guest_consultation_requests")
    .select(
      "id, submitted_by, full_name, birth_date, sex, mobile_number, email, address, existing_conditions, allergies, preferred_hospital_id, assigned_doctor_id, identification_file_path, request_status",
    )
    .eq("id", guestRequestId)
    .maybeSingle();
  if (guestError) throw guestError;
  if (!guest) throw new HttpError(404, "Guest consultation request was not found");
  if (guest.email && guest.email.trim().toLowerCase() !== email) {
    throw new HttpError(409, "The account email must match the verified guest request email");
  }
  if (!convertibleStatuses.has(guest.request_status)) {
    throw new HttpError(
      409,
      "The guest request must be approved before a patient account can be created",
    );
  }

  const selectedDoctorId = actor.role === "doctor"
    ? actor.doctorId!
    : optionalUuid(body, "assigned_doctor_id") ?? guest.assigned_doctor_id;
  if (!selectedDoctorId || !uuidPattern.test(selectedDoctorId)) {
    throw new HttpError(400, "An assigned doctor is required");
  }

  const { data: selectedDoctor, error: doctorError } = await admin
    .from("doctors")
    .select("id, hospital_id")
    .eq("id", selectedDoctorId)
    .maybeSingle();
  if (doctorError) throw doctorError;
  if (!selectedDoctor || selectedDoctor.hospital_id !== actor.hospitalId) {
    throw new HttpError(403, "The assigned doctor is outside your hospital");
  }
  if (actor.role === "doctor" && guest.assigned_doctor_id !== actor.doctorId) {
    throw new HttpError(403, "Only the assigned doctor can convert this guest request");
  }
  if (
    actor.role === "hospital_admin" &&
    guest.preferred_hospital_id !== actor.hospitalId
  ) {
    throw new HttpError(403, "The guest request is outside your hospital");
  }

  const { data: consultations, error: consultationError } = await admin
    .from("consultations")
    .select("id, guest_request_id, patient_id, doctor_id, hospital_id, status")
    .eq("guest_request_id", guestRequestId);
  if (consultationError) throw consultationError;
  if ((consultations ?? []).some((item) => item.hospital_id !== actor.hospitalId)) {
    throw new HttpError(409, "The request contains a consultation from another hospital");
  }

  const doctorIds = [...new Set([
    selectedDoctorId,
    ...(consultations ?? []).map((item) => String(item.doctor_id)),
  ])];
  await ensureDoctorsBelongToHospital(admin, doctorIds, actor.hospitalId);

  const names = patientNames(body, guest.full_name);
  const compensation: Compensation = {
    authUserId: null,
    createdAuthUser: false,
    patientId: null,
    createdPatient: false,
    activatedPatient: false,
    createdAssignmentIds: [],
    originalAppUser: null,
    originalPatient: null,
    originalGuest: {
      id: guest.id,
      submitted_by: guest.submitted_by,
      assigned_doctor_id: guest.assigned_doctor_id,
      request_status: guest.request_status,
    },
    originalConsultations: consultations ?? [],
  };

  try {
    const authUser = await resolveOrCreateAuthUser(
      admin,
      guest.submitted_by,
      email,
      password,
      names,
    );
    compensation.authUserId = authUser.id;
    compensation.createdAuthUser = authUser.created;

    const { data: currentAppUser, error: appUserError } = await admin
      .from("users")
      .select(
        "id, role_id, first_name, middle_name, last_name, email, mobile_number, birth_date, sex, address, hospital_id, account_status",
      )
      .eq("auth_user_id", authUser.id)
      .maybeSingle();
    if (appUserError) throw appUserError;
    if (!currentAppUser) throw new Error("Authentication profile was not provisioned");
    compensation.originalAppUser = currentAppUser;

    const { data: patientRole, error: roleError } = await admin
      .from("roles")
      .select("id")
      .eq("role_name", "patient")
      .single();
    if (roleError) throw roleError;

    const { data: appUser, error: updateUserError } = await admin
      .from("users")
      .update({
        role_id: patientRole.id,
        first_name: names.firstName,
        last_name: names.lastName,
        email,
        mobile_number: guest.mobile_number,
        birth_date: guest.birth_date,
        sex: guest.sex,
        address: guest.address,
        hospital_id: null,
        account_status: "active",
      })
      .eq("id", currentAppUser.id)
      .select("id")
      .single();
    if (updateUserError) throw updateUserError;

    const { data: existingPatient, error: existingPatientError } = await admin
      .from("patients")
      .select(
        "id, user_id, patient_number, created_by_doctor, primary_hospital_id, identity_verification_status, account_activation_status, converted_from_guest, converted_at, profile_status, activated_at",
      )
      .eq("guest_request_id", guestRequestId)
      .maybeSingle();
    if (existingPatientError) throw existingPatientError;

    const { data: patientForUser, error: patientForUserError } = await admin
      .from("patients")
      .select("id, guest_request_id")
      .eq("user_id", appUser.id)
      .maybeSingle();
    if (patientForUserError) throw patientForUserError;
    if (patientForUser && patientForUser.id !== existingPatient?.id) {
      throw new HttpError(
        409,
        "This authentication account is already linked to a different patient profile",
      );
    }

    await rejectAmbiguousDuplicatePatient(
      admin,
      guest,
      appUser.id,
      existingPatient?.id ?? null,
      email,
    );

    let patientId: string;
    if (existingPatient) {
      if (existingPatient.user_id && existingPatient.user_id !== appUser.id) {
        throw new HttpError(409, "This guest request is already linked to another patient account");
      }
      patientId = existingPatient.id;

      const now = new Date().toISOString();
      let claimedPatient: Record<string, unknown> | null = null;
      let claimQuery = admin
        .from("patients")
        .update({
          user_id: appUser.id,
          patient_number: existingPatient.patient_number ?? makePatientNumber(),
          created_by_doctor: existingPatient.created_by_doctor ?? selectedDoctorId,
          primary_hospital_id: existingPatient.primary_hospital_id ?? actor.hospitalId,
          identity_verification_status: "verified",
          account_activation_status: "active",
          converted_from_guest: true,
          converted_at: existingPatient.converted_at ?? now,
          profile_status: "official",
          activated_at: existingPatient.activated_at ?? now,
        })
        .eq("id", existingPatient.id)
        .eq("guest_request_id", guestRequestId);
      claimQuery = existingPatient.user_id == null
        ? claimQuery.is("user_id", null)
        : claimQuery.eq("user_id", appUser.id);
      const { data: claimed, error: claimError } = await claimQuery
        .select("id")
        .maybeSingle();
      if (claimError) throw claimError;
      claimedPatient = claimed;

      if (!claimedPatient) {
        // A concurrent retry may have completed the same idempotent claim.
        const { data: concurrentPatient, error: concurrentError } = await admin
          .from("patients")
          .select("id, user_id")
          .eq("id", existingPatient.id)
          .maybeSingle();
        if (concurrentError) throw concurrentError;
        if (concurrentPatient?.user_id !== appUser.id) {
          throw new HttpError(409, "The temporary patient profile changed during activation");
        }
      } else {
        compensation.originalPatient = existingPatient;
        compensation.activatedPatient = existingPatient.user_id == null ||
          existingPatient.account_activation_status !== "active" ||
          existingPatient.profile_status !== "official";
      }
    } else {
      if (patientForUser) {
        throw new HttpError(
          409,
          "This authentication account is already linked to a different patient profile",
        );
      }
      const { data: patient, error: patientError } = await admin
        .from("patients")
        .insert({
          user_id: appUser.id,
          patient_number: makePatientNumber(),
          created_by_doctor: selectedDoctorId,
          guest_request_id: guestRequestId,
          primary_hospital_id: actor.hospitalId,
          allergies: guest.allergies ?? [],
          existing_conditions: guest.existing_conditions ?? [],
          identity_verification_status: "pending",
          account_activation_status: "active",
          converted_from_guest: true,
          converted_at: new Date().toISOString(),
          profile_status: "official",
          activated_at: new Date().toISOString(),
        })
        .select("id")
        .single();
      if (patientError) throw patientError;
      patientId = patient.id;
      compensation.createdPatient = true;
      compensation.activatedPatient = true;
    }
    compensation.patientId = patientId;

    for (const doctorId of doctorIds) {
      const assignmentId = await ensureActiveAssignment(
        admin,
        doctorId,
        patientId,
        actor,
        guestRequestId,
      );
      if (assignmentId) compensation.createdAssignmentIds.push(assignmentId);
    }

    const consultationIds = (consultations ?? []).map((item) => String(item.id));
    if (consultationIds.length > 0) {
      const { data: updatedConsultations, error: updateConsultationsError } = await admin
        .from("consultations")
        .update({ patient_id: patientId, guest_request_id: null })
        .in("id", consultationIds)
        .eq("guest_request_id", guestRequestId)
        .select("id");
      if (updateConsultationsError) throw updateConsultationsError;
      if ((updatedConsultations ?? []).length !== consultationIds.length) {
        throw new Error("A consultation changed while the account was being created");
      }
    }

    const requestStatus = terminalRequestStatus(guest.request_status);
    const { data: updatedGuest, error: updateGuestError } = await admin
      .from("guest_consultation_requests")
      .update({
        submitted_by: authUser.id,
        assigned_doctor_id: selectedDoctorId,
        request_status: requestStatus,
      })
      .eq("id", guestRequestId)
      .eq("request_status", guest.request_status)
      .select("id")
      .maybeSingle();
    if (updateGuestError) throw updateGuestError;
    if (!updatedGuest) throw new Error("The guest request changed while the account was being created");

    let credentialsProvisioned = authUser.credentialsProvisioned;
    if (authUser.needsCredentialProvisioning) {
      const { error: credentialError } = await admin.auth.admin.updateUserById(
        authUser.id,
        { email, password, email_confirm: true },
      );
      if (credentialError) {
        if (/already|registered|exists/i.test(credentialError.message ?? "")) {
          throw new HttpError(
            409,
            "Another authentication account already uses this email",
          );
        }
        throw credentialError;
      }
      credentialsProvisioned = true;
    }

    return json({
      patient_id: patientId,
      user_id: appUser.id,
      auth_user_id: authUser.id,
      consultation_ids: consultationIds,
      account_activation_status: "active",
      activation_ready: true,
      credentials_provisioned: credentialsProvisioned,
      message: existingPatient
        ? "Patient account activated; care links were synchronized"
        : "Guest request converted to a patient account",
    }, existingPatient ? 200 : 201);
  } catch (error) {
    await compensateConversion(admin, compensation);
    throw error;
  }
}

async function createDirectPatientAccount(
  admin: SupabaseClient,
  actor: Actor,
  body: Record<string, unknown>,
) {
  if (!actor.doctorId) {
    throw new HttpError(403, "A doctor profile is required");
  }
  const email = requiredEmail(body);
  const password = requiredPassword(body);
  const firstName = requiredString(body, "first_name", 100);
  const lastName = requiredString(body, "last_name", 100);
  const middleName = optionalString(body, "middle_name", 100);
  const birthDate = optionalBirthDate(body);
  const sex = optionalSex(body);
  const mobileNumber = optionalMobile(body);
  const address = optionalString(body, "address", 1000);

  await rejectDirectPatientDuplicate(
    admin,
    email,
    mobileNumber,
    birthDate,
  );

  let createdAuthUserId: string | null = null;
  try {
    const { data: authData, error: authError } = await admin.auth.admin.createUser({
      email,
      password,
      email_confirm: true,
      user_metadata: {
        first_name: firstName,
        last_name: lastName,
        provisioned_by_doctor: actor.doctorId,
      },
    });
    if (authError || !authData.user) {
      if (/already|registered|exists/i.test(authError?.message ?? "")) {
        throw new HttpError(409, "An account already uses this email");
      }
      throw authError ?? new Error("Could not create the patient authentication account");
    }
    createdAuthUserId = authData.user.id;

    const { data: patientRole, error: roleError } = await admin
      .from("roles")
      .select("id")
      .eq("role_name", "patient")
      .single();
    if (roleError) throw roleError;

    const { data: appUser, error: appUserError } = await admin
      .from("users")
      .update({
        role_id: patientRole.id,
        first_name: firstName,
        middle_name: middleName,
        last_name: lastName,
        email,
        mobile_number: mobileNumber,
        birth_date: birthDate,
        sex,
        address,
        hospital_id: null,
        account_status: "active",
      })
      .eq("auth_user_id", createdAuthUserId)
      .select("id")
      .single();
    if (appUserError) throw appUserError;

    const now = new Date().toISOString();
    const { data: patient, error: patientError } = await admin
      .from("patients")
      .insert({
        user_id: appUser.id,
        patient_number: makePatientNumber(),
        created_by_doctor: actor.doctorId,
        primary_hospital_id: actor.hospitalId,
        identity_verification_status: "pending",
        account_activation_status: "active",
        profile_status: "official",
        activated_at: now,
      })
      .select("id, patient_number")
      .single();
    if (patientError) throw patientError;

    const { error: assignmentError } = await admin
      .from("doctor_patient_assignments")
      .insert({
        doctor_id: actor.doctorId,
        patient_id: patient.id,
        notes: `Direct patient creation authorized by doctor ${actor.doctorId}`,
      });
    if (assignmentError) throw assignmentError;

    return json({
      patient_id: patient.id,
      patient_number: patient.patient_number,
      user_id: appUser.id,
      auth_user_id: createdAuthUserId,
      account_activation_status: "active",
      activation_ready: true,
      credentials_provisioned: true,
      message: "Patient account created and assigned to the doctor",
    }, 201);
  } catch (error) {
    if (createdAuthUserId) {
      try {
        const { error: deleteError } = await admin.auth.admin.deleteUser(createdAuthUserId);
        if (deleteError) throw deleteError;
      } catch (rollbackError) {
        console.error("Direct patient creation compensation failed", rollbackError);
      }
    }
    throw error;
  }
}

async function rejectDirectPatientDuplicate(
  admin: SupabaseClient,
  email: string,
  mobileNumber: string | null,
  birthDate: string | null,
) {
  const escapedEmail = email.replace(/[\\%_]/g, "\\$&");
  const { data: emailMatches, error: emailError } = await admin
    .from("users")
    .select("id")
    .ilike("email", escapedEmail)
    .limit(1);
  if (emailError) throw emailError;
  if ((emailMatches ?? []).length > 0) {
    throw new HttpError(409, "A possible existing patient account requires duplicate review");
  }

  if (!mobileNumber || !birthDate) return;
  const normalizedMobile = normalizeMobile(mobileNumber);
  const { data: birthMatches, error: birthError } = await admin
    .from("users")
    .select("id, mobile_number")
    .eq("birth_date", birthDate)
    .limit(200);
  if (birthError) throw birthError;
  const possibleUserIds = (birthMatches ?? [])
    .filter((candidate) => normalizeMobile(candidate.mobile_number ?? "") === normalizedMobile)
    .map((candidate) => String(candidate.id));
  if (possibleUserIds.length === 0) return;
  const { data: patients, error: patientsError } = await admin
    .from("patients")
    .select("id")
    .in("user_id", possibleUserIds)
    .limit(1);
  if (patientsError) throw patientsError;
  if ((patients ?? []).length > 0) {
    throw new HttpError(409, "A possible existing patient account requires duplicate review");
  }
}

async function resolveOrCreateAuthUser(
  admin: SupabaseClient,
  submittedBy: string | null,
  email: string,
  password: string,
  names: { firstName: string; lastName: string },
) {
  if (submittedBy) {
    if (!uuidPattern.test(submittedBy)) {
      throw new HttpError(409, "The request has an invalid submitter account");
    }
    const { data, error } = await admin.auth.admin.getUserById(submittedBy);
    if (error || !data.user) {
      throw new HttpError(409, "The guest submitter account no longer exists");
    }
    if (data.user.email && data.user.email.toLowerCase() !== email) {
      throw new HttpError(409, "The email must match the guest submitter account");
    }
    if (!data.user.email && !data.user.phone_confirmed_at) {
      throw new HttpError(409, "The guest submitter phone account is not verified");
    }
    // Do not reset the password of an existing guest account on a staff request.
    return {
      id: data.user.id,
      created: false,
      credentialsProvisioned: false,
      needsCredentialProvisioning: !data.user.email,
    };
  }

  const { data, error } = await admin.auth.admin.createUser({
    email,
    password,
    email_confirm: true,
    user_metadata: {
      first_name: names.firstName,
      last_name: names.lastName,
      provisioned_from_guest: true,
    },
  });
  if (error || !data.user) {
    if (/already|registered|exists/i.test(error?.message ?? "")) {
      throw new HttpError(
        409,
        "An account already uses this email; link it to the guest request before conversion",
      );
    }
    throw error ?? new Error("Could not provision the authentication account");
  }
  return {
    id: data.user.id,
    created: true,
    credentialsProvisioned: true,
    needsCredentialProvisioning: false,
  };
}

async function ensureDoctorsBelongToHospital(
  admin: SupabaseClient,
  doctorIds: string[],
  hospitalId: string,
) {
  const { data, error } = await admin
    .from("doctors")
    .select("id")
    .in("id", doctorIds)
    .eq("hospital_id", hospitalId);
  if (error) throw error;
  if ((data ?? []).length !== doctorIds.length) {
    throw new HttpError(409, "A consultation doctor is outside your hospital");
  }
}

async function rejectAmbiguousDuplicatePatient(
  admin: SupabaseClient,
  guest: Record<string, unknown>,
  currentAppUserId: string,
  expectedPatientId: string | null,
  verifiedEmail: string,
) {
  const birthDate = typeof guest.birth_date === "string" ? guest.birth_date : "";
  if (!birthDate) return;
  const email = normalizeEmail(
    typeof guest.email === "string" && guest.email ? guest.email : verifiedEmail,
  );
  const mobile = normalizeMobile(
    typeof guest.mobile_number === "string" ? guest.mobile_number : "",
  );
  if (!email && !mobile) return;

  const { data: possibleUsers, error: possibleUsersError } = await admin
    .from("users")
    .select("id, email, mobile_number, birth_date")
    .eq("birth_date", birthDate)
    .neq("id", currentAppUserId)
    .limit(200);
  if (possibleUsersError) throw possibleUsersError;

  const candidateIds = (possibleUsers ?? [])
    .filter((candidate) =>
      (email && normalizeEmail(candidate.email ?? "") === email) ||
      (mobile && normalizeMobile(candidate.mobile_number ?? "") === mobile)
    )
    .map((candidate) => String(candidate.id));
  if (candidateIds.length === 0) return;

  const { data: possiblePatients, error: possiblePatientsError } = await admin
    .from("patients")
    .select("id")
    .in("user_id", candidateIds)
    .limit(2);
  if (possiblePatientsError) throw possiblePatientsError;
  if ((possiblePatients ?? []).some((patient) => patient.id !== expectedPatientId)) {
    throw new HttpError(
      409,
      "A possible existing patient record requires duplicate review before activation",
    );
  }
}

async function ensureActiveAssignment(
  admin: SupabaseClient,
  doctorId: string,
  patientId: string,
  actor: Actor,
  guestRequestId: string,
) {
  const { data: current, error: currentError } = await admin
    .from("doctor_patient_assignments")
    .select("id")
    .eq("doctor_id", doctorId)
    .eq("patient_id", patientId)
    .is("ended_at", null)
    .maybeSingle();
  if (currentError) throw currentError;
  if (current) return null;

  const { data, error } = await admin
    .from("doctor_patient_assignments")
    .insert({
      doctor_id: doctorId,
      patient_id: patientId,
      notes: `Guest conversion ${guestRequestId}; authorized by ${actor.role} ${actor.appUserId}`,
    })
    .select("id")
    .single();
  if (error) {
    // A concurrent idempotent conversion may have won the partial unique index race.
    if (error.code === "23505") return null;
    throw error;
  }
  return data.id as string;
}

async function compensateConversion(admin: SupabaseClient, state: Compensation) {
  await compensationStep("guest request", async () => {
    if (state.originalGuest && state.authUserId) {
      await admin.from("guest_consultation_requests").update({
        submitted_by: state.originalGuest.submitted_by,
        assigned_doctor_id: state.originalGuest.assigned_doctor_id,
        request_status: state.originalGuest.request_status,
      }).eq("id", state.originalGuest.id)
        .eq("submitted_by", state.authUserId);
    }
  });

  await compensationStep("consultations", async () => {
    for (const item of state.originalConsultations) {
      await admin.from("consultations").update({
        patient_id: item.patient_id,
        guest_request_id: item.guest_request_id,
      }).eq("id", item.id)
        .eq("patient_id", state.patientId)
        .is("guest_request_id", null);
    }
  });

  await compensationStep("doctor assignments", async () => {
    if (state.createdAssignmentIds.length > 0) {
      await admin.from("doctor_patient_assignments")
        .delete().in("id", state.createdAssignmentIds);
    }
  });

  await compensationStep("synchronized clinical records", async () => {
    const convertedConsultationIds = state.originalConsultations
      .filter((item) => item.patient_id == null)
      .map((item) => String(item.id));
    if (convertedConsultationIds.length > 0 && state.patientId) {
      const { error: diagnosisError } = await admin.from("diagnoses").delete()
        .in("consultation_id", convertedConsultationIds)
        .eq("patient_id", state.patientId)
        .eq("source", "consultation_completion");
      if (diagnosisError) throw diagnosisError;
      const { error: treatmentError } = await admin.from("treatment_plans").delete()
        .in("consultation_id", convertedConsultationIds)
        .eq("patient_id", state.patientId)
        .eq("source", "consultation_completion");
      if (treatmentError) throw treatmentError;
    }
  });

  await compensationStep("activation notification", async () => {
    if (state.activatedPatient && state.patientId) {
      await admin.from("notifications").delete()
        .eq("dedupe_key", `account_activation:${state.patientId}:active`);
    }
  });

  await compensationStep("patient profile", async () => {
    if (state.createdPatient && state.patientId) {
      await admin.from("patients").delete().eq("id", state.patientId);
    } else if (state.originalPatient && state.patientId) {
      const original = state.originalPatient;
      await admin.from("patients").update({
        user_id: original.user_id,
        patient_number: original.patient_number,
        created_by_doctor: original.created_by_doctor,
        primary_hospital_id: original.primary_hospital_id,
        identity_verification_status: original.identity_verification_status,
        account_activation_status: original.account_activation_status,
        converted_from_guest: original.converted_from_guest,
        converted_at: original.converted_at,
        profile_status: original.profile_status,
        activated_at: original.activated_at,
      }).eq("id", state.patientId)
        .eq("user_id", state.authUserId);
    }
  });

  await compensationStep("authentication profile", async () => {
    if (state.createdAuthUser && state.authUserId) {
      const { error } = await admin.auth.admin.deleteUser(state.authUserId);
      if (error) throw error;
    } else if (state.originalAppUser) {
      const original = state.originalAppUser;
      await admin.from("users").update({
        role_id: original.role_id,
        first_name: original.first_name,
        middle_name: original.middle_name,
        last_name: original.last_name,
        email: original.email,
        mobile_number: original.mobile_number,
        birth_date: original.birth_date,
        sex: original.sex,
        address: original.address,
        hospital_id: original.hospital_id,
        account_status: original.account_status,
      }).eq("id", original.id);
    }
  });
}

async function compensationStep(label: string, operation: () => Promise<void>) {
  try {
    await operation();
  } catch (rollbackError) {
    console.error(`care-workflows compensation failed for ${label}`, rollbackError);
  }
}

async function requireActor(request: Request, admin: SupabaseClient): Promise<Actor> {
  const token = bearerToken(request);
  const { data: authData, error: authError } = await admin.auth.getUser(token);
  if (authError || !authData.user) {
    throw new HttpError(401, "Authentication session is invalid");
  }

  const { data: appUser, error: appUserError } = await admin
    .from("users")
    .select("id, auth_user_id, hospital_id, account_status, roles!inner(role_name)")
    .eq("auth_user_id", authData.user.id)
    .maybeSingle();
  if (appUserError) throw appUserError;
  const role = relationName(appUser?.roles);
  if (
    !appUser || appUser.account_status !== "active" ||
    !["doctor", "hospital_admin"].includes(role) || !appUser.hospital_id
  ) {
    throw new HttpError(403, "An active doctor or hospital administrator account is required");
  }

  let doctorId: string | null = null;
  if (role === "doctor") {
    const { data: doctor, error: doctorError } = await admin
      .from("doctors")
      .select("id, hospital_id")
      .eq("user_id", appUser.id)
      .maybeSingle();
    if (doctorError) throw doctorError;
    if (!doctor || doctor.hospital_id !== appUser.hospital_id) {
      throw new HttpError(403, "The doctor profile is not assigned to this hospital");
    }
    doctorId = doctor.id;
  }

  return {
    appUserId: appUser.id,
    authUserId: appUser.auth_user_id,
    role: role as Actor["role"],
    hospitalId: appUser.hospital_id,
    doctorId,
  };
}

function patientNames(body: Record<string, unknown>, fullName: string) {
  const pieces = fullName.trim().split(/\s+/).filter(Boolean);
  const suppliedFirst = optionalString(body, "first_name", 100);
  const suppliedLast = optionalString(body, "last_name", 100);
  const firstName = suppliedFirst ?? pieces.slice(0, -1).join(" ") ?? "";
  const lastName = suppliedLast ?? pieces.at(-1) ?? "";
  if (!firstName || !lastName) {
    throw new HttpError(400, "The patient must have a first and last name");
  }
  if (firstName.length > 100 || lastName.length > 100) {
    throw new HttpError(400, "The patient name is too long");
  }
  return { firstName, lastName };
}

function terminalRequestStatus(current: string) {
  if (current === "consultation_completed" || current === "consultation_scheduled") {
    return current;
  }
  return "account_activation_pending";
}

function makePatientNumber() {
  const date = new Date().toISOString().slice(0, 10).replaceAll("-", "");
  return `CNPH-PAT-${date}-${crypto.randomUUID().slice(0, 8).toUpperCase()}`;
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

function relationName(value: unknown) {
  const relation = Array.isArray(value) ? value[0] : value;
  if (!relation || typeof relation !== "object") return "";
  return String((relation as Record<string, unknown>).role_name ?? "");
}

function requiredString(body: Record<string, unknown>, key: string, max: number) {
  const value = typeof body[key] === "string" ? body[key].trim() : "";
  if (!value) throw new HttpError(400, `${key} is required`);
  if (value.length > max) throw new HttpError(400, `${key} is too long`);
  return value;
}

function optionalString(body: Record<string, unknown>, key: string, max: number) {
  if (body[key] == null || body[key] === "") return null;
  return requiredString(body, key, max);
}

function optionalBirthDate(body: Record<string, unknown>) {
  const value = optionalString(body, "birth_date", 10);
  if (!value) return null;
  if (!/^\d{4}-\d{2}-\d{2}$/.test(value)) {
    throw new HttpError(400, "birth_date must use YYYY-MM-DD format");
  }
  const parsed = new Date(`${value}T00:00:00.000Z`);
  if (Number.isNaN(parsed.getTime()) || parsed.toISOString().slice(0, 10) !== value) {
    throw new HttpError(400, "birth_date is invalid");
  }
  if (value > new Date().toISOString().slice(0, 10)) {
    throw new HttpError(400, "birth_date cannot be in the future");
  }
  return value;
}

function optionalSex(body: Record<string, unknown>) {
  const value = optionalString(body, "sex", 30);
  if (!value) return null;
  if (!["male", "female", "intersex", "prefer_not_to_say"].includes(value)) {
    throw new HttpError(400, "sex is invalid");
  }
  return value;
}

function optionalMobile(body: Record<string, unknown>) {
  const value = optionalString(body, "mobile_number", 30);
  if (!value) return null;
  const digits = value.replace(/\D/g, "");
  if (digits.length < 7 || digits.length > 15) {
    throw new HttpError(400, "mobile_number is invalid");
  }
  return value;
}

function requiredUuid(body: Record<string, unknown>, key: string) {
  const value = requiredString(body, key, 36);
  if (!uuidPattern.test(value)) {
    throw new HttpError(400, `${key} must be a valid identifier`);
  }
  return value;
}

function optionalUuid(body: Record<string, unknown>, key: string) {
  return body[key] == null || body[key] === "" ? null : requiredUuid(body, key);
}

function requiredEmail(body: Record<string, unknown>) {
  const email = requiredString(body, "email", 320).toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email)) {
    throw new HttpError(400, "A valid email is required");
  }
  return email;
}

function normalizeEmail(value: string) {
  return value.trim().toLowerCase();
}

function normalizeMobile(value: string) {
  const digits = value.replace(/\D/g, "");
  if (!digits) return "";
  if (digits.startsWith("63") && digits.length === 12) return `0${digits.slice(2)}`;
  if (digits.startsWith("9") && digits.length === 10) return `0${digits}`;
  return digits;
}

function requiredPassword(body: Record<string, unknown>) {
  const value = requiredString(body, "password", 200);
  if (value.length < 12 || !/[a-z]/.test(value) || !/[A-Z]/.test(value) ||
    !/[0-9]/.test(value) || !/[^A-Za-z0-9]/.test(value)) {
    throw new HttpError(
      400,
      "Password must be at least 12 characters and include upper-case, lower-case, number, and symbol characters",
    );
  }
  return value;
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
    if (error) console.error("Could not record care workflow security event", error);
  } catch (logError) {
    console.error("Could not record care workflow security event", logError);
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
