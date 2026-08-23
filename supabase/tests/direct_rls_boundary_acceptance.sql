-- Direct authenticated-role checks for API/RLS boundaries.
-- Fixtures and direct writes are rolled back.

begin;

do $fixture$
declare
  source_record public.medical_records;
  doctor_b public.doctors;
  doctor_a public.doctors;
  doctor_c public.doctors;
  relationship_id uuid;
  consent_id uuid;
  admin_auth uuid;
begin
  select * into source_record
  from public.medical_records
  order by created_at
  limit 1;

  select doctor.* into doctor_b
  from public.doctors doctor
  join public.doctor_hospital_employments employment
    on employment.doctor_id = doctor.id
   and employment.hospital_id = doctor.hospital_id
  where doctor.hospital_id <> source_record.hospital_id
    and employment.employment_status = 'active'
    and employment.is_verified
    and (employment.ends_at is null or employment.ends_at > now())
  order by doctor.created_at
  limit 1;

  select doctor.* into doctor_a
  from public.doctors doctor
  join public.doctor_hospital_employments employment
    on employment.doctor_id = doctor.id
   and employment.hospital_id = doctor.hospital_id
  where doctor.hospital_id = source_record.hospital_id
    and employment.employment_status = 'active'
    and employment.is_verified
    and (employment.ends_at is null or employment.ends_at > now())
  order by doctor.created_at
  limit 1;

  select doctor.* into doctor_c
  from public.doctors doctor
  join public.doctor_hospital_employments employment
    on employment.doctor_id = doctor.id
   and employment.hospital_id = doctor.hospital_id
  where doctor.hospital_id not in (source_record.hospital_id, doctor_b.hospital_id)
    and employment.employment_status = 'active'
    and employment.is_verified
    and (employment.ends_at is null or employment.ends_at > now())
  order by doctor.created_at
  limit 1;

  select app_user.auth_user_id into admin_auth
  from public.users app_user
  join public.roles role on role.id = app_user.role_id
  where role.role_name = 'hospital_admin'
    and app_user.hospital_id = doctor_b.hospital_id
    and app_user.account_status = 'active'
  order by app_user.created_at
  limit 1;

  if source_record.id is null or doctor_a.id is null or doctor_b.id is null
    or doctor_c.id is null or admin_auth is null then
    raise exception 'Direct RLS acceptance fixtures require source, A/B/C doctors, and a Hospital B administrator';
  end if;

  insert into public.patient_care_relationships(
    patient_id, hospital_id, doctor_id, relationship_type, purpose,
    status, requested_at, expires_at, created_by
  ) values (
    source_record.patient_id, doctor_b.hospital_id, doctor_b.id,
    'second_opinion', 'direct_rls_acceptance', 'requested', now(),
    now() + interval '7 days', doctor_b.user_id
  ) returning id into relationship_id;

  insert into public.patient_consents(
    patient_id, consent_type, consent_version, is_granted, granted_at,
    captured_by, metadata, care_relationship_id, source_hospital_id,
    receiving_hospital_id, purpose, categories, permitted_actions,
    record_selection_mode, expires_at, granted_by, version_sequence
  ) values (
    source_record.patient_id, 'direct_rls_acceptance', relationship_id::text,
    true, now(), (select auth_user_id from public.users where id = doctor_b.user_id),
    jsonb_build_object('transactional_test', true), relationship_id,
    source_record.hospital_id, doctor_b.hospital_id, 'direct_rls_acceptance',
    array['medical_records']::text[], array['view', 'download', 'create']::text[],
    'categories', now() + interval '7 days', doctor_b.user_id, 1
  ) returning id into consent_id;

  perform private.activate_relationship_access(
    relationship_id, consent_id, doctor_b.id, null, '[]'::jsonb
  );

  perform set_config('cnph_test.source_record_id', source_record.id::text, true);
  perform set_config('cnph_test.patient_id', source_record.patient_id::text, true);
  perform set_config('cnph_test.source_hospital_id', source_record.hospital_id::text, true);
  perform set_config('cnph_test.hospital_b_id', doctor_b.hospital_id::text, true);
  perform set_config(
    'cnph_test.doctor_b_auth',
    (select auth_user_id::text from public.users where id = doctor_b.user_id),
    true
  );
  perform set_config(
    'cnph_test.doctor_a_auth',
    (select auth_user_id::text from public.users where id = doctor_a.user_id),
    true
  );
  perform set_config(
    'cnph_test.doctor_c_auth',
    (select auth_user_id::text from public.users where id = doctor_c.user_id),
    true
  );
  perform set_config('cnph_test.admin_auth', admin_auth::text, true);
  perform set_config('cnph_test.doctor_b_id', doctor_b.id::text, true);
