-- Adds a transparent, non-operational Primary Hospital record so public
-- directory and map experiences can represent every general hospital level.
-- This record is intentionally unavailable and must never be treated as a
-- real care destination.

do $$
declare
  primary_classification_id uuid;
  demo_hospital_id uuid;
  existing_hospital_id uuid;
begin
  select id
  into primary_classification_id
  from public.hospital_classifications
  where classification_name = 'Primary Hospital'
  limit 1;

  if primary_classification_id is null then
    raise exception 'Primary Hospital classification is required';
  end if;

  select id
  into existing_hospital_id
  from public.hospitals
  where hospital_name = 'CareNavigator Primary Hospital (Demo)'
    and address = 'Demo Site, San Fernando City, Pampanga'
  limit 1;

  demo_hospital_id := coalesce(existing_hospital_id, gen_random_uuid());

  insert into public.hospitals (
    id,
    hospital_name,
    classification_id,
    address,
    city,
    province,
    latitude,
    longitude,
    description,
    operating_hours,
    operating_status,
    verification_status,
    verification_notes,
    verification_decided_at,
    updated_at
  ) values (
    demo_hospital_id,
    'CareNavigator Primary Hospital (Demo)',
    primary_classification_id,
    'Demo Site, San Fernando City, Pampanga',
    'San Fernando City',
    'Pampanga',
    15.0343,
    120.6844,
    'Demonstration record only. This is not a real care location and must not be used for medical decisions.',
    jsonb_build_object(
      'emergency', 'Not operational — demo record',
      'outpatient', 'Not operational — demo record'
    ),
    'limited',
    'verified',
    'Synthetic demo record for Primary Hospital directory and map coverage. Not a real facility.',
    now(),
    now()
  )
  on conflict (id) do update set
    hospital_name = excluded.hospital_name,
    classification_id = excluded.classification_id,
    address = excluded.address,
    city = excluded.city,
    province = excluded.province,
    latitude = excluded.latitude,
    longitude = excluded.longitude,
    description = excluded.description,
    operating_hours = excluded.operating_hours,
    operating_status = excluded.operating_status,
    verification_status = excluded.verification_status,
    verification_notes = excluded.verification_notes,
    verification_decided_at = excluded.verification_decided_at,
    updated_at = excluded.updated_at;

  insert into public.emergency_room_status (
    hospital_id,
    status,
    available_beds,
    current_patient_count,
    maximum_capacity,
    last_updated
  ) values (
    demo_hospital_id,
    'temporarily_closed',
    0,
    0,
    0,
    now()
  )
  on conflict (hospital_id) do update set
    status = excluded.status,
    available_beds = excluded.available_beds,
    current_patient_count = excluded.current_patient_count,
    maximum_capacity = excluded.maximum_capacity,
    last_updated = excluded.last_updated;

  insert into public.hospital_departments (
    hospital_id,
    department_name,
    description,
    availability_status,
    updated_at
  ) values
    (
      demo_hospital_id,
      'General Medicine',
      'Demonstration department for primary-level general care.',
      'unavailable',
      now()
    ),
    (
      demo_hospital_id,
      'Emergency Medicine',
      'Demonstration department; no live emergency service is provided.',
      'unavailable',
      now()
    ),
    (
      demo_hospital_id,
      'Pediatrics',
      'Demonstration department for basic pediatric care.',
      'unavailable',
      now()
    )
  on conflict (hospital_id, department_name) do update set
    description = excluded.description,
    availability_status = excluded.availability_status,
    updated_at = excluded.updated_at;

  insert into public.hospital_services (
    hospital_id,
    service_name,
    description,
    availability_status,
    operating_hours,
    delivery_modes,
    appointment_required,
    accepts_walk_ins,
    tags,
    last_updated,
    updated_at
  ) values
    (
      demo_hospital_id,
      'General Consultation',
      'Demonstration service only; not available for booking.',
      'unavailable',
      '{}'::jsonb,
      array['in_person'],
      false,
      false,
      array['demo', 'primary-care'],
      now(),
      now()
    ),
    (
      demo_hospital_id,
      'Basic Laboratory',
      'Demonstration service only; no live laboratory service is provided.',
      'unavailable',
      '{}'::jsonb,
      array['in_person'],
      false,
      false,
      array['demo', 'laboratory'],
      now(),
      now()
    )
  on conflict (hospital_id, service_name) do update set
    description = excluded.description,
    availability_status = excluded.availability_status,
    operating_hours = excluded.operating_hours,
    delivery_modes = excluded.delivery_modes,
    appointment_required = excluded.appointment_required,
    accepts_walk_ins = excluded.accepts_walk_ins,
    tags = excluded.tags,
    last_updated = excluded.last_updated,
    updated_at = excluded.updated_at;

  insert into public.hospital_facility_status (
    hospital_id,
    facility_type,
    status,
    available_units,
    notes,
    last_updated
  ) values
    (
      demo_hospital_id,
      'laboratory',
      'unavailable',
      0,
      'Synthetic demo status — not a live facility.',
      now()
    ),
    (
      demo_hospital_id,
      'pharmacy',
      'unavailable',
      0,
      'Synthetic demo status — not a live facility.',
      now()
    )
  on conflict (hospital_id, facility_type) do update set
    status = excluded.status,
    available_units = excluded.available_units,
    notes = excluded.notes,
    last_updated = excluded.last_updated;
end
$$;
