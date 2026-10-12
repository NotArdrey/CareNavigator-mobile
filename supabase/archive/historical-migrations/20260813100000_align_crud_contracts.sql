-- Align client-facing CRUD actions with the live consultation and guest-request
-- contracts.  These operations remain server-authoritative so schedule checks
-- and role checks cannot be bypassed by the client.

alter table public.guest_consultation_requests
  add column if not exists preferred_consultation_type public.consultation_type
    not null default 'guest_online';

alter table public.guest_consultation_requests
  drop constraint if exists guest_requests_preferred_consultation_type_check;

alter table public.guest_consultation_requests
  add constraint guest_requests_preferred_consultation_type_check
  check (preferred_consultation_type in ('face_to_face', 'guest_online'));

create or replace function public.book_doctor_consultation(
  target_patient_id uuid,
  target_appointment_date timestamptz,
  target_type public.consultation_type,
  target_chief_complaint text
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  doctor_row public.doctors;
  booked_id uuid;
begin
  if (select auth.uid()) is null
    or private.current_doctor_id() is null
    or not private.has_permission('consultations.read_own') then
    raise exception 'An authorized doctor session is required';
  end if;

  if target_patient_id is null
    or target_appointment_date is null
    or target_appointment_date <= now()
    or nullif(btrim(target_chief_complaint), '') is null
    or length(btrim(target_chief_complaint)) < 5 then
    raise exception 'A patient, future appointment time, and care concern are required';
  end if;

  if target_type not in ('online', 'face_to_face') then
    raise exception 'Doctors may book online or in-person consultations';
  end if;

  select * into doctor_row
  from public.doctors
  where id = private.current_doctor_id();

  if not found or not private.can_access_patient(target_patient_id) then
    raise exception 'The patient is not assigned to this doctor';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      doctor_row.id::text || ':' || target_appointment_date::date::text,
      0
    )
  );

  if not private.is_doctor_slot_available(
    doctor_row.id,
    doctor_row.hospital_id,
    target_type,
    target_appointment_date,
    null
  ) then
    raise exception 'The selected appointment slot is unavailable';
  end if;

  insert into public.consultations(
    patient_id,
    doctor_id,
    hospital_id,
    department_id,
    consultation_type,
    appointment_date,
    status,
    chief_complaint,
    approved_by,
    approved_at
  ) values (
    target_patient_id,
    doctor_row.id,
    doctor_row.hospital_id,
    doctor_row.department_id,
    target_type,
    target_appointment_date,
    'scheduled',
    btrim(target_chief_complaint),
    private.current_user_id(),
    now()
  )
  returning id into booked_id;

  return booked_id;
end;
$function$;

revoke all on function public.book_doctor_consultation(uuid, timestamptz, public.consultation_type, text)
  from public, anon;
grant execute on function public.book_doctor_consultation(uuid, timestamptz, public.consultation_type, text)
  to authenticated, service_role;

create or replace function public.review_guest_consultation(
  target_request_id uuid,
  decision text,
  target_doctor_id uuid default null,
  target_appointment_date timestamptz default null,
  review_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  request_row public.guest_consultation_requests;
  chosen_doctor uuid;
  scheduled_time timestamptz;
  target_type public.consultation_type;
  temporary_patient_id uuid;
  created_consultation_id uuid;
begin
  if not (private.has_permission('patients.manage') or private.has_permission('hospital.manage')) then
    raise exception 'Guest consultation review permission is required';
  end if;

  select * into request_row
  from public.guest_consultation_requests
  where id = target_request_id
  for update;

  if not found then
    raise exception 'Guest consultation request was not found';
  end if;

  if not (
    private.is_hospital_admin_for(request_row.preferred_hospital_id)
    or request_row.assigned_doctor_id = private.current_doctor_id()
  ) then
    raise exception 'Not authorized to review this request';
  end if;

  if decision not in ('approved', 'rejected') then
    raise exception 'Decision must be approved or rejected';
  end if;

  if decision = 'rejected' then
    update public.guest_consultation_requests
    set request_status = 'rejected',
        reviewed_by = private.current_user_id(),
        reviewed_at = now(),
        rejection_reason = nullif(btrim(review_notes), ''),
        identity_review_notes = review_notes
    where id = target_request_id;

    return jsonb_build_object(
      'request_id', target_request_id,
      'patient_id', null,
      'consultation_id', null,
      'status', 'rejected'
    );
  end if;

  chosen_doctor := coalesce(
    target_doctor_id,
    request_row.assigned_doctor_id,
    private.current_doctor_id()
  );
  scheduled_time := coalesce(target_appointment_date, request_row.preferred_schedule);
  target_type := case request_row.preferred_consultation_type
    when 'face_to_face'::public.consultation_type then 'face_to_face'::public.consultation_type
    else 'guest_online'::public.consultation_type
  end;

  if private.current_role() = 'hospital_admin' and target_doctor_id is null then
    raise exception 'A doctor must be assigned';
  end if;
  if chosen_doctor is null or scheduled_time is null then
    raise exception 'An available doctor and future appointment time are required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      chosen_doctor::text || ':' || scheduled_time::date::text,
      0
    )
  );

  if not private.is_doctor_slot_available(
    chosen_doctor,
    request_row.preferred_hospital_id,
    target_type,
    scheduled_time,
    null
  ) then
    raise exception 'The selected appointment slot is unavailable';
  end if;

  update public.guest_consultation_requests
  set request_status = 'approved',
      assigned_doctor_id = chosen_doctor,
      reviewed_by = private.current_user_id(),
      reviewed_at = now(),
      identity_review_status = 'verified',
      identity_review_notes = review_notes
  where id = target_request_id;

  select id into temporary_patient_id
  from public.patients
  where guest_request_id = target_request_id;

  if temporary_patient_id is null then
    insert into public.patients(
      created_by_doctor,
      guest_request_id,
      primary_hospital_id,
      allergies,
      existing_conditions,
      identity_verification_status,
      account_activation_status,
      converted_from_guest,
      profile_status
    ) values (
      chosen_doctor,
      target_request_id,
      request_row.preferred_hospital_id,
      request_row.allergies,
      request_row.existing_conditions,
      'verified',
      'pending',
      true,
      'temporary'
    )
    returning id into temporary_patient_id;
  end if;

  insert into public.doctor_patient_assignments(doctor_id, patient_id, notes)
  values (
    chosen_doctor,
    temporary_patient_id,
    'Created from guest consultation ' || request_row.reference_number
  )
  on conflict do nothing;

  insert into public.consultations(
    patient_id,
    guest_request_id,
    doctor_id,
    hospital_id,
    department_id,
    consultation_type,
    appointment_date,
    status,
    chief_complaint,
    approved_by,
    approved_at
  ) values (
    null,
    target_request_id,
    chosen_doctor,
    request_row.preferred_hospital_id,
    request_row.preferred_department_id,
    target_type,
    scheduled_time,
    'scheduled',
    request_row.consultation_reason,
    private.current_user_id(),
    now()
  )
  returning id into created_consultation_id;

  update public.guest_consultation_requests
  set request_status = 'consultation_scheduled'
  where id = target_request_id;

  return jsonb_build_object(
    'request_id', target_request_id,
    'patient_id', temporary_patient_id,
    'consultation_id', created_consultation_id,
    'status', 'consultation_scheduled'
  );
end;
$function$;
