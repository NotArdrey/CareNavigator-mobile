-- Multi-hospital patient identity, consent, care relationship, scoped access,
-- immutable provenance, and reviewed online consultation foundation.
--
-- This migration is intentionally additive before it replaces legacy clinical
-- RLS near the end of the file. Existing face-to-face consultations are kept;
-- only authenticated online booking is redirected to a reviewed request.

create schema if not exists private;

-- ---------------------------------------------------------------------------
-- Foundation entities
-- ---------------------------------------------------------------------------

create table if not exists public.patient_hospital_identifiers (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  hospital_id uuid not null references public.hospitals(id) on delete cascade,
  local_mrn text not null,
  status text not null default 'active'
    check (status in ('pending', 'active', 'merged', 'retired', 'quarantined')),
  verified_at timestamptz,
  retired_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (patient_id, hospital_id),
  unique (hospital_id, local_mrn)
);

create table if not exists public.doctor_hospital_employments (
  id uuid primary key default gen_random_uuid(),
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  hospital_id uuid not null references public.hospitals(id) on delete cascade,
  employment_status text not null default 'pending'
    check (employment_status in ('pending', 'active', 'suspended', 'ended', 'revoked')),
  is_verified boolean not null default false,
  verified_by uuid references public.users(id),
  verified_at timestamptz,
  starts_at timestamptz not null default now(),
  ends_at timestamptz,
  termination_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at is null or ends_at >= starts_at),
  unique (doctor_id, hospital_id)
);

alter table public.hospitals
  add column if not exists online_request_workflow_enabled boolean not null default false;

update public.hospitals
set online_request_workflow_enabled = true,
    updated_at = now()
where id = '20000000-0000-4000-8000-000000000001'::uuid;

alter table public.doctor_patient_assignments
  add column if not exists hospital_id uuid references public.hospitals(id),
  add column if not exists care_relationship_id uuid,
  add column if not exists consultation_id uuid references public.consultations(id),
  add column if not exists assignment_status text not null default 'active',
  add column if not exists ended_reason text;

create table if not exists public.patient_care_relationships (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  hospital_id uuid not null references public.hospitals(id) on delete cascade,
  doctor_id uuid references public.doctors(id) on delete set null,
  consultation_id uuid references public.consultations(id) on delete set null,
  online_request_id uuid,
  referral_reference text,
  relationship_type text not null
    check (relationship_type in (
      'consultation', 'referral', 'second_opinion',
      'ongoing_outpatient_care', 'transfer', 'emergency'
    )),
  purpose text not null,
  status text not null default 'requested'
    check (status in (
      'requested', 'approved', 'active', 'completed', 'revoked', 'expired'
    )),
  requested_at timestamptz not null default now(),
  approved_at timestamptz,
  starts_at timestamptz,
  expires_at timestamptz,
  ended_at timestamptz,
  termination_reason text,
  created_by uuid references public.users(id),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at is null or starts_at is null or expires_at > starts_at)
);

alter table public.patient_consents
  add column if not exists care_relationship_id uuid
    references public.patient_care_relationships(id) on delete set null,
  add column if not exists source_hospital_id uuid
    references public.hospitals(id) on delete restrict,
  add column if not exists receiving_hospital_id uuid
    references public.hospitals(id) on delete restrict,
  add column if not exists purpose text,
  add column if not exists categories text[] not null default '{}'::text[],
  add column if not exists permitted_actions text[] not null default '{view}'::text[],
  add column if not exists record_selection_mode text not null default 'categories',
  add column if not exists expires_at timestamptz,
  add column if not exists granted_by uuid references public.users(id),
  add column if not exists revocation_reason text,
  add column if not exists replaces_consent_id uuid
    references public.patient_consents(id) on delete set null,
  add column if not exists version_sequence integer not null default 1;

do $block$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'patient_consents_selection_mode_check'
      and conrelid = 'public.patient_consents'::regclass
  ) then
    alter table public.patient_consents
      add constraint patient_consents_selection_mode_check
      check (record_selection_mode in ('categories', 'selected_records'));
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'patient_consents_expiry_check'
      and conrelid = 'public.patient_consents'::regclass
  ) then
    alter table public.patient_consents
      add constraint patient_consents_expiry_check
      check (expires_at is null or granted_at is null or expires_at > granted_at);
  end if;
end
$block$;

create table if not exists public.patient_access_grants (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  care_relationship_id uuid not null
    references public.patient_care_relationships(id) on delete cascade,
  consent_id uuid not null references public.patient_consents(id) on delete restrict,
  source_hospital_id uuid not null references public.hospitals(id) on delete restrict,
  receiving_hospital_id uuid not null references public.hospitals(id) on delete restrict,
  receiving_doctor_id uuid not null references public.doctors(id) on delete restrict,
  consultation_id uuid references public.consultations(id) on delete set null,
  purpose text not null,
  status text not null default 'requested'
    check (status in ('requested', 'active', 'suspended', 'revoked', 'expired')),
  selection_mode text not null default 'categories'
    check (selection_mode in ('categories', 'selected_records')),
  permitted_actions text[] not null default '{view}'::text[],
  external_read_only boolean not null default true,
  activated_at timestamptz,
  expires_at timestamptz not null,
  revoked_at timestamptz,
  revoked_by uuid references public.users(id),
  revocation_reason text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at > created_at)
);

create unique index if not exists patient_access_grants_active_source_uidx
  on public.patient_access_grants(
    care_relationship_id, source_hospital_id, receiving_hospital_id,
    receiving_doctor_id
  )
  where status in ('requested', 'active') and revoked_at is null;

create table if not exists public.patient_access_scopes (
  id uuid primary key default gen_random_uuid(),
  grant_id uuid not null references public.patient_access_grants(id) on delete cascade,
  record_category text not null
    check (record_category in (
      'consultations', 'medical_records', 'diagnoses', 'prescriptions',
      'laboratory_requests', 'laboratory_results', 'medical_documents',
      'clinical_notes', 'allergies_medications', 'treatment_plans'
    )),
  can_view boolean not null default true,
  can_download boolean not null default false,
  can_create boolean not null default false,
  created_at timestamptz not null default now(),
  unique (grant_id, record_category)
);

create table if not exists public.patient_access_record_selections (
  id uuid primary key default gen_random_uuid(),
  grant_id uuid not null references public.patient_access_grants(id) on delete cascade,
  record_category text not null,
  source_table text not null,
  record_id uuid not null,
  created_at timestamptz not null default now(),
  unique (grant_id, source_table, record_id)
);

create table if not exists public.patient_representatives (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  representative_user_id uuid not null references public.users(id) on delete cascade,
  authority_type text not null
    check (authority_type in ('guardian', 'parent', 'healthcare_proxy', 'legal_representative')),
  authority_scope text[] not null default '{consent,view}'::text[],
  verification_status text not null default 'pending'
    check (verification_status in ('pending', 'verified', 'rejected', 'revoked', 'expired')),
  evidence_document_id uuid references public.medical_documents(id) on delete set null,
  starts_at timestamptz not null default now(),
  expires_at timestamptz,
  revoked_at timestamptz,
  verified_by uuid references public.users(id),
  verified_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (patient_id, representative_user_id, authority_type)
);

create table if not exists public.clinical_record_addenda (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  record_category text not null,
  source_table text not null,
  record_id uuid not null,
  originating_hospital_id uuid not null references public.hospitals(id) on delete restrict,
  author_doctor_id uuid references public.doctors(id) on delete restrict,
  author_user_id uuid not null references public.users(id) on delete restrict,
  addendum_text text not null check (length(btrim(addendum_text)) between 2 and 10000),
  correction_reason text not null check (length(btrim(correction_reason)) between 2 and 2000),
  supersedes_addendum_id uuid references public.clinical_record_addenda(id) on delete restrict,
  created_at timestamptz not null default now()
);

create table if not exists public.emergency_access_events (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  doctor_id uuid not null references public.doctors(id) on delete restrict,
  reason text not null check (length(btrim(reason)) between 10 and 2000),
  categories text[] not null,
  status text not null default 'active'
    check (status in ('active', 'ended', 'revoked', 'expired', 'under_review')),
  started_at timestamptz not null default now(),
  expires_at timestamptz not null,
  ended_at timestamptz,
  patient_notified_at timestamptz,
  reviewed_by uuid references public.users(id),
  reviewed_at timestamptz,
  review_notes text,
  created_at timestamptz not null default now(),
  check (expires_at > started_at),
  check (expires_at <= started_at + interval '4 hours')
);

create table if not exists public.clinical_record_quarantine (
  id uuid primary key default gen_random_uuid(),
  source_table text not null,
  record_id uuid not null,
  patient_id uuid references public.patients(id) on delete set null,
  quarantine_reason text not null,
  snapshot jsonb not null,
  quarantined_at timestamptz not null default now(),
  resolved_at timestamptz,
  resolved_by uuid references public.users(id),
  resolution_notes text,
  unique (source_table, record_id)
);

-- Provenance fields that are missing from the legacy document contract.
alter table public.medical_documents
  add column if not exists author_doctor_id uuid references public.doctors(id),
  add column if not exists origin_type text not null default 'hospital_generated',
  add column if not exists record_status text not null default 'final';

do $block$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'medical_documents_origin_type_check'
      and conrelid = 'public.medical_documents'::regclass
  ) then
    alter table public.medical_documents
      add constraint medical_documents_origin_type_check
      check (origin_type in ('hospital_generated', 'patient_supplied', 'external_import', 'legacy_unknown'));
  end if;
end
$block$;

-- ---------------------------------------------------------------------------
-- Reviewed online consultation requests
-- ---------------------------------------------------------------------------

create sequence if not exists public.online_consultation_reference_seq;

create table if not exists public.online_consultation_requests (
  id uuid primary key default gen_random_uuid(),
  reference_number text not null unique,
  patient_id uuid not null references public.patients(id) on delete restrict,
  submitted_by uuid not null references public.users(id) on delete restrict,
  profile_first_name text not null,
  profile_last_name text not null,
  profile_email text,
  phone_number_snapshot text not null,
  birth_date_snapshot date,
  address_snapshot text,
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  requested_department_id uuid not null references public.hospital_departments(id) on delete restrict,
  requested_doctor_id uuid references public.doctors(id) on delete set null,
  assigned_doctor_id uuid references public.doctors(id) on delete set null,
  medical_concern text not null check (length(btrim(medical_concern)) between 10 and 2000),
  symptom_duration text not null check (length(btrim(symptom_duration)) between 1 and 200),
  preferred_schedule timestamptz not null,
  proposed_schedule timestamptz,
  confirmed_schedule timestamptz,
  supporting_document_ids uuid[] not null default '{}'::uuid[],
  shared_categories text[] not null default '{}'::text[],
  selected_records jsonb not null default '[]'::jsonb,
  consent_id uuid not null references public.patient_consents(id) on delete restrict,
  care_relationship_id uuid not null references public.patient_care_relationships(id) on delete restrict,
  consultation_channel text
    check (consultation_channel in ('call', 'sms_assisted', 'video')),
  request_status text not null default 'submitted'
    check (request_status in (
      'submitted', 'under_review', 'more_information_required',
      'schedule_proposed', 'confirmed', 'awaiting_contact', 'video_ready',
      'in_progress', 'completed', 'patient_unreachable', 'rejected',
      'cancelled', 'no_show', 'face_to_face_recommended'
    )),
  official_consultation_id uuid references public.consultations(id) on delete set null,
  additional_information_request text,
  contact_attempt_status text,
  contact_attempted_at timestamptz,
  reviewed_by uuid references public.users(id),
  reviewed_at timestamptz,
  rejection_reason text,
  cancellation_reason text,
  hospital_feature_key text not null default 'reviewed_online_consultation',
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (preferred_schedule > created_at)
);

alter table public.patient_care_relationships
  drop constraint if exists patient_care_relationships_online_request_id_fkey;
alter table public.patient_care_relationships
  add constraint patient_care_relationships_online_request_id_fkey
  foreign key (online_request_id) references public.online_consultation_requests(id);

alter table public.doctor_patient_assignments
  drop constraint if exists doctor_patient_assignments_care_relationship_id_fkey;
alter table public.doctor_patient_assignments
  add constraint doctor_patient_assignments_care_relationship_id_fkey
  foreign key (care_relationship_id) references public.patient_care_relationships(id)
  on delete set null;

do $block$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'doctor_patient_assignments_status_check'
      and conrelid = 'public.doctor_patient_assignments'::regclass
  ) then
    alter table public.doctor_patient_assignments
      add constraint doctor_patient_assignments_status_check
      check (assignment_status in ('active', 'ended', 'revoked'));
  end if;
end
$block$;

