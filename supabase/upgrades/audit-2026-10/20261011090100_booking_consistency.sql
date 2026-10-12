-- One doctor-level transaction lock is shared by every reservation and schedule write.
create or replace function private.lock_doctor_schedule(target_doctor uuid)
returns void language sql volatile set search_path = '' as $$
  select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('doctor-schedule:' || target_doctor::text, 0));
$$;
revoke all on function private.lock_doctor_schedule(uuid) from public;

create or replace function private.has_online_reviewer(target_hospital uuid)
returns boolean language sql stable security definer set search_path = '' as $$
  select exists (select 1 from public.users u join public.roles r on r.id=u.role_id
    where u.hospital_id=target_hospital and u.account_status='active' and r.role_name='hospital_admin');
$$;
revoke all on function private.has_online_reviewer(uuid) from public;

create or replace function private.enforce_reservation_lead_time()
returns trigger language plpgsql set search_path = '' as $$
declare scheduled_at timestamptz;
begin
  if tg_table_name='consultations' then
    if tg_op='UPDATE' then
      if new.appointment_date is not distinct from old.appointment_date then return new; end if;
    end if;
    if new.consultation_type::text='emergency' then return new; end if;
    scheduled_at := new.appointment_date;
  elsif tg_table_name='guest_consultation_requests' then
    if tg_op='UPDATE' then
      if new.preferred_schedule is not distinct from old.preferred_schedule then return new; end if;
    end if;
    scheduled_at := new.preferred_schedule;
  elsif tg_table_name='online_consultation_requests' then
    if tg_op='UPDATE' then
      if new.preferred_schedule is not distinct from old.preferred_schedule then return new; end if;
    end if;
    scheduled_at := new.preferred_schedule;
  else raise exception 'Unsupported reservation table';
  end if;
  if not private.meets_reservation_lead_time(scheduled_at) then
    raise exception 'Reservations must be made at least 24 hours in advance';
  end if;
  return new;
end $$;

create or replace function private.protect_reserved_schedule()
returns trigger language plpgsql security definer set search_path = '' as $$
declare doctor_id uuid; reservation record;
begin
  if tg_op='INSERT' then doctor_id:=new.doctor_id; else doctor_id:=old.doctor_id; end if;
  perform private.lock_doctor_schedule(doctor_id);
  if tg_op='UPDATE' and new.doctor_id is distinct from old.doctor_id then
    raise exception 'Schedule ownership is immutable';
  end if;
  if tg_op<>'INSERT' then
    for reservation in select c.appointment_date from public.consultations c
      where c.doctor_id=old.doctor_id and c.status not in ('cancelled','rejected','completed')
        and c.appointment_date+interval '4 hours'>now()
        and c.consultation_type in (old.consultation_type,
          case when old.consultation_type='online' then 'guest_online'::public.consultation_type else old.consultation_type end)
        and extract(dow from c.appointment_date at time zone 'Asia/Manila')::integer=old.day_of_week
        and (c.appointment_date at time zone 'Asia/Manila')::time>=old.starts_at
        and (c.appointment_date at time zone 'Asia/Manila')::time<old.ends_at
    loop
      if tg_op='DELETE' then raise exception 'This schedule has reserved appointments'; end if;
      if not new.is_active or new.consultation_type<>old.consultation_type or new.day_of_week<>old.day_of_week
        or new.slot_minutes<>old.slot_minutes
        or (reservation.appointment_date at time zone 'Asia/Manila')::time<new.starts_at
        or (reservation.appointment_date at time zone 'Asia/Manila')::time+make_interval(mins=>new.slot_minutes)>new.ends_at then
        raise exception 'The change would invalidate a reserved appointment';
      end if;
    end loop;
  end if;
  if tg_op<>'DELETE' then
    if new.is_active and new.consultation_type in ('online','guest_online') and not exists (
      select 1 from public.doctors d where d.id=new.doctor_id and private.has_online_reviewer(d.hospital_id)
    ) then raise exception 'An active hospital reviewer is required to publish online booking'; end if;
    return new;
  end if;
  return old;
end $$;
create trigger protect_reserved_schedule before insert or update or delete on public.doctor_schedules
for each row execute function private.protect_reserved_schedule();
revoke all on function private.protect_reserved_schedule() from public;

-- Dates are synchronized by a trigger so approved legacy clients receive the same guarantees.
create or replace function private.sync_rescheduled_consultation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.appointment_date is not distinct from old.appointment_date then return new; end if;
  update public.online_consultation_requests set confirmed_schedule=new.appointment_date
    where official_consultation_id=new.id;
  update public.patient_care_relationships set expires_at=new.appointment_date+interval '7 days'
    where consultation_id=new.id and status in ('requested','active');
  update public.patient_access_grants set expires_at=new.appointment_date+interval '7 days'
    where consultation_id=new.id and status in ('requested','active');
  update public.patient_consents set expires_at=new.appointment_date+interval '7 days'
    where care_relationship_id in (select id from public.patient_care_relationships where consultation_id=new.id)
      and revoked_at is null;
  update public.video_sessions set starts_at=new.appointment_date,expires_at=new.appointment_date+interval '4 hours'
    where consultation_id=new.id and status='cancelled';
  update public.notification_outbox o set status='cancelled',last_error='Appointment rescheduled'
    from public.notifications n where n.id=o.notification_id and n.reference_id=new.id
      and n.notification_type='appointment_reminder' and o.status in ('pending','failed');
  return new;
