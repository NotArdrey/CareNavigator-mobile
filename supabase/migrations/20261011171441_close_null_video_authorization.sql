-- SQL NULL must never authorize an unrelated video participant.
CREATE OR REPLACE FUNCTION public.get_approved_video_room(target_consultation_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  consultation_row public.consultations;
  session_row public.video_sessions;
  online_request public.online_consultation_requests;
  is_authorized_participant boolean := false;
begin
  if (select auth.uid()) is null then
    raise exception 'A signed-in consultation participant is required';
  end if;
  select * into consultation_row
  from public.consultations where id = target_consultation_id;
  if not found then raise exception 'Consultation was not found'; end if;

  is_authorized_participant :=
    consultation_row.patient_id = private.current_patient_id()
    or (
      consultation_row.doctor_id = private.current_doctor_id()
      and private.has_active_doctor_employment(
        consultation_row.doctor_id, consultation_row.hospital_id
      )
    )
    or exists (
      select 1 from public.guest_consultation_requests guest_request
      where guest_request.id = consultation_row.guest_request_id
        and guest_request.submitted_by = (select auth.uid())
    );

  if not coalesce(is_authorized_participant, false)
    or consultation_row.consultation_type not in ('online', 'guest_online')
    or consultation_row.status not in ('approved', 'scheduled', 'in_progress') then
    raise exception 'An approved online consultation participant is required';
  end if;

  select * into online_request
  from public.online_consultation_requests request
  where request.official_consultation_id = consultation_row.id;
  if online_request.id is not null
    and (
      online_request.consultation_channel <> 'video'
      or online_request.request_status not in (
        'confirmed', 'awaiting_contact', 'video_ready', 'in_progress'
      )
    ) then
    raise exception 'Video is not the confirmed channel for this request';
  end if;
  if now() < consultation_row.appointment_date - interval '15 minutes'
    or now() >= consultation_row.appointment_date + interval '4 hours' then
    raise exception 'The video room is outside its scheduled join window';
  end if;

  select * into session_row
  from public.video_sessions
  where consultation_id = target_consultation_id
    and provider = 'jitsi'
    and status in ('ready', 'active')
    and starts_at = consultation_row.appointment_date
    and expires_at > now();
  if not found or session_row.join_url !~ '^https://meet[.]jit[.]si/cnph-[0-9a-f]{32}$' then
    raise exception 'The approved video room is not ready';
  end if;
  return session_row.join_url;
end
$function$
;