create table if not exists public.online_consultation_request_status_history (
  id bigint generated by default as identity primary key,
  request_id uuid not null references public.online_consultation_requests(id) on delete cascade,
  from_status text,
  to_status text not null,
  changed_by uuid references public.users(id),
  notes text,
  created_at timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Indexes
-- ---------------------------------------------------------------------------

create index if not exists patient_identifiers_patient_idx
  on public.patient_hospital_identifiers(patient_id, status);
create index if not exists doctor_employments_actor_idx
  on public.doctor_hospital_employments(doctor_id, hospital_id, employment_status, ends_at);
create index if not exists care_relationships_actor_idx
  on public.patient_care_relationships(patient_id, hospital_id, doctor_id, status, expires_at);
create index if not exists care_relationships_consultation_idx
  on public.patient_care_relationships(consultation_id) where consultation_id is not null;
create index if not exists care_relationships_online_request_idx
  on public.patient_care_relationships(online_request_id) where online_request_id is not null;
create unique index if not exists doctor_assignments_active_relationship_uidx
  on public.doctor_patient_assignments(care_relationship_id)
  where care_relationship_id is not null and ended_at is null and assignment_status = 'active';
create index if not exists patient_consents_access_idx
  on public.patient_consents(patient_id, receiving_hospital_id, care_relationship_id, expires_at)
  where is_granted and revoked_at is null;
create index if not exists patient_access_grants_actor_idx
  on public.patient_access_grants(patient_id, receiving_doctor_id, receiving_hospital_id, status, expires_at);
create index if not exists patient_access_grants_source_idx
  on public.patient_access_grants(patient_id, source_hospital_id, status, expires_at);
create index if not exists patient_access_scopes_category_idx
  on public.patient_access_scopes(grant_id, record_category);
create index if not exists patient_access_record_selection_idx
  on public.patient_access_record_selections(grant_id, record_category, record_id);
create index if not exists clinical_addenda_record_idx
  on public.clinical_record_addenda(source_table, record_id, created_at);
create index if not exists emergency_access_actor_idx
  on public.emergency_access_events(patient_id, doctor_id, hospital_id, status, expires_at);
create index if not exists online_requests_patient_idx
  on public.online_consultation_requests(patient_id, created_at desc);
create index if not exists online_requests_hospital_queue_idx
  on public.online_consultation_requests(hospital_id, request_status, created_at);
create index if not exists online_requests_doctor_queue_idx
  on public.online_consultation_requests(assigned_doctor_id, request_status, confirmed_schedule);
create index if not exists online_request_history_idx
  on public.online_consultation_request_status_history(request_id, created_at);

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------

create or replace function private.valid_record_category(target_category text)
returns boolean
language sql
immutable
set search_path to ''
as $function$
  select target_category = any (array[
    'consultations', 'medical_records', 'diagnoses', 'prescriptions',
    'laboratory_requests', 'laboratory_results', 'medical_documents',
    'clinical_notes', 'allergies_medications', 'treatment_plans'
  ]::text[])
$function$;

create or replace function private.has_active_doctor_employment(
  target_doctor_id uuid,
  target_hospital_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(exists (
    select 1
    from public.doctor_hospital_employments employment
    join public.doctors doctor on doctor.id = employment.doctor_id
    where employment.doctor_id = target_doctor_id
      and employment.hospital_id = target_hospital_id
      and employment.employment_status = 'active'
      and employment.is_verified
      and employment.starts_at <= now()
      and (employment.ends_at is null or employment.ends_at > now())
      and doctor.user_id = private.current_user_id()
  ), false)
$function$;

create or replace function private.is_active_care_relationship(
  target_relationship_id uuid,
  target_patient_id uuid,
  target_hospital_id uuid,
  target_doctor_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(exists (
    select 1
    from public.patient_care_relationships relationship
    where relationship.id = target_relationship_id
      and relationship.patient_id = target_patient_id
      and relationship.hospital_id = target_hospital_id
      and relationship.doctor_id = target_doctor_id
      and relationship.status = 'active'
      and coalesce(relationship.starts_at, relationship.approved_at, relationship.requested_at) <= now()
      and (relationship.expires_at is null or relationship.expires_at > now())
      and (relationship.ended_at is null or relationship.ended_at > now())
      and (
        relationship.consultation_id is null
        or exists (
          select 1
          from public.consultations consultation
          where consultation.id = relationship.consultation_id
            and consultation.patient_id = relationship.patient_id
            and consultation.hospital_id = relationship.hospital_id
            and consultation.doctor_id = relationship.doctor_id
            and consultation.status in ('approved', 'scheduled', 'in_progress')
        )
      )
      and exists (
        select 1
        from public.doctor_patient_assignments assignment
        where assignment.patient_id = relationship.patient_id
          and assignment.doctor_id = relationship.doctor_id
          and assignment.care_relationship_id = relationship.id
          and assignment.assignment_status = 'active'
          and assignment.ended_at is null
      )
  ), false)
$function$;

create or replace function private.can_access_clinical_record(
  target_patient_id uuid,
  target_source_hospital_id uuid,
  target_category text,
  target_record_id uuid,
  target_action text default 'view'
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    target_patient_id = private.current_patient_id()
    or (
      private.valid_record_category(target_category)
      and target_action in ('view', 'download', 'create')
      and exists (
        select 1
        from public.patient_access_grants grant_row
        join public.patient_consents consent on consent.id = grant_row.consent_id
        join public.patient_access_scopes scope on scope.grant_id = grant_row.id
        where grant_row.patient_id = target_patient_id
          and grant_row.receiving_doctor_id = private.current_doctor_id()
          and (
            grant_row.source_hospital_id = target_source_hospital_id
            or (
              target_source_hospital_id is null
              and target_category = 'medical_documents'
              and target_record_id is not null
              and exists (
                select 1
                from public.patient_access_record_selections patient_selection
                where patient_selection.grant_id = grant_row.id
                  and patient_selection.record_category = target_category
                  and patient_selection.record_id = target_record_id
              )
            )
          )
          and grant_row.status = 'active'
          and grant_row.activated_at is not null
          and grant_row.activated_at <= now()
          and grant_row.expires_at > now()
          and grant_row.revoked_at is null
          and consent.patient_id = grant_row.patient_id
          and consent.care_relationship_id = grant_row.care_relationship_id
          and consent.is_granted
          and consent.granted_at is not null
          and consent.revoked_at is null
          and (consent.expires_at is null or consent.expires_at > now())
          and target_category = any(consent.categories)
          and target_action = any(consent.permitted_actions)
          and scope.record_category = target_category
          and case target_action
            when 'view' then scope.can_view
            when 'download' then scope.can_download
            when 'create' then scope.can_create
            else false
          end
          and private.has_active_doctor_employment(
            grant_row.receiving_doctor_id,
            grant_row.receiving_hospital_id
          )
          and private.is_active_care_relationship(
            grant_row.care_relationship_id,
            grant_row.patient_id,
            grant_row.receiving_hospital_id,
            grant_row.receiving_doctor_id
          )
          and (
            target_action <> 'create'
            or (
              grant_row.source_hospital_id = grant_row.receiving_hospital_id
              and not grant_row.external_read_only
            )
          )
          and (
            grant_row.selection_mode = 'categories'
            or target_record_id is null
            or exists (
              select 1
              from public.patient_access_record_selections selection
              where selection.grant_id = grant_row.id
                and selection.record_category = target_category
                and selection.record_id = target_record_id
            )
          )
      )
    )
    or (
      target_action = 'view'
      and exists (
        select 1
        from public.emergency_access_events emergency
        where emergency.patient_id = target_patient_id
          and emergency.doctor_id = private.current_doctor_id()
          and emergency.status = 'active'
          and emergency.started_at <= now()
          and emergency.expires_at > now()
          and target_category = any(emergency.categories)
          and private.has_active_doctor_employment(
            emergency.doctor_id,
            emergency.hospital_id
          )
      )
    ),
    false
  )
$function$;

-- Compatibility helper retained for existing application queries. It now means
-- "the current actor has at least one active scoped grant", not broad patient
-- access from any historical consultation.
create or replace function private.can_access_patient(target_patient_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    target_patient_id = private.current_patient_id()
    or exists (
      select 1
      from public.patient_access_grants grant_row
      join public.patient_access_scopes scope on scope.grant_id = grant_row.id
      where grant_row.patient_id = target_patient_id
        and grant_row.receiving_doctor_id = private.current_doctor_id()
        and grant_row.status = 'active'
        and grant_row.activated_at <= now()
        and grant_row.expires_at > now()
        and grant_row.revoked_at is null
        and scope.can_view
        and private.has_active_doctor_employment(
          grant_row.receiving_doctor_id,
          grant_row.receiving_hospital_id
        )
        and private.is_active_care_relationship(
          grant_row.care_relationship_id,
          grant_row.patient_id,
          grant_row.receiving_hospital_id,
          grant_row.receiving_doctor_id
        )
    )
    or exists (
      select 1
      from public.emergency_access_events emergency
      where emergency.patient_id = target_patient_id
        and emergency.doctor_id = private.current_doctor_id()
        and emergency.status = 'active'
        and emergency.expires_at > now()
    ),
    false
  )
$function$;

create or replace function private.can_access_online_request(target_request_id uuid)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(exists (
    select 1
    from public.online_consultation_requests request
    where request.id = target_request_id
      and (
        request.patient_id = private.current_patient_id()
        or request.submitted_by = private.current_user_id()
        or request.assigned_doctor_id = private.current_doctor_id()
        or (
          request.requested_doctor_id = private.current_doctor_id()
          and request.request_status in ('submitted', 'under_review', 'schedule_proposed')
        )
        or private.is_hospital_admin_for(request.hospital_id)
      )
  ), false)
$function$;

create or replace function private.set_online_request_reference()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if nullif(btrim(new.reference_number), '') is null then
    new.reference_number := 'ONL-' || to_char(now() at time zone 'Asia/Manila', 'YYYYMMDD')
      || '-' || lpad(nextval('public.online_consultation_reference_seq')::text, 6, '0');
  end if;
  return new;
end
$function$;

create or replace function private.record_online_request_status()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if tg_op = 'INSERT' or new.request_status is distinct from old.request_status then
    insert into public.online_consultation_request_status_history(
      request_id, from_status, to_status, changed_by
    ) values (
      new.id,
      case when tg_op = 'UPDATE' then old.request_status else null end,
      new.request_status,
      private.current_user_id()
    );
  end if;
  return new;
end
$function$;

create or replace function private.audit_multi_hospital_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  payload jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  actor_hospital uuid := nullif(payload->>'hospital_id', '')::uuid;
  target_id uuid := nullif(payload->>'id', '')::uuid;
begin
  insert into public.audit_logs(user_id, hospital_id, action, module, record_id, metadata)
  values (
    private.current_user_id(),
    actor_hospital,
    lower(tg_op),
    tg_table_name,
    target_id,
    jsonb_build_object(
      'table', tg_table_schema || '.' || tg_table_name,
      'patient_id', payload->>'patient_id',
      'care_relationship_id', payload->>'care_relationship_id',
      'request_id', payload->>'request_id'
    )
  );
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$function$;

create or replace function private.enforce_clinical_provenance()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  old_row jsonb := to_jsonb(old);
  new_row jsonb := to_jsonb(new);
  protected_column text;
begin
  foreach protected_column in array array[
    'patient_id', 'hospital_id', 'doctor_id', 'author_doctor_id',
    'consultation_id', 'created_at', 'record_date', 'requested_at', 'uploaded_at'
  ] loop
    if old_row ? protected_column
      and new_row ? protected_column
      and old_row->protected_column is distinct from new_row->protected_column then
      raise exception 'Clinical provenance column % is immutable; add an addendum instead', protected_column;
    end if;
  end loop;
  return new;
end
$function$;

revoke all on function private.valid_record_category(text) from public, anon, authenticated;
revoke all on function private.has_active_doctor_employment(uuid, uuid) from public, anon, authenticated;
revoke all on function private.is_active_care_relationship(uuid, uuid, uuid, uuid) from public, anon, authenticated;
revoke all on function private.can_access_clinical_record(uuid, uuid, text, uuid, text) from public, anon, authenticated;
revoke all on function private.can_access_online_request(uuid) from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Backfill live provenance and existing confirmed care
-- ---------------------------------------------------------------------------

insert into public.doctor_hospital_employments(
  doctor_id, hospital_id, employment_status, is_verified,
  verified_at, starts_at
)
select doctor.id, doctor.hospital_id, 'active', true,
       coalesce(doctor.created_at, now()), coalesce(doctor.created_at, now())
from public.doctors doctor
on conflict (doctor_id, hospital_id) do update
set employment_status = case
      when public.doctor_hospital_employments.employment_status = 'pending' then 'active'
      else public.doctor_hospital_employments.employment_status
    end,
    is_verified = public.doctor_hospital_employments.is_verified
      or public.doctor_hospital_employments.employment_status = 'pending',
    verified_at = coalesce(public.doctor_hospital_employments.verified_at, excluded.verified_at),
    updated_at = now();

-- A doctor-authored document has reliable hospital provenance through the
-- immutable author profile. Patient-supplied documents intentionally retain a
-- null hospital and are labelled separately.
update public.medical_documents document
set author_doctor_id = doctor.id,
    hospital_id = coalesce(document.hospital_id, doctor.hospital_id),
    origin_type = 'hospital_generated'
from public.doctors doctor
where doctor.user_id = document.uploaded_by
  and document.author_doctor_id is null;

update public.medical_documents document
set origin_type = 'patient_supplied'
from public.patients patient
where patient.id = document.patient_id
  and patient.user_id = document.uploaded_by
  and document.author_doctor_id is null;

update public.medical_documents
set origin_type = 'legacy_unknown'
where hospital_id is null and origin_type <> 'patient_supplied';

insert into public.clinical_record_quarantine(
  source_table, record_id, patient_id, quarantine_reason, snapshot
)
select 'medical_documents', document.id, document.patient_id,
       'Hospital provenance could not be derived from the author, consultation, or reference',
       to_jsonb(document)
from public.medical_documents document
where document.hospital_id is null
  and document.origin_type = 'legacy_unknown'
on conflict (source_table, record_id) do nothing;

insert into public.patient_hospital_identifiers(
  patient_id, hospital_id, local_mrn, status, verified_at
)
select source.patient_id, source.hospital_id,
       'LEGACY-' || upper(substr(replace(source.patient_id::text, '-', ''), 1, 12)),
       'active', now()
from (
  select patient.id patient_id, patient.primary_hospital_id hospital_id
  from public.patients patient
  where patient.primary_hospital_id is not null
  union
  select consultation.patient_id, consultation.hospital_id
  from public.consultations consultation
  where consultation.patient_id is not null
) source
on conflict (patient_id, hospital_id) do nothing;

insert into public.patient_care_relationships(
  patient_id, hospital_id, doctor_id, consultation_id,
  relationship_type, purpose, status, requested_at, approved_at,
  starts_at, expires_at, ended_at, created_at, updated_at
)
select consultation.patient_id,
       consultation.hospital_id,
       consultation.doctor_id,
       consultation.id,
       'consultation',
       'Legacy confirmed consultation migration',
       case consultation.status
         when 'approved' then 'active'
         when 'scheduled' then 'active'
         when 'in_progress' then 'active'
         when 'completed' then 'completed'
         when 'pending' then 'requested'
         else 'revoked'
       end,
       consultation.created_at,
       consultation.approved_at,
       coalesce(consultation.approved_at, consultation.created_at),
       case when consultation.status in ('approved', 'scheduled', 'in_progress')
         then greatest(consultation.appointment_date + interval '7 days', now() + interval '30 days')
         else greatest(
           coalesce(consultation.completed_at, consultation.updated_at),
           coalesce(consultation.approved_at, consultation.created_at) + interval '1 second'
         )
       end,
       case when consultation.status in ('completed', 'cancelled', 'rejected')
         then coalesce(consultation.completed_at, consultation.updated_at)
         else null
       end,
       consultation.created_at,
       consultation.updated_at
from public.consultations consultation
where consultation.patient_id is not null
  and not exists (
    select 1 from public.patient_care_relationships relationship
    where relationship.consultation_id = consultation.id
  );

insert into public.patient_care_relationships(
  patient_id, hospital_id, doctor_id, relationship_type, purpose, status,
  requested_at, approved_at, starts_at, expires_at, created_at, updated_at
)
select assignment.patient_id,
       doctor.hospital_id,
       assignment.doctor_id,
       'ongoing_outpatient_care',
       'Legacy active doctor-patient assignment migration',
       'active',
       assignment.assigned_at,
       assignment.assigned_at,
       assignment.assigned_at,
       now() + interval '90 days',
       assignment.assigned_at,
       now()
from public.doctor_patient_assignments assignment
join public.doctors doctor on doctor.id = assignment.doctor_id
where assignment.ended_at is null
  and not exists (
    select 1 from public.patient_care_relationships relationship
    where relationship.patient_id = assignment.patient_id
      and relationship.doctor_id = assignment.doctor_id
      and relationship.status = 'active'
  );

with selected_relationship as (
  select distinct on (assignment.id)
    assignment.id assignment_id,
    doctor.hospital_id,
    relationship.id relationship_id,
    relationship.consultation_id
  from public.doctor_patient_assignments assignment
  join public.doctors doctor on doctor.id = assignment.doctor_id
  join public.patient_care_relationships relationship
    on relationship.patient_id = assignment.patient_id
   and relationship.doctor_id = assignment.doctor_id
  where assignment.care_relationship_id is null
  order by assignment.id,
    case when relationship.status = 'active' then 0 else 1 end,
    relationship.created_at desc
)
update public.doctor_patient_assignments assignment
set hospital_id = selected.hospital_id,
    care_relationship_id = selected.relationship_id,
    consultation_id = selected.consultation_id,
    assignment_status = case when assignment.ended_at is null then 'active' else 'ended' end
from selected_relationship selected
where selected.assignment_id = assignment.id;

insert into public.doctor_patient_assignments(
  doctor_id, patient_id, hospital_id, care_relationship_id,
  consultation_id, assigned_at, assignment_status, notes
)
select relationship.doctor_id, relationship.patient_id,
       relationship.hospital_id, relationship.id, relationship.consultation_id,
       coalesce(relationship.starts_at, relationship.requested_at),
       'active',
       'Backfilled from an active confirmed consultation'
from public.patient_care_relationships relationship
where relationship.status = 'active'
  and relationship.doctor_id is not null
  and not exists (
    select 1 from public.doctor_patient_assignments assignment
    where assignment.doctor_id = relationship.doctor_id
      and assignment.patient_id = relationship.patient_id
      and assignment.care_relationship_id = relationship.id
      and assignment.ended_at is null
  );

insert into public.patient_consents(
  patient_id, consent_type, consent_version, is_granted, granted_at,
  captured_by, metadata, care_relationship_id, source_hospital_id,
  receiving_hospital_id, purpose, categories, permitted_actions,
  record_selection_mode, expires_at, granted_by, version_sequence
)
select relationship.patient_id,
       'care_relationship_access',
       'legacy-' || relationship.id::text,
       true,
       coalesce(relationship.approved_at, relationship.starts_at, relationship.requested_at),
       app_user.auth_user_id,
       jsonb_build_object('backfilled', true, 'review_required', true),
       relationship.id,
       coalesce(patient.primary_hospital_id, relationship.hospital_id),
       relationship.hospital_id,
       relationship.purpose,
       array[
         'consultations', 'medical_records', 'diagnoses', 'prescriptions',
         'laboratory_requests', 'laboratory_results', 'medical_documents',
         'clinical_notes', 'allergies_medications', 'treatment_plans'
       ]::text[],
       array['view', 'download', 'create']::text[],
       'categories',
       relationship.expires_at,
       app_user.id,
       1
from public.patient_care_relationships relationship
join public.patients patient on patient.id = relationship.patient_id
join public.users app_user on app_user.id = patient.user_id
where relationship.status = 'active'
  and relationship.doctor_id is not null
on conflict (patient_id, consent_type, consent_version) do nothing;

insert into public.patient_access_grants(
  patient_id, care_relationship_id, consent_id, source_hospital_id,
  receiving_hospital_id, receiving_doctor_id, consultation_id, purpose,
  status, selection_mode, permitted_actions, external_read_only,
  activated_at, expires_at, created_at
)
select relationship.patient_id,
       relationship.id,
       consent.id,
       relationship.hospital_id,
       relationship.hospital_id,
       relationship.doctor_id,
       relationship.consultation_id,
       relationship.purpose,
       'active',
       'categories',
       array['view', 'download', 'create']::text[],
       false,
       coalesce(relationship.starts_at, now()),
       coalesce(relationship.expires_at, now() + interval '30 days'),
       coalesce(relationship.created_at, now())
from public.patient_care_relationships relationship
join public.patient_consents consent on consent.care_relationship_id = relationship.id
where relationship.status = 'active'
  and relationship.doctor_id is not null
on conflict do nothing;

insert into public.patient_access_grants(
  patient_id, care_relationship_id, consent_id, source_hospital_id,
  receiving_hospital_id, receiving_doctor_id, consultation_id, purpose,
  status, selection_mode, permitted_actions, external_read_only,
  activated_at, expires_at, created_at
)
select relationship.patient_id,
       relationship.id,
       consent.id,
       consent.source_hospital_id,
       relationship.hospital_id,
       relationship.doctor_id,
       relationship.consultation_id,
       relationship.purpose,
       'active',
       consent.record_selection_mode,
       array['view', 'download']::text[],
       true,
       coalesce(relationship.starts_at, now()),
       coalesce(consent.expires_at, relationship.expires_at, now() + interval '30 days'),
       coalesce(relationship.created_at, now())
from public.patient_care_relationships relationship
join public.patient_consents consent on consent.care_relationship_id = relationship.id
where relationship.status = 'active'
  and relationship.doctor_id is not null
  and consent.source_hospital_id is not null
  and consent.source_hospital_id <> relationship.hospital_id
on conflict do nothing;

insert into public.patient_access_scopes(
  grant_id, record_category, can_view, can_download, can_create
)
select grant_row.id,
       category,
       true,
       category in ('prescriptions', 'laboratory_results', 'medical_documents'),
       not grant_row.external_read_only
from public.patient_access_grants grant_row
cross join lateral unnest(array[
  'consultations', 'medical_records', 'diagnoses', 'prescriptions',
  'laboratory_requests', 'laboratory_results', 'medical_documents',
  'clinical_notes', 'allergies_medications', 'treatment_plans'
]::text[]) category
on conflict (grant_id, record_category) do nothing;

-- ---------------------------------------------------------------------------
-- Relationship activation and revocation
-- ---------------------------------------------------------------------------

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

  if consent_row.source_hospital_id is not null
    and consent_row.source_hospital_id <> relationship_row.hospital_id
    and cardinality(consent_row.categories) > 0 then
    select id into external_grant_id
    from public.patient_access_grants
    where care_relationship_id = relationship_row.id
      and source_hospital_id = consent_row.source_hospital_id
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
        consent_row.source_hospital_id, relationship_row.hospital_id,
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

    delete from public.patient_access_record_selections
    where grant_id = external_grant_id;
    if consent_row.record_selection_mode = 'selected_records'
      and jsonb_typeof(target_selected_records) = 'array' then
      for selected_record in
        select value from jsonb_array_elements(target_selected_records)
      loop
        if private.valid_record_category(selected_record->>'category')
          and nullif(selected_record->>'source_table', '') is not null
          and coalesce(selected_record->>'record_id', '')
            ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
          insert into public.patient_access_record_selections(
            grant_id, record_category, source_table, record_id
          ) values (
            external_grant_id,
            selected_record->>'category',
            selected_record->>'source_table',
            (selected_record->>'record_id')::uuid
          )
          on conflict (grant_id, source_table, record_id) do nothing;
        end if;
      end loop;
    end if;
  end if;

  return local_grant_id;
end
$function$;

create or replace function private.revoke_relationship_access(
  target_relationship_id uuid,
  target_status text,
  target_reason text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  update public.patient_care_relationships
  set status = case when target_status = 'completed' then 'completed' else 'revoked' end,
      ended_at = coalesce(ended_at, now()),
      termination_reason = coalesce(nullif(btrim(target_reason), ''), target_status),
      updated_at = now()
  where id = target_relationship_id;

  update public.patient_access_grants
  set status = 'revoked',
      revoked_at = coalesce(revoked_at, now()),
      revoked_by = private.current_user_id(),
      revocation_reason = coalesce(nullif(btrim(target_reason), ''), target_status),
      updated_at = now()
  where care_relationship_id = target_relationship_id
    and status in ('requested', 'active', 'suspended')
    and revoked_at is null;

  update public.doctor_patient_assignments
  set assignment_status = 'ended',
      ended_at = coalesce(ended_at, now()),
      ended_reason = coalesce(nullif(btrim(target_reason), ''), target_status)
  where care_relationship_id = target_relationship_id
    and ended_at is null;
end
$function$;

revoke all on function private.activate_relationship_access(uuid, uuid, uuid, uuid, jsonb)
  from public, anon, authenticated;
revoke all on function private.revoke_relationship_access(uuid, text, text)
  from public, anon, authenticated;

-- ---------------------------------------------------------------------------
-- Patient submission and hospital review RPCs
-- ---------------------------------------------------------------------------

create or replace function public.submit_online_consultation_request(
  request_payload jsonb
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
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
  if not hospital_row.online_request_workflow_enabled then
    raise exception 'Reviewed online requests are not enabled for this hospital';
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
$function$;

create or replace function public.review_online_consultation_request(
  target_request_id uuid,
  decision text,
  target_doctor_id uuid default null,
  target_confirmed_schedule timestamptz default null,
  target_channel text default null,
  review_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  request_row public.online_consultation_requests;
  chosen_doctor_id uuid;
  chosen_schedule timestamptz;
  normalized_decision text := lower(btrim(coalesce(decision, '')));
  normalized_channel text := nullif(lower(btrim(coalesce(target_channel, ''))), '');
  consultation_id uuid;
begin
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
      or normalized_channel not in ('call', 'sms_assisted', 'video') then
      raise exception 'Choose call, SMS-assisted, or video consultation';
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

    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(chosen_doctor_id::text || ':' || chosen_schedule::date::text, 0)
    );
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
$function$;

create or replace function public.transition_online_consultation_request(
  target_request_id uuid,
  target_status text,
  transition_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  request_row public.online_consultation_requests;
  normalized_status text := lower(btrim(coalesce(target_status, '')));
begin
  select * into request_row
  from public.online_consultation_requests
  where id = target_request_id
  for update;

  if not found or (
    request_row.assigned_doctor_id is distinct from private.current_doctor_id()
    and not private.is_hospital_admin_for(request_row.hospital_id)
  ) then
    raise exception 'This online request is not assigned to the current care team';
  end if;
  if normalized_status not in (
    'awaiting_contact', 'video_ready', 'in_progress', 'completed',
    'patient_unreachable', 'no_show', 'face_to_face_recommended'
  ) then
    raise exception 'Unsupported online request transition';
  end if;
  if request_row.official_consultation_id is null
    or request_row.request_status not in (
      'confirmed', 'awaiting_contact', 'video_ready', 'in_progress'
    ) then
    raise exception 'Only a confirmed request may enter the consultation workflow';
  end if;
  if normalized_status = 'in_progress'
    and (now() < request_row.confirmed_schedule - interval '15 minutes'
      or now() >= request_row.confirmed_schedule + interval '4 hours') then
    raise exception 'The consultation is outside its confirmed appointment window';
  end if;

  update public.online_consultation_requests
  set request_status = normalized_status,
      contact_attempt_status = case
        when normalized_status in ('awaiting_contact', 'patient_unreachable')
          then normalized_status
        else contact_attempt_status
      end,
      contact_attempted_at = case
        when normalized_status in ('awaiting_contact', 'patient_unreachable')
          then now()
        else contact_attempted_at
      end,
      additional_information_request = case
        when normalized_status = 'face_to_face_recommended' then btrim(transition_notes)
        else additional_information_request
      end,
      updated_at = now()
  where id = request_row.id
  returning * into request_row;

  return jsonb_build_object(
    'request_id', request_row.id,
    'status', request_row.request_status,
    'consultation_id', request_row.official_consultation_id
  );
end
$function$;

create or replace function public.get_online_consultation_request_tracking(
  target_reference text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  request_row public.online_consultation_requests;
  doctor_name text;
  department_name text;
begin
  select * into request_row
  from public.online_consultation_requests request
  where request.reference_number = upper(btrim(target_reference))
     or request.id::text = btrim(target_reference)
  limit 1;

  if not found or not private.can_access_online_request(request_row.id) then
    raise exception 'The tracked request was not found for this verified account';
  end if;

  select doctor.display_name into doctor_name
  from public.doctors doctor where doctor.id = request_row.assigned_doctor_id;
  select department.department_name into department_name
  from public.hospital_departments department
  where department.id = request_row.requested_department_id;

  return jsonb_build_object(
    'request_id', request_row.id,
    'reference_number', request_row.reference_number,
    'status', request_row.request_status,
    'preferred_schedule', request_row.preferred_schedule,
    'proposed_schedule', request_row.proposed_schedule,
    'confirmed_schedule', request_row.confirmed_schedule,
    'registered_phone', request_row.phone_number_snapshot,
    'department', department_name,
    'doctor', doctor_name,
    'channel', request_row.consultation_channel,
    'consultation_id', request_row.official_consultation_id,
    'additional_information_request', request_row.additional_information_request,
    'contact_attempt_status', request_row.contact_attempt_status,
    'rejection_reason', request_row.rejection_reason,
    'cancellation_reason', request_row.cancellation_reason,
    'video_may_be_requested', request_row.request_status in ('confirmed', 'awaiting_contact', 'video_ready', 'in_progress')
      and request_row.consultation_channel = 'video'
  );
end
$function$;

create or replace function public.revoke_patient_access_grant(
  target_grant_id uuid,
  reason text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  grant_row public.patient_access_grants;
begin
  select * into grant_row
  from public.patient_access_grants
  where id = target_grant_id
  for update;
  if not found or grant_row.patient_id is distinct from private.current_patient_id() then
    raise exception 'The access grant was not found for this patient';
  end if;

  update public.patient_consents
  set is_granted = false,
      revoked_at = coalesce(revoked_at, now()),
      revocation_reason = nullif(btrim(reason), ''),
      updated_at = now()
  where id = grant_row.consent_id;

  perform private.revoke_relationship_access(
    grant_row.care_relationship_id, 'revoked', reason
  );
end
$function$;

revoke all on function public.submit_online_consultation_request(jsonb) from public, anon;
grant execute on function public.submit_online_consultation_request(jsonb) to authenticated, service_role;
revoke all on function public.review_online_consultation_request(uuid, text, uuid, timestamptz, text, text) from public, anon;
grant execute on function public.review_online_consultation_request(uuid, text, uuid, timestamptz, text, text) to authenticated, service_role;
revoke all on function public.transition_online_consultation_request(uuid, text, text) from public, anon;
grant execute on function public.transition_online_consultation_request(uuid, text, text) to authenticated, service_role;
revoke all on function public.get_online_consultation_request_tracking(text) from public, anon;
grant execute on function public.get_online_consultation_request_tracking(text) to authenticated, service_role;
revoke all on function public.revoke_patient_access_grant(uuid, text) from public, anon;
grant execute on function public.revoke_patient_access_grant(uuid, text) to authenticated, service_role;

-- Patient face-to-face scheduling stays an immediate official booking. At an
-- enabled hospital, the online branch creates only a reviewed request and does
-- not reserve the doctor slot.
create or replace function public.book_consultation(booking_payload jsonb)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
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

  if target_type = 'online' and reviewed_enabled then
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
    return (online_result->>'request_id')::uuid;
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(target_doctor::text || ':' || target_date::date::text, 0)
  );
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

  return booked_id;
end
$function$;

revoke all on function public.book_consultation(jsonb) from public, anon;
grant execute on function public.book_consultation(jsonb) to authenticated, service_role;

create or replace function private.sync_consultation_care_access()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  relationship_row public.patient_care_relationships;
  consent_row public.patient_consents;
  selected_records jsonb := '[]'::jsonb;
begin
  select * into relationship_row
  from public.patient_care_relationships relationship
  where relationship.consultation_id = new.id
  order by relationship.created_at desc
  limit 1;

  if relationship_row.id is null then
    return new;
  end if;

  if new.status in ('approved', 'scheduled', 'in_progress') then
    select * into consent_row
    from public.patient_consents consent
    where consent.care_relationship_id = relationship_row.id
      and consent.is_granted
      and consent.revoked_at is null
      and (consent.expires_at is null or consent.expires_at > now())
    order by consent.version_sequence desc, consent.created_at desc
    limit 1;

    if consent_row.id is not null then
      selected_records := coalesce(consent_row.metadata->'selected_records', '[]'::jsonb);
      perform private.activate_relationship_access(
        relationship_row.id, consent_row.id, new.doctor_id, new.id, selected_records
      );
    end if;
  elsif new.status in ('completed', 'cancelled', 'rejected') then
    perform private.revoke_relationship_access(
      relationship_row.id, new.status::text,
      coalesce(new.rejection_reason, 'Consultation ' || new.status::text)
    );
  end if;

  update public.online_consultation_requests request
  set request_status = case new.status
        when 'in_progress' then 'in_progress'
        when 'completed' then 'completed'
        when 'cancelled' then 'cancelled'
        when 'rejected' then 'rejected'
        else request.request_status
      end,
      updated_at = now()
  where request.official_consultation_id = new.id
    and new.status in ('in_progress', 'completed', 'cancelled', 'rejected');

  return new;
end
$function$;

create or replace function private.enforce_consultation_assignment_provenance()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.patient_id is distinct from old.patient_id
    or new.hospital_id is distinct from old.hospital_id then
    raise exception 'Consultation patient and hospital provenance are immutable';
  end if;
  if new.doctor_id is distinct from old.doctor_id
    and coalesce(current_setting('app.authorized_reassignment', true), 'off') <> 'on' then
    raise exception 'Use the protected reassignment workflow to change the assigned doctor';
  end if;
  return new;
end
$function$;

create or replace function public.reassign_consultation_doctor(
  target_consultation_id uuid,
  new_doctor_id uuid,
  reason text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  consultation_row public.consultations;
  relationship_row public.patient_care_relationships;
  consent_row public.patient_consents;
begin
  select * into consultation_row
  from public.consultations
  where id = target_consultation_id
  for update;
  if not found or not private.is_hospital_admin_for(consultation_row.hospital_id) then
    raise exception 'Hospital administration authorization is required';
  end if;
  if consultation_row.status not in ('approved', 'scheduled') then
    raise exception 'Only an approved or scheduled consultation may be reassigned';
  end if;
  if nullif(btrim(reason), '') is null then
    raise exception 'A reassignment reason is required';
  end if;
  if not exists (
    select 1 from public.doctor_hospital_employments employment
    where employment.doctor_id = new_doctor_id
      and employment.hospital_id = consultation_row.hospital_id
      and employment.employment_status = 'active'
      and employment.is_verified
      and (employment.ends_at is null or employment.ends_at > now())
  ) then
    raise exception 'The replacement doctor is not actively employed and verified';
  end if;

  perform set_config('app.authorized_reassignment', 'on', true);
  update public.consultations
  set doctor_id = new_doctor_id, updated_at = now()
  where id = consultation_row.id;

  select * into relationship_row
  from public.patient_care_relationships
  where consultation_id = consultation_row.id
  order by created_at desc limit 1;
  select * into consent_row
  from public.patient_consents
  where care_relationship_id = relationship_row.id
    and is_granted and revoked_at is null
  order by version_sequence desc, created_at desc limit 1;

  perform private.activate_relationship_access(
    relationship_row.id, consent_row.id, new_doctor_id,
    consultation_row.id, coalesce(consent_row.metadata->'selected_records', '[]'::jsonb)
  );
  insert into public.audit_logs(user_id, hospital_id, action, module, record_id, metadata)
  values (
    private.current_user_id(), consultation_row.hospital_id,
    'reassign', 'consultations', consultation_row.id,
    jsonb_build_object(
      'from_doctor_id', consultation_row.doctor_id,
      'to_doctor_id', new_doctor_id,
      'reason', btrim(reason)
    )
  );
end
$function$;

create or replace function private.sync_employment_termination()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.employment_status in ('suspended', 'ended', 'revoked')
    or (new.ends_at is not null and new.ends_at <= now()) then
    update public.patient_access_grants
    set status = 'revoked', revoked_at = coalesce(revoked_at, now()),
        revocation_reason = coalesce(revocation_reason, 'Doctor employment ended'),
        updated_at = now()
    where receiving_doctor_id = new.doctor_id
      and receiving_hospital_id = new.hospital_id
      and status in ('requested', 'active', 'suspended')
      and revoked_at is null;

    update public.patient_care_relationships
    set status = 'revoked', ended_at = coalesce(ended_at, now()),
        termination_reason = coalesce(termination_reason, 'Doctor employment ended'),
        updated_at = now()
    where doctor_id = new.doctor_id
      and hospital_id = new.hospital_id
      and status in ('requested', 'approved', 'active');

    update public.doctor_patient_assignments
    set assignment_status = 'ended', ended_at = coalesce(ended_at, now()),
        ended_reason = coalesce(ended_reason, 'Doctor employment ended')
    where doctor_id = new.doctor_id
      and hospital_id = new.hospital_id
      and ended_at is null;
  end if;
  return new;
end
$function$;

revoke all on function public.reassign_consultation_doctor(uuid, uuid, text) from public, anon;
grant execute on function public.reassign_consultation_doctor(uuid, uuid, text) to authenticated, service_role;

-- ---------------------------------------------------------------------------
-- Provenance, lifecycle, audit, and Storage triggers
-- ---------------------------------------------------------------------------

create or replace function private.set_medical_document_provenance()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  current_doctor public.doctors;
begin
  if new.uploaded_by is distinct from private.current_user_id() then
    raise exception 'Medical document author must match the authenticated application user';
  end if;

  select * into current_doctor
  from public.doctors doctor
  where doctor.id = private.current_doctor_id();

  if current_doctor.id is not null then
    new.author_doctor_id := current_doctor.id;
    new.hospital_id := current_doctor.hospital_id;
    new.origin_type := 'hospital_generated';
    if not private.can_access_clinical_record(
      new.patient_id, current_doctor.hospital_id,
      'medical_documents', null, 'create'
    ) then
      raise exception 'The doctor is not authorized to add a document for this care relationship';
    end if;
  elsif new.patient_id = private.current_patient_id() then
    new.author_doctor_id := null;
    new.hospital_id := null;
    new.origin_type := 'patient_supplied';
  else
    raise exception 'Only the patient or an authorized treating doctor may upload this document';
  end if;
  return new;
end
$function$;

create or replace function private.can_access_patient_storage(
  object_name text,
  object_bucket text,
  target_action text default 'view'
)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  folder text := (storage.foldername(object_name))[1];
  folder_uuid uuid;
begin
  if folder is not null
    and folder ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    folder_uuid := folder::uuid;
    if folder_uuid = private.current_patient_id() then
      return true;
    end if;
  end if;

  if exists (
    select 1
    from public.medical_documents document
    where document.storage_bucket = object_bucket
      and document.storage_path = object_name
      and private.can_access_clinical_record(
        document.patient_id, document.hospital_id,
        'medical_documents', document.id, target_action
      )
  ) then return true; end if;

  if exists (
    select 1
    from public.laboratory_results result
    where result.file_path = object_name
      and private.can_access_clinical_record(
        result.patient_id, result.hospital_id,
        'laboratory_results', result.id, target_action
      )
  ) then return true; end if;

  if exists (
    select 1
    from public.consultation_attachments attachment
    join public.consultations consultation on consultation.id = attachment.consultation_id
    where attachment.storage_path = object_name
      and private.can_access_clinical_record(
        coalesce(attachment.patient_id, consultation.patient_id),
        consultation.hospital_id, 'consultations', consultation.id, target_action
      )
  ) then return true; end if;

  return false;
end
$function$;

create or replace function private.can_upload_patient_storage(
  object_name text,
  object_bucket text
)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  folder text := (storage.foldername(object_name))[1];
  target_patient_id uuid;
  doctor_row public.doctors;
  category text;
begin
  if folder is null
    or folder !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return false;
  end if;
  target_patient_id := folder::uuid;
  if target_patient_id = private.current_patient_id() then return true; end if;

  select * into doctor_row from public.doctors where id = private.current_doctor_id();
  if doctor_row.id is null then return false; end if;
  category := case
    when object_bucket in ('laboratory-results', 'scanned-medical-results') then 'laboratory_results'
    when object_bucket = 'prescriptions' then 'prescriptions'
    else 'medical_documents'
  end;
  return private.can_access_clinical_record(
    target_patient_id, doctor_row.hospital_id, category, null, 'create'
  );
end
$function$;

revoke all on function private.can_access_patient_storage(text, text, text)
  from public, anon, authenticated;
revoke all on function private.can_upload_patient_storage(text, text)
  from public, anon, authenticated;

drop trigger if exists set_online_request_reference_before_insert
  on public.online_consultation_requests;
create trigger set_online_request_reference_before_insert
before insert on public.online_consultation_requests
for each row execute function private.set_online_request_reference();

drop trigger if exists set_online_requests_updated_at
  on public.online_consultation_requests;
create trigger set_online_requests_updated_at
before update on public.online_consultation_requests
for each row execute function public.set_updated_at();

drop trigger if exists record_online_request_status_after_write
  on public.online_consultation_requests;
create trigger record_online_request_status_after_write
after insert or update of request_status on public.online_consultation_requests
for each row execute function private.record_online_request_status();

drop trigger if exists sync_consultation_care_access_after_write
  on public.consultations;
create trigger sync_consultation_care_access_after_write
after insert or update of status, doctor_id on public.consultations
for each row execute function private.sync_consultation_care_access();

drop trigger if exists enforce_consultation_assignment_provenance_before_update
  on public.consultations;
create trigger enforce_consultation_assignment_provenance_before_update
before update on public.consultations
for each row execute function private.enforce_consultation_assignment_provenance();

drop trigger if exists sync_employment_termination_after_update
  on public.doctor_hospital_employments;
create trigger sync_employment_termination_after_update
after update of employment_status, ends_at on public.doctor_hospital_employments
for each row execute function private.sync_employment_termination();

drop trigger if exists set_medical_document_provenance_before_insert
  on public.medical_documents;
create trigger set_medical_document_provenance_before_insert
before insert on public.medical_documents
for each row execute function private.set_medical_document_provenance();

do $block$
declare
  target_table text;
begin
  foreach target_table in array array[
    'medical_records', 'diagnoses', 'prescriptions', 'laboratory_requests',
    'laboratory_results', 'medical_documents', 'treatment_plans'
  ]::text[] loop
    execute format(
      'drop trigger if exists enforce_clinical_provenance_before_update on public.%I',
      target_table
    );
    execute format(
      'create trigger enforce_clinical_provenance_before_update before update on public.%I for each row execute function private.enforce_clinical_provenance()',
      target_table
    );
  end loop;
end
$block$;

-- ---------------------------------------------------------------------------
-- Default-deny RLS for the foundation and reviewed request workflow
-- ---------------------------------------------------------------------------

alter table public.patient_hospital_identifiers enable row level security;
alter table public.doctor_hospital_employments enable row level security;
alter table public.patient_care_relationships enable row level security;
alter table public.patient_access_grants enable row level security;
alter table public.patient_access_scopes enable row level security;
alter table public.patient_access_record_selections enable row level security;
alter table public.patient_representatives enable row level security;
alter table public.clinical_record_addenda enable row level security;
alter table public.emergency_access_events enable row level security;
alter table public.clinical_record_quarantine enable row level security;
alter table public.online_consultation_requests enable row level security;
alter table public.online_consultation_request_status_history enable row level security;

revoke all on table
  public.patient_hospital_identifiers,
  public.doctor_hospital_employments,
  public.patient_care_relationships,
  public.patient_access_grants,
  public.patient_access_scopes,
  public.patient_access_record_selections,
  public.patient_representatives,
  public.clinical_record_addenda,
  public.emergency_access_events,
  public.clinical_record_quarantine,
  public.online_consultation_requests,
  public.online_consultation_request_status_history
from anon;

revoke all on table
  public.patient_hospital_identifiers,
  public.doctor_hospital_employments,
  public.patient_care_relationships,
  public.patient_access_grants,
  public.patient_access_scopes,
  public.patient_access_record_selections,
  public.patient_representatives,
  public.clinical_record_addenda,
  public.emergency_access_events,
  public.clinical_record_quarantine,
  public.online_consultation_requests,
  public.online_consultation_request_status_history
from authenticated;

grant select on table
  public.patient_hospital_identifiers,
  public.doctor_hospital_employments,
  public.patient_care_relationships,
  public.patient_access_grants,
  public.patient_access_scopes,
  public.patient_access_record_selections,
  public.patient_representatives,
  public.clinical_record_addenda,
  public.emergency_access_events,
  public.online_consultation_requests,
  public.online_consultation_request_status_history
to authenticated;
grant insert on table public.clinical_record_addenda to authenticated;
grant all on table
  public.patient_hospital_identifiers,
  public.doctor_hospital_employments,
  public.patient_care_relationships,
  public.patient_access_grants,
  public.patient_access_scopes,
  public.patient_access_record_selections,
  public.patient_representatives,
  public.clinical_record_addenda,
  public.emergency_access_events,
  public.clinical_record_quarantine,
  public.online_consultation_requests,
  public.online_consultation_request_status_history
to service_role;

drop policy if exists patient_identifiers_authorized_read
  on public.patient_hospital_identifiers;
create policy patient_identifiers_authorized_read
on public.patient_hospital_identifiers for select to authenticated
using (
  patient_id = private.current_patient_id()
  or private.can_access_patient(patient_id)
  or private.is_hospital_admin_for(hospital_id)
);

drop policy if exists doctor_employments_authorized_read
  on public.doctor_hospital_employments;
create policy doctor_employments_authorized_read
on public.doctor_hospital_employments for select to authenticated
using (
  doctor_id = private.current_doctor_id()
  or private.is_hospital_admin_for(hospital_id)
);

drop policy if exists care_relationships_authorized_read
  on public.patient_care_relationships;
create policy care_relationships_authorized_read
on public.patient_care_relationships for select to authenticated
using (
  patient_id = private.current_patient_id()
  or doctor_id = private.current_doctor_id()
  or private.is_hospital_admin_for(hospital_id)
);

drop policy if exists access_grants_participant_read
  on public.patient_access_grants;
create policy access_grants_participant_read
on public.patient_access_grants for select to authenticated
using (
  patient_id = private.current_patient_id()
  or receiving_doctor_id = private.current_doctor_id()
);

drop policy if exists access_scopes_participant_read
  on public.patient_access_scopes;
create policy access_scopes_participant_read
on public.patient_access_scopes for select to authenticated
using (
  exists (
    select 1 from public.patient_access_grants grant_row
    where grant_row.id = patient_access_scopes.grant_id
      and (
        grant_row.patient_id = private.current_patient_id()
        or grant_row.receiving_doctor_id = private.current_doctor_id()
      )
  )
);

drop policy if exists access_selections_participant_read
  on public.patient_access_record_selections;
create policy access_selections_participant_read
on public.patient_access_record_selections for select to authenticated
using (
  exists (
    select 1 from public.patient_access_grants grant_row
    where grant_row.id = patient_access_record_selections.grant_id
      and (
        grant_row.patient_id = private.current_patient_id()
        or grant_row.receiving_doctor_id = private.current_doctor_id()
      )
  )
);

drop policy if exists patient_representatives_participant_read
  on public.patient_representatives;
create policy patient_representatives_participant_read
on public.patient_representatives for select to authenticated
using (
  patient_id = private.current_patient_id()
  or representative_user_id = private.current_user_id()
);

drop policy if exists clinical_addenda_authorized_read
  on public.clinical_record_addenda;
create policy clinical_addenda_authorized_read
on public.clinical_record_addenda for select to authenticated
using (
  private.can_access_clinical_record(
    patient_id, originating_hospital_id,
    record_category, record_id, 'view'
  )
);
drop policy if exists clinical_addenda_authorized_insert
  on public.clinical_record_addenda;
create policy clinical_addenda_authorized_insert
on public.clinical_record_addenda for insert to authenticated
with check (
  author_user_id = private.current_user_id()
  and author_doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, originating_hospital_id,
    record_category, record_id, 'create'
  )
);

drop policy if exists emergency_access_participant_read
  on public.emergency_access_events;
create policy emergency_access_participant_read
on public.emergency_access_events for select to authenticated
using (
  patient_id = private.current_patient_id()
  or doctor_id = private.current_doctor_id()
  or private.is_hospital_admin_for(hospital_id)
);

drop policy if exists online_requests_authorized_read
  on public.online_consultation_requests;
create policy online_requests_authorized_read
on public.online_consultation_requests for select to authenticated
using (private.can_access_online_request(id));

drop policy if exists online_request_history_authorized_read
  on public.online_consultation_request_status_history;
create policy online_request_history_authorized_read
on public.online_consultation_request_status_history for select to authenticated
using (private.can_access_online_request(request_id));

-- Consent changes are versioned/protected RPC operations. Direct update/delete
-- is removed so an old consent row cannot be silently rewritten.
drop policy if exists patient_consents_care_team_read on public.patient_consents;
drop policy if exists patient_consents_patient_delete on public.patient_consents;
drop policy if exists patient_consents_patient_insert on public.patient_consents;
drop policy if exists patient_consents_patient_update on public.patient_consents;
drop policy if exists patient_consents_authorized_read on public.patient_consents;
create policy patient_consents_authorized_read
on public.patient_consents for select to authenticated
using (
  patient_id = private.current_patient_id()
  or exists (
    select 1 from public.patient_access_grants grant_row
    where grant_row.consent_id = patient_consents.id
      and grant_row.receiving_doctor_id = private.current_doctor_id()
      and grant_row.status = 'active'
      and grant_row.expires_at > now()
      and grant_row.revoked_at is null
  )
);
revoke insert, update, delete on public.patient_consents from anon, authenticated;

-- Patient profiles are no longer discoverable from broad historical
-- assignments. Operational request queues use their own profile snapshots.
drop policy if exists patients_authorized_read on public.patients;
drop policy if exists patients_doctor_update on public.patients;
drop policy if exists patients_scoped_read on public.patients;
create policy patients_scoped_read
on public.patients for select to authenticated
using (
  id = private.current_patient_id()
  or private.can_access_patient(id)
);

-- Consultation rows remain operational records, but direct inserts are removed
-- so online callers cannot bypass the reviewed request RPC.
drop policy if exists consultations_authorized_insert on public.consultations;
drop policy if exists consultations_participant_read on public.consultations;
drop policy if exists consultations_doctor_update on public.consultations;
create policy consultations_participant_read
on public.consultations for select to authenticated
using (
  patient_id = private.current_patient_id()
  or (
    doctor_id = private.current_doctor_id()
    and private.has_active_doctor_employment(doctor_id, hospital_id)
  )
  or (
    guest_request_id is not null
    and private.can_access_guest_request(guest_request_id)
  )
  or private.is_hospital_admin_for(hospital_id)
  or (
    patient_id is not null
    and private.can_access_clinical_record(
      patient_id, hospital_id, 'consultations', id, 'view'
    )
  )
);
create policy consultations_assigned_care_team_update
on public.consultations for update to authenticated
using (
  (
    doctor_id = private.current_doctor_id()
    and private.has_active_doctor_employment(doctor_id, hospital_id)
  )
  or private.is_hospital_admin_for(hospital_id)
)
with check (
  (
    doctor_id = private.current_doctor_id()
    and private.has_active_doctor_employment(doctor_id, hospital_id)
  )
  or private.is_hospital_admin_for(hospital_id)
);
revoke insert, delete on public.consultations from anon, authenticated;

drop policy if exists assignments_doctor_delete on public.doctor_patient_assignments;
drop policy if exists assignments_doctor_insert on public.doctor_patient_assignments;
drop policy if exists assignments_doctor_update on public.doctor_patient_assignments;
drop policy if exists assignments_participant_read on public.doctor_patient_assignments;
create policy assignments_scoped_read
on public.doctor_patient_assignments for select to authenticated
using (
  patient_id = private.current_patient_id()
  or doctor_id = private.current_doctor_id()
  or (
    hospital_id is not null and private.is_hospital_admin_for(hospital_id)
  )
);
revoke insert, update, delete on public.doctor_patient_assignments from anon, authenticated;

drop policy if exists medical_records_care_team_read on public.medical_records;
drop policy if exists medical_records_doctor_insert on public.medical_records;
drop policy if exists medical_records_doctor_update on public.medical_records;
create policy medical_records_scoped_read
on public.medical_records for select to authenticated
using (
  private.can_access_clinical_record(
    patient_id, hospital_id, 'medical_records', id, 'view'
  )
);
create policy medical_records_scoped_insert
on public.medical_records for insert to authenticated
with check (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'medical_records', null, 'create'
  )
);
create policy medical_records_origin_update
on public.medical_records for update to authenticated
using (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'medical_records', id, 'create'
  )
)
with check (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'medical_records', id, 'create'
  )
);

drop policy if exists diagnoses_care_team_read on public.diagnoses;
drop policy if exists diagnoses_doctor_insert on public.diagnoses;
drop policy if exists diagnoses_doctor_update on public.diagnoses;
create policy diagnoses_scoped_read
on public.diagnoses for select to authenticated
using (
  private.can_access_clinical_record(
    patient_id, hospital_id, 'diagnoses', id, 'view'
  )
);
create policy diagnoses_scoped_insert
on public.diagnoses for insert to authenticated
with check (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'diagnoses', null, 'create'
  )
);
create policy diagnoses_origin_update
on public.diagnoses for update to authenticated
using (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'diagnoses', id, 'create'
  )
)
with check (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'diagnoses', id, 'create'
  )
);

update public.prescriptions prescription
set hospital_id = doctor.hospital_id
from public.doctors doctor
where prescription.hospital_id is null and doctor.id = prescription.doctor_id;

do $block$
begin
  if not exists (select 1 from public.prescriptions where hospital_id is null) then
    alter table public.prescriptions alter column hospital_id set not null;
  end if;
end
$block$;

drop policy if exists prescriptions_care_team_read on public.prescriptions;
drop policy if exists prescriptions_doctor_insert on public.prescriptions;
drop policy if exists prescriptions_doctor_update on public.prescriptions;
create policy prescriptions_scoped_read
on public.prescriptions for select to authenticated
using (
  private.can_access_clinical_record(
    patient_id, hospital_id, 'prescriptions', id, 'view'
  )
);
create policy prescriptions_scoped_insert
on public.prescriptions for insert to authenticated
with check (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'prescriptions', null, 'create'
  )
);
create policy prescriptions_origin_update
on public.prescriptions for update to authenticated
using (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'prescriptions', id, 'create'
  )
)
with check (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'prescriptions', id, 'create'
  )
);

