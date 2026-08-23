-- The legacy contract permits only one non-ended doctor/patient assignment.
-- Starting a newly approved relationship therefore atomically ends the prior
-- assignment. Its grants and relationship are revoked by the companion trigger.

create or replace function private.end_replaced_doctor_patient_assignment()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.assignment_status = 'active' and new.ended_at is null then
    update public.doctor_patient_assignments assignment
    set assignment_status = 'ended',
        ended_at = now(),
        ended_reason = 'Replaced by a newly approved care relationship'
    where assignment.doctor_id = new.doctor_id
      and assignment.patient_id = new.patient_id
      and assignment.ended_at is null
      and assignment.assignment_status = 'active'
      and assignment.id is distinct from new.id
      and assignment.care_relationship_id is distinct from new.care_relationship_id;
  end if;
  return new;
end
$function$;

create or replace function private.revoke_ended_assignment_access()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if old.ended_at is null
    and (
      new.ended_at is not null
      or new.assignment_status in ('ended', 'revoked')
    )
    and new.care_relationship_id is not null then
    update public.patient_access_grants grant_row
    set status = 'revoked',
        revoked_at = coalesce(grant_row.revoked_at, now()),
        revoked_by = private.current_user_id(),
        revocation_reason = coalesce(
          grant_row.revocation_reason,
          new.ended_reason,
          'Doctor assignment ended'
        ),
        updated_at = now()
    where grant_row.care_relationship_id = new.care_relationship_id
      and grant_row.receiving_doctor_id = new.doctor_id
      and grant_row.status in ('requested', 'active', 'suspended')
      and grant_row.revoked_at is null;

    update public.patient_care_relationships relationship
    set status = case
          when relationship.status = 'completed' then 'completed'
          else 'revoked'
        end,
        ended_at = coalesce(relationship.ended_at, now()),
        termination_reason = coalesce(
          relationship.termination_reason,
          new.ended_reason,
          'Doctor assignment ended'
        ),
        updated_at = now()
    where relationship.id = new.care_relationship_id
      and relationship.status in ('requested', 'approved', 'active');
  end if;
  return new;
end
$function$;

revoke all on function private.end_replaced_doctor_patient_assignment()
  from public, anon, authenticated;
revoke all on function private.revoke_ended_assignment_access()
  from public, anon, authenticated;

drop trigger if exists end_replaced_assignment_before_write
  on public.doctor_patient_assignments;
create trigger end_replaced_assignment_before_write
before insert or update of doctor_id, patient_id, assignment_status, ended_at
on public.doctor_patient_assignments
for each row execute function private.end_replaced_doctor_patient_assignment();

drop trigger if exists revoke_ended_assignment_access_after_update
  on public.doctor_patient_assignments;
create trigger revoke_ended_assignment_access_after_update
after update of assignment_status, ended_at
on public.doctor_patient_assignments
for each row execute function private.revoke_ended_assignment_access();
