begin;

-- Synthetic demo capability differences for UI and recommendation testing.
-- These rows are not assertions of current real-world hospital availability.
create or replace function private.seed_demo_hospital_capabilities()
returns void
language plpgsql
set search_path = ''
as $$
begin
with department_catalog(hospital_id, department_name, description) as (
  values
    ('20000000-0000-4000-8000-000000000001'::uuid, 'Cardiology', 'Heart and cardiovascular evaluation'),
    ('20000000-0000-4000-8000-000000000001'::uuid, 'Nephrology', 'Kidney care and renal medicine'),
    ('20000000-0000-4000-8000-000000000001'::uuid, 'Orthopedics', 'Bone, joint, and musculoskeletal care'),
    ('20000000-0000-4000-8000-000000000002'::uuid, 'Oncology', 'Cancer evaluation and coordinated care'),
    ('20000000-0000-4000-8000-000000000002'::uuid, 'Radiology', 'Diagnostic imaging and image-guided assessment'),
    ('20000000-0000-4000-8000-000000000002'::uuid, 'Rehabilitation Medicine', 'Recovery, mobility, and functional rehabilitation'),
    ('20000000-0000-4000-8000-000000000003'::uuid, 'Neurology', 'Brain, spine, and nervous-system care'),
    ('20000000-0000-4000-8000-000000000003'::uuid, 'Ophthalmology', 'Medical and surgical eye care'),
    ('20000000-0000-4000-8000-000000000003'::uuid, 'Otorhinolaryngology', 'Ear, nose, and throat care'),
    ('20000000-0000-4000-8000-000000000004'::uuid, 'Cardiology', 'Heart and cardiovascular evaluation'),
    ('20000000-0000-4000-8000-000000000004'::uuid, 'Psychiatry', 'Mental health assessment and treatment'),
    ('20000000-0000-4000-8000-000000000004'::uuid, 'Pulmonology', 'Lung and respiratory care'),
    ('20000000-0000-4000-8000-000000000005'::uuid, 'Nephrology', 'Kidney care and renal medicine'),
    ('20000000-0000-4000-8000-000000000005'::uuid, 'Orthopedics', 'Bone, joint, and musculoskeletal care'),
    ('20000000-0000-4000-8000-000000000005'::uuid, 'Urology', 'Urinary tract and urologic care'),
    ('20000000-0000-4000-8000-000000000006'::uuid, 'Diagnostic Imaging', 'General diagnostic imaging services'),
    ('20000000-0000-4000-8000-000000000006'::uuid, 'Family Medicine', 'Comprehensive first-contact and continuing care'),
    ('20000000-0000-4000-8000-000000000007'::uuid, 'Anesthesiology', 'Anesthesia assessment and perioperative support'),
    ('20000000-0000-4000-8000-000000000007'::uuid, 'Community Health', 'Screening, prevention, and community-based care'),
    ('20000000-0000-4000-8000-000000000007'::uuid, 'Family Medicine', 'Comprehensive first-contact and continuing care')
)
insert into public.hospital_departments (hospital_id, department_name, description)
select hospital_id, department_name, description
from department_catalog
on conflict (hospital_id, department_name) do update
set description = excluded.description,
    availability_status = 'available';

