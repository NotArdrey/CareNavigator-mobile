-- Keep the consultation pilot explicitly synthetic. Relationships use the
-- stable hospital ID, so replacing directory identity does not disturb access,
-- appointments, staff, departments, or the reviewed-online workflow.

update public.hospitals
set hospital_name = 'CareNavigator Regional Hospital (Demo)',
    address = 'Demo Site, City of San Fernando, Pampanga',
    city = 'City of San Fernando',
    province = 'Pampanga',
    latitude = 15.0300,
    longitude = 120.6800,
    contact_number = null,
    emergency_contact_number = null,
    email = null,
    description =
      'Synthetic CareNavigator hospital used to demonstrate consultation workflows. It is not a real care facility or affiliated provider.',
    operating_hours = jsonb_build_object(
      'emergency', 'Demo workflow only',
      'outpatient', 'Demo workflow only'
    ),
    operating_status = 'limited',
    image_url =
      'https://placehold.co/1280x800/0f766e/ffffff/png?text=CareNavigator+Regional+Hospital',
    image_attribution = 'CareNavigator demonstration placeholder',
    image_source_url = 'https://placehold.co/',
    directory_source_url = null,
    directory_verified_at = null,
    verification_notes =
      'Synthetic demo hospital for application workflow validation; not a real facility.',
    online_request_workflow_enabled = true,
    updated_at = now()
where id = '20000000-0000-4000-8000-000000000001'::uuid;