drop policy if exists laboratory_requests_care_team_read on public.laboratory_requests;
drop policy if exists laboratory_requests_doctor_delete on public.laboratory_requests;
drop policy if exists laboratory_requests_doctor_insert on public.laboratory_requests;
drop policy if exists laboratory_requests_doctor_update on public.laboratory_requests;
create policy laboratory_requests_scoped_read
on public.laboratory_requests for select to authenticated
using (
  private.can_access_clinical_record(
    patient_id, hospital_id, 'laboratory_requests', id, 'view'
  )
);
create policy laboratory_requests_scoped_insert
on public.laboratory_requests for insert to authenticated
with check (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'laboratory_requests', null, 'create'
  )
);
create policy laboratory_requests_origin_update
on public.laboratory_requests for update to authenticated
using (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'laboratory_requests', id, 'create'
  )
)
with check (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'laboratory_requests', id, 'create'
  )
);
create policy laboratory_requests_origin_delete
on public.laboratory_requests for delete to authenticated
using (
  doctor_id = private.current_doctor_id()
  and status in ('requested', 'scheduled')
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'laboratory_requests', id, 'create'
  )
);

drop policy if exists laboratory_results_care_team_read on public.laboratory_results;
drop policy if exists laboratory_results_doctor_insert on public.laboratory_results;
drop policy if exists laboratory_results_doctor_update on public.laboratory_results;
create policy laboratory_results_scoped_read
on public.laboratory_results for select to authenticated
using (
  private.can_access_clinical_record(
    patient_id, hospital_id, 'laboratory_results', id, 'view'
  )
);
create policy laboratory_results_scoped_insert
on public.laboratory_results for insert to authenticated
with check (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'laboratory_results', null, 'create'
  )
);
create policy laboratory_results_origin_update
on public.laboratory_results for update to authenticated
using (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'laboratory_results', id, 'create'
  )
)
with check (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'laboratory_results', id, 'create'
  )
);

