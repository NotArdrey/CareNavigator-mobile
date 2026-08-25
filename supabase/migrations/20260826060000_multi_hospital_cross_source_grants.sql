-- Multi-hospital Cross-source Access Grant Activation
-- Ensures that when a care relationship or consultation is approved/activated,
-- receiving doctors receive authorized external read-only access grants across
-- all hospitals where the patient has historical clinical records.

create or replace function private.activate_relationship_access(
  target_relationship_id uuid,
  target_consent_id uuid,
  target_doctor_id uuid,
  target_consultation_id uuid,
  target_selected_records jsonb default '[]'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
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

  return local_grant_id;
end;
$function$;
