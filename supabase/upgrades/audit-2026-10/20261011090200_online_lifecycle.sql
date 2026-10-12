alter table public.consultations add column outcome_reason text;
alter table public.online_consultation_requests add column patient_response text,
  add column contact_attempt_notes text, add column outcome_notes text;

create or replace function private.guard_clinical_consultation()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.status is distinct from old.status and new.status in ('in_progress','completed') then
    if new.doctor_id is distinct from private.current_doctor_id()
      or not private.has_active_doctor_employment(new.doctor_id,new.hospital_id) then
      raise exception 'Only the assigned active doctor may start or complete clinical care';
    end if;
    if new.consultation_type in ('online','guest_online') and
      (now()<new.appointment_date-interval '15 minutes' or now()>=new.appointment_date+interval '4 hours') then
      raise exception 'The consultation is outside its appointment window';
    end if;
    if new.status='completed' and (
      length(btrim(coalesce(new.consultation_summary,'')))<10
      or length(btrim(coalesce(new.confirmed_diagnosis,'')))<3
      or length(btrim(coalesce(new.treatment_plan,'')))<5
      or (nullif(btrim(new.current_symptoms),'') is null and new.vitals_recorded_at is null
        and nullif(btrim(new.relevant_medical_history),'') is null and nullif(btrim(new.doctor_notes),'') is null)
    ) then raise exception 'Complete the structured checkup, diagnosis, treatment plan and consultation summary'; end if;
  end if;
  return new;
end $$;
create trigger guard_clinical_consultation before update of status on public.consultations
for each row execute function private.guard_clinical_consultation();
revoke all on function private.guard_clinical_consultation() from public;

create or replace function private.finalize_online_outcome()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.request_status is not distinct from old.request_status then return new; end if;
  if new.request_status in ('rejected','cancelled','patient_unreachable','no_show','face_to_face_recommended') then
    if new.official_consultation_id is not null then
      update public.consultations set status='cancelled'
      where id=new.official_consultation_id and status not in ('cancelled','rejected','completed');
      if private.current_role() in ('doctor','hospital_admin','super_admin') then
        update public.consultations set outcome_reason=new.request_status where id=new.official_consultation_id;
      end if;
    end if;
    perform private.revoke_relationship_access(new.care_relationship_id,new.request_status,
      coalesce(new.outcome_notes,new.cancellation_reason,new.rejection_reason,new.request_status));
  end if;
  perform private.enqueue_notification(
    (select u.auth_user_id from public.patients p join public.users u on u.id=p.user_id where p.id=new.patient_id),
    'Online consultation update',
    case new.request_status
      when 'more_information_required' then 'The hospital needs more information: '||coalesce(new.additional_information_request,'')
      when 'schedule_proposed' then 'The hospital proposed a schedule. Accept or decline it in your appointments.'
      when 'face_to_face_recommended' then 'The care team recommends a face-to-face visit. Make a new booking when ready.'
      else 'Request status: '||replace(new.request_status,'_',' ') end,
    'consultation_update',new.id,jsonb_build_object('status',new.request_status,'event_key',new.request_status||':'||new.updated_at::text)
  );
  return new;
end $$;
create trigger finalize_online_outcome after update of request_status on public.online_consultation_requests
for each row execute function private.finalize_online_outcome();
revoke all on function private.finalize_online_outcome() from public;