drop policy if exists medical_documents_care_team_read on public.medical_documents;
drop policy if exists medical_documents_participant_insert on public.medical_documents;
drop policy if exists medical_documents_scoped_read on public.medical_documents;
create policy medical_documents_scoped_read
on public.medical_documents for select to authenticated
using (
  private.can_access_clinical_record(
    patient_id, hospital_id, 'medical_documents', id, 'view'
  )
);
create policy medical_documents_scoped_insert
on public.medical_documents for insert to authenticated
with check (
  (
    patient_id = private.current_patient_id()
    and uploaded_by = private.current_user_id()
    and author_doctor_id is null
    and origin_type = 'patient_supplied'
  )
  or (
    author_doctor_id = private.current_doctor_id()
    and uploaded_by = private.current_user_id()
    and hospital_id is not null
    and private.can_access_clinical_record(
      patient_id, hospital_id, 'medical_documents', null, 'create'
    )
  )
);

drop policy if exists treatment_plans_care_team_read on public.treatment_plans;
drop policy if exists treatment_plans_doctor_delete on public.treatment_plans;
drop policy if exists treatment_plans_doctor_insert on public.treatment_plans;
drop policy if exists treatment_plans_doctor_update on public.treatment_plans;
create policy treatment_plans_scoped_read
on public.treatment_plans for select to authenticated
using (
  private.can_access_clinical_record(
    patient_id, hospital_id, 'treatment_plans', id, 'view'
  )
);
create policy treatment_plans_scoped_insert
on public.treatment_plans for insert to authenticated
with check (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'treatment_plans', null, 'create'
  )
);
create policy treatment_plans_origin_update
on public.treatment_plans for update to authenticated
using (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'treatment_plans', id, 'create'
  )
)
with check (
  doctor_id = private.current_doctor_id()
  and private.can_access_clinical_record(
    patient_id, hospital_id, 'treatment_plans', id, 'create'
  )
);

