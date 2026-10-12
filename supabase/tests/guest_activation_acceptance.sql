-- Transactional guest review and persistent tracking acceptance check.

begin;

do $test$
declare
  guest_auth uuid;
  admin_auth uuid;
  hospital_row public.hospitals;
  doctor_row public.doctors;
  department_id uuid;
  preferred_time timestamptz;
  request_id uuid;
  reference_number text := 'GST-TEST-' || upper(substr(replace(gen_random_uuid()::text, '-', ''), 1, 12));
  review_result jsonb;
  tracking_result jsonb;
  created_consultation_id uuid;
  temporary_patient_id uuid;
  consultation_before bigint;
  submission_payload jsonb; activation jsonb; first_id uuid; existing_password text; original_count bigint; blocked boolean;
begin
  select app_user.auth_user_id into guest_auth
  from public.users app_user
  join public.roles role on role.id = app_user.role_id
  join auth.users auth_user on auth_user.id=app_user.auth_user_id and auth_user.email_confirmed_at is not null
  where role.role_name = 'guest'
    and app_user.account_status = 'active'
  order by app_user.created_at
  limit 1;

  select hospital.* into hospital_row
  from public.hospitals hospital
  where hospital.online_request_workflow_enabled
  order by hospital.created_at
  limit 1;
  select doctor.* into doctor_row
  from public.doctors doctor
  join public.doctor_hospital_employments employment
    on employment.doctor_id = doctor.id
   and employment.hospital_id = doctor.hospital_id
  where doctor.hospital_id = hospital_row.id
    and doctor.department_id is not null
    and employment.employment_status = 'active'
    and employment.is_verified
  order by doctor.created_at
  limit 1;
  department_id := doctor_row.department_id;

  select app_user.auth_user_id into admin_auth
  from public.users app_user
  join public.roles role on role.id = app_user.role_id
  where role.role_name = 'hospital_admin'
    and app_user.hospital_id = hospital_row.id
    and app_user.account_status = 'active'
  order by app_user.created_at
  limit 1;
  if guest_auth is null or admin_auth is null or doctor_row.id is null then
    raise exception 'Acceptance fixture requires guest, pilot administrator, and doctor accounts';
  end if;

  select slot.starts_at into preferred_time
  from public.list_available_consultation_slots(
    doctor_row.id, 'guest_online'::public.consultation_type, 60
  ) slot
  order by slot.starts_at
  limit 1;
  if preferred_time is null then
    raise exception 'Guest online intake did not expose published online slots';
  end if;

  select count(*) into consultation_before from public.consultations;
  perform set_config('request.jwt.claim.sub',guest_auth::text,true);
  select encrypted_password into existing_password from auth.users where id=guest_auth;
  select count(*) into original_count from public.patients where user_id=(select id from public.users where auth_user_id=guest_auth);
  submission_payload:=jsonb_build_object('first_name','Transactional','last_name','Guest','birth_date','1990-01-01',
    'sex','male','mobile_number','+639171234567','email',(select email from auth.users where id=guest_auth),
    'address','Transactional test address','symptoms','Persistent cough for transactional testing','symptom_duration','Three days',
    'preferred_hospital_id',hospital_row.id,'preferred_department_id',department_id,'preferred_consultation_type','guest_online','preferred_schedule',preferred_time);
  request_id:=public.submit_guest_consultation_request(submission_payload,'repair-guest-idempotency-test');
  first_id:=public.submit_guest_consultation_request(submission_payload,'repair-guest-idempotency-test');
  if first_id<>request_id then raise exception 'Guest retry duplicated the request'; end if;
  select g.reference_number into reference_number from public.guest_consultation_requests g where g.id=request_id;
  blocked:=false;
  begin perform public.activate_approved_guest(request_id); exception when others then blocked:=true; end;
  if not blocked then raise exception 'Guest activation before approval was permitted'; end if;
  if (select count(*) from public.consultations) <> consultation_before then
    raise exception 'Guest request created an official consultation before review';
  end if;

  perform set_config('request.jwt.claim.sub',admin_auth::text,true);
  update public.guest_consultation_requests set assigned_doctor_id=doctor_row.id where id=request_id;
  perform set_config('request.jwt.claim.sub',(select auth_user_id::text from public.users where id=doctor_row.user_id),true);
  blocked:=false;
  begin perform public.review_guest_consultation(request_id,'approved',doctor_row.id,preferred_time,'Doctor cannot bypass hospital confirmation');
  exception when others then
    if sqlerrm not like '%Hospital confirmation%' then raise; end if;
    blocked:=true; end;
  if not blocked then raise exception 'Doctor reserved an online guest appointment without hospital confirmation'; end if;
  perform set_config('request.jwt.claim.sub', admin_auth::text, true);
  review_result := public.review_guest_consultation(
    request_id, 'approved', doctor_row.id, preferred_time,
    'Transactional identity and hospital review'
  );
  created_consultation_id := nullif(review_result->>'consultation_id', '')::uuid;
  temporary_patient_id := nullif(review_result->>'patient_id', '')::uuid;
  if created_consultation_id is null or temporary_patient_id is null then
    raise exception 'Guest approval did not create linked patient and consultation records';
  end if;
  if not exists (
    select 1
    from public.consultations consultation
    join public.patient_care_relationships relationship
      on relationship.consultation_id = consultation.id
    join public.doctor_patient_assignments assignment
      on assignment.care_relationship_id = relationship.id
    join public.patient_access_grants grant_row
      on grant_row.care_relationship_id = relationship.id
    where consultation.id = created_consultation_id
      and consultation.patient_id = temporary_patient_id
      and consultation.guest_request_id = request_id
      and consultation.status = 'scheduled'
      and relationship.status = 'active'
      and assignment.hospital_id = hospital_row.id
      and assignment.assignment_status = 'active'
      and assignment.ended_at is null
      and grant_row.status = 'active'
      and grant_row.expires_at > now()
  ) then
    raise exception 'Guest approval did not activate the provenance-scoped care relationship';
  end if;

  perform set_config('request.jwt.claim.sub', guest_auth::text, true);
  tracking_result := public.get_guest_consultation_request_tracking(reference_number);
  if tracking_result->>'status' <> 'consultation_scheduled'
    or nullif(tracking_result->>'consultation_id', '')::uuid is distinct from created_consultation_id then
    raise exception 'Guest request was not persistently trackable after approval';
  end if;
  -- An approved guest can join with its verified intake identity before activation.
  alter table public.consultations disable trigger enforce_reservation_lead_time;
  alter table public.consultations disable trigger aa_lock_consultation_reservation;
  update public.consultations set appointment_date=now() where id=created_consultation_id;
  alter table public.consultations enable trigger enforce_reservation_lead_time;
  alter table public.consultations enable trigger aa_lock_consultation_reservation;
  perform set_config('request.jwt.claim.sub',(select auth_user_id::text from public.users where id=doctor_row.user_id),true);
  perform public.set_consultation_meet_link(created_consultation_id,'https://meet.google.com/abc-defg-hij');
  perform set_config('request.jwt.claim.sub',guest_auth::text,true);
  if public.get_approved_video_room(created_consultation_id)<>'https://meet.google.com/abc-defg-hij' then
    raise exception 'Approved guest could not obtain the doctor link before activation'; end if;
  perform set_config('request.jwt.claim.sub',admin_auth::text,true);
  blocked:=false;
  begin perform public.activate_approved_guest(request_id); exception when others then blocked:=true; end;
  if not blocked then raise exception 'Another identity activated the guest profile'; end if;
  perform set_config('request.jwt.claim.sub',guest_auth::text,true);
  activation:=public.activate_approved_guest(request_id);
  if activation->>'status'<>'active' or (activation->>'patient_id')::uuid<>temporary_patient_id then raise exception 'Activation did not reuse the approved patient'; end if;
  if not exists(select 1 from public.patients p join public.users u on u.id=p.user_id
    where p.id=temporary_patient_id and u.auth_user_id=guest_auth and p.profile_status='official' and p.account_activation_status='active') then
    raise exception 'Activation did not establish the authenticated patient identity'; end if;
  if public.activate_approved_guest(request_id)->>'patient_id'<>temporary_patient_id::text then raise exception 'Activation retry changed patient identity'; end if;
  if (select encrypted_password from auth.users where id=guest_auth) is distinct from existing_password then raise exception 'Activation altered existing credentials'; end if;
  if (select count(*) from public.patients where user_id=(select id from public.users where auth_user_id=guest_auth))<>greatest(original_count,1) then raise exception 'Activation duplicated the patient profile'; end if;

end
$test$;

rollback;
