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
  outcome:=public.book_consultation_v2(jsonb_build_object('doctor_id',doctor_row.id,'hospital_id',hospital_row.id,'consultation_type','online','appointment_date',preferred_time,'chief_complaint','Synthetic structured completion journey','symptom_duration','Three days'));
  request_id:=(outcome->>'request_id')::uuid;
  perform set_config('request.jwt.claim.sub',admin_auth::text,true);
  result:=public.review_online_consultation_request(request_id,'confirmed',doctor_row.id,preferred_time,'video');
  select * into request_row from public.online_consultation_requests where id=request_id;
  alter table public.consultations disable trigger enforce_reservation_lead_time;
  alter table public.consultations disable trigger aa_lock_consultation_reservation;
  update public.consultations set appointment_date=now() where id=request_row.official_consultation_id;
  alter table public.consultations enable trigger enforce_reservation_lead_time;
  alter table public.consultations enable trigger aa_lock_consultation_reservation;
  perform set_config('request.jwt.claim.sub',doctor_auth::text,true);
  perform public.set_consultation_meet_link(request_row.official_consultation_id,'https://meet.google.com/abc-defg-hij');
  perform public.ensure_video_session(request_row.official_consultation_id);
  perform set_config('request.jwt.claim.sub',admin_auth::text,true);
  did_fail:=false;
  begin perform public.get_approved_video_room(request_row.official_consultation_id); exception when others then did_fail:=true; end;
  if not did_fail then raise exception 'Unrelated video participant was authorized by a NULL identity comparison'; end if;
  perform set_config('request.jwt.claim.sub',doctor_auth::text,true);
  perform public.transition_consultation(request_row.official_consultation_id,'in_progress');
  perform public.transition_online_consultation_request(request_id,'awaiting_contact','Contacted patient while consultation was active');
  if (select request_status from public.online_consultation_requests where id=request_id)<>'in_progress' then raise exception 'Contact attempt downgraded active care'; end if;
  did_fail:=false;
  begin perform public.transition_consultation(request_row.official_consultation_id,'completed'); exception when others then
    if sqlerrm not like '%structured checkup%' then raise; end if; did_fail:=true;
  end;
  if not did_fail then raise exception 'Unstructured completion was allowed'; end if;
  perform public.transition_consultation(request_row.official_consultation_id,'completed',null,null,jsonb_build_object(
    'consultation_summary','Synthetic test consultation was completed with a reviewed checkup',
    'confirmed_diagnosis','Synthetic diagnosis','treatment_plan','Synthetic test care plan','current_symptoms','Synthetic stable symptoms','doctor_notes','Synthetic structured notes'));
  if not exists(select 1 from public.consultations where id=request_row.official_consultation_id and status='completed')
    or not exists(select 1 from public.online_consultation_requests where id=request_id and request_status='completed')
    or exists(select 1 from public.patient_access_grants where care_relationship_id=request_row.care_relationship_id and status='active')
    or exists(select 1 from public.video_sessions where consultation_id=request_row.official_consultation_id and status in ('active','ready'))
    or not exists(select 1 from public.medical_records where consultation_id=request_row.official_consultation_id) then
    raise exception 'Clinical completion did not finalize records, tracking, room and access'; end if;
end $test$;
rollback;
