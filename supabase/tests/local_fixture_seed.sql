-- Synthetic database fixtures. Run only in an empty, isolated test database.
-- No real identity, contact, password, or clinical information is included.
do $$
declare h uuid; dep uuid; a uuid; u uuid; d uuid; p uuid; rel uuid; consent uuid; i int;
begin
  if exists(select 1 from public.hospitals) then raise exception 'Fixture seed requires an empty hospital directory'; end if;
  for i in 1..3 loop
    insert into public.hospitals(hospital_name,address,verification_status,operating_status,online_request_workflow_enabled)
    values('Synthetic Test Hospital '||i,'Synthetic address','verified','open',true) returning id into h;
    insert into public.hospital_departments(hospital_id,department_name,availability_status)
    values(h,'Synthetic department','available') returning id into dep;
    a:=gen_random_uuid();
    insert into auth.users(id,email,email_confirmed_at,is_anonymous,raw_user_meta_data,raw_app_meta_data)
    values(a,'admin-'||i||'@example.test',now(),false,'{"first_name":"Synthetic","last_name":"Administrator"}','{}');
    update public.users set role_id=(select id from public.roles where role_name='hospital_admin'),hospital_id=h,account_status='active' where auth_user_id=a;
    a:=gen_random_uuid();
    insert into auth.users(id,email,email_confirmed_at,is_anonymous,raw_user_meta_data,raw_app_meta_data)
    values(a,'doctor-'||i||'@example.test',now(),false,'{"first_name":"Synthetic","last_name":"Doctor"}','{}');
    update public.users set role_id=(select id from public.roles where role_name='doctor'),hospital_id=h,account_status='active' where auth_user_id=a returning id into u;
    insert into public.doctors(user_id,hospital_id,department_id,display_name,specialization,license_number,availability_status)
    values(u,h,dep,'Synthetic Doctor '||i,'Synthetic test specialty','TEST-PRC-'||i,'available') returning id into d;
    insert into public.doctor_hospital_employments(doctor_id,hospital_id,is_verified,employment_status) values(d,h,true,'active');
    insert into public.doctor_schedules(doctor_id,day_of_week,starts_at,ends_at,consultation_type,slot_minutes,is_active)
    select d,day,'08:00','18:00',mode::public.consultation_type,30,true from generate_series(0,6) day cross join unnest(array['online','face_to_face']) mode;
    if i=1 then
      a:=gen_random_uuid();
      insert into auth.users(id,email,email_confirmed_at,is_anonymous,raw_user_meta_data,raw_app_meta_data)
      values(a,'patient@example.test',now(),false,'{"first_name":"Synthetic","last_name":"Patient"}','{}');
      update public.users set role_id=(select id from public.roles where role_name='patient'),account_status='active',mobile_number='+639171234567',birth_date='1990-01-01',sex='male',address='Synthetic address' where auth_user_id=a returning id into u;
      insert into public.patients(user_id,primary_hospital_id,profile_status,account_activation_status) values(u,h,'official','active') returning id into p;
      insert into public.patient_care_relationships(patient_id,hospital_id,doctor_id,relationship_type,purpose,status,expires_at,created_by)
      values(p,h,d,'consultation','synthetic_fixture','requested',now()+interval '30 days',u) returning id into rel;
      insert into public.patient_consents(patient_id,consent_type,consent_version,is_granted,granted_at,captured_by,care_relationship_id,source_hospital_id,receiving_hospital_id,purpose,categories,permitted_actions,record_selection_mode,expires_at,granted_by)
      values(p,'synthetic_fixture',rel::text,true,now(),a,rel,h,h,'synthetic_fixture',array['medical_records','consultations','prescriptions','medical_documents'],array['view','download','create'],'categories',now()+interval '30 days',u) returning id into consent;
      perform private.activate_relationship_access(rel,consent,d,null,'[]');
      perform set_config('request.jwt.claim.sub',(select auth_user_id::text from public.users where id=(select user_id from public.doctors where id=d)),true);
      insert into public.medical_records(patient_id,doctor_id,hospital_id,record_type,title,description)
      values(p,d,h,'synthetic_fixture','Synthetic source record','Synthetic test content');
      perform set_config('request.jwt.claim.sub','',true);
    end if;
  end loop;
  a:=gen_random_uuid();
  insert into auth.users(id,email,email_confirmed_at,is_anonymous,raw_user_meta_data,raw_app_meta_data)
  values(a,'guest@example.test',now(),false,'{"first_name":"Synthetic","last_name":"Guest"}','{}');
  update public.users set account_status='active' where auth_user_id=a;
end $$;