end $$;
create trigger zz_sync_rescheduled_consultation after update of appointment_date on public.consultations
for each row execute function private.sync_rescheduled_consultation();
revoke all on function private.sync_rescheduled_consultation() from public;

-- Legitimate existing consultations retain their current status and reservation.
update public.hospitals set online_request_workflow_enabled=true
where not online_request_workflow_enabled and private.has_online_reviewer(id);

CREATE OR REPLACE FUNCTION public.book_consultation_v2(booking_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  target_patient uuid := private.current_patient_id();
  target_user uuid := private.current_user_id();
  target_doctor uuid := nullif(booking_payload->>'doctor_id', '')::uuid;
  target_hospital uuid := nullif(booking_payload->>'hospital_id', '')::uuid;
  target_type public.consultation_type := coalesce(
    nullif(booking_payload->>'consultation_type', ''), 'face_to_face'
  )::public.consultation_type;
  target_date timestamptz := nullif(booking_payload->>'appointment_date', '')::timestamptz;
  target_complaint text := btrim(coalesce(booking_payload->>'chief_complaint', ''));
  categories text[] := array(
    select distinct value
    from jsonb_array_elements_text(coalesce(booking_payload->'shared_categories', '[]'::jsonb)) value
  );
  selected_records jsonb := coalesce(booking_payload->'selected_records', '[]'::jsonb);
  target_department uuid;
  source_hospital uuid;
  reviewed_enabled boolean;
  booked_id uuid;
  relationship_id uuid;
  consent_id uuid;
  online_result jsonb;
  patient_auth_id uuid;
begin
  perform private.lock_doctor_schedule(target_doctor);
  if (select auth.uid()) is null or target_patient is null or target_user is null then
    raise exception 'An active patient profile is required';
  end if;
  if target_doctor is null or target_hospital is null then
    raise exception 'A published clinician and hospital are required';
  end if;
  if target_date is null or target_date <= now() then
    raise exception 'Choose a future appointment time';
  end if;
  if length(target_complaint) < 5 or length(target_complaint) > 2000 then
    raise exception 'Describe the care concern in 5 to 2000 characters';
  end if;
  if target_type not in ('face_to_face', 'online') then
    raise exception 'Patients may book face-to-face care or request online care';
  end if;

  select doctor.department_id,
         hospital.online_request_workflow_enabled
  into target_department, reviewed_enabled
  from public.doctors doctor
  join public.hospitals hospital on hospital.id = doctor.hospital_id
  join public.doctor_hospital_employments employment
    on employment.doctor_id = doctor.id and employment.hospital_id = hospital.id
  where doctor.id = target_doctor
    and doctor.hospital_id = target_hospital
    and doctor.availability_status <> 'unavailable'
    and hospital.verification_status = 'verified'
    and hospital.operating_status in ('open', 'limited')
    and employment.employment_status = 'active'
    and employment.is_verified
    and employment.starts_at <= now()
    and (employment.ends_at is null or employment.ends_at > now());

  if not found or target_department is null then
    raise exception 'Doctor is not available at the selected hospital and department';
  end if;

  if target_type = 'online' then
    online_result := public.submit_online_consultation_request(
      jsonb_build_object(
        'hospital_id', target_hospital,
        'department_id', target_department,
        'requested_doctor_id', target_doctor,
        'preferred_schedule', target_date,
        'medical_concern', target_complaint,
        'symptom_duration', coalesce(
          nullif(btrim(booking_payload->>'symptom_duration'), ''),
          'Not specified'
        ),
        'shared_categories', coalesce(
          booking_payload->'shared_categories',
          '["consultations","medical_records","diagnoses","prescriptions","laboratory_requests","laboratory_results","medical_documents","clinical_notes","allergies_medications","treatment_plans"]'::jsonb
        ),
        'selected_records', selected_records,
        'supporting_document_ids', coalesce(
          booking_payload->'supporting_document_ids', '[]'::jsonb
        )
      )
    );
    return online_result || jsonb_build_object('consultation_id',null,'slot_reserved',false);
  end if;

  perform private.lock_doctor_schedule(target_doctor);
  if not private.is_doctor_slot_available(
    target_doctor, target_hospital, target_type, target_date, null
  ) then
    raise exception 'The selected appointment slot is no longer available';
  end if;

  insert into public.consultations(
    patient_id, doctor_id, hospital_id, department_id,
    consultation_type, appointment_date, status, chief_complaint,
    follow_up_of
  ) values (
    target_patient, target_doctor, target_hospital, target_department,
    target_type, target_date, 'pending', target_complaint,
    nullif(booking_payload->>'follow_up_of', '')::uuid
  ) returning id into booked_id;

  insert into public.patient_care_relationships(
    patient_id, hospital_id, doctor_id, consultation_id,
    relationship_type, purpose, status, requested_at, expires_at, created_by
  ) values (
    target_patient, target_hospital, target_doctor, booked_id,
    'consultation', case when target_type = 'face_to_face'
      then 'face_to_face_consultation' else 'legacy_online_consultation' end,
    'requested', now(), target_date + interval '7 days', target_user
  ) returning id into relationship_id;

  if cardinality(categories) = 0 then
    categories := array[
      'consultations', 'medical_records', 'diagnoses', 'prescriptions',
      'laboratory_requests', 'laboratory_results', 'medical_documents',
      'clinical_notes', 'allergies_medications', 'treatment_plans'
    ]::text[];
  end if;
  select app_user.auth_user_id into patient_auth_id
  from public.users app_user where app_user.id = target_user;
  select coalesce(patient.primary_hospital_id, target_hospital) into source_hospital
  from public.patients patient where patient.id = target_patient;

  insert into public.patient_consents(
    patient_id, consent_type, consent_version, is_granted, granted_at,
    captured_by, metadata, care_relationship_id, source_hospital_id,
    receiving_hospital_id, purpose, categories, permitted_actions,
    record_selection_mode, expires_at, granted_by, version_sequence
  ) values (
    target_patient, 'consultation_access', relationship_id::text, true, now(),
    patient_auth_id,
    jsonb_build_object(
      'booking_type', target_type,
      'selected_records', selected_records
    ),
    relationship_id, source_hospital, target_hospital,
    case when target_type = 'face_to_face'
      then 'face_to_face_consultation' else 'legacy_online_consultation' end,
    categories, array['view', 'download', 'create']::text[],
    case when jsonb_array_length(selected_records) > 0
      then 'selected_records' else 'categories' end,
    target_date + interval '7 days', target_user, 1
  ) returning id into consent_id;

  return jsonb_build_object('request_id',null,'consultation_id',booked_id,'status','pending','slot_reserved',true);
end
$function$
;

CREATE OR REPLACE FUNCTION public.review_online_consultation_request(target_request_id uuid, decision text, target_doctor_id uuid DEFAULT NULL::uuid, target_confirmed_schedule timestamp with time zone DEFAULT NULL::timestamp with time zone, target_channel text DEFAULT NULL::text, review_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  request_row public.online_consultation_requests;
  chosen_doctor_id uuid;
  chosen_schedule timestamptz;
  normalized_decision text := lower(btrim(coalesce(decision, '')));
  normalized_channel text := nullif(lower(btrim(coalesce(target_channel, ''))), '');
  consultation_id uuid;
begin
  -- Accept the retired wire value during a rolling client deployment, but
  -- persist and act on it as email only.
  if normalized_channel = 'sms_assisted' then
    normalized_channel := 'email';
  end if;

  if (select auth.uid()) is null or private.current_user_id() is null then
    raise exception 'An authenticated reviewer is required';
  end if;

  select * into request_row
  from public.online_consultation_requests
  where id = target_request_id
  for update;

  if not found then
    raise exception 'Online consultation request was not found';
  end if;
  if not private.is_hospital_admin_for(request_row.hospital_id) then
    raise exception 'Hospital acceptance is required for this request';
  end if;
  if request_row.request_status in ('confirmed', 'completed', 'rejected', 'cancelled') then
    raise exception 'This request is already in a terminal or confirmed state';
  end if;

  if normalized_decision = 'under_review' then
    update public.online_consultation_requests
    set request_status = 'under_review', reviewed_by = private.current_user_id(),
        reviewed_at = now(), updated_at = now()
    where id = request_row.id;
  elsif normalized_decision = 'more_information_required' then
    if nullif(btrim(review_notes), '') is null then
      raise exception 'Describe the additional information required';
    end if;
    update public.online_consultation_requests
    set request_status = 'more_information_required',
        additional_information_request = btrim(review_notes),
        reviewed_by = private.current_user_id(), reviewed_at = now(), updated_at = now()
    where id = request_row.id;
  elsif normalized_decision = 'schedule_proposed' then
    chosen_doctor_id := coalesce(target_doctor_id, request_row.requested_doctor_id);
    chosen_schedule := coalesce(target_confirmed_schedule, request_row.preferred_schedule);
    if normalized_channel is not null
      and normalized_channel not in ('call', 'email', 'video') then
      raise exception 'Choose call, email, or video consultation';
    end if;
    if chosen_doctor_id is null or chosen_schedule is null
      or not private.is_doctor_slot_available(
        chosen_doctor_id, request_row.hospital_id, 'online', chosen_schedule, null
      ) then
      raise exception 'Choose an eligible doctor and currently available proposal';
    end if;
    update public.online_consultation_requests
    set request_status = 'schedule_proposed',
        assigned_doctor_id = chosen_doctor_id,
        proposed_schedule = chosen_schedule,
        consultation_channel = coalesce(normalized_channel, consultation_channel, 'video'),
        reviewed_by = private.current_user_id(), reviewed_at = now(), updated_at = now()
    where id = request_row.id;
  elsif normalized_decision in ('rejected', 'cancelled', 'patient_unreachable', 'face_to_face_recommended') then
    if normalized_decision = 'rejected' and nullif(btrim(review_notes), '') is null then
      raise exception 'A rejection reason is required';
    end if;
    update public.online_consultation_requests
    set request_status = normalized_decision,
        rejection_reason = case when normalized_decision = 'rejected' then btrim(review_notes) else rejection_reason end,
        cancellation_reason = case when normalized_decision = 'cancelled' then btrim(review_notes) else cancellation_reason end,
        reviewed_by = private.current_user_id(), reviewed_at = now(), updated_at = now()
    where id = request_row.id;
    perform private.revoke_relationship_access(
      request_row.care_relationship_id, normalized_decision, review_notes
    );
  elsif normalized_decision = 'confirmed' then
    chosen_doctor_id := coalesce(target_doctor_id, request_row.assigned_doctor_id, request_row.requested_doctor_id);
    chosen_schedule := coalesce(
      target_confirmed_schedule, request_row.proposed_schedule, request_row.preferred_schedule
    );
    if normalized_channel is null
      or normalized_channel not in ('call', 'email', 'video') then
      raise exception 'Choose call, email, or video consultation';
    end if;
    if normalized_channel = 'email'
      and nullif(btrim(request_row.profile_email), '') is null then
      raise exception 'The patient must have a registered email address for email contact';
    end if;
    if chosen_doctor_id is null or chosen_schedule is null then
      raise exception 'A verified doctor and confirmed schedule are required';
    end if;
    if not exists (
      select 1
      from public.doctors doctor
      join public.doctor_hospital_employments employment
        on employment.doctor_id = doctor.id
       and employment.hospital_id = request_row.hospital_id
      where doctor.id = chosen_doctor_id
        and doctor.department_id = request_row.requested_department_id
        and doctor.availability_status <> 'unavailable'
        and employment.employment_status = 'active'
        and employment.is_verified
        and employment.starts_at <= now()
        and (employment.ends_at is null or employment.ends_at > now())
    ) then
      raise exception 'The selected doctor is not verified and active at this hospital';
    end if;

    perform private.lock_doctor_schedule(chosen_doctor_id);
    if not private.is_doctor_slot_available(
      chosen_doctor_id, request_row.hospital_id, 'online', chosen_schedule, null
    ) then
      raise exception 'The selected appointment slot is no longer available';
    end if;

    insert into public.consultations(
      patient_id, doctor_id, hospital_id, department_id,
      consultation_type, appointment_date, status, chief_complaint,
      approved_by, approved_at
    ) values (
      request_row.patient_id, chosen_doctor_id, request_row.hospital_id,
      request_row.requested_department_id, 'online', chosen_schedule,
      'scheduled', request_row.medical_concern,
      private.current_user_id(), now()
    ) returning id into consultation_id;

    perform private.activate_relationship_access(
      request_row.care_relationship_id,
      request_row.consent_id,
      chosen_doctor_id,
      consultation_id,
      request_row.selected_records
    );

    update public.online_consultation_requests
    set request_status = 'confirmed',
        assigned_doctor_id = chosen_doctor_id,
        confirmed_schedule = chosen_schedule,
        consultation_channel = normalized_channel,
        official_consultation_id = consultation_id,
        reviewed_by = private.current_user_id(), reviewed_at = now(), updated_at = now()
    where id = request_row.id;
  else
    raise exception 'Unsupported online request decision';
  end if;

  select * into request_row
  from public.online_consultation_requests
  where id = target_request_id;

  return jsonb_build_object(
    'request_id', request_row.id,
    'reference_number', request_row.reference_number,
    'status', request_row.request_status,
    'consultation_id', request_row.official_consultation_id,
    'assigned_doctor_id', request_row.assigned_doctor_id,
    'confirmed_schedule', request_row.confirmed_schedule,
    'channel', request_row.consultation_channel,
    'slot_reserved', request_row.official_consultation_id is not null
  );
end
$function$
;

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
  if not (
    private.is_hospital_admin_for(request_row.preferred_hospital_id)
    or request_row.assigned_doctor_id = private.current_doctor_id()
  ) then
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

CREATE OR REPLACE FUNCTION public.reschedule_consultation(target_consultation_id uuid, scheduled_for timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  consultation_row public.consultations;
begin
  if (select auth.uid()) is null or scheduled_for is null or scheduled_for <= now() then
    raise exception 'A signed-in patient and a future appointment time are required';
  end if;

  select * into consultation_row
  from public.consultations
  where id = target_consultation_id
  for update;

  if not found
    or private.current_patient_id() is null
    or consultation_row.patient_id is distinct from private.current_patient_id() then
    raise exception 'The consultation is not accessible to this patient';
  end if;
  if consultation_row.status not in ('approved','scheduled') then
    raise exception 'Only an approved or scheduled consultation may be rescheduled';
  end if;

  perform private.lock_doctor_schedule(consultation_row.doctor_id);
  if not private.is_doctor_slot_available(
    consultation_row.doctor_id,
    consultation_row.hospital_id,
    consultation_row.consultation_type,
    scheduled_for,
    consultation_row.id
  ) then
    raise exception 'The selected appointment slot is unavailable';
  end if;

  update public.consultations
  set appointment_date = scheduled_for
  where id = target_consultation_id
  returning * into consultation_row;

  return jsonb_build_object(
    'id', consultation_row.id,
    'status', consultation_row.status,
    'appointment_date', consultation_row.appointment_date
  );
end;
$function$
;

CREATE OR REPLACE FUNCTION public.transition_consultation(target_consultation_id uuid, target_status consultation_status, transition_notes text DEFAULT NULL::text, scheduled_for timestamp with time zone DEFAULT NULL::timestamp with time zone, clinical_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  result_row public.consultations;
  next_height numeric;
  next_weight numeric;
begin
  if not (
    private.has_permission('consultations.read_own')
    or private.has_permission('hospital.manage')
  ) then
    raise exception 'Consultation workflow permission is required';
  end if;

  select * into result_row
  from public.consultations
  where id = target_consultation_id
  for update;
  if not found or not private.is_consultation_participant(target_consultation_id) then
    raise exception 'Consultation was not found or is not accessible';
  end if;

  if scheduled_for is not null and scheduled_for is distinct from result_row.appointment_date then
    if target_status not in ('approved', 'scheduled') then
      raise exception 'Only an approved or scheduled consultation may be rescheduled';
    end if;
    perform private.lock_doctor_schedule(result_row.doctor_id);
    if not private.is_doctor_slot_available(
      result_row.doctor_id,
      result_row.hospital_id,
      result_row.consultation_type,
      scheduled_for,
      result_row.id
    ) then
      raise exception 'The selected appointment slot is unavailable';
    end if;
  end if;

  next_height := result_row.height_cm;
  next_weight := result_row.weight_kg;
  if private.current_doctor_id() = result_row.doctor_id then
    if clinical_payload ? 'height_cm' then
      next_height := nullif(btrim(clinical_payload->>'height_cm'), '')::numeric;
    end if;
    if clinical_payload ? 'weight_kg' then
      next_weight := nullif(btrim(clinical_payload->>'weight_kg'), '')::numeric;
    end if;
  end if;

  update public.consultations
  set
    status = target_status,
    appointment_date = coalesce(scheduled_for, appointment_date),
    rejection_reason = case
      when target_status = 'rejected' then nullif(btrim(transition_notes), '')
      else rejection_reason
    end,
    doctor_notes = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'doctor_notes'
        then nullif(btrim(clinical_payload->>'doctor_notes'), '')
      else doctor_notes
    end,
    confirmed_diagnosis = case
      when private.current_doctor_id() = doctor_id
        then coalesce(clinical_payload->>'confirmed_diagnosis', confirmed_diagnosis)
      else confirmed_diagnosis
    end,
    treatment_plan = case
      when private.current_doctor_id() = doctor_id
        then coalesce(clinical_payload->>'treatment_plan', treatment_plan)
      else treatment_plan
    end,
    consultation_summary = case
      when private.current_doctor_id() = doctor_id
        then coalesce(clinical_payload->>'consultation_summary', consultation_summary)
      else consultation_summary
    end,
    height_cm = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'height_cm'
        then next_height
      else height_cm
    end,
    weight_kg = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'weight_kg'
        then next_weight
      else weight_kg
    end,
    bmi = case
      when private.current_doctor_id() = doctor_id
        and (clinical_payload ? 'height_cm' or clinical_payload ? 'weight_kg')
        and next_height is not null
        and next_weight is not null
        then round(next_weight / power(next_height / 100, 2), 2)
      when private.current_doctor_id() = doctor_id
        and (clinical_payload ? 'height_cm' or clinical_payload ? 'weight_kg')
        then null
      else bmi
    end,
    blood_pressure_systolic = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'blood_pressure_systolic'
        then nullif(btrim(clinical_payload->>'blood_pressure_systolic'), '')::smallint
      else blood_pressure_systolic
    end,
    blood_pressure_diastolic = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'blood_pressure_diastolic'
        then nullif(btrim(clinical_payload->>'blood_pressure_diastolic'), '')::smallint
      else blood_pressure_diastolic
    end,
    body_temperature_c = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'body_temperature_c'
        then nullif(btrim(clinical_payload->>'body_temperature_c'), '')::numeric
      else body_temperature_c
    end,
    heart_rate_bpm = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'heart_rate_bpm'
        then nullif(btrim(clinical_payload->>'heart_rate_bpm'), '')::smallint
      else heart_rate_bpm
    end,
    respiratory_rate_bpm = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'respiratory_rate_bpm'
        then nullif(btrim(clinical_payload->>'respiratory_rate_bpm'), '')::smallint
      else respiratory_rate_bpm
    end,
    oxygen_saturation_percent = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'oxygen_saturation_percent'
        then nullif(btrim(clinical_payload->>'oxygen_saturation_percent'), '')::numeric
      else oxygen_saturation_percent
    end,
    vitals_recorded_at = case
      when private.current_doctor_id() = doctor_id
        and (
          nullif(btrim(clinical_payload->>'height_cm'), '') is not null
          or nullif(btrim(clinical_payload->>'weight_kg'), '') is not null
          or nullif(btrim(clinical_payload->>'blood_pressure_systolic'), '') is not null
          or nullif(btrim(clinical_payload->>'blood_pressure_diastolic'), '') is not null
          or nullif(btrim(clinical_payload->>'body_temperature_c'), '') is not null
          or nullif(btrim(clinical_payload->>'heart_rate_bpm'), '') is not null
          or nullif(btrim(clinical_payload->>'respiratory_rate_bpm'), '') is not null
          or nullif(btrim(clinical_payload->>'oxygen_saturation_percent'), '') is not null
        ) then coalesce(vitals_recorded_at, now())
      when private.current_doctor_id() = doctor_id
        and (
          clinical_payload ? 'height_cm'
          or clinical_payload ? 'weight_kg'
          or clinical_payload ? 'blood_pressure_systolic'
          or clinical_payload ? 'blood_pressure_diastolic'
          or clinical_payload ? 'body_temperature_c'
          or clinical_payload ? 'heart_rate_bpm'
          or clinical_payload ? 'respiratory_rate_bpm'
          or clinical_payload ? 'oxygen_saturation_percent'
        ) then null
      else vitals_recorded_at
    end,
    current_symptoms = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'current_symptoms'
        then nullif(btrim(clinical_payload->>'current_symptoms'), '')
      else current_symptoms
    end,
    known_medical_conditions = case
      when private.current_doctor_id() = doctor_id
        and jsonb_typeof(clinical_payload->'known_medical_conditions') = 'array'
        then array(select jsonb_array_elements_text(clinical_payload->'known_medical_conditions'))
      else known_medical_conditions
    end,
    allergies = case
      when private.current_doctor_id() = doctor_id
        and jsonb_typeof(clinical_payload->'allergies') = 'array'
        then array(select jsonb_array_elements_text(clinical_payload->'allergies'))
      else allergies
    end,
    current_medications = case
      when private.current_doctor_id() = doctor_id
        and jsonb_typeof(clinical_payload->'current_medications') = 'array'
        then array(select jsonb_array_elements_text(clinical_payload->'current_medications'))
      else current_medications
    end,
    relevant_medical_history = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'relevant_medical_history'
        then nullif(btrim(clinical_payload->>'relevant_medical_history'), '')
      else relevant_medical_history
    end,
    previous_surgeries = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'previous_surgeries'
        then nullif(btrim(clinical_payload->>'previous_surgeries'), '')
      else previous_surgeries
    end,
    smoking_status = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'smoking_status'
        then nullif(btrim(clinical_payload->>'smoking_status'), '')
      else smoking_status
    end,
    alcohol_use = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'alcohol_use'
        then nullif(btrim(clinical_payload->>'alcohol_use'), '')
      else alcohol_use
    end,
    pregnancy_status = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'pregnancy_status'
        then nullif(btrim(clinical_payload->>'pregnancy_status'), '')
      else pregnancy_status
    end,
    approved_by = case
      when target_status in ('approved', 'scheduled') then private.current_user_id()
      else approved_by
    end,
    approved_at = case
      when target_status in ('approved', 'scheduled') then coalesce(approved_at, now())
      else approved_at
    end,
    rejected_at = case
      when target_status = 'rejected' then now()
      else rejected_at
    end
  where id = target_consultation_id
  returning * into result_row;

  if result_row.guest_request_id is not null then
    update public.guest_consultation_requests
    set request_status = case target_status
      when 'completed' then 'consultation_completed'::public.guest_request_status
      when 'cancelled' then 'cancelled'::public.guest_request_status
      else request_status
    end
    where id = result_row.guest_request_id;
  end if;

  return jsonb_build_object(
    'id', result_row.id,
    'status', result_row.status,
    'appointment_date', result_row.appointment_date,
    'completed_at', result_row.completed_at
  );
end;
$function$
;

create or replace function public.book_consultation(booking_payload jsonb)
returns uuid language plpgsql security definer set search_path = '' as $$
declare result jsonb;
begin
 result:=public.book_consultation_v2(booking_payload);
 return coalesce(result->>'request_id',result->>'consultation_id')::uuid;
end $$;
revoke all on function public.book_consultation_v2(jsonb) from public,anon;
grant execute on function public.book_consultation_v2(jsonb) to authenticated;

CREATE OR REPLACE FUNCTION public.submit_online_consultation_request(request_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  patient_row public.patients;
  user_row public.users;
  hospital_row public.hospitals;
  target_hospital_id uuid := nullif(request_payload->>'hospital_id', '')::uuid;
  target_department_id uuid := nullif(request_payload->>'department_id', '')::uuid;
  requested_doctor_id uuid := nullif(request_payload->>'requested_doctor_id', '')::uuid;
  preferred_time timestamptz := nullif(request_payload->>'preferred_schedule', '')::timestamptz;
  concern text := btrim(coalesce(request_payload->>'medical_concern', ''));
  duration_text text := btrim(coalesce(request_payload->>'symptom_duration', ''));
  categories text[] := array(
    select distinct value
    from jsonb_array_elements_text(coalesce(request_payload->'shared_categories', '[]'::jsonb)) value
  );
  selected_records jsonb := coalesce(request_payload->'selected_records', '[]'::jsonb);
  supporting_ids uuid[] := array(
    select value::uuid
    from jsonb_array_elements_text(coalesce(request_payload->'supporting_document_ids', '[]'::jsonb)) value
    where value ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  );
  relationship_id uuid;
  consent_id uuid;
  request_id uuid;
  request_reference text;
  category text;
begin
  if (select auth.uid()) is null
    or private.current_patient_id() is null
    or private.current_user_id() is null then
    raise exception 'An authenticated patient profile is required';
  end if;

  select * into patient_row
  from public.patients
  where id = private.current_patient_id();
  select * into user_row
  from public.users
  where id = private.current_user_id();
  select * into hospital_row
  from public.hospitals
  where id = target_hospital_id;

  if not found
    or hospital_row.verification_status <> 'verified'
    or hospital_row.operating_status not in ('open', 'limited') then
    raise exception 'A verified operating hospital is required';
  end if;
  if not private.has_online_reviewer(hospital_row.id) then
    raise exception 'An active hospital reviewer is required for online care';
  end if;
  if nullif(btrim(user_row.mobile_number), '') is null
    or nullif(btrim(user_row.first_name), '') is null
    or nullif(btrim(user_row.last_name), '') is null then
    raise exception 'Update the account profile and registered phone before requesting care';
  end if;
  if target_department_id is null or not exists (
    select 1 from public.hospital_departments department
    where department.id = target_department_id
      and department.hospital_id = hospital_row.id
      and department.availability_status <> 'unavailable'
  ) then
    raise exception 'Choose an available department at the selected hospital';
  end if;
  if requested_doctor_id is not null and not exists (
    select 1
    from public.doctors doctor
    join public.doctor_hospital_employments employment
      on employment.doctor_id = doctor.id and employment.hospital_id = hospital_row.id
    where doctor.id = requested_doctor_id
      and doctor.department_id = target_department_id
      and doctor.availability_status <> 'unavailable'
      and employment.employment_status = 'active'
      and employment.is_verified
      and (employment.ends_at is null or employment.ends_at > now())
  ) then
    raise exception 'The requested doctor is not actively employed in this department';
  end if;
  if preferred_time is null or preferred_time <= now()
    or preferred_time > now() + interval '180 days' then
    raise exception 'Choose a preferred time within the next 180 days';
  end if;
  if length(concern) < 10 or length(concern) > 2000
    or length(duration_text) < 1 or length(duration_text) > 200 then
    raise exception 'A care concern and symptom duration are required';
  end if;
  if cardinality(categories) = 0 then
    categories := array[
      'consultations', 'medical_records', 'diagnoses', 'prescriptions',
      'laboratory_requests', 'laboratory_results', 'medical_documents',
      'clinical_notes', 'allergies_medications', 'treatment_plans'
    ]::text[];
  end if;
  foreach category in array categories loop
    if not private.valid_record_category(category) then
      raise exception 'Unsupported shared record category: %', category;
    end if;
  end loop;
  if jsonb_typeof(selected_records) <> 'array' then
    raise exception 'Selected records must be an array';
  end if;

  insert into public.patient_care_relationships(
    patient_id, hospital_id, doctor_id, relationship_type, purpose, status,
    requested_at, expires_at, created_by
  ) values (
    patient_row.id, hospital_row.id, requested_doctor_id,
    'consultation', 'reviewed_online_consultation', 'requested',
    now(), preferred_time + interval '7 days', user_row.id
  ) returning id into relationship_id;

  insert into public.patient_consents(
    patient_id, consent_type, consent_version, is_granted, granted_at,
    captured_by, metadata, care_relationship_id, source_hospital_id,
    receiving_hospital_id, purpose, categories, permitted_actions,
    record_selection_mode, expires_at, granted_by, version_sequence
  ) values (
    patient_row.id,
    'reviewed_online_consultation_access',
    relationship_id::text,
    true,
    now(),
    (select auth.uid()),
    jsonb_build_object(
      'request_source', 'patient_account',
      'phone_snapshot', user_row.mobile_number,
      'selected_records_count', jsonb_array_length(selected_records)
    ),
    relationship_id,
    coalesce(patient_row.primary_hospital_id, hospital_row.id),
    hospital_row.id,
    'reviewed_online_consultation',
    categories,
    array['view', 'download', 'create']::text[],
    case when jsonb_array_length(selected_records) > 0
      then 'selected_records' else 'categories' end,
    preferred_time + interval '7 days',
    user_row.id,
    1
  ) returning id into consent_id;

  insert into public.online_consultation_requests(
    reference_number, patient_id, submitted_by,
    profile_first_name, profile_last_name, profile_email,
    phone_number_snapshot, birth_date_snapshot, address_snapshot,
    hospital_id, requested_department_id, requested_doctor_id,
    medical_concern, symptom_duration, preferred_schedule,
    supporting_document_ids, shared_categories, selected_records,
    consent_id, care_relationship_id, request_status
  ) values (
    '', patient_row.id, user_row.id,
    user_row.first_name, user_row.last_name, user_row.email,
    user_row.mobile_number, user_row.birth_date, user_row.address,
    hospital_row.id, target_department_id, requested_doctor_id,
    concern, duration_text, preferred_time,
    supporting_ids, categories, selected_records,
    consent_id, relationship_id, 'submitted'
  ) returning id, reference_number into request_id, request_reference;

  update public.patient_care_relationships
  set online_request_id = request_id, updated_at = now()
  where id = relationship_id;

  return jsonb_build_object(
    'request_id', request_id,
    'reference_number', request_reference,
    'status', 'submitted',
    'preferred_schedule', preferred_time,
    'phone_number', user_row.mobile_number,
    'slot_reserved', false
  );
end
$function$
;

CREATE OR REPLACE FUNCTION private.is_doctor_slot_available(target_doctor_id uuid, target_hospital_id uuid, target_type consultation_type, target_start timestamp with time zone, excluded_consultation_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    private.meets_reservation_lead_time(target_start)
    and (target_type not in ('online','guest_online') or private.has_online_reviewer(target_hospital_id))
    and exists (
      select 1
      from public.doctors doctor
      join public.hospitals hospital on hospital.id = doctor.hospital_id
      where doctor.id = target_doctor_id
        and doctor.hospital_id = target_hospital_id
        and doctor.availability_status <> 'unavailable'
        and hospital.verification_status = 'verified'
        and hospital.operating_status in ('open', 'limited')
    )
    and exists (
      select 1
      from public.doctor_schedules schedule
      where schedule.doctor_id = target_doctor_id
        and schedule.is_active
        and (
          schedule.consultation_type = target_type
          or (
            target_type = 'guest_online'
            and schedule.consultation_type = 'online'
          )
        )
        and schedule.day_of_week = extract(
          dow from target_start at time zone 'Asia/Manila'
        )::integer
        and (target_start at time zone 'Asia/Manila')::time >= schedule.starts_at
        and (target_start at time zone 'Asia/Manila')::time
          + make_interval(mins => schedule.slot_minutes) <= schedule.ends_at
        and not exists (
          select 1
          from public.consultations consultation
          where consultation.doctor_id = target_doctor_id
            and consultation.id is distinct from excluded_consultation_id
            and consultation.status not in ('rejected', 'cancelled')
            and consultation.appointment_date
              < target_start + make_interval(mins => schedule.slot_minutes)
            and consultation.appointment_date
              > target_start - make_interval(mins => schedule.slot_minutes)
        )
    ),
    false
  )
$function$
;

create or replace function private.lock_consultation_reservation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
 perform private.lock_doctor_schedule(new.doctor_id);
 if tg_op='UPDATE' then
   if new.appointment_date is not distinct from old.appointment_date then return new; end if;
 end if;
 if new.consultation_type<>'emergency' and not private.is_doctor_slot_available(
   new.doctor_id,new.hospital_id,new.consultation_type,new.appointment_date,new.id)
 then raise exception 'The selected appointment slot is unavailable'; end if;
 return new;
end $$;
create trigger aa_lock_consultation_reservation before insert or update of appointment_date on public.consultations
for each row execute function private.lock_consultation_reservation();
revoke all on function private.lock_consultation_reservation() from public;