drop policy if exists consultation_attachments_participant_read on public.consultation_attachments;
drop policy if exists consultation_attachments_participant_insert on public.consultation_attachments;
create policy consultation_attachments_scoped_read
on public.consultation_attachments for select to authenticated
using (
  (
    patient_id is not null
    and exists (
      select 1 from public.consultations consultation
      where consultation.id = consultation_attachments.consultation_id
        and private.can_access_clinical_record(
          consultation_attachments.patient_id,
          consultation.hospital_id,
          'consultations', consultation.id, 'view'
        )
    )
  )
  or (
    guest_request_id is not null
    and private.can_access_guest_request(guest_request_id)
  )
);
create policy consultation_attachments_scoped_insert
on public.consultation_attachments for insert to authenticated
with check (
  uploaded_by = private.current_user_id()
  and (
    (
      patient_id is not null
      and exists (
        select 1 from public.consultations consultation
        where consultation.id = consultation_attachments.consultation_id
          and private.can_access_clinical_record(
            consultation_attachments.patient_id,
            consultation.hospital_id,
            'consultations', consultation.id,
            case when consultation_attachments.patient_id = private.current_patient_id()
              then 'view' else 'create' end
          )
      )
    )
    or (
      guest_request_id is not null
      and private.can_access_guest_request(guest_request_id)
    )
  )
);

