begin;

insert into auth.users (id, aud, role, email, raw_app_meta_data, raw_user_meta_data)
values
  (
    '10000000-0000-4000-8000-000000000001',
    'authenticated',
    'authenticated',
    'admin-crud-test@example.invalid',
    '{}',
    '{"first_name":"CRUD","last_name":"Admin"}'
  ),
  (
    '10000000-0000-4000-8000-000000000002',
    'authenticated',
    'authenticated',
    'doctor-crud-test@example.invalid',
    '{}',
    '{"first_name":"CRUD","last_name":"Doctor"}'
  ),
  (
    '10000000-0000-4000-8000-000000000003',
    'authenticated',
    'authenticated',
    'other-doctor-crud-test@example.invalid',
    '{}',
    '{"first_name":"Other","last_name":"Doctor"}'
  );

insert into public.hospitals (
  id,
  hospital_name,
  address,
  operating_status,
  verification_status
) values (
  '20000000-0000-4000-8000-000000000001',
  'Transactional CRUD Test Hospital',
  'Rollback Street',
  'open',
  'verified'
), (
  '20000000-0000-4000-8000-000000000002',
  'Other Transactional Test Hospital',
  'Other Rollback Street',
  'open',
  'verified'
);

update public.users
set
  role_id = (select id from public.roles where role_name = 'hospital_admin'),
  hospital_id = '20000000-0000-4000-8000-000000000001'
where id = '10000000-0000-4000-8000-000000000001';

update public.users
set
  role_id = (select id from public.roles where role_name = 'doctor'),
  hospital_id = '20000000-0000-4000-8000-000000000001'
where id = '10000000-0000-4000-8000-000000000002';

update public.users
set
  role_id = (select id from public.roles where role_name = 'doctor'),
  hospital_id = '20000000-0000-4000-8000-000000000002'
where id = '10000000-0000-4000-8000-000000000003';

insert into public.hospital_departments (id, hospital_id, department_name)
values (
  '30000000-0000-4000-8000-000000000001',
  '20000000-0000-4000-8000-000000000001',
  'Test Medicine'
);

insert into public.doctors (
  id,
  user_id,
  hospital_id,
  department_id,
  display_name,
  specialization,
  license_number,
  created_by_admin
) values (
  '40000000-0000-4000-8000-000000000001',
  '10000000-0000-4000-8000-000000000002',
  '20000000-0000-4000-8000-000000000001',
  '30000000-0000-4000-8000-000000000001',
  'Dr. CRUD Doctor',
  'Test Medicine',
  'CRUD-ROLLBACK-001',
  '10000000-0000-4000-8000-000000000001'
);

insert into public.doctors (
  id,
  user_id,
  hospital_id,
  display_name,
  specialization,
  license_number
) values (
  '40000000-0000-4000-8000-000000000002',
  '10000000-0000-4000-8000-000000000003',
  '20000000-0000-4000-8000-000000000002',
  'Dr. Other Hospital',
  'Test Medicine',
  'CRUD-ROLLBACK-002'
);

set local role authenticated;
select set_config(
  'request.jwt.claim.sub',
  '10000000-0000-4000-8000-000000000001',
  true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"10000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  saved_service_id uuid;
  saved_schedule_id uuid;
  cross_hospital_rejected boolean := false;
begin
  saved_service_id := public.save_hospital_service(
    jsonb_build_object(
      'hospital_id', '20000000-0000-4000-8000-000000000001',
      'department_id', '30000000-0000-4000-8000-000000000001',
      'category_id', (
        select id from public.healthcare_service_categories
        order by display_order limit 1
      ),
      'service_name', 'Flexible CRUD Service',
      'service_code', 'FLEX-001',
      'description', 'Created in a rolled-back live test',
      'availability_status', 'available',
      'operating_hours', jsonb_build_object(
        'monday',
        jsonb_build_object(
          'enabled', true,
          'open', '08:00',
          'close', '17:00'
        )
      ),
      'delivery_modes', jsonb_build_array('in_person', 'online'),
      'appointment_required', true,
      'accepts_walk_ins', false,
      'fee_min', 500,
      'fee_max', 900,
      'tags', jsonb_build_array('test', 'flexible')
    ),
    array['40000000-0000-4000-8000-000000000001']::uuid[],
    '40000000-0000-4000-8000-000000000001'
  );

  if not exists (
    select 1
    from public.hospital_service_doctors assignment
    where assignment.service_id = saved_service_id
      and assignment.is_primary
  ) then
    raise exception 'service doctor assignment was not created';
  end if;

  begin
    perform public.replace_hospital_service_doctors(
      saved_service_id,
      array['40000000-0000-4000-8000-000000000002']::uuid[],
      null
    );
  exception when others then
    cross_hospital_rejected := true;
  end;
  if not cross_hospital_rejected then
    raise exception 'cross-hospital doctor assignment was accepted';
  end if;
  if not exists (
    select 1
    from public.hospital_service_doctors assignment
    where assignment.service_id = saved_service_id
      and assignment.doctor_id = '40000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'failed assignment did not roll back atomically';
  end if;

  perform public.save_hospital_service(
    jsonb_build_object(
      'id', saved_service_id,
      'hospital_id', '20000000-0000-4000-8000-000000000001',
      'department_id', '30000000-0000-4000-8000-000000000001',
      'service_name', 'Flexible CRUD Service Updated',
      'service_code', 'FLEX-001',
      'description', 'Updated atomically',
      'availability_status', 'limited',
      'operating_hours', '{}'::jsonb,
      'delivery_modes', jsonb_build_array('home_service'),
      'appointment_required', false,
      'accepts_walk_ins', true,
      'fee_min', 700,
      'fee_max', 700,
      'tags', jsonb_build_array('updated')
    ),
    array['40000000-0000-4000-8000-000000000001']::uuid[],
    null
  );

  if not exists (
    select 1
    from public.hospital_services service
    where service.id = saved_service_id
      and service.service_name = 'Flexible CRUD Service Updated'
      and service.delivery_modes = array['home_service']::text[]
      and service.fee_min = 700
  ) then
    raise exception 'service update did not persist';
  end if;

  insert into public.doctor_schedules (
    doctor_id,
    day_of_week,
    starts_at,
    ends_at,
    consultation_type,
    slot_minutes
  ) values (
    '40000000-0000-4000-8000-000000000001',
    1,
    '09:00',
    '12:00',
    'online',
    30
  ) returning id into saved_schedule_id;

  update public.doctor_schedules
  set slot_minutes = 45
  where id = saved_schedule_id;

  if not exists (
    select 1 from public.doctor_schedules schedule
    where schedule.id = saved_schedule_id and schedule.slot_minutes = 45
  ) then
    raise exception 'schedule update failed';
  end if;

  delete from public.doctor_schedules schedule
  where schedule.id = saved_schedule_id;
  if exists (
    select 1 from public.doctor_schedules schedule
    where schedule.id = saved_schedule_id
  ) then
    raise exception 'schedule delete failed';
  end if;

  delete from public.hospital_services service
  where service.id = saved_service_id;
  if exists (
    select 1 from public.hospital_services service
    where service.id = saved_service_id
  ) then
    raise exception 'service delete failed';
  end if;
end;
$$;

rollback;
