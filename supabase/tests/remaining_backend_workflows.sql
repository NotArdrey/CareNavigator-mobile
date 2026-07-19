begin;

insert into auth.users(id,aud,role,email,phone,raw_app_meta_data,raw_user_meta_data) values
('11000000-0000-4000-8000-000000000001','authenticated','authenticated','workflow-admin@example.invalid',null,'{}','{"first_name":"Workflow","last_name":"Admin"}'),
('11000000-0000-4000-8000-000000000002','authenticated','authenticated','workflow-doctor@example.invalid',null,'{}','{"first_name":"Workflow","last_name":"Doctor"}'),
('11000000-0000-4000-8000-000000000003','authenticated','authenticated','workflow-patient@example.invalid',null,'{}','{"first_name":"Workflow","last_name":"Patient"}'),
('11000000-0000-4000-8000-000000000004','authenticated','authenticated','workflow-guest@example.invalid','+639170000004','{}','{"first_name":"Workflow","last_name":"Guest"}'),
('11000000-0000-4000-8000-000000000005','authenticated','authenticated','other-doctor@example.invalid',null,'{}','{"first_name":"Other","last_name":"Doctor"}'),
('11000000-0000-4000-8000-000000000006','authenticated','authenticated','workflow-super@example.invalid',null,'{}','{"first_name":"Workflow","last_name":"Super"}');

insert into public.hospitals(id,hospital_name,address,latitude,longitude,operating_status,verification_status) values
('21000000-0000-4000-8000-000000000001','Workflow Hospital','Rollback Workflow Street',14.5995,120.9842,'open','verified'),
('21000000-0000-4000-8000-000000000002','Other Workflow Hospital','Other Rollback Street',14.6095,120.9942,'open','verified');

update public.users set role_id=(select id from public.roles where role_name='hospital_admin'),hospital_id='21000000-0000-4000-8000-000000000001',account_status='active'
where id='11000000-0000-4000-8000-000000000001';
update public.users set role_id=(select id from public.roles where role_name='doctor'),hospital_id='21000000-0000-4000-8000-000000000001',account_status='active'
where id='11000000-0000-4000-8000-000000000002';
update public.users set role_id=(select id from public.roles where role_name='patient'),account_status='active'
where id='11000000-0000-4000-8000-000000000003';
update public.users set account_status='active' where id='11000000-0000-4000-8000-000000000004';
update public.users set role_id=(select id from public.roles where role_name='doctor'),hospital_id='21000000-0000-4000-8000-000000000002',account_status='active'
where id='11000000-0000-4000-8000-000000000005';
update public.users set role_id=(select id from public.roles where role_name='super_admin'),account_status='active'
where id='11000000-0000-4000-8000-000000000006';

insert into public.hospital_departments(id,hospital_id,department_name) values
('31000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000001','Workflow Medicine'),
('31000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000002','Other Medicine');

insert into public.doctors(id,user_id,hospital_id,department_id,display_name,specialization,license_number) values
('41000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000002','21000000-0000-4000-8000-000000000001','31000000-0000-4000-8000-000000000001','Dr. Workflow','Internal Medicine','WORKFLOW-001'),
('41000000-0000-4000-8000-000000000002','11000000-0000-4000-8000-000000000005','21000000-0000-4000-8000-000000000002','31000000-0000-4000-8000-000000000002','Dr. Other','Internal Medicine','WORKFLOW-002');

insert into public.patients(id,user_id,created_by_doctor,primary_hospital_id,identity_verification_status,account_activation_status,profile_status)
values('51000000-0000-4000-8000-000000000001','11000000-0000-4000-8000-000000000003','41000000-0000-4000-8000-000000000001',
  '21000000-0000-4000-8000-000000000001','verified','active','official');
insert into public.doctor_patient_assignments(doctor_id,patient_id) values
('41000000-0000-4000-8000-000000000001','51000000-0000-4000-8000-000000000001');

insert into public.doctor_schedules(doctor_id,day_of_week,starts_at,ends_at,consultation_type,slot_minutes)
values('41000000-0000-4000-8000-000000000001',extract(dow from current_date+2)::integer,'08:00','12:00','online',30);

insert into public.hospital_services(hospital_id,department_id,service_name,tags)
values('21000000-0000-4000-8000-000000000001','31000000-0000-4000-8000-000000000001','Internal Medicine Consultation',array['internal medicine']);
insert into public.emergency_room_status(hospital_id,status,available_beds,current_patient_count,maximum_capacity)
values('21000000-0000-4000-8000-000000000001','available',5,3,20);
insert into public.hospital_beds(hospital_id,department_id,bed_type,total_beds,available_beds,occupied_beds)
values('21000000-0000-4000-8000-000000000001','31000000-0000-4000-8000-000000000001','regular',10,6,4);
insert into public.hospital_rooms(hospital_id,room_type,total_rooms,available_rooms,occupied_rooms)
values('21000000-0000-4000-8000-000000000001','regular',5,2,3);

