-- Transactional acceptance checks for email consultation confirmation.
-- Run with a privileged test connection. No fixture or email survives rollback.

begin;

do $test$
declare
  patient_row public.patients;
  patient_user public.users;
  hospital_row public.hospitals;
  doctor_row public.doctors;
  admin_auth uuid;
  preferred_time timestamptz;
  request_id uuid;
begin
  select patient.*
  into patient_row
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where app_user.account_status = 'active'
    and nullif(btrim(app_user.email), '') is not null
    and nullif(btrim(app_user.mobile_number), '') is not null
    and nullif(btrim(app_user.first_name), '') is not null
    and nullif(btrim(app_user.last_name), '') is not null
  order by patient.created_at
  limit 1;
  if patient_row.id is null then
    raise exception 'Acceptance fixture requires an active patient with a registered email';
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
    raise exception 'Acceptance fixture requires a pilot hospital, doctor, and administrator';
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

  request_id := public.book_consultation(jsonb_build_object(
    'doctor_id', doctor_row.id,
    'hospital_id', hospital_row.id,
    'consultation_type', 'online',
    'appointment_date', preferred_time,
    'chief_complaint', 'Transactional email delivery test',
    'symptom_duration', 'Three days',
    'shared_categories', jsonb_build_array('consultations')
  ));

  perform set_config('request.jwt.claim.sub', admin_auth::text, true);
  perform public.review_online_consultation_request(
    request_id, 'confirmed', doctor_row.id, preferred_time, 'email',
    'Transactional email confirmation'
  );

  if not exists (
    select 1
    from public.online_consultation_requests request
    where request.id = request_id
      and request.request_status = 'confirmed'
      and request.consultation_channel = 'email'
      and request.official_consultation_id is not null
  ) then
    raise exception 'Email-channel review did not confirm the online request';
  end if;

  if not exists (
    select 1
    from public.notifications notification
    join public.notification_outbox outbox
      on outbox.notification_id = notification.id
    where notification.user_id = patient_user.auth_user_id
      and notification.dedupe_key =
        'online-consultation-confirmed-email:' || request_id::text
      and notification.data ->> 'consultation_channel' = 'email'
      and outbox.user_id = patient_user.auth_user_id
      and outbox.channel = 'email'
      and outbox.status = 'pending'
  ) then
    raise exception 'Email-channel confirmation was not queued for SMTP delivery';
  end if;
end
$test$;

rollback;
