-- Keep consultation scheduling and video-room access server-authoritative.
-- Raw provider URLs are deliberately unavailable through table APIs; clients
-- receive them only from a short-window participant RPC.

create or replace function public.enforce_consultation_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor_role text := private.current_role();
  patient_cancel boolean := false;
  patient_reschedule boolean := false;
begin
  if tg_op = 'UPDATE' then
    if new.patient_id is distinct from old.patient_id
      or new.guest_request_id is distinct from old.guest_request_id
      or new.doctor_id is distinct from old.doctor_id
      or new.hospital_id is distinct from old.hospital_id
      or new.consultation_type is distinct from old.consultation_type
      or new.created_at is distinct from old.created_at then
      raise exception 'Consultation ownership fields are immutable';
    end if;

    if new.status is distinct from old.status and not (
      (old.status = 'pending' and new.status in ('approved','rejected','scheduled','cancelled'))
      or (old.status = 'approved' and new.status in ('scheduled','in_progress','cancelled'))
      or (old.status = 'scheduled' and new.status in ('in_progress','cancelled'))
      or (old.status = 'in_progress' and new.status in ('completed','cancelled'))
    ) then
      raise exception 'Invalid consultation status transition from % to %', old.status, new.status;
    end if;

    if actor_role = 'patient' then
      patient_cancel :=
        old.status in ('pending','approved','scheduled')
        and new.status = 'cancelled'
        and (to_jsonb(new) - array['status','updated_at'])
          is not distinct from (to_jsonb(old) - array['status','updated_at']);

      patient_reschedule :=
        old.status in ('approved','scheduled')
        and new.status = old.status
        and new.appointment_date is distinct from old.appointment_date
        and (to_jsonb(new) - array['appointment_date','updated_at'])
          is not distinct from (to_jsonb(old) - array['appointment_date','updated_at']);

      if not patient_cancel and not patient_reschedule then
        raise exception 'Patients may only cancel or reschedule their own eligible consultation';
      end if;
    elsif actor_role = 'hospital_admin' and (
      new.doctor_notes is distinct from old.doctor_notes
      or new.confirmed_diagnosis is distinct from old.confirmed_diagnosis
      or new.treatment_plan is distinct from old.treatment_plan
      or new.consultation_summary is distinct from old.consultation_summary
    ) then
      raise exception 'Hospital administrators cannot modify clinical content';
    end if;

    if new.status = 'completed' and new.completed_at is null then
      new.completed_at := now();
    end if;
    if new.status = 'in_progress' and new.started_at is null then
      new.started_at := now();
    end if;
    if new.status = 'approved' and new.approved_at is null then
      new.approved_at := now();
    end if;
  end if;
  return new;
end;
$function$;

create or replace function public.reschedule_consultation(
  target_consultation_id uuid,
  scheduled_for timestamptz
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  consultation_row public.consultations;
begin
  if (select auth.uid()) is null or scheduled_for is null or scheduled_for <= now() then
    raise exception 'A signed-in patient and a future appointment time are required';
  end if;

  select * into consultation_row
  from public.consultations
  where id = target_consultation_id
  for update;

  if not found
    or private.current_patient_id() is null
    or consultation_row.patient_id is distinct from private.current_patient_id() then
    raise exception 'The consultation is not accessible to this patient';
  end if;
  if consultation_row.status not in ('approved','scheduled') then
    raise exception 'Only an approved or scheduled consultation may be rescheduled';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      consultation_row.doctor_id::text || ':' || scheduled_for::date::text,
      0
    )
  );
  if not private.is_doctor_slot_available(
    consultation_row.doctor_id,
    consultation_row.hospital_id,
    consultation_row.consultation_type,
    scheduled_for,
    consultation_row.id
  ) then
    raise exception 'The selected appointment slot is unavailable';
  end if;

  update public.consultations
  set appointment_date = scheduled_for
  where id = target_consultation_id
  returning * into consultation_row;

  return jsonb_build_object(
    'id', consultation_row.id,
    'status', consultation_row.status,
    'appointment_date', consultation_row.appointment_date
  );
end;
$function$;

create or replace function public.cancel_consultation(target_consultation_id uuid)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  consultation_row public.consultations;
begin
  if (select auth.uid()) is null then
    raise exception 'A signed-in patient is required';
  end if;

  select * into consultation_row
  from public.consultations
  where id = target_consultation_id
  for update;

  if not found
    or private.current_patient_id() is null
    or consultation_row.patient_id is distinct from private.current_patient_id() then
    raise exception 'The consultation is not accessible to this patient';
  end if;
  if consultation_row.status not in ('pending','approved','scheduled') then
    raise exception 'This consultation can no longer be cancelled by the patient';
  end if;

  update public.consultations
  set status = 'cancelled'
  where id = target_consultation_id
  returning * into consultation_row;

  return jsonb_build_object('id', consultation_row.id, 'status', consultation_row.status);
end;
$function$;

create or replace function public.invalidate_video_session_after_consultation_change()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.appointment_date is distinct from old.appointment_date then
    update public.video_sessions
    set status = 'cancelled',
        ended_at = coalesce(ended_at, now()),
        expires_at = least(coalesce(expires_at, now()), now())
    where consultation_id = new.id
      and status not in ('ended','cancelled','failed');
  elsif new.status is distinct from old.status
    and new.status in ('rejected','cancelled','completed') then
    update public.video_sessions
    set status = case when new.status = 'completed' then 'ended' else 'cancelled' end,
        ended_at = coalesce(ended_at, now()),
        expires_at = least(coalesce(expires_at, now()), now())
    where consultation_id = new.id
      and status not in ('ended','cancelled','failed');
  end if;
  return new;
