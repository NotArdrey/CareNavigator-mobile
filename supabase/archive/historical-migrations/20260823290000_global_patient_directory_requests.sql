-- Global patient identity discovery for verified clinicians.
-- Directory discovery and clinical-record authorization are intentionally
-- separate: selecting an identity creates a pending connection request only.

create table if not exists public.patient_connection_requests (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  hospital_id uuid not null references public.hospitals(id) on delete cascade,
  doctor_id uuid not null references public.doctors(id) on delete cascade,
  requested_by uuid not null references public.users(id) on delete restrict,
  purpose text not null default 'clinician_patient_connection',
  status text not null default 'requested'
    check (status in ('requested', 'approved', 'rejected', 'cancelled', 'expired')),
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  expires_at timestamptz not null default (now() + interval '7 days'),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (expires_at > requested_at)
);

create unique index if not exists patient_connection_requests_pending_uidx
  on public.patient_connection_requests(doctor_id, patient_id)
  where status = 'requested';

alter table public.patient_connection_requests enable row level security;
revoke all on table public.patient_connection_requests from public, anon, authenticated;
grant select on table public.patient_connection_requests to service_role;

create or replace function public.search_existing_patients(search_query text)
returns table(patient_id uuid, display_name text, email text)
language plpgsql
security definer
set search_path to ''
as $function$
declare
  normalized_query text := pg_catalog.lower(
    pg_catalog.btrim(coalesce(search_query, ''))
  );
begin
  if (select auth.uid()) is null
    or private.current_doctor_id() is null
    or not private.has_permission('patients.manage') then
    raise exception 'An authorized doctor session is required';
  end if;

  if pg_catalog.length(normalized_query) < 2 then
    raise exception 'Enter at least 2 characters';
  end if;

  return query
  select
    patient.id,
    pg_catalog.btrim(
      pg_catalog.concat_ws(' ', app_user.first_name, app_user.last_name)
    ),
    coalesce(app_user.email, '')
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where app_user.account_status = 'active'
    and patient.account_activation_status = 'active'
    and patient.profile_status = 'official'
    and (
      pg_catalog.strpos(
        pg_catalog.lower(
          pg_catalog.concat_ws(' ', app_user.first_name, app_user.last_name)
        ),
        normalized_query
      ) > 0
      or pg_catalog.strpos(
        pg_catalog.lower(coalesce(app_user.email, '')),
        normalized_query
      ) > 0
    )
  order by
    case when pg_catalog.lower(app_user.email) = normalized_query then 0 else 1 end,
    case when pg_catalog.lower(
      pg_catalog.btrim(
        pg_catalog.concat_ws(' ', app_user.first_name, app_user.last_name)
      )
    ) = normalized_query then 0 else 1 end,
    app_user.last_name,
    app_user.first_name,
    app_user.email
  limit 100;
end
$function$;

create or replace function public.link_existing_patient(target_patient_id uuid)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  doctor_row public.doctors;
  current_app_user_id uuid;
  request_id uuid;
  patient_auth_user_id uuid;
  employment_is_active boolean := true;
begin
  current_app_user_id := private.current_user_id();
  if (select auth.uid()) is null
    or current_app_user_id is null
    or private.current_doctor_id() is null
    or not private.has_permission('patients.manage') then
    raise exception 'An authorized doctor session is required';
  end if;

  select * into doctor_row
  from public.doctors doctor
  where doctor.id = private.current_doctor_id();

  if not found or doctor_row.hospital_id is null then
    raise exception 'An active hospital doctor profile is required';
  end if;

  if pg_catalog.to_regclass('public.doctor_hospital_employments') is not null then
    execute $sql$
      select exists (
        select 1
        from public.doctor_hospital_employments employment
        where employment.doctor_id = $1
          and employment.hospital_id = $2
          and employment.employment_status = 'active'
          and employment.is_verified
          and employment.starts_at <= now()
          and (employment.ends_at is null or employment.ends_at > now())
      )
    $sql$
    into employment_is_active
    using doctor_row.id, doctor_row.hospital_id;
  end if;

  if not employment_is_active then
    raise exception 'The doctor is not actively verified at this hospital';
  end if;

  select app_user.auth_user_id into patient_auth_user_id
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where patient.id = target_patient_id
    and app_user.account_status = 'active'
    and patient.account_activation_status = 'active'
    and patient.profile_status = 'official';

  if not found then
    raise exception 'The selected active patient account was not found';
  end if;

  select request.id into request_id
  from public.patient_connection_requests request
  where request.doctor_id = doctor_row.id
    and request.patient_id = target_patient_id
    and request.status = 'requested'
    and request.expires_at > now()
  order by request.requested_at desc
  limit 1;

  if request_id is null then
    insert into public.patient_connection_requests(
      patient_id,
      hospital_id,
      doctor_id,
      requested_by
    ) values (
      target_patient_id,
      doctor_row.hospital_id,
      doctor_row.id,
      current_app_user_id
    )
    returning id into request_id;

    insert into public.notifications(
      user_id,
      title,
      message,
      notification_type,
      reference_id,
      data
    ) values (
      patient_auth_user_id,
      'Clinician connection request',
      'A verified clinician requested to connect with your patient account.',
      'access_request',
      request_id,
      pg_catalog.jsonb_build_object(
        'connection_request_id', request_id,
        'doctor_id', doctor_row.id,
        'hospital_id', doctor_row.hospital_id,
        'status', 'requested'
      )
    );
  end if;

  return request_id;
end
$function$;

revoke all on function public.search_existing_patients(text)
  from public, anon;
grant execute on function public.search_existing_patients(text)
  to authenticated, service_role;

revoke all on function public.link_existing_patient(uuid)
  from public, anon;
grant execute on function public.link_existing_patient(uuid)
  to authenticated, service_role;

drop function if exists public.link_existing_patient(text);
