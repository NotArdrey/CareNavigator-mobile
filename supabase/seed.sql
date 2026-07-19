-- CareNavigator PH demo seed
--
-- Hospital identity and location data is based on public DOH, PhilHealth, and
-- provincial-government directories. Capacity, availability, staff, patient,
-- and consultation records below are synthetic demo data and are not live.
-- Demo credentials are intentionally weak and must never be used in production.

begin;

-- Auth accounts are created first by tool/seed-demo.ps1 through Supabase's
-- supported Admin Auth API. Stable IDs keep this relational seed repeatable.

insert into public.hospitals (
  id, hospital_name, classification_id, address, city, province, latitude, longitude,
  contact_number, email, description, operating_hours, operating_status, verification_status
)
values
  ('20000000-0000-4000-8000-000000000001', 'Jose B. Lingad Memorial General Hospital', (select id from public.hospital_classifications where classification_name='Tertiary Hospital'), 'Dolores, City of San Fernando, Pampanga', 'City of San Fernando', 'Pampanga', 15.034140, 120.684330, '(045) 409-6688', 'mcc@jblmgh.com.ph', 'DOH-retained Level 3 referral hospital serving Central Luzon.', '{"emergency":"24/7","outpatient":"Monday-Friday"}', 'open', 'verified'),
  ('20000000-0000-4000-8000-000000000002', 'Bataan General Hospital and Medical Center', (select id from public.hospital_classifications where classification_name='Tertiary Hospital'), 'Manahan Street, Tenejero, Balanga City, Bataan', 'Balanga City', 'Bataan', 14.676200, 120.536200, null, null, 'DOH-retained tertiary general hospital and medical center.', '{"emergency":"24/7","outpatient":"Monday-Friday"}', 'open', 'verified'),
  ('20000000-0000-4000-8000-000000000003', 'Bulacan Medical Center', (select id from public.hospital_classifications where classification_name='Tertiary Hospital'), '99 Potenciano Street, Mojon, Malolos City, Bulacan', 'Malolos City', 'Bulacan', 14.852700, 120.811400, null, null, 'Provincial Level 3 tertiary teaching and training hospital.', '{"emergency":"24/7","outpatient":"Monday-Friday"}', 'open', 'verified'),
  ('20000000-0000-4000-8000-000000000004', 'Dr. Paulino J. Garcia Memorial Research and Medical Center', (select id from public.hospital_classifications where classification_name='Tertiary Hospital'), 'Mabini Street, Cabanatuan City, Nueva Ecija', 'Cabanatuan City', 'Nueva Ecija', 15.489400, 120.968100, null, null, 'DOH-retained regional medical center in Nueva Ecija.', '{"emergency":"24/7","outpatient":"Monday-Friday"}', 'open', 'verified'),
  ('20000000-0000-4000-8000-000000000005', 'Tarlac Provincial Hospital', (select id from public.hospital_classifications where classification_name='Tertiary Hospital'), 'Hospital Drive, San Vicente, Tarlac City, Tarlac', 'Tarlac City', 'Tarlac', 15.477500, 120.596300, null, null, 'Provincial government tertiary hospital serving Tarlac.', '{"emergency":"24/7","outpatient":"Monday-Friday"}', 'open', 'verified'),
  ('20000000-0000-4000-8000-000000000006', 'President Ramon Magsaysay Memorial Hospital', (select id from public.hospital_classifications where classification_name='Secondary Hospital'), 'Palanginan, Iba, Zambales', 'Iba', 'Zambales', 15.326100, 119.980000, null, null, 'Provincial government hospital serving Zambales.', '{"emergency":"24/7","outpatient":"Monday-Friday"}', 'open', 'verified'),
  ('20000000-0000-4000-8000-000000000007', 'Aurora Memorial Hospital', (select id from public.hospital_classifications where classification_name='Secondary Hospital'), 'Reserva, Baler, Aurora', 'Baler', 'Aurora', 15.758200, 121.562000, null, null, 'Provincial hospital serving Aurora communities.', '{"emergency":"24/7","outpatient":"Monday-Friday"}', 'open', 'verified')
on conflict (id) do update set
  hospital_name=excluded.hospital_name, classification_id=excluded.classification_id,
  address=excluded.address, city=excluded.city, province=excluded.province,
  latitude=excluded.latitude, longitude=excluded.longitude,
  contact_number=excluded.contact_number, email=excluded.email,
  description=excluded.description, operating_hours=excluded.operating_hours,
  operating_status=excluded.operating_status, verification_status=excluded.verification_status;

