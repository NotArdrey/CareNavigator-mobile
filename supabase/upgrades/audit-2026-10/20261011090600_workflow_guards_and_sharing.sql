create or replace function private.guard_online_request_change()
returns trigger language plpgsql security definer set search_path = '' as $$
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
end $$;
create trigger guard_online_request_change before update on public.online_consultation_requests
for each row execute function private.guard_online_request_change();
revoke all on function private.guard_online_request_change() from public;

create or replace function public.list_patient_sharing_relationships()
returns jsonb language sql stable security definer set search_path = '' as $$
 select coalesce(jsonb_agg(row_to_json(r)),'[]'::jsonb) from (
  select relationship.id,relationship.status,h.hospital_name,d.display_name,
    (select jsonb_agg(jsonb_build_object('grant_id',g.id,'status',g.status,'expires_at',g.expires_at,
      'categories',(select jsonb_agg(s.record_category) from public.patient_access_scopes s where s.grant_id=g.id)))
     from public.patient_access_grants g where g.care_relationship_id=relationship.id and g.status='active' and g.revoked_at is null) as grants
  from public.patient_care_relationships relationship join public.hospitals h on h.id=relationship.hospital_id
    left join public.doctors d on d.id=relationship.doctor_id
  where relationship.patient_id=private.current_patient_id() and relationship.status='active'
  order by relationship.created_at desc
 ) r;
$$;
revoke all on function public.list_patient_sharing_relationships() from public,anon;
grant execute on function public.list_patient_sharing_relationships() to authenticated;

create or replace function private.guard_document_review()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if new.origin_type is distinct from old.origin_type or new.uploaded_by is distinct from old.uploaded_by then
  raise exception 'Document provenance and uploader are immutable'; end if;
 if new.review_state is distinct from old.review_state or new.reviewed_by is distinct from old.reviewed_by
  or new.reviewed_at is distinct from old.reviewed_at or new.review_rejection_reason is distinct from old.review_rejection_reason then
  if private.current_doctor_id() is null or new.reviewed_by is distinct from private.current_user_id()
    or new.reviewed_at is null or old.review_state<>'unreviewed'
    or not private.can_access_clinical_record(new.patient_id,new.hospital_id,'medical_documents',new.id,'view') then
   raise exception 'Only an authorized treating doctor may review the original document'; end if;
 end if;
 return new;
end $$;
create trigger guard_document_review before update on public.medical_documents for each row execute function private.guard_document_review();
revoke all on function private.guard_document_review() from public;

create or replace function private.validate_document_reference()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if new.reference_type='prescription_order' then
  if new.origin_type<>'hospital_generated' or not exists(select 1 from public.prescription_orders o
    where o.id=new.reference_id and o.patient_id=new.patient_id and o.doctor_id=private.current_doctor_id()
      and o.hospital_id=new.hospital_id) then raise exception 'The attachment must match this doctor official order'; end if;
 end if;
 return new;
end $$;
create trigger z_validate_document_reference before insert on public.medical_documents for each row execute function private.validate_document_reference();
revoke all on function private.validate_document_reference() from public;

create or replace function private.notification_action_path(target_type text,target_data jsonb)
returns text language sql immutable set search_path = '' as $$
 select case when target_type='hospital_alert' then '/hospitals' else '/notification' end;
$$;

