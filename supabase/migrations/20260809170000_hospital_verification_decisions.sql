alter table public.hospitals
  add column if not exists verification_notes text,
  add column if not exists verification_decided_at timestamptz,
  add column if not exists verification_decided_by uuid
    references public.users(id) on delete set null;

comment on column public.hospitals.verification_notes is
  'The latest super-administrator hospital verification decision note.';
comment on column public.hospitals.verification_decided_at is
  'When the latest hospital verification decision was recorded.';
comment on column public.hospitals.verification_decided_by is
  'Application user who recorded the latest hospital verification decision.';

create or replace function public.review_hospital_application(
  target_hospital_id uuid,
  decision public.verification_status,
  decision_note text
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  normalized_note text := btrim(coalesce(decision_note, ''));
  actor_user_id uuid := private.current_user_id();
begin
  if not private.is_super_admin() then
    raise exception 'Super administrator access is required';
  end if;
  if decision not in ('verified'::public.verification_status, 'rejected'::public.verification_status) then
    raise exception 'Hospital verification decision must be verified or rejected';
  end if;
  if char_length(normalized_note) < 5 or char_length(normalized_note) > 1000 then
    raise exception 'A verification note between 5 and 1000 characters is required';
  end if;

  update public.hospitals
  set verification_status = decision,
      verification_notes = normalized_note,
      verification_decided_at = now(),
      verification_decided_by = actor_user_id
  where id = target_hospital_id;

  if not found then
    raise exception 'Hospital was not found';
  end if;

  insert into public.audit_logs(user_id, hospital_id, action, module, record_id, metadata)
  values (
    actor_user_id,
    target_hospital_id,
    'hospital_verification_decision',
    'hospitals',
    target_hospital_id,
    jsonb_build_object('decision', decision, 'note', normalized_note)
  );
end;
$$;

revoke all on function public.review_hospital_application(uuid, public.verification_status, text) from public;
grant execute on function public.review_hospital_application(uuid, public.verification_status, text) to authenticated;
