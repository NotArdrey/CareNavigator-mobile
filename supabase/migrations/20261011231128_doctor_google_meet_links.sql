-- Google Meet links are supplied by the assigned doctor after hospital approval.
-- Retain the existing participant, hospital and appointment-time boundaries.
create or replace function private.normalize_google_meet_link(value text)
returns text language plpgsql immutable set search_path='' as $$
declare canonical text;
begin
  if value is null or length(value)>2048 then raise exception 'Enter a valid Google Meet link'; end if;
  canonical:=lower(regexp_replace(btrim(value),'[?#].*$',''));
  if canonical !~ '^https://meet[.]google[.]com/[a-z]{3}-[a-z]{4}-[a-z]{3}/?$' then
    raise exception 'Use a Google Meet link such as https://meet.google.com/abc-defg-hij';
  end if;
  return rtrim(canonical,'/');
end $$;
revoke all on function private.normalize_google_meet_link(text) from public,anon,authenticated;

create or replace function public.set_consultation_meet_link(target_consultation_id uuid,meeting_url text)
returns uuid language plpgsql security definer set search_path='' as $$
declare c public.consultations; r public.online_consultation_requests; v public.video_sessions;
  canonical text; chosen_doctor uuid; recipient uuid; session_id uuid;
begin
  if private.current_role() is distinct from 'doctor' or not exists(
    select 1 from auth.users a where a.id=auth.uid() and a.email_confirmed_at is not null and not coalesce(a.is_anonymous,false)
  ) then raise exception 'A verified assigned doctor is required'; end if;
  canonical:=private.normalize_google_meet_link(meeting_url);
  select appointment.doctor_id into chosen_doctor from public.consultations appointment where appointment.id=target_consultation_id;
  if chosen_doctor is null then raise exception 'Consultation was not found'; end if;
  perform private.lock_doctor_schedule(chosen_doctor);
  select * into c from public.consultations where id=target_consultation_id for update;
  if c.doctor_id is distinct from private.current_doctor_id()
    or c.patient_id is null or c.consultation_type not in ('online','guest_online')
    or c.status not in ('approved','scheduled','in_progress')
    or not coalesce(private.has_active_doctor_employment(c.doctor_id,c.hospital_id),false)
    or not coalesce(private.actor_has_category_access(c.patient_id,'consultations'),false)
    then raise exception 'Only the assigned active doctor can set the link for a confirmed online appointment'; end if;
  select * into r from public.online_consultation_requests where official_consultation_id=c.id;
  if r.id is not null and (r.consultation_channel is distinct from 'video'
    or r.request_status not in ('confirmed','awaiting_contact','video_ready','in_progress')) then
    raise exception 'Hospital confirmation with the video channel is required'; end if;
  if now()>=c.appointment_date+interval '4 hours' then raise exception 'The appointment window has ended'; end if;
  select * into v from public.video_sessions where consultation_id=c.id for update;
  if v.id is not null and v.provider='google_meet' and v.join_url=canonical
    and v.status in ('ready','active') and v.starts_at=c.appointment_date and v.expires_at>now() then return v.id; end if;
  insert into public.video_sessions(consultation_id,provider,room_name,join_url,status,created_by,starts_at,expires_at,provider_metadata)
    values(c.id,'google_meet','cnph-'||c.id::text,canonical,
      case when c.status='in_progress' then 'active' else 'ready' end,auth.uid(),c.appointment_date,
      c.appointment_date+interval '4 hours',jsonb_build_object('link_supplied_by',auth.uid(),'link_supplied_at',now()))
    on conflict(consultation_id) do update set provider=excluded.provider,room_name=excluded.room_name,
      join_url=excluded.join_url,status=excluded.status,created_by=excluded.created_by,
      starts_at=excluded.starts_at,expires_at=excluded.expires_at,ended_at=null,provider_metadata=excluded.provider_metadata
    returning id into session_id;
  select u.auth_user_id into recipient from public.patients p join public.users u on u.id=p.user_id where p.id=c.patient_id;
  if recipient is null and c.guest_request_id is not null then
    select submitted_by into recipient from public.guest_consultation_requests where id=c.guest_request_id;
  end if;
  if recipient is not null then perform private.enqueue_notification(recipient,'Google Meet link ready',
    'Your doctor added or updated the meeting link. Open your appointment to join during its scheduled window.',
    'appointment',c.id,jsonb_build_object('consultation_id',c.id,'hospital_id',c.hospital_id,
      'event_key','meet_link_updated:'||gen_random_uuid()::text)); end if;
  return session_id;