create or replace function public.review_patient_document(target_document_id uuid,decision text,review_notes text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d public.medical_documents; doctor public.doctors; record_id uuid;
begin
  select * into d from public.medical_documents where id=target_document_id for update;
  select * into doctor from public.doctors where id=private.current_doctor_id();
  if d.id is null or d.origin_type<>'patient_supplied' or doctor.id is null
    or not private.has_active_doctor_employment(doctor.id,doctor.hospital_id)
    or not (private.can_access_clinical_record(d.patient_id,d.hospital_id,'medical_documents',d.id,'view')) then
    raise exception 'An authorized active treating doctor must review this patient document'; end if;
  if d.review_state<>'unreviewed' then
    return jsonb_build_object('document_id',d.id,'review_state',d.review_state,'already_reviewed',true);
  end if;
  if decision not in ('approved','rejected') then raise exception 'Choose approve or reject'; end if;
  if decision='rejected' and nullif(btrim(review_notes),'') is null then raise exception 'A rejection reason is required'; end if;
  update public.medical_documents set review_state=decision,reviewed_by=private.current_user_id(),reviewed_at=now(),
    review_rejection_reason=case when decision='rejected' then btrim(review_notes) else null end where id=d.id;
  if decision='approved' then
    insert into public.medical_records(patient_id,doctor_id,hospital_id,record_type,title,description,record_date,source_document_id)
    values(d.patient_id,doctor.id,doctor.hospital_id,'document_review','Reviewed supporting document: '||d.title,
      coalesce(nullif(btrim(review_notes),''),'Doctor reviewed the original patient-supplied document. AI extraction remains preliminary.'),now(),d.id)
    returning id into record_id;
  end if;
  return jsonb_build_object('document_id',d.id,'review_state',decision,'medical_record_id',record_id);
end $$;

CREATE OR REPLACE FUNCTION public.get_guest_consultation_request_tracking(target_reference text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  request_row public.guest_consultation_requests;
  official_consultation public.consultations;
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in with the verified request account to track this request';
  end if;

  select * into request_row
  from public.guest_consultation_requests request
  where request.reference_number = btrim(target_reference)
     or request.id::text = btrim(target_reference);
  if not found or not (
    request_row.submitted_by = (select auth.uid())
    or private.is_hospital_admin_for(request_row.preferred_hospital_id)
    or request_row.assigned_doctor_id = private.current_doctor_id()
  ) then
    raise exception 'Guest consultation request was not found';
  end if;

  select * into official_consultation
  from public.consultations consultation
  where consultation.guest_request_id = request_row.id
  order by consultation.created_at desc
  limit 1;

  return jsonb_build_object(
    'request_id', request_row.id,
    'reference_number', request_row.reference_number,
    'status', request_row.request_status,
    'identity_review_status', request_row.identity_review_status,
    'review_notes', request_row.identity_review_notes,
    'rejection_reason', request_row.rejection_reason,
    'hospital_id', request_row.preferred_hospital_id,
    'department_id', request_row.preferred_department_id,
    'doctor_id', request_row.assigned_doctor_id,
    'preferred_schedule', request_row.preferred_schedule,
    'consultation_id', official_consultation.id,
    'confirmed_schedule', official_consultation.appointment_date,
    'consultation_status', official_consultation.status,
    'consultation_type', official_consultation.consultation_type,
    'updated_at', request_row.updated_at
  );
end
$function$
;

create or replace function public.issue_prescription_order(order_payload jsonb,idempotency_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
#variable_conflict use_variable
declare doctor public.doctors; patient_id uuid:=(order_payload->>'patient_id')::uuid;
  consultation_id uuid:=nullif(order_payload->>'consultation_id','')::uuid;
  assignment_id uuid:=nullif(order_payload->>'assignment_id','')::uuid;
  order_row public.prescription_orders; medication jsonb; medication_ids jsonb; notification_status text;
begin
  select * into doctor from public.doctors where id=private.current_doctor_id();
  if doctor.id is null or auth.uid() is null or not private.has_active_doctor_employment(doctor.id,doctor.hospital_id)
    or not (private.can_access_clinical_record(patient_id,doctor.hospital_id,'prescriptions',null,'create')
      or private.can_create_assigned_patient_document(patient_id,doctor.hospital_id)) then
    raise exception 'An authorized active prescriber is required'; end if;
  if not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null and not coalesce(is_anonymous,false)) then
    raise exception 'A verified prescriber account is required'; end if;
  if consultation_id is not null and not exists (select 1 from public.consultations c
    where c.id=consultation_id and c.patient_id=patient_id and c.doctor_id=doctor.id
      and c.hospital_id=doctor.hospital_id and c.status in ('approved','scheduled','in_progress','completed')) then
    raise exception 'The selected consultation is not assigned to this prescriber'; end if;
  if assignment_id is not null and not exists(select 1 from public.doctor_patient_assignments a
    where a.id=assignment_id and a.patient_id=patient_id and a.doctor_id=doctor.id and a.hospital_id=doctor.hospital_id
      and a.assignment_status='active' and a.ended_at is null) then raise exception 'The care assignment is not active'; end if;
  if consultation_id is null and assignment_id is null then raise exception 'A consultation or active care assignment is required'; end if;
  if length(coalesce(idempotency_key,''))<16 or length(idempotency_key)>160 then raise exception 'An issuance idempotency key is required'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(doctor.id::text||':'||idempotency_key,0));
  select * into order_row from public.prescription_orders o where o.doctor_id=doctor.id and o.idempotency_key=$2;
  if found then
    if order_row.payload_fingerprint is distinct from md5(order_payload::text) then raise exception 'This issuance key belongs to a different order'; end if;
  else
    if jsonb_typeof(order_payload->'medications') is distinct from 'array'
      or jsonb_array_length(order_payload->'medications') not between 1 and 50 then raise exception 'Supply the complete medication list'; end if;
    insert into public.prescription_orders(patient_id,doctor_id,hospital_id,consultation_id,assignment_id,issued_by,diagnosis_reason,idempotency_key,payload_fingerprint)
    values(patient_id,doctor.id,doctor.hospital_id,consultation_id,assignment_id,private.current_user_id(),
      btrim(order_payload->>'diagnosis_reason'),$2,md5(order_payload::text)) returning * into order_row;
    for medication in select value from jsonb_array_elements(order_payload->'medications') loop
      if exists(select 1 from unnest(array['medication_name','dosage','frequency','duration','medication_form_strength','route','exact_dose','quantity_to_dispense']) key
        where nullif(btrim(medication->>key),'') is null) then raise exception 'Every medication requires complete dispensing directions'; end if;
      insert into public.prescriptions(order_id,patient_id,doctor_id,hospital_id,consultation_id,assignment_id,
        diagnosis_reason,medication_name,dosage,frequency,duration,medication_form_strength,route,exact_dose,quantity_to_dispense,
        refills,start_date,end_date,is_prn,prn_reason,maximum_daily_dose,instructions)
      values(order_row.id,patient_id,doctor.id,doctor.hospital_id,consultation_id,assignment_id,order_row.diagnosis_reason,
        btrim(medication->>'medication_name'),btrim(medication->>'dosage'),btrim(medication->>'frequency'),btrim(medication->>'duration'),
        btrim(medication->>'medication_form_strength'),btrim(medication->>'route'),btrim(medication->>'exact_dose'),btrim(medication->>'quantity_to_dispense'),
        (medication->>'refills')::integer,(medication->>'start_date')::date,nullif(medication->>'end_date','')::date,
        coalesce((medication->>'is_prn')::boolean,false),nullif(btrim(medication->>'prn_reason'),''),
        nullif(btrim(medication->>'maximum_daily_dose'),''),nullif(btrim(medication->>'instructions'),''));
    end loop;
  end if;
  select jsonb_agg(id order by created_at,id) into medication_ids from public.prescriptions where order_id=order_row.id;
  notification_status:=private.queue_prescription_order_notification(order_row.id);
  return jsonb_build_object('order_id',order_row.id,'medication_ids',medication_ids,'notification_status',notification_status);
end $$;
