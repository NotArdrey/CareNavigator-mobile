-- Keep guest consultation identity on the same first/last-name model as
-- registration, patient profiles, and doctor-created patient accounts.
alter table public.guest_consultation_requests
  add column if not exists first_name text,
  add column if not exists last_name text;

update public.guest_consultation_requests
set
  first_name = coalesce(nullif(btrim(first_name), ''), split_part(btrim(full_name), ' ', 1)),
  last_name = coalesce(
    nullif(btrim(last_name), ''),
    nullif(btrim(substr(btrim(full_name), length(split_part(btrim(full_name), ' ', 1)) + 1)), '')
  );

update public.guest_consultation_requests
set last_name = coalesce(nullif(btrim(last_name), ''), first_name)
where nullif(btrim(last_name), '') is null;

alter table public.guest_consultation_requests
  alter column first_name set not null,
  alter column last_name set not null;

create or replace function public.standardize_guest_request_identity()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  name_parts text[];
begin
  if nullif(btrim(new.first_name), '') is null
    or nullif(btrim(new.last_name), '') is null then
    name_parts := regexp_split_to_array(btrim(coalesce(new.full_name, '')), '\s+');
    if nullif(btrim(new.first_name), '') is null then
      new.first_name := nullif(btrim(name_parts[1]), '');
    end if;
    if nullif(btrim(new.last_name), '') is null
      and array_length(name_parts, 1) > 1 then
      new.last_name := nullif(
        btrim(array_to_string(name_parts[2:array_length(name_parts, 1)], ' ')),
        ''
      );
    end if;
  end if;
  new.first_name := nullif(btrim(new.first_name), '');
  new.last_name := nullif(btrim(new.last_name), '');
  if new.first_name is null or new.last_name is null then
    raise exception 'First and last names are required for a consultation request';
  end if;
  new.full_name := btrim(concat_ws(' ', new.first_name, new.last_name));
  return new;
end;
$function$;

drop trigger if exists standardize_guest_request_identity_before_write
  on public.guest_consultation_requests;
create trigger standardize_guest_request_identity_before_write
before insert or update on public.guest_consultation_requests
for each row execute function public.standardize_guest_request_identity();
