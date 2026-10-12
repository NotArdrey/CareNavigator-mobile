-- Online guest reservations require hospital confirmation; NULL cannot authorize review.
CREATE OR REPLACE FUNCTION public.review_guest_consultation(target_request_id uuid, decision text, target_doctor_id uuid DEFAULT NULL::uuid, target_appointment_date timestamp with time zone DEFAULT NULL::timestamp with time zone, review_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  request_row public.guest_consultation_requests;
  normalized_decision text := lower(btrim(coalesce(decision, '')));
  chosen_doctor uuid;
  scheduled_time timestamptz;
  target_type public.consultation_type;
  temporary_patient_id uuid;
  created_consultation_id uuid;
  relationship_id uuid;
  consent_id uuid;
begin
  if not (
    private.has_permission('patients.manage')
    or private.has_permission('hospital.manage')
  ) then
    raise exception 'Guest consultation review permission is required';
  end if;

  select * into request_row
  from public.guest_consultation_requests
  where id = target_request_id
  for update;
  if not found then
    raise exception 'Guest consultation request was not found';
  end if;
  if not coalesce(private.is_hospital_admin_for(request_row.preferred_hospital_id) or request_row.assigned_doctor_id = private.current_doctor_id(), false) then
    raise exception 'Not authorized to review this request';
  end if;
  if request_row.request_status in (
    'rejected', 'consultation_scheduled', 'consultation_completed', 'cancelled'
  ) then
    raise exception 'This request is already in a terminal or scheduled state';
  end if;
  if normalized_decision not in ('approved', 'rejected') then
    raise exception 'Decision must be approved or rejected';
  end if;

  if normalized_decision = 'rejected' then
    if nullif(btrim(review_notes), '') is null then
      raise exception 'A rejection reason is required';
    end if;
    update public.guest_consultation_requests
    set request_status = 'rejected',
        reviewed_by = private.current_user_id(),
        reviewed_at = now(),
        rejection_reason = btrim(review_notes),
        identity_review_notes = btrim(review_notes),
        updated_at = now()
    where id = target_request_id;
    return jsonb_build_object(
      'request_id', target_request_id,
      'patient_id', null,
      'consultation_id', null,
      'status', 'rejected'
    );
  end if;

  chosen_doctor := coalesce(
    target_doctor_id, request_row.assigned_doctor_id, private.current_doctor_id()
  );
  scheduled_time := coalesce(
    target_appointment_date, request_row.preferred_schedule
  );
  target_type := case request_row.preferred_consultation_type
    when 'face_to_face'::public.consultation_type
      then 'face_to_face'::public.consultation_type
    else 'guest_online'::public.consultation_type
  end;

  if target_type='guest_online' and not private.is_hospital_admin_for(request_row.preferred_hospital_id) then
    raise exception 'Hospital confirmation is required for every new online guest appointment';
  end if;
  if chosen_doctor is null
    or scheduled_time is null
    or scheduled_time <= now() then
    raise exception 'An available doctor and future appointment time are required';
  end if;
  if not exists (
    select 1
    from public.doctors doctor
    join public.doctor_hospital_employments employment
      on employment.doctor_id = doctor.id
     and employment.hospital_id = request_row.preferred_hospital_id
    where doctor.id = chosen_doctor
      and doctor.hospital_id = request_row.preferred_hospital_id
      and (
        request_row.preferred_department_id is null
        or doctor.department_id = request_row.preferred_department_id
      )
      and doctor.availability_status <> 'unavailable'
      and employment.employment_status = 'active'
      and employment.is_verified
      and employment.starts_at <= now()
      and (employment.ends_at is null or employment.ends_at > now())
  ) then
    raise exception 'The selected doctor is not verified and active for this hospital';
  end if;

  perform private.lock_doctor_schedule(chosen_doctor);
  if not private.is_doctor_slot_available(
    chosen_doctor, request_row.preferred_hospital_id,
    target_type, scheduled_time, null
  ) then
    raise exception 'The selected appointment slot is unavailable';
  end if;

  select id into temporary_patient_id
  from public.patients
  where guest_request_id = target_request_id;
  if temporary_patient_id is null then
    select p.id into temporary_patient_id from public.patients p
    join public.users u on u.id=p.user_id join auth.users a on a.id=u.auth_user_id
    where a.id=request_row.submitted_by and a.email_confirmed_at is not null
      and lower(a.email)=lower(request_row.email);
  end if;
  if temporary_patient_id is null then
    insert into public.patients(
      created_by_doctor, guest_request_id, primary_hospital_id,
      allergies, existing_conditions, identity_verification_status,
      account_activation_status, converted_from_guest, profile_status
    ) values (
      chosen_doctor, target_request_id, request_row.preferred_hospital_id,
      request_row.allergies, request_row.existing_conditions, 'verified',
      'pending', true, 'temporary'
    ) returning id into temporary_patient_id;
  end if;

  insert into public.patient_hospital_identifiers(
    patient_id, hospital_id, local_mrn, status, verified_at
  ) values (
    temporary_patient_id, request_row.preferred_hospital_id,
    request_row.reference_number, 'active', now()
  )
  on conflict (patient_id, hospital_id) do update
    set status = 'active',
        verified_at = coalesce(
          public.patient_hospital_identifiers.verified_at, excluded.verified_at
        ),
        updated_at = now();

  insert into public.patient_care_relationships(
    patient_id, hospital_id, doctor_id, relationship_type, purpose,
    status, requested_at, expires_at, created_by
  ) values (
    temporary_patient_id, request_row.preferred_hospital_id,
    chosen_doctor, 'consultation', 'reviewed_guest_consultation',
    'requested', now(), greatest(
      scheduled_time + interval '7 days', now() + interval '30 days'
    ), private.current_user_id()
  ) returning id into relationship_id;

  insert into public.patient_consents(
    patient_id, consent_type, consent_version, is_granted, granted_at,
    captured_by, metadata, care_relationship_id, source_hospital_id,
    receiving_hospital_id, purpose, categories, permitted_actions,
    record_selection_mode, expires_at, granted_by, version_sequence
  ) values (
    temporary_patient_id, 'guest_consultation_access',
    relationship_id::text, request_row.consent_at is not null,
    request_row.consent_at, (select auth.uid()),
    jsonb_build_object(
      'guest_request_id', request_row.id,
      'reference_number', request_row.reference_number,
      'consent_captured_during_submission', true
    ),
    relationship_id, request_row.preferred_hospital_id,
    request_row.preferred_hospital_id, 'reviewed_guest_consultation',
    array[
      'consultations', 'medical_records', 'diagnoses', 'prescriptions',
      'laboratory_requests', 'laboratory_results', 'medical_documents',
      'clinical_notes', 'allergies_medications', 'treatment_plans'
    ]::text[],
    array['view', 'download', 'create']::text[], 'categories',
    greatest(scheduled_time + interval '7 days', now() + interval '30 days'),
    private.current_user_id(), 1
  ) returning id into consent_id;

  if request_row.consent_at is null then
    raise exception 'Recorded guest consent is required before approval';
  end if;

  insert into public.consultations(
    patient_id, guest_request_id, doctor_id, hospital_id, department_id,
    consultation_type, appointment_date, status, chief_complaint,
    approved_by, approved_at
  ) values (
    temporary_patient_id, target_request_id, chosen_doctor,
    request_row.preferred_hospital_id, request_row.preferred_department_id,
    target_type, scheduled_time, 'scheduled',
    request_row.consultation_reason, private.current_user_id(), now()
  ) returning id into created_consultation_id;

  update public.patient_care_relationships
  set consultation_id = created_consultation_id, updated_at = now()
  where id = relationship_id;
  perform private.activate_relationship_access(
    relationship_id, consent_id, chosen_doctor,
    created_consultation_id, '[]'::jsonb
  );

  update public.guest_consultation_requests
  set request_status = 'consultation_scheduled',
      assigned_doctor_id = chosen_doctor,
      reviewed_by = private.current_user_id(),
      reviewed_at = now(),
      identity_review_status = 'verified',
      identity_review_notes = nullif(btrim(review_notes), ''),
      updated_at = now()
  where id = target_request_id;

  return jsonb_build_object(
    'request_id', target_request_id,
    'reference_number', request_row.reference_number,
    'patient_id', temporary_patient_id,
    'consultation_id', created_consultation_id,
    'status', 'consultation_scheduled'
  );
end
$function$
;