set local role authenticated;
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000003","role":"authenticated"}',true);

create temporary table workflow_test_state(key text primary key,value uuid not null) on commit drop;

do $$ declare booked_id uuid; begin
  booked_id:=public.book_consultation(jsonb_build_object(
    'doctor_id','41000000-0000-4000-8000-000000000001','hospital_id','21000000-0000-4000-8000-000000000001',
    'consultation_type','online','appointment_date',(current_date+2+time '09:00')::timestamptz,'chief_complaint','Workflow integration test'));
  insert into workflow_test_state values('consultation',booked_id);
  if not exists(select 1 from public.consultation_status_history history where history.consultation_id=booked_id and history.new_status='pending') then
    raise exception 'Initial consultation history was not recorded'; end if;
end $$;

select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
do $$ declare booked_id uuid; conversation_id uuid; message_id uuid; result_id uuid; confirmed jsonb; video_id uuid; processing_job_id uuid; access_log_id bigint; reschedule_rejected boolean:=false; begin
  if private.current_doctor_id() is distinct from '41000000-0000-4000-8000-000000000001'::uuid then
    raise exception 'Doctor JWT did not resolve to the expected profile: %',private.current_doctor_id();
  end if;
  select value into booked_id from workflow_test_state where key='consultation';
  perform public.transition_consultation(booked_id,'approved','Approved for test',null,'{}');
  begin
    perform public.transition_consultation(booked_id,'approved','Invalid outside-hours reschedule',
      (current_date+2+time '13:00')::timestamptz,'{}');
  exception when others then reschedule_rejected:=true; end;
  if not reschedule_rejected then raise exception 'Outside-hours consultation reschedule was accepted'; end if;
  conversation_id:=public.ensure_consultation_conversation(booked_id);
  insert into workflow_test_state values('conversation',conversation_id);
  video_id:=public.ensure_video_session(booked_id,'jitsi');
  if video_id is null or not exists(select 1 from public.video_sessions where id=video_id and status='ready') then raise exception 'Video session was not created'; end if;
  message_id:=public.send_chat_message(conversation_id,'Doctor workflow message','{}');
  insert into workflow_test_state values('message',message_id);
  insert into public.laboratory_results(patient_id,doctor_id,hospital_id,consultation_id,test_name,file_path,verification_status,extracted_text,ai_summary)
  values('51000000-0000-4000-8000-000000000001','41000000-0000-4000-8000-000000000001','21000000-0000-4000-8000-000000000001',
    booked_id,'Workflow CBC','51000000-0000-4000-8000-000000000001/workflow-cbc.pdf','pending_doctor_review','test extraction','AI preliminary summary') returning id into result_id;
  insert into workflow_test_state values('laboratory_result',result_id);
  insert into public.document_processing_jobs(laboratory_result_id,requested_by,status,attempt_count,started_at,completed_at)
  values(result_id,'41000000-0000-4000-8000-000000000001','pending_doctor_review',1,now(),now())
  returning id into processing_job_id;
  confirmed:=public.confirm_medical_result(result_id,'Doctor-confirmed normal findings','Reviewed by the responsible physician',true);
  if confirmed->>'status'<>'saved_to_patient_record' or not exists(select 1 from public.medical_records where source_laboratory_result_id=result_id) then
    raise exception 'Medical result confirmation did not create an official record'; end if;
  if not exists(select 1 from public.document_processing_jobs where id=processing_job_id and status='completed') then
    raise exception 'Doctor confirmation did not complete the document processing job'; end if;
  access_log_id:=public.record_clinical_access('laboratory_result',result_id,'view');
  if not exists(select 1 from public.medical_record_access_logs where id=access_log_id
    and resource_type='laboratory_result' and resource_id=result_id and access_type='view') then
    raise exception 'Authorized clinical access was not logged'; end if;
  if not exists(select 1 from public.notifications where user_id='11000000-0000-4000-8000-000000000002' and reference_id=booked_id and action_path='/care') then
    raise exception 'Assigned doctor did not receive a consultation update'; end if;
end $$;

set local role service_role;
do $$ declare first_count bigint; second_count bigint; begin
  perform public.enqueue_due_appointment_reminders(100,interval '3 days');
  select count(*) into first_count from public.notifications where notification_type='appointment_reminder';
  perform public.enqueue_due_appointment_reminders(100,interval '3 days');
  select count(*) into second_count from public.notifications where notification_type='appointment_reminder';
  if first_count<2 or second_count<>first_count then
    raise exception 'Appointment reminders were not produced idempotently: %, %',first_count,second_count;
  end if;
end $$;
set local role authenticated;

