-- Expose only bookable, unoccupied times derived from each clinician's
-- published recurring schedule. The booking RPC remains the final authority
-- and rechecks the slot inside the insert transaction.
create or replace function public.list_available_consultation_slots(
  target_doctor_id uuid,
  target_type public.consultation_type,
  horizon_days integer default 30
)
returns table (
  starts_at timestamptz,
  ends_at timestamptz
)
language sql
stable
security definer
set search_path = ''
as $function$
  with requested_window as (
    select
      (now() at time zone 'Asia/Manila')::date as first_date,
      least(greatest(coalesce(horizon_days, 30), 1), 60) as day_count
  ),
  calendar_dates as (
    select generated_date.value::date as local_date
    from requested_window bounds,
    lateral generate_series(
      bounds.first_date::timestamp,
      (bounds.first_date + bounds.day_count - 1)::timestamp,
      interval '1 day'
    ) as generated_date(value)
  ),
  published_slots as (
    select
      (
        generated_local_start.value at time zone 'Asia/Manila'
      ) as slot_start,
      schedule.slot_minutes
    from public.doctor_schedules schedule
    join calendar_dates calendar
      on schedule.day_of_week = extract(dow from calendar.local_date)::integer
    , lateral generate_series(
      calendar.local_date + schedule.starts_at,
      calendar.local_date + schedule.ends_at
        - make_interval(mins => schedule.slot_minutes),
      make_interval(mins => schedule.slot_minutes)
    ) as generated_local_start(value)
    where schedule.doctor_id = target_doctor_id
      and schedule.is_active
      and schedule.consultation_type = target_type
  )
  select
    slot.slot_start as starts_at,
    slot.slot_start + make_interval(mins => slot.slot_minutes) as ends_at
  from published_slots slot
  join public.doctors doctor on doctor.id = target_doctor_id
  where private.is_doctor_slot_available(
    target_doctor_id,
    doctor.hospital_id,
    target_type,
    slot.slot_start,
    null
  )
  order by slot.slot_start
  limit 240
$function$;

revoke all on function public.list_available_consultation_slots(
  uuid,
  public.consultation_type,
  integer
) from public;
revoke all on function public.list_available_consultation_slots(
  uuid,
  public.consultation_type,
  integer
) from anon;
grant execute on function public.list_available_consultation_slots(
  uuid,
  public.consultation_type,
  integer
) to authenticated;

comment on function public.list_available_consultation_slots(
  uuid,
  public.consultation_type,
  integer
) is 'Returns published, future, unoccupied clinician appointment slots in a bounded window.';

-- Complete the standard synthetic account profiles with realistic values.
with demo_profiles(
  email,
  middle_name,
  latitude,
  longitude
) as (
  values
    ('admin@demo.test', 'Tan', 14.5547::double precision, 121.0244::double precision),
    ('hospital@demo.test', 'Mendoza', 14.6760::double precision, 121.0437::double precision),
    ('doctor@demo.test', 'Dela Cruz', 14.5995::double precision, 120.9842::double precision),
    ('patient@demo.test', 'Dizon', 15.0287::double precision, 120.6890::double precision),
    ('guest@demo.test', 'Flores', 15.1450::double precision, 120.5887::double precision),
    ('history.doctor@demo.test', 'Navarro', 10.3157::double precision, 123.8854::double precision)
)
update public.users app_user
set
  middle_name = demo.middle_name,
  address_latitude = demo.latitude,
  address_longitude = demo.longitude,
  address_geocode_hash = encode(
    sha256(convert_to(lower(btrim(app_user.address)), 'UTF8')),
    'hex'
  ),
  avatar_url = coalesce(app_user.avatar_url, app_user.profile_image_url),
  profile_image_url = coalesce(app_user.profile_image_url, app_user.avatar_url),
  updated_at = now()
from demo_profiles demo
where lower(app_user.email) = demo.email;

update public.patients patient
set
  patient_number = coalesce(nullif(patient.patient_number, ''), 'CNPH-PAT-0001'),
  primary_hospital_id = coalesce(
    patient.primary_hospital_id,
    (select app_user.hospital_id from public.users app_user where app_user.id = patient.user_id)
  ),
  blood_type = coalesce(nullif(patient.blood_type, ''), 'O+'),
  emergency_contact = jsonb_build_object(
    'name', 'Maria Dizon Reyes',
    'relationship', 'Spouse',
    'phone', '09181234567',
    'address', 'City of San Fernando, Pampanga'
  ),
  allergies = array['Penicillin', 'Shellfish']::text[],
  existing_conditions = array['Hypertension', 'Seasonal allergic rhinitis']::text[],
  identity_verification_status = 'verified',
  account_activation_status = 'active',
  profile_status = 'official',
  activated_at = coalesce(patient.activated_at, now() - interval '90 days'),
  updated_at = now()
