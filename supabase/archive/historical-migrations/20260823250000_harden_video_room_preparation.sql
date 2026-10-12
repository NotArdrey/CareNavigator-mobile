-- Recheck employment and consultation-scoped access when a clinician prepares
-- a video room. Confirmation-time authorization is not sufficient because an
-- employment, assignment, consent, or grant may be revoked before the visit.

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
  request_row public.online_consultation_requests;
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
    or consultation_row.patient_id is null
    or consultation_row.doctor_id is distinct from private.current_doctor_id()
    or consultation_row.consultation_type not in ('online', 'guest_online')
    or consultation_row.status not in ('approved', 'scheduled', 'in_progress')
    or not private.has_active_doctor_employment(
      consultation_row.doctor_id, consultation_row.hospital_id
    )
    or not private.actor_has_category_access(
      consultation_row.patient_id, 'consultations'
    ) then
    raise exception 'An active authorized online consultation assigned to this doctor is required';
  end if;

  select * into request_row
  from public.online_consultation_requests request
  where request.official_consultation_id = consultation_row.id;
  if request_row.id is not null
    and (
      request_row.consultation_channel <> 'video'
      or request_row.request_status not in (
        'confirmed', 'awaiting_contact', 'video_ready', 'in_progress'
      )
    ) then
    raise exception 'Video is not the confirmed channel for this request';
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
    and session_row.status in ('ready', 'active')
    and session_row.starts_at = consultation_row.appointment_date
    and session_row.expires_at > now() then
    return session_row.id;
  end if;

  generated_room := 'cnph-' || replace(gen_random_uuid()::text, '-', '');
  generated_url := 'https://meet.jit.si/' || generated_room;

  if session_row.id is null then
    insert into public.video_sessions(
      consultation_id, provider, room_name, join_url, status, created_by,
      starts_at, expires_at
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
end
$function$;

revoke all on function public.ensure_video_session(uuid, text)
  from public, anon;
grant execute on function public.ensure_video_session(uuid, text)
  to authenticated, service_role;