create or replace function public.transition_online_consultation_request(target_request_id uuid,target_status text,transition_notes text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.online_consultation_requests; c public.consultations;
begin
  select * into r from public.online_consultation_requests where id=target_request_id for update;
  if not found or auth.uid() is null or private.current_role() not in ('doctor','hospital_admin')
    or (r.assigned_doctor_id is distinct from private.current_doctor_id() and not private.is_hospital_admin_for(r.hospital_id)) then
    raise exception 'This online request is not assigned to the current care team';
  end if;
  select * into c from public.consultations where id=r.official_consultation_id for update;
  if not found or r.request_status not in ('confirmed','awaiting_contact','video_ready','in_progress') then
    raise exception 'Only a confirmed active request may enter the consultation workflow';
  end if;
  if target_status='completed' then raise exception 'Complete the consultation using the structured checkup'; end if;
  if target_status='in_progress' then
    perform public.transition_consultation(c.id,'in_progress',transition_notes);
  elsif target_status='video_ready' then
    perform public.ensure_video_session(c.id,'jitsi');
  elsif target_status='awaiting_contact' then
    if nullif(btrim(transition_notes),'') is null then raise exception 'Record the contact attempt'; end if;
    update public.online_consultation_requests set request_status='awaiting_contact',
      contact_attempt_status='attempted',contact_attempted_at=now(),contact_attempt_notes=btrim(transition_notes)
      where id=r.id;
  elsif target_status in ('no_show','patient_unreachable') then
    if now()<c.appointment_date+interval '30 minutes' or c.started_at is not null or c.status='in_progress'
      or r.contact_attempted_at is null or nullif(btrim(r.contact_attempt_notes),'') is null then
      raise exception 'A missed visit requires 30 elapsed minutes, a recorded contact attempt and no clinical start';
    end if;
    if nullif(btrim(transition_notes),'') is null then raise exception 'Record the missed-visit outcome'; end if;
    update public.online_consultation_requests set request_status=target_status,outcome_notes=btrim(transition_notes) where id=r.id;
  elsif target_status='face_to_face_recommended' then
    if r.assigned_doctor_id is distinct from private.current_doctor_id() then raise exception 'Only the assigned doctor may recommend clinical follow-up'; end if;
    if nullif(btrim(transition_notes),'') is null then raise exception 'A recommendation reason is required'; end if;
    update public.online_consultation_requests set request_status=target_status,outcome_notes=btrim(transition_notes),
      additional_information_request=btrim(transition_notes) where id=r.id;
  else raise exception 'Unsupported online transition'; end if;
  return (select jsonb_build_object('request_id',id,'status',request_status,'consultation_id',official_consultation_id)
    from public.online_consultation_requests where id=r.id);
end $$;

create or replace function public.respond_online_consultation_request(target_request_id uuid,response_action text,response_text text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.online_consultation_requests;
begin
  select * into r from public.online_consultation_requests where id=target_request_id for update;
  if not found or auth.uid() is null or r.patient_id is distinct from private.current_patient_id()
    or r.submitted_by is distinct from private.current_user_id() then raise exception 'This request is not owned by the current patient'; end if;
  if response_action='information' and r.request_status='more_information_required' then
    if length(btrim(coalesce(response_text,'')))<5 then raise exception 'Enter the information requested by the hospital'; end if;
    update public.online_consultation_requests set patient_response=btrim(response_text),request_status='under_review' where id=r.id;
  elsif response_action='decline' and r.request_status='schedule_proposed' then
    update public.online_consultation_requests set patient_response=coalesce(nullif(btrim(response_text),''),'Schedule declined'),
      request_status='under_review',proposed_schedule=null where id=r.id;
  elsif response_action='accept' and r.request_status='schedule_proposed' then
    return public.review_online_consultation_request(r.id,'confirmed',r.assigned_doctor_id,r.proposed_schedule,r.consultation_channel,'Patient accepted approved proposal');
  else raise exception 'The patient action does not match the current request state'; end if;
  return jsonb_build_object('request_id',r.id,'status','under_review','slot_reserved',false);
end $$;
revoke all on function public.respond_online_consultation_request(uuid,text,text) from public,anon;
grant execute on function public.respond_online_consultation_request(uuid,text,text) to authenticated;

CREATE OR REPLACE FUNCTION private.sync_consultation_care_access()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  relationship_row public.patient_care_relationships;
  consent_row public.patient_consents;
  selected_records jsonb := '[]'::jsonb;
begin
  select * into relationship_row
  from public.patient_care_relationships relationship
  where relationship.consultation_id = new.id
  order by relationship.created_at desc
  limit 1;

  if relationship_row.id is null then
    return new;
  end if;

  if new.status in ('approved', 'scheduled', 'in_progress') then
    select * into consent_row
    from public.patient_consents consent
    where consent.care_relationship_id = relationship_row.id
      and consent.is_granted
      and consent.revoked_at is null
      and (consent.expires_at is null or consent.expires_at > now())
    order by consent.version_sequence desc, consent.created_at desc
    limit 1;

    if consent_row.id is not null then
      selected_records := coalesce(consent_row.metadata->'selected_records', '[]'::jsonb);
      perform private.activate_relationship_access(
        relationship_row.id, consent_row.id, new.doctor_id, new.id, selected_records
      );
    end if;
  elsif new.status in ('completed', 'cancelled', 'rejected') then
    perform private.revoke_relationship_access(
      relationship_row.id, new.status::text,
      coalesce(new.rejection_reason, 'Consultation ' || new.status::text)
    );
  end if;

  update public.online_consultation_requests request
  set request_status = case new.status
        when 'in_progress' then 'in_progress'
        when 'completed' then 'completed'
        when 'cancelled' then 'cancelled'
        when 'rejected' then 'rejected'
        else request.request_status
      end,
      updated_at = now()
  where request.official_consultation_id = new.id
    and new.status in ('in_progress', 'completed', 'cancelled', 'rejected')
    and request.request_status not in ('no_show','patient_unreachable','face_to_face_recommended','rejected','cancelled','completed');

  return new;
end
$function$
;

CREATE OR REPLACE FUNCTION public.review_online_consultation_request(target_request_id uuid, decision text, target_doctor_id uuid DEFAULT NULL::uuid, target_confirmed_schedule timestamp with time zone DEFAULT NULL::timestamp with time zone, target_channel text DEFAULT NULL::text, review_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  request_row public.online_consultation_requests;
  chosen_doctor_id uuid;
  chosen_schedule timestamptz;
  normalized_decision text := lower(btrim(coalesce(decision, '')));
  normalized_channel text := nullif(lower(btrim(coalesce(target_channel, ''))), '');
  consultation_id uuid;
begin
  -- Accept the retired wire value during a rolling client deployment, but
  -- persist and act on it as email only.
  if normalized_channel = 'sms_assisted' then
    normalized_channel := 'email';
  end if;

  if (select auth.uid()) is null or private.current_user_id() is null then
    raise exception 'An authenticated reviewer is required';
  end if;

  select * into request_row
  from public.online_consultation_requests
  where id = target_request_id
  for update;

  if not found then
    raise exception 'Online consultation request was not found';
  end if;
  if not private.is_hospital_admin_for(request_row.hospital_id) and not (
    normalized_decision='confirmed' and request_row.request_status='schedule_proposed'
    and request_row.patient_id=private.current_patient_id() and request_row.submitted_by=private.current_user_id()
    and target_doctor_id=request_row.assigned_doctor_id and target_confirmed_schedule=request_row.proposed_schedule
    and normalized_channel=request_row.consultation_channel and request_row.reviewed_by is not null
  ) then
    raise exception 'Hospital acceptance is required for this request';
  end if;
  if request_row.request_status in ('confirmed','awaiting_contact','video_ready','in_progress','completed','rejected','cancelled','no_show','face_to_face_recommended','patient_unreachable') then
    raise exception 'This request is already in a terminal or confirmed state';
  end if;

  if normalized_decision = 'under_review' then
    update public.online_consultation_requests
    set request_status = 'under_review', reviewed_by = private.current_user_id(),
        reviewed_at = now(), updated_at = now()
    where id = request_row.id;
  elsif normalized_decision = 'more_information_required' then
    if nullif(btrim(review_notes), '') is null then
      raise exception 'Describe the additional information required';
    end if;
    update public.online_consultation_requests
    set request_status = 'more_information_required',
        additional_information_request = btrim(review_notes),
        reviewed_by = private.current_user_id(), reviewed_at = now(), updated_at = now()
    where id = request_row.id;
  elsif normalized_decision = 'schedule_proposed' then
    chosen_doctor_id := coalesce(target_doctor_id, request_row.requested_doctor_id);
    chosen_schedule := coalesce(target_confirmed_schedule, request_row.preferred_schedule);
    if normalized_channel is not null
      and normalized_channel not in ('call', 'email', 'video') then
      raise exception 'Choose call, email, or video consultation';
    end if;
    if chosen_doctor_id is null or chosen_schedule is null
      or not private.is_doctor_slot_available(
        chosen_doctor_id, request_row.hospital_id, 'online', chosen_schedule, null
      ) then
      raise exception 'Choose an eligible doctor and currently available proposal';
    end if;
    update public.online_consultation_requests
    set request_status = 'schedule_proposed',
        assigned_doctor_id = chosen_doctor_id,
        proposed_schedule = chosen_schedule,
        consultation_channel = coalesce(normalized_channel, consultation_channel, 'video'),
        reviewed_by = private.current_user_id(), reviewed_at = now(), updated_at = now()
    where id = request_row.id;
  elsif normalized_decision in ('rejected', 'cancelled') then
    if normalized_decision = 'rejected' and nullif(btrim(review_notes), '') is null then
      raise exception 'A rejection reason is required';
    end if;
    update public.online_consultation_requests
    set request_status = normalized_decision,
        rejection_reason = case when normalized_decision = 'rejected' then btrim(review_notes) else rejection_reason end,
        cancellation_reason = case when normalized_decision = 'cancelled' then btrim(review_notes) else cancellation_reason end,
        reviewed_by = private.current_user_id(), reviewed_at = now(), updated_at = now()
    where id = request_row.id;
    perform private.revoke_relationship_access(
      request_row.care_relationship_id, normalized_decision, review_notes
    );
  elsif normalized_decision = 'confirmed' then
    chosen_doctor_id := coalesce(target_doctor_id, request_row.assigned_doctor_id, request_row.requested_doctor_id);
    chosen_schedule := coalesce(
      target_confirmed_schedule, request_row.proposed_schedule, request_row.preferred_schedule
    );
    if normalized_channel is null
      or normalized_channel not in ('call', 'email', 'video') then
      raise exception 'Choose call, email, or video consultation';
    end if;
    if normalized_channel = 'email'
      and nullif(btrim(request_row.profile_email), '') is null then
      raise exception 'The patient must have a registered email address for email contact';
    end if;
    if chosen_doctor_id is null or chosen_schedule is null then
      raise exception 'A verified doctor and confirmed schedule are required';
    end if;
    if not exists (
      select 1
      from public.doctors doctor
      join public.doctor_hospital_employments employment
        on employment.doctor_id = doctor.id
       and employment.hospital_id = request_row.hospital_id
      where doctor.id = chosen_doctor_id
        and doctor.department_id = request_row.requested_department_id
        and doctor.availability_status <> 'unavailable'
        and employment.employment_status = 'active'
        and employment.is_verified
        and employment.starts_at <= now()
        and (employment.ends_at is null or employment.ends_at > now())
    ) then
      raise exception 'The selected doctor is not verified and active at this hospital';
    end if;

    perform private.lock_doctor_schedule(chosen_doctor_id);
    if not private.is_doctor_slot_available(
      chosen_doctor_id, request_row.hospital_id, 'online', chosen_schedule, null
    ) then
      raise exception 'The selected appointment slot is no longer available';
    end if;

    insert into public.consultations(
      patient_id, doctor_id, hospital_id, department_id,
      consultation_type, appointment_date, status, chief_complaint,
      approved_by, approved_at
    ) values (
      request_row.patient_id, chosen_doctor_id, request_row.hospital_id,
      request_row.requested_department_id, 'online', chosen_schedule,
      'scheduled', request_row.medical_concern,
      private.current_user_id(), now()
    ) returning id into consultation_id;

    perform private.activate_relationship_access(
      request_row.care_relationship_id,
      request_row.consent_id,
      chosen_doctor_id,
      consultation_id,
      request_row.selected_records
    );

    update public.online_consultation_requests
    set request_status = 'confirmed',
        assigned_doctor_id = chosen_doctor_id,
        confirmed_schedule = chosen_schedule,
        consultation_channel = normalized_channel,
        official_consultation_id = consultation_id,
        reviewed_by = coalesce(request_row.reviewed_by,private.current_user_id()), reviewed_at = coalesce(request_row.reviewed_at,now()), updated_at = now()
    where id = request_row.id;
  else
    raise exception 'Unsupported online request decision';
  end if;

  select * into request_row
  from public.online_consultation_requests
  where id = target_request_id;

  return jsonb_build_object(
    'request_id', request_row.id,
    'reference_number', request_row.reference_number,
    'status', request_row.request_status,
    'consultation_id', request_row.official_consultation_id,
    'assigned_doctor_id', request_row.assigned_doctor_id,
    'confirmed_schedule', request_row.confirmed_schedule,
    'channel', request_row.consultation_channel,
    'slot_reserved', request_row.official_consultation_id is not null
  );
end
$function$;