-- Promote the trigger-created demo profiles to their intended roles.
update public.users set role_id=(select id from public.roles where role_name='super_admin'), first_name='Demo', last_name='Admin', email='admin@demo.test', account_status='active', hospital_id=null where auth_user_id='10000000-0000-4000-8000-000000000001';
update public.users set role_id=(select id from public.roles where role_name='hospital_admin'), first_name='Hospital', last_name='Admin', email='hospital@demo.test', account_status='active', hospital_id='20000000-0000-4000-8000-000000000001' where auth_user_id='10000000-0000-4000-8000-000000000002';
update public.users set role_id=(select id from public.roles where role_name='doctor'), first_name='Maria', last_name='Santos', email='doctor@demo.test', account_status='active', hospital_id='20000000-0000-4000-8000-000000000001', mobile_number='09170000003' where auth_user_id='10000000-0000-4000-8000-000000000003';
update public.users set role_id=(select id from public.roles where role_name='patient'), first_name='Juan', last_name='Dela Cruz', email='patient@demo.test', account_status='active', hospital_id='20000000-0000-4000-8000-000000000001', mobile_number='09170000004', birth_date='1994-06-15', sex='male', address='City of San Fernando, Pampanga' where auth_user_id='10000000-0000-4000-8000-000000000004';
update public.users set role_id=(select id from public.roles where role_name='guest'), first_name='Guest', last_name='User', email='guest@demo.test', account_status='active', hospital_id=null where auth_user_id='10000000-0000-4000-8000-000000000005';

-- Common departments and services. These are demo offerings, not assertions of
-- current real-time service availability.
insert into public.hospital_departments (hospital_id, department_name, description)
select hospital.id, department.name, department.description
from public.hospitals hospital
cross join (values
  ('Emergency Medicine', '24-hour emergency assessment and stabilization'),
  ('Internal Medicine', 'Adult medical care'),
  ('Pediatrics', 'Medical care for infants, children, and adolescents'),
  ('Obstetrics and Gynecology', 'Maternal and reproductive healthcare'),
  ('Surgery', 'General surgical services')
) as department(name, description)
where hospital.id::text like '20000000-0000-4000-8000-%'
on conflict (hospital_id, department_name) do update set description=excluded.description;

insert into public.hospital_services (
  hospital_id, department_id, category_id, service_name, description,
  delivery_modes, appointment_required, accepts_walk_ins, tags, operating_hours
)
select hospital.id, department.id, category.id, service.name, service.description,
       service.modes, service.appointment_required, service.walk_ins, service.tags,
       service.hours
from public.hospitals hospital
join (values
  ('Emergency Medicine', 'Emergency Room', 'Emergency & Critical Care', 'Emergency assessment and stabilization', array['in_person','emergency']::text[], false, true, array['emergency','24-hour']::text[], '{"daily":"24 hours"}'::jsonb),
  ('Internal Medicine', 'General Medicine Consultation', 'Medical Consultation', 'Adult outpatient medical consultation', array['in_person','online']::text[], true, true, array['adult-care']::text[], '{"weekdays":"08:00-17:00"}'::jsonb),
  ('Pediatrics', 'Pediatric Consultation', 'Maternal & Child Care', 'Outpatient pediatric care', array['in_person']::text[], true, true, array['children']::text[], '{"weekdays":"08:00-17:00"}'::jsonb),
  ('Obstetrics and Gynecology', 'Prenatal Care', 'Maternal & Child Care', 'Routine prenatal assessment', array['in_person']::text[], true, true, array['maternal']::text[], '{"weekdays":"08:00-17:00"}'::jsonb),
  ('Surgery', 'General Surgery', 'Surgical Services', 'Surgical evaluation and care', array['in_person']::text[], true, false, array['surgery']::text[], '{"weekdays":"08:00-17:00"}'::jsonb)
) as service(department_name, name, category_name, description, modes, appointment_required, walk_ins, tags, hours) on true
join public.hospital_departments department on department.hospital_id=hospital.id and department.department_name=service.department_name
join public.healthcare_service_categories category on category.category_name=service.category_name
where hospital.id::text like '20000000-0000-4000-8000-%'
on conflict (hospital_id, service_name) do update set
  department_id=excluded.department_id, category_id=excluded.category_id,
  description=excluded.description, delivery_modes=excluded.delivery_modes,
  appointment_required=excluded.appointment_required, accepts_walk_ins=excluded.accepts_walk_ins,
  tags=excluded.tags, operating_hours=excluded.operating_hours;

-- Add distinct synthetic specialties and services per demo hospital. The
-- migration owns the catalog so reseeding and live upgrades stay consistent.
select private.seed_demo_hospital_capabilities();