select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000003',true);
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000003","role":"authenticated"}',true);
do $$ declare conversation_id uuid; message_id uuid; tamper_rejected boolean:=false; begin
  select value into conversation_id from workflow_test_state where key='conversation';
  select value into message_id from workflow_test_state where key='message';
  if not exists(select 1 from public.notifications where reference_id=message_id
    and action_path='/messages/'||conversation_id::text) then
    raise exception 'Message notification action path is invalid'; end if;
  if (select count(*) from public.notifications where reference_id=(select value from workflow_test_state where key='laboratory_result')
    and notification_type='medical_result')<>1 then
    raise exception 'Doctor-reviewed result notification was not deduplicated'; end if;
  if not exists(select 1 from public.notifications where reference_id=(select value from workflow_test_state where key='laboratory_result')
    and action_path='/care') then
    raise exception 'Medical result notification action path is invalid'; end if;
  insert into public.notification_preferences(user_id,email_enabled) values('11000000-0000-4000-8000-000000000003',true)
  on conflict(user_id) do update set email_enabled=excluded.email_enabled;
  perform public.mark_conversation_read(conversation_id);
  perform public.send_chat_message(conversation_id,'Patient workflow reply','{}');
  begin update public.chat_messages set message='tampered' where id=message_id;
  exception when others then tamper_rejected:=true; end;
  if not tamper_rejected then raise exception 'Sent chat content was mutable'; end if;
end $$;

select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000002',true);
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000002","role":"authenticated"}',true);
do $$ declare booked_id uuid; begin
  select value into booked_id from workflow_test_state where key='consultation';
  perform public.transition_consultation(booked_id,'in_progress','Workflow started',null,'{}');
  perform public.transition_consultation(
    booked_id,'completed','Workflow completed',null,
    jsonb_build_object(
      'doctor_notes','Rollback-only clinical notes',
      'confirmed_diagnosis','Workflow-confirmed diagnosis',
      'treatment_plan','Workflow follow-up plan',
      'consultation_summary','Rollback-only completion summary'
    )
  );
  if (select count(*) from public.diagnoses where consultation_id=booked_id and is_primary)<>1 then
    raise exception 'Completed consultation diagnosis was not synchronized idempotently'; end if;
  if (select count(*) from public.treatment_plans where consultation_id=booked_id and source='consultation_completion')<>1 then
    raise exception 'Completed consultation treatment plan was not synchronized idempotently'; end if;
  insert into public.prescriptions(patient_id,doctor_id,consultation_id,hospital_id,medication_name,dosage,frequency,duration,instructions)
  values('51000000-0000-4000-8000-000000000001','41000000-0000-4000-8000-000000000001',booked_id,
    '21000000-0000-4000-8000-000000000001','Rollback medication','Test dose','Once','One day','Rollback only');
  if not private.has_permission('records.write') or not ('records.write'=any(public.current_permissions())) then
    raise exception 'Doctor permissions are not enforced/exposed correctly'; end if;
end $$;

set local role service_role;
do $$ declare outbox_id bigint; begin
  if not exists(select 1 from public.notifications where user_id='11000000-0000-4000-8000-000000000003'
    and notification_type='prescription' and action_path='/care') then
    raise exception 'Prescription notification was not produced'; end if;
  select id into outbox_id from public.notification_outbox order by id desc limit 1;
  if outbox_id is null then raise exception 'Opted-in external notification was not queued'; end if;
  update public.notification_outbox set status='processing',attempt_count=5 where id=outbox_id;
  perform public.complete_notification_delivery(outbox_id,false,null,'Rollback terminal failure');
  if not exists(select 1 from public.notification_outbox where id=outbox_id and status='cancelled') then
    raise exception 'Outbox retries were not capped'; end if;
end $$;
set local role authenticated;

select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000004',true);
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000004","role":"authenticated","email":"workflow-guest@example.invalid"}',true);
insert into public.guest_consultation_requests(id,reference_number,submitted_by,full_name,birth_date,sex,mobile_number,email,address,symptoms,symptom_duration,
  consultation_reason,preferred_hospital_id,preferred_department_id,preferred_schedule,identification_file_path,consent_at)
values('61000000-0000-4000-8000-000000000001','','11000000-0000-4000-8000-000000000004','Workflow Guest','1990-01-01','prefer_not_to_say',
  '+639170000004','workflow-guest@example.invalid','Rollback Guest Street','Persistent cough','Three days','Online review','21000000-0000-4000-8000-000000000001',
  '31000000-0000-4000-8000-000000000001',(current_date+2+time '10:00')::timestamptz,'11000000-0000-4000-8000-000000000004/valid-id.pdf',now());

