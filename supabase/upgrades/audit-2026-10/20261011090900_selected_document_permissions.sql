create or replace function private.validate_record_selections(target_patient uuid,categories text[],selections jsonb)
returns void language plpgsql security definer set search_path='' as $$
declare item jsonb; owner_id uuid; source_name text;
begin
  if jsonb_typeof(selections)<>'array' then raise exception 'Selected records must be an array'; end if;
  for item in select value from jsonb_array_elements(selections) loop
    source_name:=item->>'source_table';
    if not ((item->>'category')=any(categories)) or source_name is distinct from (item->>'category')
      or source_name not in ('consultations','medical_records','diagnoses','prescriptions','laboratory_requests','laboratory_results','medical_documents','treatment_plans') then
      raise exception 'Unsupported selected record scope';
    end if;
    execute format('select patient_id from public.%I where id=$1',source_name) into owner_id using (item->>'record_id')::uuid;
    if owner_id is distinct from target_patient then raise exception 'Selected records must belong to the requesting patient'; end if;
  end loop;
end $$;
revoke all on function private.validate_record_selections(uuid,text[],jsonb) from public;
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
  selection_mode text;
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

  if exists (select 1 from unnest(supporting_ids) id where not exists (
    select 1 from public.medical_documents d where d.id=id and d.patient_id=patient_row.id
  )) then raise exception 'Supporting documents must belong to the requesting patient'; end if;
  if cardinality(supporting_ids)>0 and not ('medical_documents'=any(categories)) then
    raise exception 'Consent to share the supporting medical documents is required';
  end if;
  selection_mode := case when jsonb_array_length(selected_records)>0 then 'selected_records' else 'categories' end;
  selected_records := selected_records || coalesce((select jsonb_agg(jsonb_build_object(
    'category','medical_documents','source_table','medical_documents','record_id',id)) from unnest(supporting_ids) id),'[]'::jsonb);
  perform private.validate_record_selections(patient_row.id,categories,selected_records);

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
      'selected_records_count', jsonb_array_length(selected_records), 'selected_records',selected_records
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
CREATE OR REPLACE FUNCTION private.activate_relationship_access(target_relationship_id uuid, target_consent_id uuid, target_doctor_id uuid, target_consultation_id uuid, target_selected_records jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  relationship_row public.patient_care_relationships;
  consent_row public.patient_consents;
  local_grant_id uuid;
  external_grant_id uuid;
  grant_expiry timestamptz;
  category text;
  local_categories text[];
  selected_record jsonb;
  ext_hospital_id uuid;
begin
  select * into relationship_row
  from public.patient_care_relationships
  where id = target_relationship_id
  for update;

  select * into consent_row
  from public.patient_consents
  where id = target_consent_id
  for update;

  if not found
    or relationship_row.id is null
    or consent_row.patient_id is distinct from relationship_row.patient_id
    or consent_row.care_relationship_id is distinct from relationship_row.id
    or not consent_row.is_granted
    or consent_row.granted_at is null
    or consent_row.revoked_at is not null
    or (consent_row.expires_at is not null and consent_row.expires_at <= now()) then
    raise exception 'An active patient consent for this care relationship is required';
  end if;
  if target_doctor_id is null
    or not exists (
      select 1 from public.doctors doctor
      where doctor.id = target_doctor_id
        and doctor.hospital_id = relationship_row.hospital_id
    )
    or not exists (
      select 1
      from public.doctor_hospital_employments employment
      where employment.doctor_id = target_doctor_id
        and employment.hospital_id = relationship_row.hospital_id
        and employment.employment_status = 'active'
        and employment.is_verified
        and employment.starts_at <= now()
        and (employment.ends_at is null or employment.ends_at > now())
    ) then
    raise exception 'A verified doctor with active hospital employment is required';
  end if;

  grant_expiry := least(
    coalesce(consent_row.expires_at, now() + interval '30 days'),
    coalesce(relationship_row.expires_at, now() + interval '30 days')
  );
  if grant_expiry <= now() then
    raise exception 'The consent or care relationship has expired';
  end if;

  update public.doctor_patient_assignments
  set assignment_status = 'ended',
      ended_at = coalesce(ended_at, now()),
      ended_reason = coalesce(ended_reason, 'Consultation reassigned')
  where care_relationship_id = relationship_row.id
    and doctor_id <> target_doctor_id
    and ended_at is null;

  update public.patient_access_grants
  set status = 'revoked',
      revoked_at = coalesce(revoked_at, now()),
      revoked_by = private.current_user_id(),
      revocation_reason = coalesce(revocation_reason, 'Consultation reassigned'),
      updated_at = now()
  where care_relationship_id = relationship_row.id
    and receiving_doctor_id <> target_doctor_id
    and status in ('requested', 'active')
    and revoked_at is null;

  insert into public.doctor_patient_assignments(
    doctor_id, patient_id, hospital_id, care_relationship_id,
    consultation_id, assigned_at, assignment_status, notes
  )
  select target_doctor_id, relationship_row.patient_id,
         relationship_row.hospital_id, relationship_row.id,
         target_consultation_id, now(), 'active',
         'Activated from verified care relationship'
  where not exists (
    select 1 from public.doctor_patient_assignments assignment
    where assignment.care_relationship_id = relationship_row.id
      and assignment.doctor_id = target_doctor_id
      and assignment.assignment_status = 'active'
      and assignment.ended_at is null
  );

  update public.patient_care_relationships
  set doctor_id = target_doctor_id,
      consultation_id = coalesce(target_consultation_id, consultation_id),
      status = 'active',
      approved_at = coalesce(approved_at, now()),
      starts_at = coalesce(starts_at, now()),
      expires_at = grant_expiry,
      ended_at = null,
      termination_reason = null,
      updated_at = now()
  where id = relationship_row.id
  returning * into relationship_row;

  select id into local_grant_id
  from public.patient_access_grants
  where care_relationship_id = relationship_row.id
    and source_hospital_id = relationship_row.hospital_id
    and receiving_hospital_id = relationship_row.hospital_id
    and receiving_doctor_id = target_doctor_id
    and status in ('requested', 'active')
    and revoked_at is null
  for update;

  if local_grant_id is null then
    insert into public.patient_access_grants(
      patient_id, care_relationship_id, consent_id, source_hospital_id,
      receiving_hospital_id, receiving_doctor_id, consultation_id,
      purpose, status, selection_mode, permitted_actions,
      external_read_only, activated_at, expires_at
    ) values (
      relationship_row.patient_id, relationship_row.id, consent_row.id,
      relationship_row.hospital_id, relationship_row.hospital_id,
      target_doctor_id, target_consultation_id, relationship_row.purpose,
      'active', 'categories', array['view', 'download', 'create']::text[],
      false, now(), grant_expiry
    ) returning id into local_grant_id;
  else
    update public.patient_access_grants
    set consent_id = consent_row.id,
        consultation_id = coalesce(target_consultation_id, consultation_id),
        status = 'active',
        selection_mode = 'categories',
        permitted_actions = array['view', 'download', 'create']::text[],
        external_read_only = false,
        activated_at = coalesce(activated_at, now()),
        expires_at = grant_expiry,
        updated_at = now()
    where id = local_grant_id;
  end if;

  local_categories := case
    when cardinality(consent_row.categories) > 0 then consent_row.categories
    else array['consultations']::text[]
  end;
  foreach category in array local_categories loop
    if not private.valid_record_category(category) then
      raise exception 'Unsupported record category: %', category;
    end if;
    insert into public.patient_access_scopes(
      grant_id, record_category, can_view, can_download, can_create
    ) values (
      local_grant_id, category, true,
      category in ('prescriptions', 'laboratory_results', 'medical_documents'),
      true
    )
    on conflict (grant_id, record_category) do update
    set can_view = excluded.can_view,
        can_download = excluded.can_download,
        can_create = excluded.can_create;
  end loop;

  -- External source hospitals
  if cardinality(consent_row.categories) > 0 then
    for ext_hospital_id in
      select distinct src_hosp.id
      from (
        select hospital_id as id from public.medical_records where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select hospital_id as id from public.prescriptions where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select hospital_id as id from public.laboratory_results where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select hospital_id as id from public.laboratory_requests where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select hospital_id as id from public.medical_documents where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select hospital_id as id from public.diagnoses where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select hospital_id as id from public.treatment_plans where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select hospital_id as id from public.consultations where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select consent_row.source_hospital_id as id where consent_row.source_hospital_id is not null
        union
        select id from public.hospitals where verification_status = 'verified'
      ) src_hosp
      where src_hosp.id <> relationship_row.hospital_id
    loop
      select id into external_grant_id
      from public.patient_access_grants
      where care_relationship_id = relationship_row.id
        and source_hospital_id = ext_hospital_id
        and receiving_hospital_id = relationship_row.hospital_id
        and receiving_doctor_id = target_doctor_id
        and status in ('requested', 'active')
        and revoked_at is null
      for update;

      if external_grant_id is null then
        insert into public.patient_access_grants(
          patient_id, care_relationship_id, consent_id, source_hospital_id,
          receiving_hospital_id, receiving_doctor_id, consultation_id,
          purpose, status, selection_mode, permitted_actions,
          external_read_only, activated_at, expires_at
        ) values (
          relationship_row.patient_id, relationship_row.id, consent_row.id,
          ext_hospital_id, relationship_row.hospital_id,
          target_doctor_id, target_consultation_id, relationship_row.purpose,
          'active', consent_row.record_selection_mode,
          array['view', 'download']::text[], true, now(), grant_expiry
        ) returning id into external_grant_id;
      else
        update public.patient_access_grants
        set consent_id = consent_row.id,
            consultation_id = coalesce(target_consultation_id, consultation_id),
            status = 'active',
            selection_mode = consent_row.record_selection_mode,
            permitted_actions = array['view', 'download']::text[],
            external_read_only = true,
            activated_at = coalesce(activated_at, now()),
            expires_at = grant_expiry,
            updated_at = now()
        where id = external_grant_id;
      end if;

      foreach category in array consent_row.categories loop
        if not private.valid_record_category(category) then
          raise exception 'Unsupported record category: %', category;
        end if;
        insert into public.patient_access_scopes(
          grant_id, record_category, can_view, can_download, can_create
        ) values (
          external_grant_id, category, true,
          category in ('prescriptions', 'laboratory_results', 'medical_documents'),
          false
        )
        on conflict (grant_id, record_category) do update
        set can_view = excluded.can_view,
            can_download = excluded.can_download,
            can_create = false;
      end loop;
    end loop;
  end if;

  perform private.validate_record_selections(relationship_row.patient_id,consent_row.categories,target_selected_records);
  insert into public.patient_access_record_selections(grant_id,record_category,source_table,record_id)
  select g.id,item->>'category',item->>'source_table',(item->>'record_id')::uuid
  from public.patient_access_grants g cross join jsonb_array_elements(target_selected_records) item
  where g.care_relationship_id=relationship_row.id and g.status='active' and g.revoked_at is null
  on conflict (grant_id,source_table,record_id) do nothing;
  return local_grant_id;
end;
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
  if not private.is_hospital_admin_for(request_row.hospital_id) and not (
    normalized_decision='confirmed' and request_row.request_status='schedule_proposed'
    and request_row.patient_id=private.current_patient_id() and request_row.submitted_by=private.current_user_id()
    and target_doctor_id=request_row.assigned_doctor_id and target_confirmed_schedule=request_row.proposed_schedule
    and normalized_channel=request_row.consultation_channel and request_row.reviewed_by is not null
  ) then
    raise exception 'Hospital acceptance is required for this request';
  end if;
  if request_row.request_status in ('confirmed','awaiting_contact','video_ready','in_progress','completed','rejected','cancelled','no_show','face_to_face_recommended','patient_unreachable') then
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
  elsif normalized_decision in ('rejected', 'cancelled') then
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
        reviewed_by = coalesce(request_row.reviewed_by,private.current_user_id()), reviewed_at = coalesce(request_row.reviewed_at,now()), updated_at = now()
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
CREATE OR REPLACE FUNCTION public.transition_online_consultation_request(target_request_id uuid, target_status text, transition_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.online_consultation_requests; c public.consultations;
begin
  select * into r from public.online_consultation_requests where id=target_request_id for update;
  if not found or auth.uid() is null or private.current_role() not in ('doctor','hospital_admin')
    or (r.assigned_doctor_id is distinct from private.current_doctor_id() and not private.is_hospital_admin_for(r.hospital_id)) then
    raise exception 'This online request is not assigned to the current care team';
  end if;
  select * into c from public.consultations where id=r.official_consultation_id for update;
  if not found or r.request_status not in ('confirmed','awaiting_contact','video_ready','in_progress') then
    raise exception 'Only a confirmed active request may enter the consultation workflow';
  end if;
  if target_status='completed' then raise exception 'Complete the consultation using the structured checkup'; end if;
  if target_status='in_progress' then
    perform public.transition_consultation(c.id,'in_progress',transition_notes);
  elsif target_status='video_ready' then
    perform public.ensure_video_session(c.id,'jitsi');
  elsif target_status='awaiting_contact' then
    if nullif(btrim(transition_notes),'') is null then raise exception 'Record the contact attempt'; end if;
    update public.online_consultation_requests set request_status=case when r.request_status='in_progress' then 'in_progress' else 'awaiting_contact' end,
      contact_attempt_status='attempted',contact_attempted_at=now(),contact_attempt_notes=btrim(transition_notes)
      where id=r.id;
  elsif target_status in ('no_show','patient_unreachable') then
    if now()<c.appointment_date+interval '30 minutes' or c.started_at is not null or c.status='in_progress'
      or r.contact_attempted_at is null or nullif(btrim(r.contact_attempt_notes),'') is null then
      raise exception 'A missed visit requires 30 elapsed minutes, a recorded contact attempt and no clinical start';
    end if;
    if nullif(btrim(transition_notes),'') is null then raise exception 'Record the missed-visit outcome'; end if;
    update public.online_consultation_requests set request_status=target_status,outcome_notes=btrim(transition_notes) where id=r.id;
  elsif target_status='face_to_face_recommended' then
    if r.assigned_doctor_id is distinct from private.current_doctor_id() then raise exception 'Only the assigned doctor may recommend clinical follow-up'; end if;
    if nullif(btrim(transition_notes),'') is null then raise exception 'A recommendation reason is required'; end if;
    update public.online_consultation_requests set request_status=target_status,outcome_notes=btrim(transition_notes),
      additional_information_request=btrim(transition_notes) where id=r.id;
  else raise exception 'Unsupported online transition'; end if;
  return (select jsonb_build_object('request_id',id,'status',request_status,'consultation_id',official_consultation_id)
    from public.online_consultation_requests where id=r.id);
end $function$
;