from public.users app_user
where patient.user_id = app_user.id
  and lower(app_user.email) = 'patient@demo.test';

update public.doctors doctor
set
  consultation_fee = case lower(app_user.email)
    when 'doctor@demo.test' then 750.00
    else 650.00
  end,
  biography = case lower(app_user.email)
    when 'doctor@demo.test' then
      'Board-certified internist focused on adult primary care, hypertension management, diabetes prevention, and coordinated follow-up care.'
    else
      'Internal medicine clinician experienced in preventive care, chronic disease management, and continuity of care across hospital settings.'
  end,
  availability_status = 'available',
  profile_image_url = coalesce(doctor.profile_image_url, app_user.profile_image_url),
  updated_at = now()
from public.users app_user
where doctor.user_id = app_user.id
  and lower(app_user.email) in ('doctor@demo.test', 'history.doctor@demo.test');

-- Publish a varied weekly schedule for both standard demo clinicians.
insert into public.doctor_schedules(
  doctor_id,
  day_of_week,
  starts_at,
  ends_at,
  consultation_type,
  slot_minutes,
  is_active
)
select doctor.id, schedule.day_of_week, schedule.starts_at, schedule.ends_at,
       schedule.consultation_type::public.consultation_type,
       schedule.slot_minutes, true
from public.doctors doctor
join public.users app_user on app_user.id = doctor.user_id
cross join (
  values
    (1::smallint, '09:00'::time, '12:00'::time, 'online', 30),
    (2::smallint, '13:00'::time, '16:00'::time, 'face_to_face', 30),
    (3::smallint, '09:00'::time, '12:00'::time, 'online', 30),
    (4::smallint, '13:00'::time, '16:00'::time, 'face_to_face', 30),
    (5::smallint, '09:00'::time, '12:00'::time, 'online', 30)
) schedule(day_of_week, starts_at, ends_at, consultation_type, slot_minutes)
where lower(app_user.email) in ('doctor@demo.test', 'history.doctor@demo.test')
on conflict (doctor_id, day_of_week, starts_at, consultation_type)
do update set
  ends_at = excluded.ends_at,
  slot_minutes = excluded.slot_minutes,
  is_active = true;

-- Give every standard demo login useful, fully populated inbox records.
insert into public.notifications(
  user_id,
  title,
  message,
  notification_type,
  is_read,
  created_at,
  data,
  action_url,
  action_path,
  dedupe_key
)
select
  app_user.auth_user_id,
  notice.title,
  notice.message,
  notice.notification_type,
  notice.is_read,
  now() - notice.age,
  jsonb_build_object(
    'source', 'demo_seed',
    'role', role.role_name,
    'priority', notice.priority
  ),
  'https://carenavigator.ph' || notice.action_path,
  notice.action_path,
  'demo-' || role.role_name || '-' || notice.sequence
from public.users app_user
join public.roles role on role.id = app_user.role_id
cross join (
  values
    ('Welcome to CareNavigator PH', 'Your complete demo workspace is ready to explore.', 'account', false, interval '2 hours', 'normal', '/notifications', 'welcome'),
    ('Profile information verified', 'Contact, identity, and role details are complete for this demonstration account.', 'profile', true, interval '2 days', 'normal', '/profile', 'profile-ready'),
    ('New workspace activity', 'Fresh linked demonstration records are available in your workspace.', 'workspace', false, interval '20 minutes', 'high', '/notifications', 'workspace-activity')
) notice(title, message, notification_type, is_read, age, priority, action_path, sequence)
where lower(app_user.email) in (
  'admin@demo.test',
  'hospital@demo.test',
  'doctor@demo.test',
  'patient@demo.test',
  'guest@demo.test',
  'history.doctor@demo.test'
)
on conflict (user_id, dedupe_key) where dedupe_key is not null
do update set
  title = excluded.title,
  message = excluded.message,
  notification_type = excluded.notification_type,
  is_read = excluded.is_read,
  data = excluded.data,
  action_url = excluded.action_url,
  action_path = excluded.action_path;