select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000001',true);
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000001","role":"authenticated"}',true);
do $$ declare review_rejected boolean:=false; collision_rejected boolean:=false; approval_tamper_rejected boolean:=false; guest_result jsonb; analytics jsonb; begin
  begin perform public.review_guest_consultation('61000000-0000-4000-8000-000000000001','approved','41000000-0000-4000-8000-000000000002',(current_date+2+time '10:00')::timestamptz,'invalid cross-hospital assignment');
  exception when others then review_rejected:=true; end;
  if not review_rejected then raise exception 'Cross-hospital guest assignment was accepted'; end if;
  begin perform public.review_guest_consultation('61000000-0000-4000-8000-000000000001','approved','41000000-0000-4000-8000-000000000001',(current_date+2+time '09:00')::timestamptz,'occupied appointment slot');
  exception when others then collision_rejected:=true; end;
  if not collision_rejected then raise exception 'Occupied guest appointment slot was accepted'; end if;
  guest_result:=public.review_guest_consultation('61000000-0000-4000-8000-000000000001','approved','41000000-0000-4000-8000-000000000001',(current_date+2+time '10:00')::timestamptz,'Identity reviewed');
  if guest_result->>'status'<>'consultation_scheduled' or not exists(select 1 from public.patients where guest_request_id='61000000-0000-4000-8000-000000000001' and profile_status='temporary') then
    raise exception 'Guest approval did not create a temporary patient'; end if;
  begin
    update public.hospitals set verification_status='rejected'
    where id='21000000-0000-4000-8000-000000000001';
  exception when others then approval_tamper_rejected:=true; end;
  if not approval_tamper_rejected then
    raise exception 'Hospital administrator changed a super-admin approval field'; end if;
  update public.hospitals set description='Rollback hospital profile update'
  where id='21000000-0000-4000-8000-000000000001';
  insert into public.hospital_announcements(hospital_id,title,message,created_by)
  values('21000000-0000-4000-8000-000000000001','Rollback announcement','Workflow-only hospital announcement','11000000-0000-4000-8000-000000000001');
  update public.emergency_room_status set status='limited' where hospital_id='21000000-0000-4000-8000-000000000001';
  if (select count(*) from public.notifications where notification_type='hospital_alert' and action_path='/hospitals')<2 then
    raise exception 'Hospital announcement/status notifications were not produced'; end if;
  analytics:=public.hospital_analytics();
  if (analytics->>'consultations_total')::integer<2 then raise exception 'Hospital analytics did not include consultations'; end if;
  if analytics->'room_occupancy'->>'occupied' is null or analytics->'er_utilization' is null
    or jsonb_array_length(analytics->'consultations_by_doctor')=0 or jsonb_array_length(analytics->'doctor_activity')=0 then
    raise exception 'Hospital analytics is missing occupancy, ER, or doctor activity fields'; end if;
end $$;

reset role;
update public.patients set user_id='11000000-0000-4000-8000-000000000004',patient_number='CNPH-ROLLBACK-GUEST',
  account_activation_status='active',profile_status='official',activated_at=now()
where guest_request_id='61000000-0000-4000-8000-000000000001';
do $$ begin
  if not exists(select 1 from public.notifications where user_id='11000000-0000-4000-8000-000000000004'
    and reference_id=(select id from public.patients where guest_request_id='61000000-0000-4000-8000-000000000001')
    and notification_type='account_activation' and action_path='/care') then
    raise exception 'Patient account activation notification was not produced'; end if;
end $$;
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000006',true);
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000006","role":"authenticated"}',true);
update public.users set account_status='suspended' where id='11000000-0000-4000-8000-000000000005';
set local role authenticated;
select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000005',true);
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000005","role":"authenticated"}',true);
do $$ begin
  if private.current_user_id() is not null or private.current_role() is not null
    or private.current_hospital_id() is not null
    or private.can_access_patient('51000000-0000-4000-8000-000000000001') then
    raise exception 'A deactivated account retained helper-based RLS access'; end if;
end $$;

select set_config('request.jwt.claim.sub','11000000-0000-4000-8000-000000000006',true);
select set_config('request.jwt.claims','{"sub":"11000000-0000-4000-8000-000000000006","role":"authenticated"}',true);
do $$ begin
  update public.system_settings set value='false'::jsonb where key='maintenance_mode';
  if (public.platform_analytics()->>'hospitals')::integer<2 then raise exception 'Platform analytics did not include hospitals'; end if;
  if not exists(select 1 from public.recommend_hospitals(14.5995,120.9842,'Workflow Medicine',array['Internal Medicine'],'Internal Medicine',false,25,10)
    where hospital_id='21000000-0000-4000-8000-000000000001' and match_score>0) then raise exception 'Ranked recommendation failed'; end if;
  if not exists(select 1 from public.notification_outbox where user_id='11000000-0000-4000-8000-000000000003') then raise exception 'Notification outbox was not populated'; end if;
end $$;

rollback;
