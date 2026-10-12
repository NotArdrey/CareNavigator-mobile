-- Approved guest requests already create a temporary patient profile. Link that
-- profile to the consultation before consultation relationship validation so
-- doctor identity and checkup history use the same patient source of truth.
create or replace function public.link_guest_patient_to_consultation()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.patient_id is null and new.guest_request_id is not null then
    select patient.id into new.patient_id
    from public.patients as patient
    where patient.guest_request_id = new.guest_request_id
    order by patient.created_at desc
    limit 1;
  end if;
  return new;
end;
$function$;

drop trigger if exists link_guest_patient_before_validation
  on public.consultations;
create trigger link_guest_patient_before_validation
before insert on public.consultations
for each row execute function public.link_guest_patient_to_consultation();