with service_catalog(
  hospital_id, department_name, service_name, category_name, description,
  appointment_required, accepts_walk_ins, tags
) as (
  values
    ('20000000-0000-4000-8000-000000000001'::uuid, 'Cardiology', 'Cardiology Consultation', 'Medical Consultation', 'Heart and cardiovascular specialist assessment', true, false, array['cardiology','heart','cardiac']::text[]),
    ('20000000-0000-4000-8000-000000000001'::uuid, 'Nephrology', 'Hemodialysis', 'Medical Consultation', 'Scheduled renal replacement therapy', true, false, array['nephrology','kidney','dialysis']::text[]),
    ('20000000-0000-4000-8000-000000000001'::uuid, 'Orthopedics', 'Orthopedic Consultation', 'Medical Consultation', 'Bone, joint, and musculoskeletal assessment', true, true, array['orthopedics','bone','joint']::text[]),
    ('20000000-0000-4000-8000-000000000002'::uuid, 'Oncology', 'Oncology Consultation', 'Medical Consultation', 'Cancer evaluation and care planning', true, false, array['oncology','cancer']::text[]),
    ('20000000-0000-4000-8000-000000000002'::uuid, 'Radiology', 'Diagnostic Imaging', 'Diagnostics & Imaging', 'General radiography and imaging assessment', true, true, array['radiology','imaging','x-ray']::text[]),
    ('20000000-0000-4000-8000-000000000002'::uuid, 'Rehabilitation Medicine', 'Physical Rehabilitation', 'Rehabilitation & Therapy', 'Mobility and functional recovery program', true, false, array['rehabilitation','physical-therapy','mobility']::text[]),
    ('20000000-0000-4000-8000-000000000003'::uuid, 'Neurology', 'Neurology Consultation', 'Medical Consultation', 'Brain, spine, and nervous-system assessment', true, false, array['neurology','brain','nerves']::text[]),
    ('20000000-0000-4000-8000-000000000003'::uuid, 'Ophthalmology', 'Eye Clinic', 'Medical Consultation', 'Medical eye assessment and follow-up', true, true, array['ophthalmology','eye','vision']::text[]),
    ('20000000-0000-4000-8000-000000000003'::uuid, 'Otorhinolaryngology', 'ENT Consultation', 'Medical Consultation', 'Ear, nose, and throat assessment', true, true, array['ent','ear','nose','throat']::text[]),
    ('20000000-0000-4000-8000-000000000004'::uuid, 'Cardiology', 'Cardiology Consultation', 'Medical Consultation', 'Heart and cardiovascular specialist assessment', true, false, array['cardiology','heart','cardiac']::text[]),
    ('20000000-0000-4000-8000-000000000004'::uuid, 'Psychiatry', 'Behavioral Health Consultation', 'Medical Consultation', 'Mental health assessment and treatment planning', true, false, array['psychiatry','mental-health','behavioral-health']::text[]),
    ('20000000-0000-4000-8000-000000000004'::uuid, 'Pulmonology', 'Pulmonary Consultation', 'Medical Consultation', 'Lung and respiratory specialist assessment', true, true, array['pulmonology','lung','respiratory']::text[]),
    ('20000000-0000-4000-8000-000000000005'::uuid, 'Nephrology', 'Renal Consultation', 'Medical Consultation', 'Kidney and renal medicine assessment', true, true, array['nephrology','kidney','renal']::text[]),
    ('20000000-0000-4000-8000-000000000005'::uuid, 'Orthopedics', 'Fracture and Trauma Care', 'Surgical Services', 'Assessment and management of fractures and orthopedic trauma', false, true, array['orthopedics','fracture','trauma']::text[]),
    ('20000000-0000-4000-8000-000000000005'::uuid, 'Urology', 'Urology Consultation', 'Medical Consultation', 'Urinary tract and urologic assessment', true, true, array['urology','urinary']::text[]),
    ('20000000-0000-4000-8000-000000000006'::uuid, 'Diagnostic Imaging', 'Ultrasound Imaging', 'Diagnostics & Imaging', 'General diagnostic ultrasound examination', true, true, array['ultrasound','imaging','diagnostics']::text[]),
    ('20000000-0000-4000-8000-000000000006'::uuid, 'Family Medicine', 'Family Medicine Consultation', 'Medical Consultation', 'First-contact care for patients and families', true, true, array['family-medicine','primary-care']::text[]),
    ('20000000-0000-4000-8000-000000000007'::uuid, 'Anesthesiology', 'Pre-anesthesia Assessment', 'Surgical Services', 'Preoperative anesthesia risk assessment', true, false, array['anesthesiology','preoperative']::text[]),
    ('20000000-0000-4000-8000-000000000007'::uuid, 'Community Health', 'Community Health Screening', 'Preventive & Wellness', 'Preventive risk screening and health guidance', false, true, array['community-health','screening','prevention']::text[]),
    ('20000000-0000-4000-8000-000000000007'::uuid, 'Family Medicine', 'Family Medicine Consultation', 'Medical Consultation', 'First-contact care for patients and families', true, true, array['family-medicine','primary-care']::text[])
)
insert into public.hospital_services (
  hospital_id, department_id, category_id, service_name, description,
  delivery_modes, appointment_required, accepts_walk_ins, tags, operating_hours
)
select
  catalog.hospital_id,
  department.id,
  category.id,
  catalog.service_name,
  catalog.description,
  array['in_person']::text[],
  catalog.appointment_required,
  catalog.accepts_walk_ins,
  catalog.tags,
  '{"weekdays":"08:00-17:00"}'::jsonb
from service_catalog catalog
join public.hospital_departments department
  on department.hospital_id = catalog.hospital_id
 and department.department_name = catalog.department_name
join public.healthcare_service_categories category
  on category.category_name = catalog.category_name
on conflict (hospital_id, service_name) do update
set department_id = excluded.department_id,
    category_id = excluded.category_id,
    description = excluded.description,
    delivery_modes = excluded.delivery_modes,
    appointment_required = excluded.appointment_required,
    accepts_walk_ins = excluded.accepts_walk_ins,
    tags = excluded.tags,
    operating_hours = excluded.operating_hours,
    availability_status = 'available',
    last_updated = now();

end;
$$;

revoke all on function private.seed_demo_hospital_capabilities() from public;

select private.seed_demo_hospital_capabilities();

commit;
