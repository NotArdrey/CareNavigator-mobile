-- Align self-service patient registration with the application contract, close
-- legacy storage-policy gaps, and expose a permission-checked patient-link RPC.

create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  selected_role_id smallint;
  app_user_id uuid;
  is_patient_registration boolean :=
    coalesce(new.raw_user_meta_data->>'registration_source', '') =
      'patient_self_service';
begin
  if coalesce(new.is_anonymous, false) then
    return new;
  end if;

  select id into selected_role_id
  from public.roles
  where role_name = case
    when is_patient_registration then 'patient'
    else 'guest'
  end;

  if selected_role_id is null then
    raise exception 'Required application role is not configured';
  end if;

  insert into public.users(
    id,
    auth_user_id,
    role_id,
    first_name,
    last_name,
    email,
    mobile_number,
    birth_date,
    sex,
    address,
    account_status
  ) values (
    new.id,
    new.id,
    selected_role_id,
    coalesce(new.raw_user_meta_data->>'first_name', ''),
    coalesce(new.raw_user_meta_data->>'last_name', ''),
    new.email,
    coalesce(
      nullif(pg_catalog.btrim(coalesce(new.phone, '')), ''),
      nullif(
        pg_catalog.btrim(
          coalesce(new.raw_user_meta_data->>'mobile_number', '')
        ),
        ''
      )
    ),
    nullif(
      pg_catalog.btrim(coalesce(new.raw_user_meta_data->>'birth_date', '')),
      ''
    )::date,
    nullif(
      pg_catalog.btrim(coalesce(new.raw_user_meta_data->>'sex', '')),
      ''
    )::public.sex_type,
    nullif(
      pg_catalog.btrim(coalesce(new.raw_user_meta_data->>'address', '')),
      ''
    ),
    'active'
  )
  on conflict(auth_user_id) do update
  set role_id = case
        when is_patient_registration then excluded.role_id
        else public.users.role_id
      end,
      updated_at = now()
  returning id into app_user_id;

  if is_patient_registration then
    insert into public.patients(
      user_id,
      identity_verification_status,
      account_activation_status,
      profile_status,
      activated_at
    ) values (
      app_user_id,
      'pending',
      'active',
      'official',
      now()
    )
    on conflict(user_id) do update
    set account_activation_status = 'active',
        profile_status = 'official',
        activated_at = coalesce(public.patients.activated_at, now()),
        updated_at = now();
  end if;

  return new;
end;
$function$;

revoke all on function public.handle_new_auth_user()
  from public, anon, authenticated;
grant execute on function public.handle_new_auth_user()
  to postgres, service_role;

create or replace function public.link_existing_patient(target_email text)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  normalized_email text := pg_catalog.lower(
    pg_catalog.btrim(coalesce(target_email, ''))
  );
  doctor_row public.doctors;
  patient_row public.patients;
  assignment_id uuid;
begin
  if (select auth.uid()) is null
    or private.current_doctor_id() is null
    or not private.has_permission('patients.manage') then
    raise exception 'An authorized doctor session is required';
  end if;

  if normalized_email = '' then
    raise exception 'A patient email address is required';
  end if;

  select * into doctor_row
  from public.doctors
  where id = private.current_doctor_id();

  if not found then
    raise exception 'Doctor profile not found';
  end if;

  select p.* into patient_row
  from public.patients p
  join public.users u on u.id = p.user_id
  where pg_catalog.lower(u.email) = normalized_email
    and u.account_status = 'active'
    and p.account_activation_status = 'active'
    and p.profile_status = 'official'
    and (p.primary_hospital_id is null
      or p.primary_hospital_id = doctor_row.hospital_id)
  limit 1;

  if not found then
    raise exception 'No active patient account was found for this hospital';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      doctor_row.id::text || ':' || patient_row.id::text,
      0
    )
  );

  update public.patients
  set primary_hospital_id = doctor_row.hospital_id,
      updated_at = now()
  where id = patient_row.id
    and primary_hospital_id is null;

  select id into assignment_id
  from public.doctor_patient_assignments
  where doctor_id = doctor_row.id
    and patient_id = patient_row.id
    and ended_at is null;

  if assignment_id is null then
    insert into public.doctor_patient_assignments(
      doctor_id,
      patient_id,
      notes
    ) values (
      doctor_row.id,
      patient_row.id,
      'Linked by doctor using verified account email'
    )
    returning id into assignment_id;
  end if;

  return assignment_id;
end;
$function$;

revoke all on function public.link_existing_patient(text)
  from public, anon;
grant execute on function public.link_existing_patient(text)
  to authenticated, service_role;

drop policy if exists "Authenticated users can upload profile images"
  on storage.objects;
drop policy if exists "Authenticated users can update profile images"
  on storage.objects;

revoke all on function public.link_guest_patient_to_consultation()
  from public, anon, authenticated;
revoke all on function public.sync_doctor_profile_image()
  from public, anon, authenticated;
grant execute on function public.link_guest_patient_to_consultation()
  to postgres, service_role;
grant execute on function public.sync_doctor_profile_image()
  to postgres, service_role;
