-- Require a link supplied under the current active doctor assignment.
CREATE OR REPLACE FUNCTION public.set_consultation_meet_link(target_consultation_id uuid, meeting_url text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
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
  if v.id is not null and v.created_by=auth.uid() and v.provider='google_meet' and v.join_url=canonical
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
end $function$
;
CREATE OR REPLACE FUNCTION public.get_approved_video_room(target_consultation_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.consultations; r public.online_consultation_requests; v public.video_sessions; allowed boolean;
begin
  if auth.uid() is null or private.current_user_id() is null or not exists(
    select 1 from auth.users a where a.id=auth.uid() and a.email_confirmed_at is not null and not coalesce(a.is_anonymous,false)
  ) then raise exception 'A verified active consultation participant is required'; end if;
  select * into c from public.consultations where id=target_consultation_id for share;
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
    and status in ('ready','active') and starts_at=c.appointment_date and expires_at>now()
    and created_by=(select u.auth_user_id from public.doctors d join public.users u on u.id=d.user_id
      where d.id=c.doctor_id and u.account_status='active')
    and exists(select 1 from public.doctor_hospital_employments e where e.doctor_id=c.doctor_id and e.hospital_id=c.hospital_id
      and e.employment_status='active' and e.is_verified and coalesce(e.starts_at,e.created_at)<=now()
      and (e.ends_at is null or e.ends_at>now()));
  if v.id is null or v.join_url !~ '^https://meet[.]google[.]com/[a-z]{3}-[a-z]{4}-[a-z]{3}$' then
    raise exception 'The doctor has not added the Google Meet link yet. Refresh and retry'; end if;
  return v.join_url;
end $function$
;
