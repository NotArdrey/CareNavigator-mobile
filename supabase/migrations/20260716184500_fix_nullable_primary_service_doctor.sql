begin;

create or replace function public.replace_hospital_service_doctors(
  target_service_id uuid,
  target_doctor_ids uuid[] default '{}'::uuid[],
  target_primary_doctor_id uuid default null
)
returns setof public.hospital_service_doctors
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target_hospital_id uuid;
  normalized_doctor_ids uuid[];
  expected_count integer;
  inserted_count integer;
begin
  select service.hospital_id
    into target_hospital_id
  from public.hospital_services service
  where service.id = target_service_id;

  if target_hospital_id is null then
    raise exception 'Hospital service was not found';
  end if;
  if not private.is_hospital_admin_for(target_hospital_id) then
    raise exception 'Not authorized to manage this hospital service';
  end if;

  select coalesce(array_agg(distinct doctor_id), '{}'::uuid[])
    into normalized_doctor_ids
  from unnest(coalesce(target_doctor_ids, '{}'::uuid[])) doctor_id;

  expected_count := cardinality(normalized_doctor_ids);
  if target_primary_doctor_id is not null
     and not (target_primary_doctor_id = any(normalized_doctor_ids)) then
    raise exception 'Primary doctor must be assigned to the service';
  end if;

  delete from public.hospital_service_doctors assignment
  where assignment.service_id = target_service_id;

  insert into public.hospital_service_doctors (
    hospital_id,
    service_id,
    doctor_id,
    is_primary
  )
  select
    target_hospital_id,
    target_service_id,
    doctor.id,
    coalesce(doctor.id = target_primary_doctor_id, false)
  from public.doctors doctor
  where doctor.hospital_id = target_hospital_id
    and doctor.id = any(normalized_doctor_ids);

  get diagnostics inserted_count = row_count;
  if inserted_count <> expected_count then
    raise exception 'One or more selected doctors do not belong to this hospital';
  end if;

  return query
  select assignment.*
  from public.hospital_service_doctors assignment
  where assignment.service_id = target_service_id
  order by assignment.is_primary desc, assignment.created_at;
end;
$$;

revoke all on function public.replace_hospital_service_doctors(uuid, uuid[], uuid)
  from public, anon;
grant execute on function public.replace_hospital_service_doctors(uuid, uuid[], uuid)
  to authenticated;

insert into supabase_migrations.schema_migrations (version, statements, name)
values (
  '20260716184500',
  array[]::text[],
  'fix_nullable_primary_service_doctor'
)
on conflict (version) do nothing;

commit;