-- ---------------------------------------------------------------------------
-- Category-aware access RPCs, patient context, and private file authorization
-- ---------------------------------------------------------------------------

alter table public.medical_record_access_logs
  add column if not exists grant_id uuid references public.patient_access_grants(id),
  add column if not exists care_relationship_id uuid references public.patient_care_relationships(id),
  add column if not exists source_hospital_id uuid references public.hospitals(id),
  add column if not exists receiving_hospital_id uuid references public.hospitals(id),
  add column if not exists success boolean not null default true,
  add column if not exists failure_reason text;

create or replace function private.actor_has_category_access(
  target_patient_id uuid,
  target_category text
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    target_patient_id = private.current_patient_id()
    or exists (
      select 1
      from public.patient_access_grants grant_row
      join public.patient_access_scopes scope on scope.grant_id = grant_row.id
      where grant_row.patient_id = target_patient_id
        and grant_row.receiving_doctor_id = private.current_doctor_id()
        and grant_row.status = 'active'
        and grant_row.expires_at > now()
        and grant_row.revoked_at is null
        and scope.record_category = target_category
        and scope.can_view
        and private.has_active_doctor_employment(
          grant_row.receiving_doctor_id, grant_row.receiving_hospital_id
        )
        and private.is_active_care_relationship(
          grant_row.care_relationship_id, grant_row.patient_id,
          grant_row.receiving_hospital_id, grant_row.receiving_doctor_id
        )
    ), false
  )
$function$;

create or replace function public.record_clinical_access(
  target_resource_type text,
  target_resource_id uuid,
  target_action text
)
returns bigint
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_patient_id uuid;
  source_hospital_id uuid;
  target_category text;
  matching_grant public.patient_access_grants;
  created_log_id bigint;
begin
  if private.current_user_id() is null then
    raise exception 'An active account is required';
  end if;
  if target_action not in ('view', 'download') then
    raise exception 'Clinical access action must be view or download';
  end if;

  case target_resource_type
    when 'medical_record' then
      select patient_id, hospital_id, 'medical_records'
      into target_patient_id, source_hospital_id, target_category
      from public.medical_records where id = target_resource_id;
    when 'laboratory_result' then
      select patient_id, hospital_id, 'laboratory_results'
      into target_patient_id, source_hospital_id, target_category
      from public.laboratory_results where id = target_resource_id;
    when 'medical_document' then
      select patient_id, hospital_id, 'medical_documents'
      into target_patient_id, source_hospital_id, target_category
      from public.medical_documents where id = target_resource_id;
    when 'consultation_attachment' then
      select coalesce(attachment.patient_id, consultation.patient_id),
             consultation.hospital_id, 'consultations'
      into target_patient_id, source_hospital_id, target_category
      from public.consultation_attachments attachment
      join public.consultations consultation on consultation.id = attachment.consultation_id
      where attachment.id = target_resource_id;
    when 'prescription' then
      select patient_id, hospital_id, 'prescriptions'
      into target_patient_id, source_hospital_id, target_category
      from public.prescriptions where id = target_resource_id;
    when 'diagnosis' then
      select patient_id, hospital_id, 'diagnoses'
      into target_patient_id, source_hospital_id, target_category
      from public.diagnoses where id = target_resource_id;
    when 'laboratory_request' then
      select patient_id, hospital_id, 'laboratory_requests'
      into target_patient_id, source_hospital_id, target_category
      from public.laboratory_requests where id = target_resource_id;
    when 'treatment_plan' then
      select patient_id, hospital_id, 'treatment_plans'
      into target_patient_id, source_hospital_id, target_category
      from public.treatment_plans where id = target_resource_id;
    when 'consultation' then
      select patient_id, hospital_id, 'consultations'
      into target_patient_id, source_hospital_id, target_category
      from public.consultations where id = target_resource_id;
    else
      raise exception 'Unsupported clinical resource type';
  end case;

  if target_patient_id is null or not private.can_access_clinical_record(
    target_patient_id, source_hospital_id,
    target_category, target_resource_id, target_action
  ) then
    raise exception 'Clinical resource was not found or is not authorized for this action';
  end if;

  select * into matching_grant
  from public.patient_access_grants grant_row
  join public.patient_access_scopes scope on scope.grant_id = grant_row.id
  where grant_row.patient_id = target_patient_id
    and grant_row.receiving_doctor_id = private.current_doctor_id()
    and (
      grant_row.source_hospital_id = source_hospital_id
      or (source_hospital_id is null and target_category = 'medical_documents')
    )
    and grant_row.status = 'active'
    and grant_row.expires_at > now()
    and grant_row.revoked_at is null
    and scope.record_category = target_category
  order by grant_row.activated_at desc
  limit 1;

  insert into public.medical_record_access_logs(
    patient_id, actor_user_id, actor_role, resource_type, resource_id,
    access_type, metadata, grant_id, care_relationship_id,
    source_hospital_id, receiving_hospital_id, success
  ) values (
    target_patient_id, private.current_user_id(), private.current_role(),
    target_resource_type, target_resource_id, target_action,
    jsonb_build_object('category', target_category),
    matching_grant.id, matching_grant.care_relationship_id,
    source_hospital_id, matching_grant.receiving_hospital_id, true
  ) returning id into created_log_id;
  return created_log_id;
end
$function$;

