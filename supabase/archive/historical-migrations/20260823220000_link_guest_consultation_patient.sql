-- A reviewed guest consultation may retain its guest request provenance while
-- linking the temporary/global patient identity. When both keys are present,
-- a trigger proves that they refer to the same intake.

alter table public.consultations
  drop constraint if exists consultations_check;
alter table public.consultations
  add constraint consultations_identity_source_check
  check (num_nonnulls(patient_id, guest_request_id) >= 1);

create or replace function private.validate_consultation_identity_source()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.patient_id is not null
    and new.guest_request_id is not null
    and not exists (
      select 1
      from public.patients patient
      where patient.id = new.patient_id
        and patient.guest_request_id = new.guest_request_id
    ) then
    raise exception 'Consultation patient and guest request must identify the same intake';
  end if;
  return new;
end
$function$;

revoke all on function private.validate_consultation_identity_source()
  from public, anon, authenticated;

drop trigger if exists validate_consultation_identity_source_before_write
  on public.consultations;
create trigger validate_consultation_identity_source_before_write
before insert or update of patient_id, guest_request_id
on public.consultations
for each row execute function private.validate_consultation_identity_source();
