-- Transactional guest review and persistent tracking acceptance check.

begin;

do $test$
declare
  guest_auth uuid;
  admin_auth uuid;
  hospital_row public.hospitals;
  doctor_row public.doctors;
  department_id uuid;
  preferred_time timestamptz;
  request_id uuid;
  reference_number text := 'GST-TEST-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
  review_result jsonb;
  tracking_result jsonb;
  created_consultation_id uuid;
  temporary_patient_id uuid;
  consultation_before bigint;
begin
  select app_user.auth_user_id into guest_auth
  from public.users app_user
  join public.roles role on role.id = app_user.role_id
  where role.role_name = 'guest'
    and app_user.account_status = 'active'
  order by app_user.created_at
  limit 1;

  select hospital.* into hospital_row
  from public.hospitals hospital
  where hospital.online_request_workflow_enabled
  order by hospital.created_at
  limit 1;
  select doctor.* into doctor_row
  from public.doctors doctor
  join public.doctor_hospital_employments employment
    on employment.doctor_id = doctor.id
   and employment.hospital_id = doctor.hospital_id
  where doctor.hospital_id = hospital_row.id
    and doctor.department_id is not null
    and employment.employment_status = 'active'
    and employment.is_verified
  order by doctor.created_at
  limit 1;
  department_id := doctor_row.department_id;

  select app_user.auth_user_id into admin_auth
  from public.users app_user
  join public.roles role on role.id = app_user.role_id
  where role.role_name = 'hospital_admin'
    and app_user.hospital_id = hospital_row.id
    and app_user.account_status = 'active'
  order by app_user.created_at
  limit 1;
  if guest_auth is null or admin_auth is null or doctor_row.id is null then
    raise exception 'Acceptance fixture requires guest, pilot administrator, and doctor accounts';
  end if;

  select slot.starts_at into preferred_time
  from public.list_available_consultation_slots(
    doctor_row.id, 'guest_online'::public.consultation_type, 60
  ) slot
  order by slot.starts_at
  limit 1;
  if preferred_time is null then
    raise exception 'Guest online intake did not expose published online slots';
  end if;

  select count(*) into consultation_before from public.consultations;
  insert into public.guest_consultation_requests(
    submitted_by, reference_number, full_name, first_name, last_name,
    birth_date, sex, mobile_number, email, address,
    symptoms, symptom_duration, consultation_reason,
    preferred_hospital_id, preferred_department_id,
    preferred_consultation_type, preferred_schedule,
    otp_verified_at, consent_at, request_status
  ) values (
    guest_auth, reference_number, 'Transactional Guest', 'Transactional', 'Guest',
    date '1990-01-01', 'male', '+639171234567', 'guest-transaction@example.test',
    'Transactional test address', 'Persistent cough for transactional testing',
    'Three days', 'Persistent cough for transactional testing',
    hospital_row.id, department_id, 'guest_online', preferred_time,
    now(), now(), 'otp_verified'
  ) returning id into request_id;
  if (select count(*) from public.consultations) <> consultation_before then
    raise exception 'Guest request created an official consultation before review';
  end if;

  perform set_config('request.jwt.claim.sub', admin_auth::text, true);
  review_result := public.review_guest_consultation(
    request_id, 'approved', doctor_row.id, preferred_time,
    'Transactional identity and hospital review'
  );
  created_consultation_id := nullif(review_result->>'consultation_id', '')::uuid;
  temporary_patient_id := nullif(review_result->>'patient_id', '')::uuid;
  if created_consultation_id is null or temporary_patient_id is null then
    raise exception 'Guest approval did not create linked patient and consultation records';
  end if;
  if not exists (
    select 1
    from public.consultations consultation
    join public.patient_care_relationships relationship
      on relationship.consultation_id = consultation.id
    join public.doctor_patient_assignments assignment
      on assignment.care_relationship_id = relationship.id
    join public.patient_access_grants grant_row
      on grant_row.care_relationship_id = relationship.id
    where consultation.id = created_consultation_id
      and consultation.patient_id = temporary_patient_id
      and consultation.guest_request_id = request_id
      and consultation.status = 'scheduled'
      and relationship.status = 'active'
      and assignment.hospital_id = hospital_row.id
      and assignment.assignment_status = 'active'
      and assignment.ended_at is null
      and grant_row.status = 'active'
      and grant_row.expires_at > now()
  ) then
    raise exception 'Guest approval did not activate the provenance-scoped care relationship';
  end if;

  perform set_config('request.jwt.claim.sub', guest_auth::text, true);
  tracking_result := public.get_guest_consultation_request_tracking(reference_number);
  if tracking_result->>'status' <> 'consultation_scheduled'
    or nullif(tracking_result->>'consultation_id', '')::uuid is distinct from created_consultation_id then
    raise exception 'Guest request was not persistently trackable after approval';
  end if;
end
$test$;

rollback;
