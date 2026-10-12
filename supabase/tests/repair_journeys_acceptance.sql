-- Transactional acceptance checks for the reviewed online lifecycle.
-- Run with a privileged test connection. No fixture survives the rollback.

begin;

do $test$
#variable_conflict use_variable
declare
  patient_row public.patients;
  patient_user public.users;
  hospital_row public.hospitals;
  doctor_row public.doctors;
  admin_auth uuid;
  doctor_auth uuid;
  preferred_time timestamptz;
  request_id uuid;
  conflict_request_id uuid;
  request_row public.online_consultation_requests;
  consultation_before bigint;
  consultation_after bigint;
  video_url text;
  conflict_rejected boolean := false;
  upload_id uuid; result jsonb; outcome jsonb; move_to timestamptz; order_id uuid;
  valid_med jsonb; order_payload jsonb; count_before bigint; request_payload jsonb; did_fail boolean;

begin
  select patient.*
  into patient_row
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where app_user.account_status = 'active'
    and nullif(btrim(app_user.mobile_number), '') is not null
    and nullif(btrim(app_user.first_name), '') is not null
    and nullif(btrim(app_user.last_name), '') is not null
  order by patient.created_at
  limit 1;
  if patient_row.id is null then
    raise exception 'Acceptance fixture requires an active patient with a registered phone';
  end if;
  select * into patient_user
  from public.users app_user
  where app_user.id = patient_row.user_id;

  select hospital.* into hospital_row
  from public.hospitals hospital
  where hospital.online_request_workflow_enabled
    and hospital.verification_status = 'verified'
    and hospital.operating_status in ('open', 'limited')
  order by hospital.created_at
  limit 1;

  select doctor.* into doctor_row
  from public.doctors doctor
  join public.doctor_hospital_employments employment
    on employment.doctor_id = doctor.id
   and employment.hospital_id = doctor.hospital_id
  where doctor.hospital_id = hospital_row.id
    and doctor.department_id is not null
    and doctor.availability_status <> 'unavailable'
    and employment.employment_status = 'active'
    and employment.is_verified
    and (employment.ends_at is null or employment.ends_at > now())
  order by doctor.created_at
  limit 1;

  select app_user.auth_user_id into admin_auth
  from public.users app_user
  join public.roles role on role.id = app_user.role_id
  where role.role_name = 'hospital_admin'
    and app_user.hospital_id = hospital_row.id
    and app_user.account_status = 'active'
  order by app_user.created_at
  limit 1;
  if hospital_row.id is null or doctor_row.id is null or admin_auth is null then
    raise exception 'Acceptance fixture requires the pilot hospital, doctor, department, and administrator';
  end if;
  select app_user.auth_user_id into doctor_auth
  from public.users app_user
  where app_user.id = doctor_row.user_id;
  if doctor_auth is null then
    raise exception 'Acceptance fixture requires an authenticated doctor account';
  end if;

  perform set_config('request.jwt.claim.sub', patient_user.auth_user_id::text, true);
  select slot.starts_at into preferred_time
  from public.list_available_consultation_slots(
    doctor_row.id, 'online'::public.consultation_type, 60
  ) slot
  order by slot.starts_at
  limit 1;
  if preferred_time is null then
    raise exception 'Acceptance fixture requires one published online preference';
  end if;


  perform set_config('request.jwt.claim.sub',patient_user.auth_user_id::text,true);
  insert into public.medical_documents(patient_id,uploaded_by,document_type,title,storage_bucket,storage_path,mime_type,size_bytes)
  values(patient_row.id,patient_user.id,'prescription','REPAIR-TEST supporting document','medical-documents',
    patient_row.id::text||'/repair-test-'||gen_random_uuid()::text||'.pdf','application/pdf',100) returning id into upload_id;
  if not exists(select 1 from public.medical_documents where id=upload_id and origin_type='patient_supplied'
    and author_doctor_id is null and review_state='unreviewed') then raise exception 'Upload provenance was not preserved'; end if;
  outcome:=public.book_consultation_v2(jsonb_build_object('doctor_id',doctor_row.id,'hospital_id',hospital_row.id,
    'consultation_type','online','appointment_date',preferred_time,'chief_complaint','Repair regression care concern',
    'symptom_duration','Two days','shared_categories',jsonb_build_array('consultations','prescriptions','medical_records','medical_documents'),
    'supporting_document_ids',jsonb_build_array(upload_id)));
  request_id:=(outcome->>'request_id')::uuid;
  if (outcome->>'slot_reserved')::boolean or outcome->>'consultation_id' is not null then raise exception 'Online submission reserved a slot'; end if;
  perform set_config('request.jwt.claim.sub',admin_auth::text,true);
  perform public.review_online_consultation_request(request_id,'under_review');
  perform public.review_online_consultation_request(request_id,'more_information_required',null,null,null,'Describe the symptom changes');
  perform set_config('request.jwt.claim.sub',patient_user.auth_user_id::text,true);
  perform public.respond_online_consultation_request(request_id,'information','Symptoms have remained stable for two days');
  if not exists(select 1 from public.online_consultation_requests where id=request_id and request_status='under_review' and patient_response is not null) then
    raise exception 'Patient response did not return to review'; end if;
  perform set_config('request.jwt.claim.sub',admin_auth::text,true);
  perform public.review_online_consultation_request(request_id,'schedule_proposed',doctor_row.id,preferred_time,'video');
  perform set_config('request.jwt.claim.sub',patient_user.auth_user_id::text,true);
  perform public.respond_online_consultation_request(request_id,'decline','Please propose the original preferred time again');
  perform set_config('request.jwt.claim.sub',admin_auth::text,true);
  perform public.review_online_consultation_request(request_id,'schedule_proposed',doctor_row.id,preferred_time,'video');
  perform set_config('request.jwt.claim.sub',patient_user.auth_user_id::text,true);
  result:=public.respond_online_consultation_request(request_id,'accept');
  if not (result->>'slot_reserved')::boolean then raise exception 'Proposal acceptance did not reserve a slot'; end if;
  select * into request_row from public.online_consultation_requests where id=request_id;
  select starts_at into move_to from public.list_available_consultation_slots(doctor_row.id,'online',60) where starts_at<>preferred_time order by starts_at limit 1;
  perform public.reschedule_consultation(request_row.official_consultation_id,move_to);
  if not exists(select 1 from public.online_consultation_requests where id=request_id and confirmed_schedule=move_to)
    or exists(select 1 from public.patient_access_grants where consultation_id=request_row.official_consultation_id and status='active' and expires_at<>move_to+interval '7 days') then
    raise exception 'Rescheduling did not synchronize dates and access'; end if;
  perform set_config('request.jwt.claim.sub',doctor_auth::text,true);
  perform public.set_consultation_meet_link(request_row.official_consultation_id,'https://meet.google.com/abc-defg-hij');
  did_fail:=false;
  begin
    delete from public.doctor_schedules where doctor_id=doctor_row.id and consultation_type='online'
      and day_of_week=extract(dow from move_to at time zone 'Asia/Manila')::int
      and starts_at<=(move_to at time zone 'Asia/Manila')::time and ends_at>(move_to at time zone 'Asia/Manila')::time;
  exception when others then
    if sqlerrm not like '%reserved appointments%' then raise; end if;
    did_fail:=true;
  end;
  if not did_fail then raise exception 'Reserved schedule deletion was accepted'; end if;
  perform set_config('request.jwt.claim.sub',patient_user.auth_user_id::text,true);
  result:=public.share_patient_document_for_review(upload_id,request_row.care_relationship_id);
  if (result->>'shared_grants')::integer<1 then raise exception 'Owned upload could not be shared in its consent scope'; end if;
  perform set_config('request.jwt.claim.sub',admin_auth::text,true);
  did_fail:=false;
  begin perform public.share_patient_document_for_review(upload_id,request_row.care_relationship_id); exception when others then did_fail:=true; end;
  if not did_fail then raise exception 'An unrelated actor shared another patient document'; end if;
  perform set_config('request.jwt.claim.sub',doctor_auth::text,true);
  result:=public.review_patient_document(upload_id,'approved','Original supporting document reviewed; no medication order inferred');
  if result->>'medical_record_id' is null or not exists(select 1 from public.medical_documents where id=upload_id and origin_type='patient_supplied' and author_doctor_id is null and review_state='approved') then
    raise exception 'Review did not preserve patient authorship and create an explicit reference'; end if;
  valid_med:=jsonb_build_object('medication_name','Fixture medication','dosage','One tablet','exact_dose','One tablet',
    'medication_form_strength','Fixture strength','route','oral','frequency','Once daily','duration','Two days',
    'quantity_to_dispense','2','refills',0,'start_date',(now() at time zone 'Asia/Manila')::date,'is_prn',false);
  order_payload:=jsonb_build_object('patient_id',patient_row.id,'consultation_id',request_row.official_consultation_id,
    'diagnosis_reason','Controlled regression fixture','medications',jsonb_build_array(valid_med,valid_med||jsonb_build_object('route','')));
  select count(*) into count_before from public.prescriptions;
  did_fail:=false;
  begin perform public.issue_prescription_order(order_payload,'repair-rollback-test-'||request_id::text);
  exception when others then
    if sqlerrm not like '%dispensing directions%' then raise; end if; did_fail:=true;
  end;
  if not did_fail or (select count(*) from public.prescriptions)<>count_before or exists(select 1 from public.prescription_orders where idempotency_key='repair-rollback-test-'||request_id::text) then
    raise exception 'Medication validation partially committed the order'; end if;
  order_payload:=jsonb_set(order_payload,'{medications}',jsonb_build_array(valid_med,valid_med||jsonb_build_object('medication_name','Fixture PRN medication',
    'is_prn',true,'prn_reason','For fixture symptom','maximum_daily_dose','Two tablets')));
  outcome:=public.issue_prescription_order(order_payload,'repair-issuance-test-'||request_id::text);
  result:=public.issue_prescription_order(order_payload,'repair-issuance-test-'||request_id::text);
  if result->>'order_id' is distinct from outcome->>'order_id' or jsonb_array_length(outcome->'medication_ids')<>2 then raise exception 'Issuance was not idempotent'; end if;
  order_id:=(outcome->>'order_id')::uuid;
  did_fail:=false;
  begin
    insert into public.medical_documents(patient_id,uploaded_by,document_type,title,storage_bucket,storage_path,mime_type,size_bytes,reference_type,reference_id)
    values(patient_row.id,(select user_id from public.doctors where id=doctor_row.id),'prescription','REPAIR-TEST invalid attachment','medical-documents',patient_row.id::text||'/invalid-order.pdf','application/pdf',100,'prescription_order',gen_random_uuid());
  exception when others then
    if sqlerrm not like '%attachment must match%' then raise; end if; did_fail:=true;
  end;
  if not did_fail or (select count(*) from public.prescriptions where public.prescriptions.order_id=order_id)<>2 then raise exception 'Attachment failure changed the committed order'; end if;
  insert into public.medical_documents(patient_id,uploaded_by,document_type,title,storage_bucket,storage_path,mime_type,size_bytes,reference_type,reference_id)
  values(patient_row.id,(select user_id from public.doctors where id=doctor_row.id),'prescription','REPAIR-TEST attachment retry','medical-documents',patient_row.id::text||'/order-retry.pdf','application/pdf',100,'prescription_order',order_id);
  if (select count(*) from public.prescriptions where public.prescriptions.order_id=order_id)<>2 then raise exception 'Attachment retry duplicated clinical records'; end if;
  perform set_config('request.jwt.claim.sub',patient_user.auth_user_id::text,true);
  result:=public.queue_patient_email(patient_row.id,null,'medication_reminder');
  if result->>'status' not in ('queued','sent','failed') then raise exception 'Manual summary did not return a delivery state'; end if;
  if not exists(select 1 from public.notifications where id=(result->>'notification_id')::uuid and user_id=patient_user.auth_user_id
    and message like '%PRN: For fixture symptom%' and message not like '%08:00%') then raise exception 'PRN summary invented a time or used an application user id'; end if;
  did_fail:=false;
  begin perform public.queue_patient_email(patient_row.id,order_id,'medication_reminder');
  exception when others then if sqlerrm not like '%current Manila date%' then raise; end if; did_fail:=true; end;
  if not did_fail then raise exception 'Daily summary accepted an unfiltered order override'; end if;
  perform set_config('request.jwt.claim.sub',gen_random_uuid()::text,true);
  did_fail:=false;
  begin perform public.queue_patient_email(patient_row.id,order_id,'prescription');
  exception when insufficient_privilege then did_fail:=true; end;
  if not did_fail then raise exception 'An unverified actor queued another patient email'; end if;
  perform set_config('request.jwt.claim.sub',admin_auth::text,true);
  did_fail:=false;
  begin perform public.transition_consultation(request_row.official_consultation_id,'in_progress');
  exception when others then if sqlerrm not like '%assigned active doctor%' then raise; end if; did_fail:=true; end;
  if not did_fail then raise exception 'Hospital staff started clinical care'; end if;
  -- Only transaction-local fixture timestamps bypass reservation validation. DDL is rolled back.
  alter table public.consultations disable trigger enforce_reservation_lead_time;
  alter table public.consultations disable trigger aa_lock_consultation_reservation;
  update public.consultations set appointment_date=now()+interval '15 minutes 1 second' where id=request_row.official_consultation_id;
  perform set_config('request.jwt.claim.sub',doctor_auth::text,true);
  did_fail:=false;
  begin perform public.ensure_video_session(request_row.official_consultation_id); exception when others then
    if sqlerrm not like '%available from 15 minutes%' then raise; end if; did_fail:=true; end;
  if not did_fail then raise exception 'Video preparation succeeded before its window'; end if;
  update public.consultations set appointment_date=now()+interval '15 minutes' where id=request_row.official_consultation_id;
  perform public.set_consultation_meet_link(request_row.official_consultation_id,'https://meet.google.com/abc-defg-hij');
  perform public.ensure_video_session(request_row.official_consultation_id);
  perform set_config('request.jwt.claim.sub',patient_user.auth_user_id::text,true);
  perform public.get_approved_video_room(request_row.official_consultation_id);
  perform set_config('request.jwt.claim.sub',doctor_auth::text,true);
  update public.consultations set appointment_date=now()-interval '4 hours' where id=request_row.official_consultation_id;
  did_fail:=false;
  begin perform public.ensure_video_session(request_row.official_consultation_id); exception when others then
    if sqlerrm not like '%available from 15 minutes%' then raise; end if; did_fail:=true; end;
  if not did_fail then raise exception 'Video preparation succeeded after its window'; end if;
  update public.consultations set appointment_date=now()-interval '29 minutes 59 seconds' where id=request_row.official_consultation_id;
  perform public.transition_online_consultation_request(request_id,'awaiting_contact','Called the registered phone; no answer');
  did_fail:=false;
  begin perform public.transition_online_consultation_request(request_id,'no_show','Patient did not attend'); exception when others then
    if sqlerrm not like '%30 elapsed minutes%' then raise; end if; did_fail:=true; end;
  if not did_fail then raise exception 'A missed visit succeeded before 30 minutes'; end if;
  update public.consultations set appointment_date=now()-interval '30 minutes' where id=request_row.official_consultation_id;
  alter table public.consultations enable trigger enforce_reservation_lead_time;
  alter table public.consultations enable trigger aa_lock_consultation_reservation;
  perform public.transition_online_consultation_request(request_id,'no_show','Patient did not attend after a recorded contact attempt');
  if not exists(select 1 from public.consultations where id=request_row.official_consultation_id and status='cancelled' and outcome_reason='no_show')
    or exists(select 1 from public.patient_access_grants where care_relationship_id=request_row.care_relationship_id and status='active')
    or exists(select 1 from public.video_sessions where consultation_id=request_row.official_consultation_id and status in ('ready','active')) then
    raise exception 'Missed visit did not close the consultation, room and access'; end if;
end $test$;
rollback;