end $$;
revoke all on function public.set_consultation_meet_link(uuid,text) from public,anon;
grant execute on function public.set_consultation_meet_link(uuid,text) to authenticated;

-- The previous preparation RPC remains callable, but cannot generate a meeting.
create or replace function public.ensure_video_session(target_consultation_id uuid,target_provider text default 'google_meet')
returns uuid language plpgsql security definer set search_path='' as $$
declare session_id uuid; approved_url text;
begin
  if private.current_role() is distinct from 'doctor' then raise exception 'The assigned doctor is required'; end if;
  approved_url:=public.get_approved_video_room(target_consultation_id);
  select id into session_id from public.video_sessions where consultation_id=target_consultation_id and join_url=approved_url;
  return session_id;
end $$;

create or replace function public.get_approved_video_room(target_consultation_id uuid)
returns text language plpgsql security definer set search_path='' as $$
declare c public.consultations; r public.online_consultation_requests; v public.video_sessions; allowed boolean;
begin
  if auth.uid() is null or private.current_user_id() is null or not exists(
    select 1 from auth.users a where a.id=auth.uid() and a.email_confirmed_at is not null and not coalesce(a.is_anonymous,false)
  ) then raise exception 'A verified active consultation participant is required'; end if;
  select * into c from public.consultations where id=target_consultation_id;
  if c.id is null then raise exception 'Consultation was not found'; end if;
  allowed:=c.patient_id=private.current_patient_id()
    or (c.doctor_id=private.current_doctor_id() and private.has_active_doctor_employment(c.doctor_id,c.hospital_id))
    or exists(select 1 from public.guest_consultation_requests g where g.id=c.guest_request_id and g.submitted_by=auth.uid());
  if not coalesce(allowed,false) or c.consultation_type not in ('online','guest_online')
    or c.status not in ('approved','scheduled','in_progress') then raise exception 'An approved online consultation participant is required'; end if;
  select * into r from public.online_consultation_requests where official_consultation_id=c.id;
  if r.id is not null and (r.consultation_channel is distinct from 'video'
    or r.request_status not in ('confirmed','awaiting_contact','video_ready','in_progress')) then
    raise exception 'Video is not the confirmed channel for this request'; end if;
  if now()<c.appointment_date-interval '15 minutes' or now()>=c.appointment_date+interval '4 hours' then
    raise exception 'Google Meet is available from 15 minutes before until 4 hours after the appointment'; end if;
  select * into v from public.video_sessions where consultation_id=c.id and provider='google_meet'
    and status in ('ready','active') and starts_at=c.appointment_date and expires_at>now();
  if v.id is null or v.join_url !~ '^https://meet[.]google[.]com/[a-z]{3}-[a-z]{4}-[a-z]{3}$' then
    raise exception 'The doctor has not added the Google Meet link yet. Refresh and retry'; end if;
  return v.join_url;
end $$;
revoke all on function public.get_approved_video_room(uuid) from public,anon;
grant execute on function public.get_approved_video_room(uuid) to authenticated;
revoke all on function public.ensure_video_session(uuid,text) from public,anon;
grant execute on function public.ensure_video_session(uuid,text) to authenticated;

-- Join URLs are returned only by the authorized, time-gated RPC.
revoke all on public.video_sessions from anon,authenticated;

-- Keep appointments intact; legacy open Jitsi rooms need a doctor-supplied link.
update public.video_sessions v set provider='google_meet',room_name='cnph-'||v.consultation_id::text,
  join_url='',status='pending',provider_metadata=jsonb_build_object('replaced_provider','jitsi')
from public.consultations c where c.id=v.consultation_id and c.status in ('approved','scheduled','in_progress')
  and v.provider='jitsi' and v.status in ('pending','ready','active');
update public.online_consultation_requests r set request_status='confirmed'
  from public.video_sessions v where r.official_consultation_id=v.consultation_id
  and r.request_status='video_ready' and v.provider='google_meet' and v.status='pending';
