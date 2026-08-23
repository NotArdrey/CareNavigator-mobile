create or replace function public.assign_doctor_department(
  target_user_id uuid,
  target_department_id uuid
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  admin_hospital_id uuid;
  updated_doctor_id uuid;
begin
  select hospital_id into admin_hospital_id
  from public.users
  where auth_user_id = auth.uid();

  if admin_hospital_id is null
    or not private.is_hospital_admin_for(admin_hospital_id) then
    raise exception 'Hospital administrator access is required';
  end if;

  if not exists (
    select 1
    from public.hospital_departments
    where id = target_department_id
      and hospital_id = admin_hospital_id
  ) then
    raise exception 'The selected department does not belong to your hospital';
  end if;

  update public.doctors
  set department_id = target_department_id,
      updated_at = now()
  where user_id = target_user_id
    and hospital_id = admin_hospital_id
  returning id into updated_doctor_id;

  if updated_doctor_id is null then
    raise exception 'Doctor not found in your hospital';
  end if;
end;
$function$;

revoke all on function public.assign_doctor_department(uuid, uuid)
  from public, anon;

grant execute on function public.assign_doctor_department(uuid, uuid)
  to authenticated, service_role;

comment on function public.assign_doctor_department(uuid, uuid) is
  'Allows a hospital administrator to assign or reassign one of their doctors to a department in the same hospital.';