end
$fixture$;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub', current_setting('cnph_test.doctor_b_auth'), true
);

do $doctor_b_rls$
declare
  visible_count bigint;
  wrong_origin_denied boolean := false;
  wrong_origin_updated bigint := 0;
  hospital_b_record_id uuid;
begin
  if private.current_doctor_id() is distinct from
      current_setting('cnph_test.doctor_b_id')::uuid then
    raise exception 'Authenticated doctor identity was not resolved for direct RLS';
  end if;
  if not private.can_access_clinical_record(
    current_setting('cnph_test.patient_id')::uuid,
    current_setting('cnph_test.hospital_b_id')::uuid,
    'medical_records', null, 'create'
  ) then
    raise exception 'Direct RLS fixture did not activate Hospital B create scope';
  end if;
  select count(*) into visible_count
  from public.medical_records
  where id = current_setting('cnph_test.source_record_id')::uuid;
  if visible_count <> 1 then
    raise exception 'Direct RLS denied Hospital B the explicitly granted Hospital A record';
  end if;

  begin
    insert into public.medical_records(
      patient_id, doctor_id, hospital_id, record_type, title, description
    ) values (
      current_setting('cnph_test.patient_id')::uuid,
      current_setting('cnph_test.doctor_b_id')::uuid,
      current_setting('cnph_test.source_hospital_id')::uuid,
      'consultation_note', 'Forbidden Hospital A write',
      'Direct RLS acceptance test'
    );
  exception when others then
    wrong_origin_denied := true;
  end;
  if not wrong_origin_denied then
    raise exception 'Direct API write created a Hospital A record from Hospital B';
  end if;

  begin
    update public.medical_records
    set description = 'Forbidden cross-hospital update'
    where id = current_setting('cnph_test.source_record_id')::uuid;
    get diagnostics wrong_origin_updated = row_count;
  exception when others then
    wrong_origin_updated := 0;
  end;
  if wrong_origin_updated <> 0 then
    raise exception 'Direct API update changed a Hospital A record from Hospital B';
  end if;

  insert into public.medical_records(
    patient_id, doctor_id, hospital_id, record_type, title, description
  ) values (
    current_setting('cnph_test.patient_id')::uuid,
    current_setting('cnph_test.doctor_b_id')::uuid,
    current_setting('cnph_test.hospital_b_id')::uuid,
    'consultation_note', 'Hospital B finding',
    'Direct RLS acceptance test'
  ) returning id into hospital_b_record_id;
  perform set_config('cnph_test.hospital_b_record_id', hospital_b_record_id::text, true);
end
$doctor_b_rls$;

select set_config(
  'request.jwt.claim.sub', current_setting('cnph_test.doctor_a_auth'), true
);
do $doctor_a_rls$
begin
  if exists (
    select 1 from public.medical_records
    where id = current_setting('cnph_test.hospital_b_record_id')::uuid
  ) then
    raise exception 'Hospital A inherited access to the new Hospital B finding';
  end if;
end
$doctor_a_rls$;

select set_config(
  'request.jwt.claim.sub', current_setting('cnph_test.doctor_c_auth'), true
);
do $doctor_c_rls$
begin
  if exists (
    select 1 from public.medical_records
    where id = current_setting('cnph_test.source_record_id')::uuid
  ) then
    raise exception 'Hospital B transitively shared Hospital A data with Hospital C';
  end if;
end
$doctor_c_rls$;

select set_config(
  'request.jwt.claim.sub', current_setting('cnph_test.admin_auth'), true
);
do $admin_rls$
begin
  if exists (
    select 1 from public.patients
    where id = current_setting('cnph_test.patient_id')::uuid
  ) or exists (
    select 1 from public.medical_records
    where id = current_setting('cnph_test.source_record_id')::uuid
  ) then
    raise exception 'Hospital administrator bypassed the operational-only boundary';
  end if;
end
$admin_rls$;

reset role;

do $audit_check$
begin
  if not exists (
    select 1 from public.audit_logs audit
    where audit.module = 'medical_records'
      and audit.record_id = current_setting('cnph_test.hospital_b_record_id')::uuid
      and audit.action = 'insert'
  ) then
    raise exception 'The authorized Hospital B finding was not audit logged';
  end if;
end
$audit_check$;

rollback;
