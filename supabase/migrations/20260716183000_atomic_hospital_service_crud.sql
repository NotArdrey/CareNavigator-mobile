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
    doctor.id = target_primary_doctor_id
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

create or replace function public.save_hospital_service(
  service_payload jsonb,
  target_doctor_ids uuid[] default '{}'::uuid[],
  target_primary_doctor_id uuid default null
)
returns uuid
language plpgsql
security invoker
set search_path = ''
as $$
declare
  target_service_id uuid := nullif(service_payload ->> 'id', '')::uuid;
  target_hospital_id uuid := nullif(service_payload ->> 'hospital_id', '')::uuid;
  delivery_modes_value text[];
  tags_value text[];
begin
  if target_hospital_id is null then
    raise exception 'Hospital is required';
  end if;
  if not private.is_hospital_admin_for(target_hospital_id) then
    raise exception 'Not authorized to manage services for this hospital';
  end if;

  select coalesce(array_agg(value), array['in_person']::text[])
    into delivery_modes_value
  from jsonb_array_elements_text(
    coalesce(service_payload -> 'delivery_modes', '["in_person"]'::jsonb)
  ) value;
  select coalesce(array_agg(value), '{}'::text[])
    into tags_value
  from jsonb_array_elements_text(
    coalesce(service_payload -> 'tags', '[]'::jsonb)
  ) value;

  if target_service_id is null then
    insert into public.hospital_services (
      hospital_id,
      department_id,
      category_id,
      service_name,
      service_code,
      description,
      availability_status,
      operating_hours,
      delivery_modes,
      appointment_required,
      accepts_walk_ins,
      fee_min,
      fee_max,
      fee_notes,
      contact_number,
      booking_url,
      preparation_instructions,
      tags,
      last_updated
    ) values (
      target_hospital_id,
      nullif(service_payload ->> 'department_id', '')::uuid,
      nullif(service_payload ->> 'category_id', '')::uuid,
      btrim(service_payload ->> 'service_name'),
      nullif(btrim(service_payload ->> 'service_code'), ''),
      coalesce(service_payload ->> 'description', ''),
      coalesce(nullif(service_payload ->> 'availability_status', ''), 'available')::public.availability_status,
      coalesce(service_payload -> 'operating_hours', '{}'::jsonb),
      delivery_modes_value,
      coalesce((service_payload ->> 'appointment_required')::boolean, false),
      coalesce((service_payload ->> 'accepts_walk_ins')::boolean, true),
      nullif(service_payload ->> 'fee_min', '')::numeric,
      nullif(service_payload ->> 'fee_max', '')::numeric,
      nullif(btrim(service_payload ->> 'fee_notes'), ''),
      nullif(btrim(service_payload ->> 'contact_number'), ''),
      nullif(btrim(service_payload ->> 'booking_url'), ''),
      nullif(btrim(service_payload ->> 'preparation_instructions'), ''),
      tags_value,
      now()
    )
    returning id into target_service_id;
  else
    update public.hospital_services service
    set
      department_id = nullif(service_payload ->> 'department_id', '')::uuid,
      category_id = nullif(service_payload ->> 'category_id', '')::uuid,
      service_name = btrim(service_payload ->> 'service_name'),
      service_code = nullif(btrim(service_payload ->> 'service_code'), ''),
      description = coalesce(service_payload ->> 'description', ''),
      availability_status = coalesce(nullif(service_payload ->> 'availability_status', ''), 'available')::public.availability_status,
      operating_hours = coalesce(service_payload -> 'operating_hours', '{}'::jsonb),
      delivery_modes = delivery_modes_value,
      appointment_required = coalesce((service_payload ->> 'appointment_required')::boolean, false),
      accepts_walk_ins = coalesce((service_payload ->> 'accepts_walk_ins')::boolean, true),
      fee_min = nullif(service_payload ->> 'fee_min', '')::numeric,
      fee_max = nullif(service_payload ->> 'fee_max', '')::numeric,
      fee_notes = nullif(btrim(service_payload ->> 'fee_notes'), ''),
      contact_number = nullif(btrim(service_payload ->> 'contact_number'), ''),
      booking_url = nullif(btrim(service_payload ->> 'booking_url'), ''),
      preparation_instructions = nullif(btrim(service_payload ->> 'preparation_instructions'), ''),
      tags = tags_value,
      last_updated = now()
    where service.id = target_service_id
      and service.hospital_id = target_hospital_id;

    if not found then
      raise exception 'Hospital service was not found';
    end if;
  end if;

  perform public.replace_hospital_service_doctors(
    target_service_id,
    target_doctor_ids,
    target_primary_doctor_id
  );
  return target_service_id;
end;
$$;

revoke all on function public.replace_hospital_service_doctors(uuid, uuid[], uuid)
  from public, anon;
revoke all on function public.save_hospital_service(jsonb, uuid[], uuid)
  from public, anon;
grant execute on function public.replace_hospital_service_doctors(uuid, uuid[], uuid)
  to authenticated;
grant execute on function public.save_hospital_service(jsonb, uuid[], uuid)
  to authenticated;

insert into supabase_migrations.schema_migrations (version, statements, name)
values (
  '20260716183000',
  array[]::text[],
  'atomic_hospital_service_crud'
)
on conflict (version) do nothing;

commit;
