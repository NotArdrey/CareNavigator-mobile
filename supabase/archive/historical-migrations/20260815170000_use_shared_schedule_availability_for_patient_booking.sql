create or replace function public.book_consultation(booking_payload jsonb)
returns uuid
language plpgsql
set search_path = ''
as $function$
declare
  target_patient uuid := private.current_patient_id();
  target_doctor uuid := nullif(booking_payload ->> 'doctor_id', '')::uuid;
  target_hospital uuid := nullif(booking_payload ->> 'hospital_id', '')::uuid;
  target_type public.consultation_type := coalesce(
    nullif(booking_payload ->> 'consultation_type', ''),
    'online'
  )::public.consultation_type;
  target_date timestamptz := nullif(
    booking_payload ->> 'appointment_date',
    ''
  )::timestamptz;
  target_complaint text := btrim(booking_payload ->> 'chief_complaint');
  booked_id uuid;
begin
  if target_patient is null then
    raise exception 'An active patient profile is required';
  end if;
  if target_doctor is null or target_hospital is null then
    raise exception 'A published clinician and hospital are required';
  end if;
  if target_date is null or target_date <= now() then
    raise exception 'Choose a future appointment time';
  end if;
  if nullif(target_complaint, '') is null or length(target_complaint) < 5 then
    raise exception 'Describe the care concern in at least 5 characters';
  end if;
  if not exists (
    select 1
    from public.doctors doctor
    where doctor.id = target_doctor
      and doctor.hospital_id = target_hospital
      and doctor.availability_status <> 'unavailable'
  ) then
    raise exception 'Doctor is not available at the selected hospital';
  end if;
  if not private.is_doctor_slot_available(
    target_doctor,
    target_hospital,
    target_type,
    target_date,
    null
  ) then
    raise exception 'The selected appointment slot is no longer available';
  end if;

  insert into public.consultations (
    patient_id,
    doctor_id,
    hospital_id,
    department_id,
    consultation_type,
    appointment_date,
    status,
    chief_complaint,
    follow_up_of
  )
  select
    target_patient,
    doctor.id,
    doctor.hospital_id,
    doctor.department_id,
    target_type,
    target_date,
    'pending',
    target_complaint,
    nullif(booking_payload ->> 'follow_up_of', '')::uuid
  from public.doctors doctor
  where doctor.id = target_doctor
  returning id into booked_id;

  return booked_id;
end;
$function$;
