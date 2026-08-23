-- Face-to-face booking must retain the original immediate reservation path,
-- even at a hospital where the reviewed-online flag is enabled.

begin;

do $test$
declare
  patient_row public.patients;
  patient_user public.users;
  doctor_row public.doctors;
  hospital_row public.hospitals;
  appointment_time timestamptz;
  consultation_id uuid;
  consultation_row public.consultations;
  consultation_before bigint;
  online_before bigint;
begin
  select patient.* into patient_row
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where app_user.account_status = 'active'
    and nullif(btrim(app_user.mobile_number), '') is not null
  order by patient.created_at
  limit 1;
  select * into patient_user
  from public.users app_user
  where app_user.id = patient_row.user_id;

  select doctor.*
  into doctor_row
  from public.doctors doctor
  join public.hospitals hospital on hospital.id = doctor.hospital_id
  join public.doctor_hospital_employments employment
    on employment.doctor_id = doctor.id
   and employment.hospital_id = hospital.id
  where hospital.online_request_workflow_enabled
    and employment.employment_status = 'active'
    and employment.is_verified
    and (employment.ends_at is null or employment.ends_at > now())
    and exists (
      select 1
      from public.list_available_consultation_slots(
        doctor.id, 'face_to_face'::public.consultation_type, 60
      ) slot
    )
  order by doctor.created_at
  limit 1;
  select * into hospital_row
  from public.hospitals hospital
  where hospital.id = doctor_row.hospital_id;

  select slot.starts_at into appointment_time
  from public.list_available_consultation_slots(
    doctor_row.id, 'face_to_face'::public.consultation_type, 60
  ) slot
  where not exists (
    select 1 from public.consultations consultation
    where consultation.patient_id = patient_row.id
      and consultation.appointment_date = slot.starts_at
      and consultation.status in ('pending', 'approved', 'scheduled', 'in_progress')
  )
  order by slot.starts_at
  limit 1;

  if patient_row.id is null or doctor_row.id is null or appointment_time is null then
    raise exception 'Face-to-face acceptance requires an active patient and published pilot-hospital slot';
  end if;

  select count(*) into consultation_before from public.consultations;
  select count(*) into online_before from public.online_consultation_requests;
  perform set_config('request.jwt.claim.sub', patient_user.auth_user_id::text, true);

  consultation_id := public.book_consultation(jsonb_build_object(
    'doctor_id', doctor_row.id,
    'hospital_id', hospital_row.id,
    'consultation_type', 'face_to_face',
    'appointment_date', appointment_time,
    'chief_complaint', 'Transactional face-to-face compatibility test'
  ));

  select * into consultation_row
  from public.consultations consultation
  where consultation.id = consultation_id;
  if consultation_row.id is null
    or consultation_row.patient_id <> patient_row.id
    or consultation_row.doctor_id <> doctor_row.id
    or consultation_row.hospital_id <> hospital_row.id
    or consultation_row.consultation_type <> 'face_to_face'
    or consultation_row.appointment_date <> appointment_time
    or consultation_row.status <> 'pending' then
    raise exception 'Face-to-face booking no longer creates the immediate pending consultation';
  end if;
  if (select count(*) from public.consultations) <> consultation_before + 1 then
    raise exception 'Face-to-face booking created an unexpected consultation count';
  end if;
  if (select count(*) from public.online_consultation_requests) <> online_before then
    raise exception 'Face-to-face booking was incorrectly redirected to online review';
  end if;
  if private.is_doctor_slot_available(
    doctor_row.id, hospital_row.id,
    'face_to_face'::public.consultation_type, appointment_time, null
  ) then
    raise exception 'Face-to-face booking did not reserve the selected slot';
  end if;
end
$test$;

rollback;