insert into public.emergency_room_status (hospital_id, status, available_beds, current_patient_count, maximum_capacity)
select id, case when row_number() over(order by id) % 3 = 0 then 'limited'::public.emergency_room_state else 'available'::public.emergency_room_state end,
       4 + row_number() over(order by id), 8 + row_number() over(order by id), 24 + row_number() over(order by id)
from public.hospitals where id::text like '20000000-0000-4000-8000-%'
on conflict (hospital_id) do update set status=excluded.status, available_beds=excluded.available_beds, current_patient_count=excluded.current_patient_count, maximum_capacity=excluded.maximum_capacity, last_updated=now();

insert into public.hospital_rooms (hospital_id, room_type, total_rooms, available_rooms, occupied_rooms, status)
select id, 'General Ward', 30, 8, 20, 'available' from public.hospitals where id::text like '20000000-0000-4000-8000-%'
on conflict (hospital_id, room_type) do update set total_rooms=excluded.total_rooms, available_rooms=excluded.available_rooms, occupied_rooms=excluded.occupied_rooms, status=excluded.status, last_updated=now();

insert into public.hospital_facility_status (hospital_id, facility_type, status, available_units, notes)
select hospital.id, facility.type, 'available', facility.units, 'Synthetic demo availability - not live data'
from public.hospitals hospital
cross join (values ('icu', 3), ('operating_room', 2), ('ambulance', 2), ('laboratory', 1), ('pharmacy', 1)) facility(type, units)
where hospital.id::text like '20000000-0000-4000-8000-%'
on conflict (hospital_id, facility_type) do update set status=excluded.status, available_units=excluded.available_units, notes=excluded.notes, last_updated=now();

insert into public.doctors (id, user_id, hospital_id, department_id, display_name, specialization, license_number, availability_status, consultation_fee, biography, created_by_admin)
values ('30000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000003', '20000000-0000-4000-8000-000000000001', (select id from public.hospital_departments where hospital_id='20000000-0000-4000-8000-000000000001' and department_name='Internal Medicine'), 'Dr. Maria Santos', 'Internal Medicine', 'DEMO-PHYSICIAN-001', 'available', 500, 'Synthetic clinician profile for demonstrations only.', '10000000-0000-4000-8000-000000000002')
on conflict (id) do update set department_id=excluded.department_id, availability_status=excluded.availability_status, consultation_fee=excluded.consultation_fee;

insert into public.doctor_schedules (doctor_id, day_of_week, starts_at, ends_at, consultation_type, slot_minutes)
select '30000000-0000-4000-8000-000000000001', day, '09:00', '16:00', kind, 30
from (values (1, 'face_to_face'::public.consultation_type), (2, 'online'::public.consultation_type), (3, 'face_to_face'::public.consultation_type), (4, 'online'::public.consultation_type), (5, 'face_to_face'::public.consultation_type)) schedule(day, kind)
on conflict (doctor_id, day_of_week, starts_at, consultation_type) do update set ends_at=excluded.ends_at, is_active=true;

insert into public.patients (id, user_id, patient_number, primary_hospital_id, blood_type, emergency_contact, allergies, existing_conditions, identity_verification_status, account_activation_status, profile_status, activated_at)
values ('40000000-0000-4000-8000-000000000001', '10000000-0000-4000-8000-000000000004', 'CNPH-DEMO-0001', '20000000-0000-4000-8000-000000000001', 'O+', '{"name":"Maria Dela Cruz","relationship":"Spouse","phone":"09170000009"}', array['Penicillin'], array['Hypertension'], 'verified', 'active', 'official', now())
on conflict (id) do update set primary_hospital_id=excluded.primary_hospital_id, account_activation_status='active', profile_status='official';

insert into public.doctor_patient_assignments (id, doctor_id, patient_id, notes)
values ('50000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', 'Synthetic demo assignment')
on conflict (id) do update set ended_at=null, notes=excluded.notes;

insert into public.consultations (id, patient_id, doctor_id, hospital_id, department_id, consultation_type, appointment_date, status, chief_complaint)
values ('60000000-0000-4000-8000-000000000001', '40000000-0000-4000-8000-000000000001', '30000000-0000-4000-8000-000000000001', '20000000-0000-4000-8000-000000000001', (select id from public.hospital_departments where hospital_id='20000000-0000-4000-8000-000000000001' and department_name='Internal Medicine'), 'face_to_face', date_trunc('day', now()) + interval '2 days 10 hours', 'scheduled', 'Demo follow-up for blood pressure monitoring')
on conflict (id) do update set appointment_date=excluded.appointment_date, status='scheduled', chief_complaint=excluded.chief_complaint;

commit;
