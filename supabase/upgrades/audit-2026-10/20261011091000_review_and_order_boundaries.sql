CREATE OR REPLACE FUNCTION private.guard_online_request_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.consultations; role text:=private.current_role();
begin
  if new.patient_id is distinct from old.patient_id or new.submitted_by is distinct from old.submitted_by
    or new.hospital_id is distinct from old.hospital_id or new.created_at is distinct from old.created_at then
    raise exception 'Online request identity and hospital are immutable'; end if;
  if old.official_consultation_id is not null and new.official_consultation_id is distinct from old.official_consultation_id then
    raise exception 'The official consultation reference is immutable'; end if;
  if new.request_status is not distinct from old.request_status then return new; end if;
  if old.request_status in ('completed','rejected','cancelled','no_show','patient_unreachable','face_to_face_recommended') then
    raise exception 'Terminal online requests cannot be reopened'; end if;
  if not (
    (old.request_status in ('submitted','under_review','more_information_required','schedule_proposed') and new.request_status in ('under_review','more_information_required','schedule_proposed','confirmed','rejected','cancelled','patient_unreachable'))
    or (old.request_status in ('confirmed','awaiting_contact','video_ready') and new.request_status in ('awaiting_contact','video_ready','in_progress','cancelled','no_show','patient_unreachable','face_to_face_recommended'))
    or (old.request_status='in_progress' and new.request_status in ('completed','cancelled','face_to_face_recommended'))
  ) then raise exception 'Invalid online request predecessor state'; end if;
  if old.request_status in ('submitted','under_review','more_information_required','schedule_proposed') and role<>'patient'
    and not private.is_hospital_admin_for(new.hospital_id) then raise exception 'Hospital review is required before clinical care'; end if;
  if new.request_status='face_to_face_recommended' and new.assigned_doctor_id is distinct from private.current_doctor_id() then
    raise exception 'Only the assigned doctor may recommend clinical follow-up'; end if;
  if role='patient' then
    if new.patient_id is distinct from private.current_patient_id() or new.submitted_by is distinct from private.current_user_id()
      or not ((new.request_status='cancelled' and old.request_status<>'in_progress')
        or (old.request_status in ('more_information_required','schedule_proposed') and new.request_status='under_review' and nullif(btrim(new.patient_response),'') is not null)
        or (old.request_status='schedule_proposed' and new.request_status='confirmed'
          and new.confirmed_schedule=old.proposed_schedule and new.assigned_doctor_id=old.assigned_doctor_id
          and new.consultation_channel=old.consultation_channel and new.reviewed_by=old.reviewed_by)) then
      raise exception 'The requested transition is not an authorized patient action'; end if;
  elsif not (private.is_hospital_admin_for(new.hospital_id) or new.assigned_doctor_id=private.current_doctor_id()) then
    raise exception 'The current care team cannot change this request'; end if;
  if new.request_status in ('confirmed','awaiting_contact','video_ready','in_progress','completed','no_show') then
    select * into c from public.consultations where id=new.official_consultation_id;
    if c.id is null or c.patient_id<>new.patient_id or c.hospital_id<>new.hospital_id or c.doctor_id<>new.assigned_doctor_id then
      raise exception 'This request requires its matching official consultation'; end if;
  end if;
  if new.request_status in ('no_show','patient_unreachable') and new.official_consultation_id is not null then
    select * into c from public.consultations where id=new.official_consultation_id;
    if now()<c.appointment_date+interval '30 minutes' or c.started_at is not null or c.status='in_progress'
      or old.contact_attempted_at is null or nullif(btrim(old.contact_attempt_notes),'') is null then
      raise exception 'A missed visit requires 30 elapsed minutes, a recorded contact attempt and no clinical start'; end if;
  end if;
  if new.request_status in ('in_progress','completed') then
    if c.status::text<>new.request_status or new.assigned_doctor_id is distinct from private.current_doctor_id() then
      raise exception 'Use the assigned doctor clinical start and structured completion workflow'; end if;
  end if;
  if new.request_status='video_ready' and not exists(select 1 from public.video_sessions where consultation_id=c.id and status in ('ready','active')) then
    raise exception 'A prepared authorized video room is required'; end if;
  return new;
end $function$
;
create or replace function public.list_online_booking_hospitals()
returns table(hospital_id uuid) language sql stable security definer set search_path='' as $$
 select h.id from public.hospitals h where h.verification_status='verified' and h.operating_status in ('open','limited') and private.has_online_reviewer(h.id);
$$;
revoke all on function public.list_online_booking_hospitals() from public;
grant execute on function public.list_online_booking_hospitals() to anon,authenticated;

create or replace function private.guard_prescription_order_reference()
returns trigger language plpgsql security definer set search_path='' as $$
begin
 if tg_op='UPDATE' and new.order_id is distinct from old.order_id then raise exception 'Prescription order provenance is immutable'; end if;
 if new.order_id is not null and not exists(select 1 from public.prescription_orders o where o.id=new.order_id
   and o.patient_id=new.patient_id and o.doctor_id=new.doctor_id and o.hospital_id=new.hospital_id
   and o.status='issued' and o.issued_by=private.current_user_id()) then raise exception 'Prescription must match its authorized official order'; end if;
 return new;
end $$;
revoke all on function private.guard_prescription_order_reference() from public;
create trigger guard_prescription_order_reference before insert or update of order_id on public.prescriptions
for each row execute function private.guard_prescription_order_reference();
