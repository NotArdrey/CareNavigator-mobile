-- Keep the built-in demo logins usable while giving each account a complete,
-- recognizable profile for end-to-end testing.
with demo_profiles(
  email,
  first_name,
  last_name,
  mobile_number,
  birth_date,
  sex,
  address
) as (
  values
    ('admin@demo.test', 'David', 'Lim', '09170000001', '1985-02-14', 'male', 'Makati City, Metro Manila'),
    ('hospital@demo.test', 'Sofia', 'Garcia', '09170000002', '1988-09-22', 'female', 'Quezon City, Metro Manila'),
    ('doctor@demo.test', 'Maria', 'Santos', '09170000003', '1982-05-11', 'female', 'Manila City, Metro Manila'),
    ('patient@demo.test', 'John', 'Reyes', '09170000004', '1994-06-15', 'male', 'City of San Fernando, Pampanga'),
    ('guest@demo.test', 'Ana', 'Cruz', '09170000005', '1996-03-28', 'female', 'Angeles City, Pampanga'),
    ('history.doctor@demo.test', 'Elena', 'Reyes', '09170000006', '1985-11-07', 'female', 'Cebu City, Cebu')
)
update public.users as u
set
  first_name = demo.first_name,
  last_name = demo.last_name,
  mobile_number = demo.mobile_number,
  birth_date = demo.birth_date::date,
  sex = demo.sex::public.sex_type,
  address = demo.address,
  address_geocode_hash = null,
  address_latitude = null,
  address_longitude = null
from demo_profiles as demo
where lower(u.email) = lower(demo.email);

with demo_profiles(
  email,
  first_name,
  last_name,
  mobile_number,
  birth_date,
  sex,
  address
) as (
  values
    ('admin@demo.test', 'David', 'Lim', '09170000001', '1985-02-14', 'male', 'Makati City, Metro Manila'),
    ('hospital@demo.test', 'Sofia', 'Garcia', '09170000002', '1988-09-22', 'female', 'Quezon City, Metro Manila'),
    ('doctor@demo.test', 'Maria', 'Santos', '09170000003', '1982-05-11', 'female', 'Manila City, Metro Manila'),
    ('patient@demo.test', 'John', 'Reyes', '09170000004', '1994-06-15', 'male', 'City of San Fernando, Pampanga'),
    ('guest@demo.test', 'Ana', 'Cruz', '09170000005', '1996-03-28', 'female', 'Angeles City, Pampanga'),
    ('history.doctor@demo.test', 'Elena', 'Reyes', '09170000006', '1985-11-07', 'female', 'Cebu City, Cebu')
)
update auth.users as a
set raw_user_meta_data = coalesce(a.raw_user_meta_data, '{}'::jsonb) || jsonb_build_object(
  'first_name', demo.first_name,
  'last_name', demo.last_name,
  'email', a.email,
  'mobile_number', demo.mobile_number,
  'birth_date', demo.birth_date,
  'sex', demo.sex,
  'address', demo.address,
  'email_verified', true
)
from demo_profiles as demo
where lower(a.email) = lower(demo.email);

update public.patients as p
set
  blood_type = 'O+',
  emergency_contact = jsonb_build_object(
    'name', 'Maria Reyes',
    'relationship', 'Spouse',
    'phone', '09170000009'
  ),
  allergies = array['Penicillin']::text[],
  existing_conditions = array['Hypertension']::text[],
  profile_status = 'official',
  identity_verification_status = 'verified',
  account_activation_status = 'active'
from public.users as u
where p.user_id = u.id
  and lower(u.email) = 'patient@demo.test';

update public.doctors as d
set
  display_name = case lower(u.email)
    when 'doctor@demo.test' then 'Dr. Maria Santos'
    when 'history.doctor@demo.test' then 'Dr. Elena Reyes'
    else d.display_name
  end,
  specialization = coalesce(nullif(d.specialization, ''), 'Internal Medicine'),
  license_number = coalesce(nullif(d.license_number, ''), case lower(u.email)
    when 'doctor@demo.test' then 'DEMO-PHYSICIAN-001'
    when 'history.doctor@demo.test' then 'DEMO-PHYSICIAN-002'
    else d.license_number
  end)
from public.users as u
where d.user_id = u.id
  and lower(u.email) in ('doctor@demo.test', 'history.doctor@demo.test');

insert into public.notification_preferences(
  user_id,
  consultation_updates,
  appointment_reminders,
  medical_results,
  prescriptions,
  messages,
  hospital_alerts,
  email_enabled,
  in_app_enabled
)
select
  a.id,
  true,
  true,
  true,
  true,
  true,
  true,
  false,
  true
from auth.users as a
where lower(a.email) in (
  'admin@demo.test',
  'hospital@demo.test',
  'doctor@demo.test',
  'patient@demo.test',
  'guest@demo.test',
  'history.doctor@demo.test'
)
on conflict (user_id) do nothing;
