create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  guest_role_id smallint;
begin
  if coalesce(new.is_anonymous, false) then
    return new;
  end if;

  select id into guest_role_id
  from public.roles
  where role_name = 'guest';

  insert into public.users(
    id,
    auth_user_id,
    role_id,
    first_name,
    last_name,
    email,
    mobile_number,
    address,
    account_status
  ) values (
    new.id,
    new.id,
    guest_role_id,
    coalesce(new.raw_user_meta_data->>'first_name', ''),
    coalesce(new.raw_user_meta_data->>'last_name', ''),
    new.email,
    new.phone,
    nullif(btrim(coalesce(new.raw_user_meta_data->>'address', '')), ''),
    'active'
  ) on conflict(auth_user_id) do nothing;

  return new;
end;
$function$;
