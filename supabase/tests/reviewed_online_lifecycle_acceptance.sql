-- Transactional acceptance checks for the reviewed online lifecycle.
-- Run with a privileged test connection. No fixture survives the rollback.

begin;

do $test$
declare
  patient_row public.patients;
  patient_user public.users;
  hospital_row public.hospitals;
  doctor_row public.doctors;
  admin_auth uuid;
  doctor_auth uuid;
  preferred_time timestamptz;
  request_id uuid;
  conflict_request_id uuid;
  request_row public.online_consultation_requests;
  consultation_before bigint;
  consultation_after bigint;
  video_url text;
  conflict_rejected boolean := false;
begin
  select patient.*
  into patient_row
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where app_user.account_status = 'active'
    and nullif(btrim(app_user.mobile_number), '') is not null
    and nullif(btrim(app_user.first_name), '') is not null
    and nullif(btrim(app_user.last_name), '') is not null
  order by patient.created_at
  limit 1;
  if patient_row.id is null then
    raise exception 'Acceptance fixture requires an active patient with a registered phone';
  end if;
  select * into patient_user
  from public.users app_user
  where app_user.id = patient_row.user_id;

  select hospital.* into hospital_row
  from public.hospitals hospital
  where hospital.online_request_workflow_enabled
    and hospital.verification_status = 'verified'
    and hospital.operating_status in ('open', 'limited')
  order by hospital.created_at
  limit 1;

  select doctor.* into doctor_row
  from public.doctors doctor
  join public.doctor_hospital_employments employment
    on employment.doctor_id = doctor.id
   and employment.hospital_id = doctor.hospital_id
  where doctor.hospital_id = hospital_row.id
    and doctor.department_id is not null
    and doctor.availability_status <> 'unavailable'
    and employment.employment_status = 'active'
    and employment.is_verified
    and (employment.ends_at is null or employment.ends_at > now())
  order by doctor.created_at
  limit 1;

  select app_user.auth_user_id into admin_auth
  from public.users app_user
  join public.roles role on role.id = app_user.role_id
  where role.role_name = 'hospital_admin'
    and app_user.hospital_id = hospital_row.id
    and app_user.account_status = 'active'
  order by app_user.created_at
  limit 1;
  if hospital_row.id is null or doctor_row.id is null or admin_auth is null then
    raise exception 'Acceptance fixture requires the pilot hospital, doctor, department, and administrator';
  end if;
  select app_user.auth_user_id into doctor_auth
  from public.users app_user
  where app_user.id = doctor_row.user_id;
  if doctor_auth is null then
    raise exception 'Acceptance fixture requires an authenticated doctor account';
  end if;

  perform set_config('request.jwt.claim.sub', patient_user.auth_user_id::text, true);
  select slot.starts_at into preferred_time
  from public.list_available_consultation_slots(
    doctor_row.id, 'online'::public.consultation_type, 60
  ) slot
  order by slot.starts_at
  limit 1;
  if preferred_time is null then
    raise exception 'Acceptance fixture requires one published online preference';
  end if;

  select count(*) into consultation_before from public.consultations;
  request_id := public.book_consultation(jsonb_build_object(
    'doctor_id', doctor_row.id,
    'hospital_id', hospital_row.id,
    'consultation_type', 'online',
    'appointment_date', preferred_time,
    'chief_complaint', 'Transactional reviewed online request test',
    'symptom_duration', 'Two days',
    'shared_categories', jsonb_build_array(
      'consultations', 'medical_records', 'diagnoses',
      'prescriptions', 'laboratory_results', 'medical_documents'
    )
  ));
  select * into request_row
  from public.online_consultation_requests
  where id = request_id;
  if request_row.id is null
    or request_row.request_status <> 'submitted'
    or request_row.official_consultation_id is not null then
    raise exception 'Online submission did not create the expected reviewed request';
  end if;
  if exists (
    select 1 from public.patient_access_grants grant_row
    where grant_row.care_relationship_id = request_row.care_relationship_id
      and grant_row.status = 'active'
      and grant_row.revoked_at is null
  ) then
    raise exception 'A pending online request activated clinical-history access';
  end if;
  if request_row.patient_id is distinct from patient_row.id
    or request_row.submitted_by is distinct from patient_user.id
    or request_row.profile_first_name is distinct from patient_user.first_name
    or request_row.profile_last_name is distinct from patient_user.last_name
    or request_row.profile_email is distinct from patient_user.email
    or request_row.phone_number_snapshot is distinct from patient_user.mobile_number
    or request_row.birth_date_snapshot is distinct from patient_user.birth_date
    or request_row.address_snapshot is distinct from patient_user.address then
    raise exception 'Online submission did not source identity and phone from the authenticated profile';
  end if;
  select count(*) into consultation_after from public.consultations;
  if consultation_after <> consultation_before then
    raise exception 'Online submission created or reserved an official consultation too early';
  end if;
  if not private.is_doctor_slot_available(
    doctor_row.id, hospital_row.id,
    'online'::public.consultation_type, preferred_time, null
  ) then
    raise exception 'Preferred online submission reserved the doctor slot';
  end if;

  perform set_config('request.jwt.claim.sub', admin_auth::text, true);
  perform public.review_online_consultation_request(
    request_id, 'confirmed', doctor_row.id, preferred_time, 'video',
    'Transactional hospital acceptance'
  );
  select * into request_row
  from public.online_consultation_requests
  where id = request_id;
  if request_row.request_status <> 'confirmed'
    or request_row.official_consultation_id is null then
    raise exception 'Hospital acceptance did not create the official consultation';
  end if;
  if not exists (
    select 1 from public.patient_access_grants grant_row
    where grant_row.care_relationship_id = request_row.care_relationship_id
      and grant_row.status = 'active'
      and grant_row.revoked_at is null
      and grant_row.expires_at > now()
  ) then
    raise exception 'Hospital acceptance did not activate the authorized access grant';
  end if;
  if not exists (
    select 1 from public.consultations consultation
    where consultation.id = request_row.official_consultation_id
      and consultation.consultation_type = 'online'
      and consultation.status = 'scheduled'
      and consultation.doctor_id = doctor_row.id
      and consultation.hospital_id = hospital_row.id
      and consultation.appointment_date = preferred_time
  ) then
    raise exception 'Official consultation did not preserve the confirmed hospital, doctor, time, and mode';
  end if;
  if private.is_doctor_slot_available(
    doctor_row.id, hospital_row.id,
    'online'::public.consultation_type, preferred_time, null
  ) then
    raise exception 'Confirmed official consultation did not reserve the slot';
  end if;

  perform set_config('request.jwt.claim.sub', doctor_auth::text, true);
  perform public.get_consultation_patient_context(
    request_row.official_consultation_id
  );
  if not exists (
    select 1 from public.medical_record_access_logs access_log
    where access_log.actor_user_id = doctor_row.user_id
      and access_log.resource_type = 'consultation_patient_context'
      and access_log.resource_id = request_row.official_consultation_id
      and access_log.access_type = 'view'
      and access_log.success
  ) then
    raise exception 'Authorized clinician context access was not audit logged';
  end if;

  perform set_config('request.jwt.claim.sub', patient_user.auth_user_id::text, true);
  conflict_request_id := public.book_consultation(jsonb_build_object(
    'doctor_id', doctor_row.id,
    'hospital_id', hospital_row.id,
    'consultation_type', 'online',
    'appointment_date', preferred_time,
    'chief_complaint', 'Transactional conflicting preference test',
    'symptom_duration', 'Two days',
    'shared_categories', jsonb_build_array('consultations')
  ));
  perform set_config('request.jwt.claim.sub', admin_auth::text, true);
  begin
    perform public.review_online_consultation_request(
      conflict_request_id, 'confirmed', doctor_row.id,
      preferred_time, 'call', 'Expected conflict'
    );
  exception when others then
    conflict_rejected := true;
  end;
  if not conflict_rejected then
    raise exception 'A second request confirmed an already occupied doctor slot';
  end if;
  if exists (
    select 1 from public.online_consultation_requests request
    where request.id = conflict_request_id
      and request.official_consultation_id is not null
  ) then
    raise exception 'Conflicting request retained an official consultation';
  end if;
  perform public.review_online_consultation_request(
    conflict_request_id, 'rejected', null, null, null,
    'Transactional rejection after schedule conflict'
  );
  if not exists (
    select 1
    from public.online_consultation_requests request
    where request.id = conflict_request_id
      and request.request_status = 'rejected'
      and request.official_consultation_id is null
      and not exists (
        select 1 from public.patient_access_grants grant_row
        where grant_row.care_relationship_id = request.care_relationship_id
          and grant_row.status = 'active'
          and grant_row.revoked_at is null
      )
  ) then
    raise exception 'Rejected request created an appointment or clinical-history access';
  end if;

  -- Preparing a server-approved room is distinct from joining it. Once ready,
  -- the patient can obtain the room during the join window before the doctor
  -- has joined.
  update public.consultations
  set appointment_date = now() + interval '5 minutes'
  where id = request_row.official_consultation_id;
  perform set_config('request.jwt.claim.sub', doctor_auth::text, true);
  perform public.ensure_video_session(request_row.official_consultation_id, 'jitsi');
  perform set_config('request.jwt.claim.sub', patient_user.auth_user_id::text, true);
  select public.get_approved_video_room(request_row.official_consultation_id)
  into video_url;
  if video_url !~ '^https://meet[.]jit[.]si/cnph-[0-9a-f]{32}$' then
    raise exception 'Patient could not join a prepared room before the doctor joined';
  end if;

  perform public.cancel_online_consultation_request(
    request_id, 'Transactional patient cancellation'
  );
  if not exists (
    select 1
    from public.online_consultation_requests request
    join public.consultations consultation
      on consultation.id = request.official_consultation_id
    join public.patient_care_relationships relationship
      on relationship.id = request.care_relationship_id
    where request.id = request_id
      and request.request_status = 'cancelled'
      and consultation.status = 'cancelled'
      and relationship.status = 'revoked'
      and not exists (
        select 1 from public.patient_access_grants grant_row
        where grant_row.care_relationship_id = relationship.id
          and grant_row.status = 'active'
          and grant_row.revoked_at is null
      )
  ) then
    raise exception 'Patient cancellation did not revoke the request, appointment, and access';
  end if;
  if not exists (
    select 1
    from public.online_consultation_request_status_history history
    where history.request_id = request_row.id and history.to_status = 'submitted'
  ) or not exists (
    select 1
    from public.online_consultation_request_status_history history
    where history.request_id = request_row.id and history.to_status = 'confirmed'
  ) or not exists (
    select 1
    from public.online_consultation_request_status_history history
    where history.request_id = request_row.id and history.to_status = 'cancelled'
  ) or not exists (
    select 1
    from public.audit_logs audit
    where audit.module = 'online_consultation_requests'
      and audit.record_id = request_row.id
  ) then
    raise exception 'Reviewed-online sensitive actions were not recorded in status and audit history';
  end if;
end
$test$;

rollback;