create or replace function public.get_authorized_medical_document_download(
  target_document_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  document_row public.medical_documents;
  access_log_id bigint;
  is_external boolean;
begin
  select * into document_row
  from public.medical_documents
  where id = target_document_id;
  if not found then raise exception 'Medical document was not found'; end if;

  access_log_id := public.record_clinical_access(
    'medical_document', target_document_id, 'download'
  );
  is_external := document_row.hospital_id is not null
    and private.current_hospital_id() is not null
    and document_row.hospital_id <> private.current_hospital_id();

  return jsonb_build_object(
    'storage_bucket', document_row.storage_bucket,
    'storage_path', document_row.storage_path,
    'expires_in_seconds', 60,
    'watermark_required', is_external,
    'access_log_id', access_log_id
  );
end
$function$;

create or replace function public.get_patient_medical_records(target_patient_id uuid)
returns setof public.medical_records
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if not private.actor_has_category_access(target_patient_id, 'medical_records') then
    raise exception 'Medical-record category access is not authorized';
  end if;
  insert into public.medical_record_access_logs(
    patient_id, actor_user_id, actor_role, resource_type, access_type,
    metadata, success
  ) values (
    target_patient_id, private.current_user_id(), private.current_role(),
    'medical_records', 'list', jsonb_build_object('category', 'medical_records'), true
  );
  return query
  select record.*
  from public.medical_records record
  where record.patient_id = target_patient_id
    and private.can_access_clinical_record(
      record.patient_id, record.hospital_id,
      'medical_records', record.id, 'view'
    )
  order by record.record_date desc, record.created_at desc;
end
$function$;

create or replace function public.get_consultation_patient_context(
  target_consultation_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  consultation_row public.consultations;
  patient_row public.patients;
  user_row public.users;
  context_result jsonb;
  records jsonb := '[]'::jsonb;
  diagnoses jsonb := '[]'::jsonb;
  prescriptions jsonb := '[]'::jsonb;
  lab_requests jsonb := '[]'::jsonb;
  lab_results jsonb := '[]'::jsonb;
  documents jsonb := '[]'::jsonb;
  plans jsonb := '[]'::jsonb;
begin
  select * into consultation_row
  from public.consultations where id = target_consultation_id;
  if not found or consultation_row.patient_id is null then
    raise exception 'A linked consultation patient is required';
  end if;
  if consultation_row.patient_id <> private.current_patient_id()
    and (
      consultation_row.doctor_id <> private.current_doctor_id()
      or not private.actor_has_category_access(
        consultation_row.patient_id, 'consultations'
      )
    ) then
    raise exception 'The consultation patient context is not authorized';
  end if;

  select * into patient_row from public.patients where id = consultation_row.patient_id;
  select * into user_row from public.users where id = patient_row.user_id;

  if private.actor_has_category_access(patient_row.id, 'medical_records') then
    select coalesce(jsonb_agg(jsonb_build_object(
      'record', to_jsonb(record),
      'originating_hospital', hospital.hospital_name,
      'authoring_doctor', doctor.display_name,
      'record_date', record.record_date,
      'record_status', 'final',
      'external_read_only', record.hospital_id <> consultation_row.hospital_id
    ) order by record.record_date desc), '[]'::jsonb)
    into records
    from public.medical_records record
    join public.hospitals hospital on hospital.id = record.hospital_id
    join public.doctors doctor on doctor.id = record.doctor_id
    where record.patient_id = patient_row.id
      and private.can_access_clinical_record(
        record.patient_id, record.hospital_id, 'medical_records', record.id, 'view'
      );
  end if;

  if private.actor_has_category_access(patient_row.id, 'diagnoses') then
    select coalesce(jsonb_agg(jsonb_build_object(
      'record', to_jsonb(record), 'originating_hospital', hospital.hospital_name,
      'authoring_doctor', doctor.display_name, 'record_date', record.confirmed_at,
      'record_status', 'final',
      'external_read_only', record.hospital_id <> consultation_row.hospital_id
    ) order by record.confirmed_at desc), '[]'::jsonb)
    into diagnoses
    from public.diagnoses record
    join public.hospitals hospital on hospital.id = record.hospital_id
    join public.doctors doctor on doctor.id = record.doctor_id
    where record.patient_id = patient_row.id
      and private.can_access_clinical_record(
        record.patient_id, record.hospital_id, 'diagnoses', record.id, 'view'
      );
  end if;

  if private.actor_has_category_access(patient_row.id, 'prescriptions') then
    select coalesce(jsonb_agg(jsonb_build_object(
      'record', to_jsonb(record), 'originating_hospital', hospital.hospital_name,
      'authoring_doctor', doctor.display_name, 'record_date', record.created_at,
      'record_status', 'final',
      'external_read_only', record.hospital_id <> consultation_row.hospital_id
    ) order by record.created_at desc), '[]'::jsonb)
    into prescriptions
    from public.prescriptions record
    join public.hospitals hospital on hospital.id = record.hospital_id
    join public.doctors doctor on doctor.id = record.doctor_id
    where record.patient_id = patient_row.id
      and private.can_access_clinical_record(
        record.patient_id, record.hospital_id, 'prescriptions', record.id, 'view'
      );
  end if;

  if private.actor_has_category_access(patient_row.id, 'laboratory_requests') then
    select coalesce(jsonb_agg(jsonb_build_object(
      'record', to_jsonb(record), 'originating_hospital', hospital.hospital_name,
      'authoring_doctor', doctor.display_name, 'record_date', record.requested_at,
      'record_status', record.status,
      'external_read_only', record.hospital_id <> consultation_row.hospital_id
    ) order by record.requested_at desc), '[]'::jsonb)
    into lab_requests
    from public.laboratory_requests record
    join public.hospitals hospital on hospital.id = record.hospital_id
    join public.doctors doctor on doctor.id = record.doctor_id
    where record.patient_id = patient_row.id
      and private.can_access_clinical_record(
        record.patient_id, record.hospital_id, 'laboratory_requests', record.id, 'view'
      );
  end if;

  if private.actor_has_category_access(patient_row.id, 'laboratory_results') then
    select coalesce(jsonb_agg(jsonb_build_object(
      'record', to_jsonb(record), 'originating_hospital', hospital.hospital_name,
      'authoring_doctor', doctor.display_name, 'record_date', record.uploaded_at,
      'record_status', record.verification_status,
      'external_read_only', record.hospital_id <> consultation_row.hospital_id
    ) order by record.uploaded_at desc), '[]'::jsonb)
    into lab_results
    from public.laboratory_results record
    join public.hospitals hospital on hospital.id = record.hospital_id
    join public.doctors doctor on doctor.id = record.doctor_id
    where record.patient_id = patient_row.id
      and private.can_access_clinical_record(
        record.patient_id, record.hospital_id, 'laboratory_results', record.id, 'view'
      );
  end if;

  if private.actor_has_category_access(patient_row.id, 'medical_documents') then
    select coalesce(jsonb_agg(jsonb_build_object(
      'record', to_jsonb(record), 'originating_hospital', hospital.hospital_name,
      'authoring_doctor', doctor.display_name, 'record_date', record.created_at,
      'record_status', record.record_status,
      'external_read_only', record.hospital_id is distinct from consultation_row.hospital_id
    ) order by record.created_at desc), '[]'::jsonb)
    into documents
    from public.medical_documents record
    left join public.hospitals hospital on hospital.id = record.hospital_id
    left join public.doctors doctor on doctor.id = record.author_doctor_id
    where record.patient_id = patient_row.id
      and private.can_access_clinical_record(
        record.patient_id, record.hospital_id, 'medical_documents', record.id, 'view'
      );
  end if;

  if private.actor_has_category_access(patient_row.id, 'treatment_plans') then
    select coalesce(jsonb_agg(jsonb_build_object(
      'record', to_jsonb(record), 'originating_hospital', hospital.hospital_name,
      'authoring_doctor', doctor.display_name, 'record_date', record.created_at,
      'record_status', record.status,
      'external_read_only', record.hospital_id <> consultation_row.hospital_id
    ) order by record.created_at desc), '[]'::jsonb)
    into plans
    from public.treatment_plans record
    join public.hospitals hospital on hospital.id = record.hospital_id
    join public.doctors doctor on doctor.id = record.doctor_id
    where record.patient_id = patient_row.id
      and private.can_access_clinical_record(
        record.patient_id, record.hospital_id, 'treatment_plans', record.id, 'view'
      );
  end if;

  context_result := jsonb_build_object(
    'patient_id', patient_row.id,
    'demographics', jsonb_build_object(
      'first_name', user_row.first_name, 'last_name', user_row.last_name,
      'birth_date', user_row.birth_date, 'sex', user_row.sex,
      'mobile_number', user_row.mobile_number, 'address', user_row.address,
      'patient_number', patient_row.patient_number
    ),
    'allergies_medications', case
      when private.actor_has_category_access(patient_row.id, 'allergies_medications')
      then jsonb_build_object(
        'allergies', consultation_row.allergies,
        'current_medications', consultation_row.current_medications,
        'source_hospital_id', consultation_row.hospital_id,
        'consultation_id', consultation_row.id
      ) else null end,
    'medical_records', records,
    'diagnoses', diagnoses,
    'prescriptions', prescriptions,
    'laboratory_requests', lab_requests,
    'laboratory_results', lab_results,
    'medical_documents', documents,
    'treatment_plans', plans
  );

  insert into public.medical_record_access_logs(
    patient_id, actor_user_id, actor_role, resource_type, resource_id,
    access_type, metadata, success
  ) values (
    patient_row.id, private.current_user_id(), private.current_role(),
    'consultation_patient_context', consultation_row.id, 'view',
    jsonb_build_object('consultation_id', consultation_row.id), true
  );
  return context_result;
end
$function$;

revoke all on function private.actor_has_category_access(uuid, text) from public, anon, authenticated;
revoke all on function public.record_clinical_access(text, uuid, text) from public, anon;
grant execute on function public.record_clinical_access(text, uuid, text) to authenticated, service_role;
revoke all on function public.get_authorized_medical_document_download(uuid) from public, anon;
grant execute on function public.get_authorized_medical_document_download(uuid) to authenticated, service_role;
revoke all on function public.get_patient_medical_records(uuid) from public, anon;
grant execute on function public.get_patient_medical_records(uuid) to authenticated, service_role;
revoke all on function public.get_consultation_patient_context(uuid) from public, anon;
grant execute on function public.get_consultation_patient_context(uuid) to authenticated, service_role;

drop policy if exists cnph_patient_documents_care_team_read on storage.objects;
create policy cnph_patient_documents_scoped_read
on storage.objects for select to authenticated
using (
  bucket_id = any(array[
    'laboratory-results', 'scanned-medical-results', 'medical-documents',
    'prescriptions', 'consultation-attachments'
  ]::text[])
  and private.can_access_patient_storage(name, bucket_id, 'view')
);

drop policy if exists cnph_patient_documents_participant_insert on storage.objects;
create policy cnph_patient_documents_scoped_insert
on storage.objects for insert to authenticated
with check (
  (
    bucket_id = 'consultation-attachments'
    and private.can_access_consultation_storage(name)
  )
  or (
    bucket_id = any(array[
      'laboratory-results', 'scanned-medical-results',
      'medical-documents', 'prescriptions'
    ]::text[])
    and private.can_upload_patient_storage(name, bucket_id)
  )
);

create or replace function private.sync_video_session_request_status()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.status in ('ready', 'active') then
    update public.online_consultation_requests request
    set request_status = case
          when request.request_status in ('confirmed', 'awaiting_contact') then 'video_ready'
          else request.request_status
        end,
        updated_at = now()
    where request.official_consultation_id = new.consultation_id
      and request.consultation_channel = 'video';
  end if;
  return new;
end
$function$;

drop trigger if exists sync_video_session_request_status_after_write
  on public.video_sessions;
create trigger sync_video_session_request_status_after_write
after insert or update of status on public.video_sessions
for each row execute function private.sync_video_session_request_status();

do $block$
declare
  target_table text;
begin
  foreach target_table in array array[
    'patient_hospital_identifiers', 'doctor_hospital_employments',
    'patient_care_relationships', 'patient_access_grants',
    'patient_representatives'
  ]::text[] loop
    execute format('drop trigger if exists set_multi_hospital_updated_at on public.%I', target_table);
    execute format(
      'create trigger set_multi_hospital_updated_at before update on public.%I for each row execute function public.set_updated_at()',
      target_table
    );
  end loop;
end
$block$;

do $block$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime')
    and not exists (
      select 1
      from pg_publication_rel publication_table
      join pg_publication publication on publication.oid = publication_table.prpubid
      where publication.pubname = 'supabase_realtime'
        and publication_table.prrelid = 'public.online_consultation_requests'::regclass
    ) then
    execute 'alter publication supabase_realtime add table public.online_consultation_requests';
  end if;
end
$block$;





do $block$
declare
  target_table text;
begin
  foreach target_table in array array[
    'patient_hospital_identifiers', 'doctor_hospital_employments',
    'patient_care_relationships', 'patient_access_grants',
    'patient_access_scopes', 'patient_access_record_selections',
    'patient_representatives', 'clinical_record_addenda',
    'emergency_access_events', 'clinical_record_quarantine',
    'online_consultation_requests'
  ]::text[] loop
    execute format('drop trigger if exists audit_multi_hospital_change on public.%I', target_table);
    execute format(
      'create trigger audit_multi_hospital_change after insert or update or delete on public.%I for each row execute function private.audit_multi_hospital_change()',
      target_table
    );
  end loop;
end
$block$;

-- ---------------------------------------------------------------------------
-- Continuing care, transfer, addendum, emergency, and video guardrails
-- ---------------------------------------------------------------------------

create or replace function public.request_patient_care_relationship(
  target_hospital_id uuid,
  target_doctor_id uuid,
  target_relationship_type text,
  target_purpose text,
  target_categories text[],
  requested_expiry timestamptz
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  patient_row public.patients;
  app_user public.users;
  relationship_id uuid;
  category text;
begin
  if private.current_patient_id() is null or private.current_user_id() is null then
    raise exception 'An authenticated patient is required';
  end if;
  if target_relationship_type not in ('second_opinion', 'ongoing_outpatient_care', 'transfer') then
    raise exception 'Choose second opinion, ongoing outpatient care, or transfer';
  end if;
  if nullif(btrim(target_purpose), '') is null
    or requested_expiry is null
    or requested_expiry <= now()
    or requested_expiry > now() + interval '365 days' then
    raise exception 'A purpose and expiry within one year are required';
  end if;
  if target_doctor_id is not null and not exists (
    select 1
    from public.doctor_hospital_employments employment
    where employment.doctor_id = target_doctor_id
      and employment.hospital_id = target_hospital_id
      and employment.employment_status = 'active'
      and employment.is_verified
      and (employment.ends_at is null or employment.ends_at > now())
  ) then
    raise exception 'The requested doctor is not actively employed at this hospital';
  end if;
  if cardinality(target_categories) = 0 then
    raise exception 'Choose at least one record category';
  end if;
  foreach category in array target_categories loop
    if not private.valid_record_category(category) then
      raise exception 'Unsupported record category: %', category;
    end if;
  end loop;

  select * into patient_row from public.patients where id = private.current_patient_id();
  select * into app_user from public.users where id = private.current_user_id();

  insert into public.patient_care_relationships(
    patient_id, hospital_id, doctor_id, relationship_type, purpose,
    status, requested_at, expires_at, created_by
  ) values (
    patient_row.id, target_hospital_id, target_doctor_id,
    target_relationship_type, btrim(target_purpose),
    'requested', now(), requested_expiry, app_user.id
  ) returning id into relationship_id;

  insert into public.patient_consents(
    patient_id, consent_type, consent_version, is_granted, granted_at,
    captured_by, metadata, care_relationship_id, source_hospital_id,
    receiving_hospital_id, purpose, categories, permitted_actions,
    record_selection_mode, expires_at, granted_by, version_sequence
  ) values (
    patient_row.id, target_relationship_type || '_access', relationship_id::text,
    true, now(), (select auth.uid()), jsonb_build_object('requested_by_patient', true),
    relationship_id, coalesce(patient_row.primary_hospital_id, target_hospital_id),
    target_hospital_id, btrim(target_purpose), target_categories,
    array['view', 'download', 'create']::text[], 'categories',
    requested_expiry, app_user.id, 1
  );

  return relationship_id;
end
$function$;

create or replace function public.approve_patient_care_relationship(
  target_relationship_id uuid,
  assigned_doctor_id uuid
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  relationship_row public.patient_care_relationships;
  consent_row public.patient_consents;
begin
  select * into relationship_row
  from public.patient_care_relationships
  where id = target_relationship_id
  for update;
  if not found or relationship_row.status <> 'requested'
    or not private.is_hospital_admin_for(relationship_row.hospital_id) then
    raise exception 'A pending relationship for this hospital is required';
  end if;
  if relationship_row.relationship_type not in (
    'second_opinion', 'ongoing_outpatient_care', 'transfer'
  ) then
    raise exception 'This relationship uses a different approval workflow';
  end if;
  select * into consent_row
  from public.patient_consents
  where care_relationship_id = relationship_row.id
    and is_granted and revoked_at is null
    and (expires_at is null or expires_at > now())
  order by version_sequence desc, created_at desc limit 1;
  if consent_row.id is null then
    raise exception 'Active patient consent is required';
  end if;

  perform private.activate_relationship_access(
    relationship_row.id, consent_row.id, assigned_doctor_id, null, '[]'::jsonb
  );

  if relationship_row.relationship_type = 'transfer' then
    update public.patients
    set primary_hospital_id = relationship_row.hospital_id, updated_at = now()
    where id = relationship_row.patient_id;
    insert into public.patient_hospital_identifiers(
      patient_id, hospital_id, local_mrn, status, verified_at
    ) values (
      relationship_row.patient_id, relationship_row.hospital_id,
      'TRANSFER-' || upper(substr(replace(relationship_row.patient_id::text, '-', ''), 1, 10)),
      'active', now()
    ) on conflict (patient_id, hospital_id) do update
      set status = 'active', verified_at = coalesce(
        public.patient_hospital_identifiers.verified_at, excluded.verified_at
      ), updated_at = now();
  end if;
end
$function$;

create or replace function public.add_clinical_record_addendum(
  target_resource_type text,
  target_record_id uuid,
  addendum_text text,
  correction_reason text
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  patient_id uuid;
  hospital_id uuid;
  category text;
  source_table text;
  addendum_id uuid;
begin
  case target_resource_type
    when 'medical_record' then
      select record.patient_id, record.hospital_id, 'medical_records', 'medical_records'
      into patient_id, hospital_id, category, source_table
      from public.medical_records record where record.id = target_record_id;
    when 'diagnosis' then
      select record.patient_id, record.hospital_id, 'diagnoses', 'diagnoses'
      into patient_id, hospital_id, category, source_table
      from public.diagnoses record where record.id = target_record_id;
    when 'prescription' then
      select record.patient_id, record.hospital_id, 'prescriptions', 'prescriptions'
      into patient_id, hospital_id, category, source_table
      from public.prescriptions record where record.id = target_record_id;
    when 'laboratory_result' then
      select record.patient_id, record.hospital_id, 'laboratory_results', 'laboratory_results'
      into patient_id, hospital_id, category, source_table
      from public.laboratory_results record where record.id = target_record_id;
    when 'treatment_plan' then
      select record.patient_id, record.hospital_id, 'treatment_plans', 'treatment_plans'
      into patient_id, hospital_id, category, source_table
      from public.treatment_plans record where record.id = target_record_id;
    else raise exception 'Unsupported addendum resource type';
  end case;
  if patient_id is null or hospital_id is null
    or not private.can_access_clinical_record(
      patient_id, hospital_id, category, target_record_id, 'create'
    ) then
    raise exception 'Only the originating authorized care team may add an addendum';
  end if;
  if nullif(btrim(addendum_text), '') is null
    or nullif(btrim(correction_reason), '') is null then
    raise exception 'Addendum text and a correction reason are required';
  end if;

  insert into public.clinical_record_addenda(
    patient_id, record_category, source_table, record_id,
    originating_hospital_id, author_doctor_id, author_user_id,
    addendum_text, correction_reason
  ) values (
    patient_id, category, source_table, target_record_id,
    hospital_id, private.current_doctor_id(), private.current_user_id(),
    btrim(addendum_text), btrim(correction_reason)
  ) returning id into addendum_id;
  return addendum_id;
end
$function$;

create or replace function public.begin_emergency_patient_access(
  target_patient_id uuid,
  target_hospital_id uuid,
  emergency_reason text,
  target_categories text[],
  duration_minutes integer default 60
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  event_id uuid;
  category text;
begin
  if private.current_doctor_id() is null
    or not private.has_active_doctor_employment(
      private.current_doctor_id(), target_hospital_id
    ) then
    raise exception 'A verified active doctor at this hospital is required';
  end if;
  if nullif(btrim(emergency_reason), '') is null or length(btrim(emergency_reason)) < 10 then
    raise exception 'A specific emergency reason is required';
  end if;
  if duration_minutes < 5 or duration_minutes > 240 then
    raise exception 'Emergency access must last 5 to 240 minutes';
  end if;
  if cardinality(target_categories) = 0 then
    raise exception 'Choose at least one emergency record category';
  end if;
  foreach category in array target_categories loop
    if not private.valid_record_category(category) then
      raise exception 'Unsupported emergency category: %', category;
    end if;
  end loop;

  insert into public.emergency_access_events(
    patient_id, hospital_id, doctor_id, reason, categories,
    status, started_at, expires_at
  ) values (
    target_patient_id, target_hospital_id, private.current_doctor_id(),
    btrim(emergency_reason), target_categories, 'active', now(),
    now() + make_interval(mins => duration_minutes)
  ) returning id into event_id;

  insert into public.notifications(
    user_id, title, message, notification_type, reference_id, data
  )
  select app_user.auth_user_id,
         'Emergency record access activated',
         'A verified clinician activated short-lived emergency access to selected records.',
         'security_alert', event_id,
         jsonb_build_object(
           'emergency_access_event_id', event_id,
           'hospital_id', target_hospital_id,
           'expires_at', now() + make_interval(mins => duration_minutes)
         )
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where patient.id = target_patient_id;

  update public.emergency_access_events
  set patient_notified_at = case
    when exists (
      select 1 from public.patients patient
      where patient.id = target_patient_id and patient.user_id is not null
    ) then now() else null end
  where id = event_id;
  return event_id;
end
$function$;

create or replace function public.end_emergency_patient_access(
  target_event_id uuid,
  review_note text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  event_row public.emergency_access_events;
begin
  select * into event_row
  from public.emergency_access_events
  where id = target_event_id
  for update;
  if not found or (
    event_row.doctor_id <> private.current_doctor_id()
    and not private.is_hospital_admin_for(event_row.hospital_id)
  ) then
    raise exception 'This emergency access event is not available for review';
  end if;
  update public.emergency_access_events
  set status = 'ended', ended_at = coalesce(ended_at, now()),
      reviewed_by = private.current_user_id(), reviewed_at = now(),
      review_notes = nullif(btrim(review_note), '')
  where id = target_event_id;
end
$function$;

create or replace function public.get_approved_video_room(target_consultation_id uuid)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  consultation_row public.consultations;
  session_row public.video_sessions;
  online_request public.online_consultation_requests;
  is_authorized_participant boolean := false;
begin
  if (select auth.uid()) is null then
    raise exception 'A signed-in consultation participant is required';
  end if;
  select * into consultation_row
  from public.consultations where id = target_consultation_id;
  if not found then raise exception 'Consultation was not found'; end if;

  is_authorized_participant :=
    consultation_row.patient_id = private.current_patient_id()
    or (
      consultation_row.doctor_id = private.current_doctor_id()
      and private.has_active_doctor_employment(
        consultation_row.doctor_id, consultation_row.hospital_id
      )
    )
    or exists (
      select 1 from public.guest_consultation_requests guest_request
      where guest_request.id = consultation_row.guest_request_id
        and guest_request.submitted_by = (select auth.uid())
    );

  if not is_authorized_participant
    or consultation_row.consultation_type not in ('online', 'guest_online')
    or consultation_row.status not in ('approved', 'scheduled', 'in_progress') then
    raise exception 'An approved online consultation participant is required';
  end if;

  select * into online_request
  from public.online_consultation_requests request
  where request.official_consultation_id = consultation_row.id;
  if online_request.id is not null
    and (
      online_request.consultation_channel <> 'video'
      or online_request.request_status not in (
        'confirmed', 'awaiting_contact', 'video_ready', 'in_progress'
      )
    ) then
    raise exception 'Video is not the confirmed channel for this request';
  end if;
  if now() < consultation_row.appointment_date - interval '15 minutes'
    or now() >= consultation_row.appointment_date + interval '4 hours' then
    raise exception 'The video room is outside its scheduled join window';
  end if;

  select * into session_row
  from public.video_sessions
  where consultation_id = target_consultation_id
    and provider = 'jitsi'
    and status in ('ready', 'active')
    and starts_at = consultation_row.appointment_date
    and expires_at > now();
  if not found or session_row.join_url !~ '^https://meet[.]jit[.]si/cnph-[0-9a-f]{32}$' then
    raise exception 'The approved video room is not ready';
  end if;
  return session_row.join_url;
end
$function$;

revoke all on function public.request_patient_care_relationship(uuid, uuid, text, text, text[], timestamptz) from public, anon;
grant execute on function public.request_patient_care_relationship(uuid, uuid, text, text, text[], timestamptz) to authenticated, service_role;
revoke all on function public.approve_patient_care_relationship(uuid, uuid) from public, anon;
grant execute on function public.approve_patient_care_relationship(uuid, uuid) to authenticated, service_role;
revoke all on function public.add_clinical_record_addendum(text, uuid, text, text) from public, anon;
grant execute on function public.add_clinical_record_addendum(text, uuid, text, text) to authenticated, service_role;
revoke all on function public.begin_emergency_patient_access(uuid, uuid, text, text[], integer) from public, anon;
grant execute on function public.begin_emergency_patient_access(uuid, uuid, text, text[], integer) to authenticated, service_role;
revoke all on function public.end_emergency_patient_access(uuid, text) from public, anon;
grant execute on function public.end_emergency_patient_access(uuid, text) to authenticated, service_role;
revoke all on function public.get_approved_video_room(uuid) from public, anon;
grant execute on function public.get_approved_video_room(uuid) to authenticated, service_role;

-- The pending local global name/email search migration conflicts with the
-- restricted-discovery model. If it was applied out of band, remove exposure.
do $block$
begin
  if to_regprocedure('public.search_existing_patients(text)') is not null then
    revoke all on function public.search_existing_patients(text)
      from public, anon, authenticated;
  end if;
end
$block$;

-- ---------------------------------------------------------------------------
-- Guest review parity and patient cancellation/tracking
-- ---------------------------------------------------------------------------

create or replace function public.cancel_online_consultation_request(
  target_request_id uuid,
  cancellation_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  request_row public.online_consultation_requests;
begin
  select * into request_row
  from public.online_consultation_requests
  where id = target_request_id
  for update;

  if not found
    or request_row.patient_id is distinct from private.current_patient_id()
    or request_row.submitted_by is distinct from private.current_user_id() then
    raise exception 'The online request was not found for the current patient';
  end if;
  if request_row.request_status in (
    'completed', 'rejected', 'cancelled', 'no_show', 'in_progress'
  ) then
    raise exception 'This online request can no longer be cancelled';
  end if;
  if nullif(btrim(cancellation_reason), '') is null then
    raise exception 'A cancellation reason is required';
  end if;

  update public.online_consultation_requests
  set request_status = 'cancelled',
      cancellation_reason = btrim(cancellation_reason),
      updated_at = now()
  where id = request_row.id;

  if request_row.official_consultation_id is not null then
    update public.consultations
    set status = 'cancelled', updated_at = now()
    where id = request_row.official_consultation_id
      and status in ('pending', 'approved', 'scheduled');
  end if;

  perform private.revoke_relationship_access(
    request_row.care_relationship_id, 'cancelled', cancellation_reason
  );

  return jsonb_build_object(
    'request_id', request_row.id,
    'reference_number', request_row.reference_number,
    'status', 'cancelled'
  );
end
$function$;

create or replace function public.get_guest_consultation_request_tracking(
  target_reference text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  request_row public.guest_consultation_requests;
  official_consultation public.consultations;
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in with the verified request account to track this request';
  end if;

  select * into request_row
  from public.guest_consultation_requests request
  where request.reference_number = btrim(target_reference)
     or request.id::text = btrim(target_reference);
  if not found or not (
    request_row.submitted_by = (select auth.uid())
    or private.is_hospital_admin_for(request_row.preferred_hospital_id)
    or request_row.assigned_doctor_id = private.current_doctor_id()
  ) then
    raise exception 'Guest consultation request was not found';
  end if;

  select * into official_consultation
  from public.consultations consultation
  where consultation.guest_request_id = request_row.id
  order by consultation.created_at desc
  limit 1;

  return jsonb_build_object(
    'request_id', request_row.id,
    'reference_number', request_row.reference_number,
    'status', request_row.request_status,
    'identity_review_status', request_row.identity_review_status,
    'review_notes', request_row.identity_review_notes,
    'rejection_reason', request_row.rejection_reason,
    'hospital_id', request_row.preferred_hospital_id,
    'department_id', request_row.preferred_department_id,
    'doctor_id', request_row.assigned_doctor_id,
    'preferred_schedule', request_row.preferred_schedule,
    'consultation_id', official_consultation.id,
    'confirmed_schedule', official_consultation.appointment_date,
    'consultation_status', official_consultation.status,
    'updated_at', request_row.updated_at
  );
end
$function$;

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

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      chosen_doctor::text || ':' || scheduled_time::date::text, 0
    )
  );
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
$function$;

revoke all on function public.cancel_online_consultation_request(uuid, text)
  from public, anon;
grant execute on function public.cancel_online_consultation_request(uuid, text)
  to authenticated, service_role;
revoke all on function public.get_guest_consultation_request_tracking(text)
  from public, anon;
grant execute on function public.get_guest_consultation_request_tracking(text)
  to authenticated, service_role;
revoke all on function public.review_guest_consultation(
  uuid, text, uuid, timestamptz, text
) from public, anon;
grant execute on function public.review_guest_consultation(
  uuid, text, uuid, timestamptz, text
) to authenticated, service_role;