end;
$function$;

drop trigger if exists invalidate_video_session_after_consultation_change on public.consultations;
create trigger invalidate_video_session_after_consultation_change
after update of appointment_date, status on public.consultations
for each row execute function public.invalidate_video_session_after_consultation_change();

create or replace function public.ensure_video_session(
  target_consultation_id uuid,
  target_provider text default 'jitsi'
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  consultation_row public.consultations;
  session_row public.video_sessions;
  generated_room text;
  generated_url text;
begin
  if (select auth.uid()) is null or lower(target_provider) <> 'jitsi' then
    raise exception 'A signed-in doctor and the supported video provider are required';
  end if;

  select * into consultation_row
  from public.consultations
  where id = target_consultation_id
  for update;

  if not found
    or private.current_doctor_id() is null
    or consultation_row.doctor_id is distinct from private.current_doctor_id()
    or consultation_row.consultation_type not in ('online','guest_online')
    or consultation_row.status not in ('approved','scheduled','in_progress') then
    raise exception 'An approved online consultation assigned to this doctor is required';
  end if;
  if now() < consultation_row.appointment_date - interval '15 minutes'
    or now() >= consultation_row.appointment_date + interval '4 hours' then
    raise exception 'The video room opens 15 minutes before the scheduled consultation';
  end if;

  select * into session_row
  from public.video_sessions
  where consultation_id = target_consultation_id
  for update;

  if found
    and session_row.provider = 'jitsi'
    and session_row.status in ('ready','active')
    and session_row.starts_at = consultation_row.appointment_date
    and session_row.expires_at > now() then
    return session_row.id;
  end if;

  generated_room := 'cnph-' || replace(gen_random_uuid()::text, '-', '');
  generated_url := 'https://meet.jit.si/' || generated_room;

  if session_row.id is null then
    insert into public.video_sessions(
      consultation_id, provider, room_name, join_url, status, created_by, starts_at, expires_at
    ) values (
      target_consultation_id, 'jitsi', generated_room, generated_url, 'ready',
      (select auth.uid()), consultation_row.appointment_date,
      consultation_row.appointment_date + interval '4 hours'
    ) returning * into session_row;
  else
    update public.video_sessions
    set provider = 'jitsi',
        room_name = generated_room,
        join_url = generated_url,
        status = 'ready',
        provider_metadata = '{}'::jsonb,
        created_by = (select auth.uid()),
        starts_at = consultation_row.appointment_date,
        started_at = null,
        ended_at = null,
        expires_at = consultation_row.appointment_date + interval '4 hours'
    where id = session_row.id
    returning * into session_row;
  end if;

  return session_row.id;
end;
$function$;

create or replace function public.get_approved_video_room(target_consultation_id uuid)
returns text
language plpgsql
security definer
set search_path to ''
as $function$
declare
  consultation_row public.consultations;
  session_row public.video_sessions;
begin
  if (select auth.uid()) is null then
    raise exception 'A signed-in consultation participant is required';
  end if;

  select * into consultation_row
  from public.consultations
  where id = target_consultation_id;

  if not found
    or not private.is_consultation_participant(target_consultation_id)
    or consultation_row.consultation_type not in ('online','guest_online')
    or consultation_row.status not in ('approved','scheduled','in_progress') then
    raise exception 'An approved online consultation participant is required';
  end if;
  if now() < consultation_row.appointment_date - interval '15 minutes'
    or now() >= consultation_row.appointment_date + interval '4 hours' then
    raise exception 'The video room is outside its scheduled join window';
  end if;

  select * into session_row
  from public.video_sessions
  where consultation_id = target_consultation_id
    and provider = 'jitsi'
    and status in ('ready','active')
    and starts_at = consultation_row.appointment_date
    and expires_at > now();

  if not found or session_row.join_url !~ '^https://meet[.]jit[.]si/cnph-[0-9a-f]{32}$' then
    raise exception 'The approved video room is not ready';
  end if;
  return session_row.join_url;
end;
$function$;

-- Remove the legacy URL copy so table reads cannot bypass session checks.
update public.consultations set meeting_link = null where meeting_link is not null;
alter table public.consultations
  drop constraint if exists consultations_meeting_link_must_be_null;
alter table public.consultations
  add constraint consultations_meeting_link_must_be_null check (meeting_link is null);

revoke all on table public.video_sessions from anon, authenticated;

revoke all on function public.invalidate_video_session_after_consultation_change() from public, anon, authenticated;
revoke all on function public.ensure_video_session(uuid, text) from public, anon;
revoke all on function public.get_approved_video_room(uuid) from public, anon;
revoke all on function public.reschedule_consultation(uuid, timestamptz) from public, anon;
revoke all on function public.cancel_consultation(uuid) from public, anon;

grant execute on function public.ensure_video_session(uuid, text) to authenticated, service_role;
grant execute on function public.get_approved_video_room(uuid) to authenticated, service_role;
grant execute on function public.reschedule_consultation(uuid, timestamptz) to authenticated, service_role;
grant execute on function public.cancel_consultation(uuid) to authenticated, service_role;
