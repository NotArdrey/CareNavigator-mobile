-- Transactional acceptance checks for multi-hospital authorization.
-- Run with a privileged test connection. No fixture survives the rollback.

begin;

do $test$
declare
  source_record public.medical_records;
  doctor_b public.doctors;
  doctor_b_auth uuid;
  doctor_a public.doctors;
  doctor_a_auth uuid;
  admin_auth uuid;
  relationship_id uuid;
  consent_id uuid;
  external_grant public.patient_access_grants;
  original_grant_created_at timestamptz;
  original_grant_expires_at timestamptz;
begin
  select * into source_record
  from public.medical_records
  order by created_at
  limit 1;
  if source_record.id is null then
    raise exception 'Acceptance fixture requires one sourced medical record';
  end if;

  select doctor.* into doctor_b
  from public.doctors doctor
  join public.doctor_hospital_employments employment
    on employment.doctor_id = doctor.id
   and employment.hospital_id = doctor.hospital_id
  where doctor.hospital_id <> source_record.hospital_id
    and employment.employment_status = 'active'
    and employment.is_verified
    and (employment.ends_at is null or employment.ends_at > now())
  order by doctor.created_at
  limit 1;
  if doctor_b.id is null then
    raise exception 'Acceptance fixture requires an active doctor at Hospital B';
  end if;
  select app_user.auth_user_id into doctor_b_auth
  from public.users app_user
  where app_user.id = doctor_b.user_id;

  select doctor.* into doctor_a
  from public.doctors doctor
  join public.doctor_hospital_employments employment
    on employment.doctor_id = doctor.id
   and employment.hospital_id = doctor.hospital_id
  where doctor.hospital_id = source_record.hospital_id
    and employment.employment_status = 'active'
    and employment.is_verified
  order by doctor.created_at
  limit 1;
  select app_user.auth_user_id into doctor_a_auth
  from public.users app_user
  where app_user.id = doctor_a.user_id;

  select app_user.auth_user_id into admin_auth
  from public.users app_user
  join public.roles role on role.id = app_user.role_id
  where role.role_name = 'hospital_admin'
    and app_user.hospital_id = doctor_b.hospital_id
  order by app_user.created_at
  limit 1;

  insert into public.patient_care_relationships(
    patient_id, hospital_id, doctor_id, relationship_type, purpose,
    status, requested_at, expires_at, created_by
  ) values (
    source_record.patient_id, doctor_b.hospital_id, doctor_b.id,
    'second_opinion', 'transactional_acceptance_test', 'requested',
    now(), now() + interval '7 days', doctor_b.user_id
  ) returning id into relationship_id;

  insert into public.patient_consents(
    patient_id, consent_type, consent_version, is_granted, granted_at,
    captured_by, metadata, care_relationship_id, source_hospital_id,
    receiving_hospital_id, purpose, categories, permitted_actions,
    record_selection_mode, expires_at, granted_by, version_sequence
  ) values (
    source_record.patient_id, 'transactional_acceptance_test',
    relationship_id::text, true, now(), doctor_b_auth,
    jsonb_build_object('transactional_test', true),
    relationship_id, source_record.hospital_id, doctor_b.hospital_id,
    'transactional_acceptance_test', array['medical_records']::text[],
    array['view', 'download', 'create']::text[], 'categories',
    now() + interval '7 days', doctor_b.user_id, 1
  ) returning id into consent_id;

  perform private.activate_relationship_access(
    relationship_id, consent_id, doctor_b.id, null, '[]'::jsonb
  );
  select * into external_grant
  from public.patient_access_grants grant_row
  where grant_row.care_relationship_id = relationship_id
    and grant_row.source_hospital_id = source_record.hospital_id
    and grant_row.receiving_hospital_id = doctor_b.hospital_id
    and grant_row.external_read_only;
  if external_grant.id is null then
    raise exception 'Hospital B external read-only grant was not created';
  end if;

  perform set_config('request.jwt.claim.sub', doctor_b_auth::text, true);
  if not private.can_access_clinical_record(
    source_record.patient_id, source_record.hospital_id,
    'medical_records', source_record.id, 'view'
  ) then
    raise exception 'Hospital B could not view the explicitly consented Hospital A record';
  end if;
  if private.can_access_clinical_record(
    source_record.patient_id, source_record.hospital_id,
    'diagnoses', gen_random_uuid(), 'view'
  ) then
    raise exception 'Hospital B could view a category excluded from patient consent';
  end if;
  if private.can_access_clinical_record(
    source_record.patient_id, source_record.hospital_id,
    'medical_records', source_record.id, 'create'
  ) then
    raise exception 'Hospital B received write authority over Hospital A provenance';
  end if;
  if not private.can_access_clinical_record(
    source_record.patient_id, doctor_b.hospital_id,
    'medical_records', null, 'create'
  ) then
    raise exception 'Hospital B could not create its own separately sourced record';
  end if;

  if doctor_a_auth is not null then
    perform set_config('request.jwt.claim.sub', doctor_a_auth::text, true);
    if private.can_access_clinical_record(
      source_record.patient_id, doctor_b.hospital_id,
      'medical_records', gen_random_uuid(), 'view'
    ) then
      raise exception 'Hospital A inherited access to a Hospital B record';
    end if;
  end if;

  if admin_auth is not null then
    perform set_config('request.jwt.claim.sub', admin_auth::text, true);
    if private.can_access_clinical_record(
      source_record.patient_id, source_record.hospital_id,
      'medical_records', source_record.id, 'view'
    ) then
      raise exception 'Hospital administrator received clinical-record access';
    end if;
  end if;

  perform set_config('request.jwt.claim.sub', doctor_b_auth::text, true);
  update public.patient_consents
  set is_granted = false,
      revoked_at = now(), revocation_reason = 'transactional test'
  where id = consent_id;
  if private.can_access_clinical_record(
    source_record.patient_id, source_record.hospital_id,
    'medical_records', source_record.id, 'view'
  ) then
    raise exception 'Revoked consent still authorized Hospital B';
  end if;
  update public.patient_consents
  set is_granted = true,
      revoked_at = null, revocation_reason = null
  where id = consent_id;

  original_grant_created_at := external_grant.created_at;
  original_grant_expires_at := external_grant.expires_at;
  update public.patient_access_grants
  set created_at = now() - interval '2 days',
      expires_at = now() - interval '1 day'
  where id = external_grant.id;
  if private.can_access_clinical_record(
    source_record.patient_id, source_record.hospital_id,
    'medical_records', source_record.id, 'view'
  ) then
    raise exception 'Expired grant still authorized Hospital B';
  end if;
  update public.patient_access_grants
  set created_at = original_grant_created_at,
      expires_at = original_grant_expires_at
  where id = external_grant.id;

  update public.doctor_hospital_employments
  set employment_status = 'ended', ends_at = now(),
      termination_reason = 'transactional acceptance test'
  where doctor_id = doctor_b.id and hospital_id = doctor_b.hospital_id;
  if private.can_access_clinical_record(
    source_record.patient_id, source_record.hospital_id,
    'medical_records', source_record.id, 'view'
  ) then
    raise exception 'Ended Hospital B employment still authorized the record';
  end if;

  update public.doctor_hospital_employments
  set employment_status = 'active', ends_at = null, termination_reason = null
  where doctor_id = doctor_b.id and hospital_id = doctor_b.hospital_id;
  update public.doctor_patient_assignments
  set assignment_status = 'ended', ended_at = now(),
      ended_reason = 'Transactional assignment removal test'
  where care_relationship_id = relationship_id
    and doctor_id = doctor_b.id
    and assignment_status = 'active'
    and ended_at is null;
  if private.can_access_clinical_record(
    source_record.patient_id, source_record.hospital_id,
    'medical_records', source_record.id, 'view'
  ) then
    raise exception 'Removed doctor assignment still authorized Hospital B';
  end if;

  insert into public.emergency_access_events(
    patient_id, hospital_id, doctor_id, reason, categories,
    status, started_at, expires_at
  ) values (
    source_record.patient_id, doctor_b.hospital_id, doctor_b.id,
    'Transactional emergency access acceptance test',
    array['medical_records']::text[], 'active', now(), now() + interval '15 minutes'
  );
  if not private.can_access_clinical_record(
    source_record.patient_id, source_record.hospital_id,
    'medical_records', source_record.id, 'view'
  ) then
    raise exception 'Audited short-lived emergency view access was not honored';
  end if;
  if private.can_access_clinical_record(
    source_record.patient_id, source_record.hospital_id,
    'medical_records', source_record.id, 'create'
  ) then
    raise exception 'Emergency access incorrectly authorized record creation';
  end if;
end
$test$;

rollback;
