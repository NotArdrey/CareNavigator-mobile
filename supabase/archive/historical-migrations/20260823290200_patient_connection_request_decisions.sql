-- Patients can review and decide clinician directory connection requests.
-- Approval creates a time-bounded, consent-backed care relationship; rejection
-- does not expose any clinical data.

create or replace function private.enrich_connection_request_notification()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  clinician_name text;
  facility_name text;
  request_status text;
  request_expires_at timestamptz;
begin
  if new.notification_type <> 'access_request' or new.reference_id is null then
    return new;
  end if;

  select
    nullif(pg_catalog.btrim(pg_catalog.concat_ws(
      ' ', app_user.first_name, app_user.last_name
    )), ''),
    hospital.hospital_name,
    request.status,
    request.expires_at
  into clinician_name, facility_name, request_status, request_expires_at
  from public.patient_connection_requests request
  join public.doctors doctor on doctor.id = request.doctor_id
  join public.users app_user on app_user.id = doctor.user_id
  join public.hospitals hospital on hospital.id = request.hospital_id
  where request.id = new.reference_id;

  new.data := coalesce(new.data, '{}'::jsonb) || pg_catalog.jsonb_build_object(
    'connection_request_id', new.reference_id,
    'doctor_display_name', coalesce(clinician_name, 'Verified clinician'),
    'hospital_name', coalesce(facility_name, 'Verified healthcare facility'),
    'status', request_status,
    'expires_at', request_expires_at
  );
  new.title := 'Care connection request';
  new.message := pg_catalog.format(
    '%s from %s would like to connect with your care account. Review the request before sharing access.',
    coalesce(clinician_name, 'A verified clinician'),
    coalesce(facility_name, 'a verified healthcare facility')
  );
  return new;
end
$function$;

revoke all on function private.enrich_connection_request_notification()
  from public, anon, authenticated;

drop trigger if exists enrich_connection_request_notification_before_write
  on public.notifications;
create trigger enrich_connection_request_notification_before_write
before insert or update of reference_id, notification_type, data
on public.notifications
for each row execute function private.enrich_connection_request_notification();

update public.notifications notification
set title = 'Care connection request',
    message = pg_catalog.format(
      '%s from %s would like to connect with your care account. Review the request before sharing access.',
      coalesce(
        nullif(pg_catalog.btrim(pg_catalog.concat_ws(
          ' ', app_user.first_name, app_user.last_name
        )), ''),
        'A verified clinician'
      ),
      coalesce(hospital.hospital_name, 'a verified healthcare facility')
    ),
    data = coalesce(notification.data, '{}'::jsonb)
  || pg_catalog.jsonb_build_object(
    'connection_request_id', request.id,
    'doctor_display_name', coalesce(
      nullif(pg_catalog.btrim(pg_catalog.concat_ws(
        ' ', app_user.first_name, app_user.last_name
      )), ''),
      'Verified clinician'
    ),
    'hospital_name', coalesce(
      hospital.hospital_name,
      'Verified healthcare facility'
    ),
    'status', request.status,
    'expires_at', request.expires_at
  )
from public.patient_connection_requests request
join public.doctors doctor on doctor.id = request.doctor_id
join public.users app_user on app_user.id = doctor.user_id
join public.hospitals hospital on hospital.id = request.hospital_id
where notification.notification_type = 'access_request'
  and notification.reference_id = request.id;

create or replace function public.decide_patient_connection_request(
  target_request_id uuid,
  approve_request boolean
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  request_row public.patient_connection_requests;
  patient_row public.patients;
  relationship_id uuid;
  consent_id uuid;
  access_expires_at timestamptz := now() + interval '90 days';
  patient_auth_id uuid := (select auth.uid());
  doctor_auth_id uuid;
  decision_status text;
  all_categories text[] := array[
    'consultations', 'medical_records', 'diagnoses', 'prescriptions',
    'laboratory_requests', 'laboratory_results', 'medical_documents',
    'clinical_notes', 'allergies_medications', 'treatment_plans'
  ]::text[];
begin
  if patient_auth_id is null
    or private.current_user_id() is null
    or private.current_patient_id() is null then
    raise exception 'An authenticated patient account is required';
  end if;

  select * into request_row
  from public.patient_connection_requests request
  where request.id = target_request_id
    and request.patient_id = private.current_patient_id()
  for update;

  if not found then
    raise exception 'This connection request was not found';
  end if;
  if request_row.status <> 'requested' then
    raise exception 'This connection request has already been decided';
  end if;
  if request_row.expires_at <= now() then
    raise exception 'This connection request has expired';
  end if;

  select * into patient_row
  from public.patients patient
  where patient.id = request_row.patient_id;

  if approve_request then
    if not exists (
      select 1
      from public.doctor_hospital_employments employment
      where employment.doctor_id = request_row.doctor_id
        and employment.hospital_id = request_row.hospital_id
        and employment.employment_status = 'active'
        and employment.is_verified
        and employment.starts_at <= now()
        and (employment.ends_at is null or employment.ends_at > now())
    ) then
      raise exception 'This clinician is no longer verified at the facility';
    end if;

    insert into public.patient_care_relationships(
      patient_id, hospital_id, doctor_id, relationship_type, purpose,
      status, requested_at, expires_at, created_by
    ) values (
      request_row.patient_id,
      request_row.hospital_id,
      request_row.doctor_id,
      'ongoing_outpatient_care',
      'clinician_patient_connection',
      'requested',
      request_row.requested_at,
      access_expires_at,
      request_row.requested_by
    ) returning id into relationship_id;

    insert into public.patient_consents(
      patient_id, consent_type, consent_version, is_granted, granted_at,
      captured_by, metadata, care_relationship_id, source_hospital_id,
      receiving_hospital_id, purpose, categories, permitted_actions,
      record_selection_mode, expires_at, granted_by, version_sequence
    ) values (
      request_row.patient_id,
      'clinician_connection_access',
      relationship_id::text,
      true,
      now(),
      patient_auth_id,
      pg_catalog.jsonb_build_object(
        'connection_request_id', request_row.id,
        'patient_decision', 'approved',
        'access_duration_days', 90
      ),
      relationship_id,
      coalesce(patient_row.primary_hospital_id, request_row.hospital_id),
      request_row.hospital_id,
      'clinician_patient_connection',
      all_categories,
      array['view', 'download', 'create']::text[],
      'categories',
      access_expires_at,
      private.current_user_id(),
      1
    ) returning id into consent_id;

    perform private.activate_relationship_access(
      relationship_id,
      consent_id,
      request_row.doctor_id,
      null,
      '[]'::jsonb
    );
    decision_status := 'approved';
  else
    decision_status := 'rejected';
  end if;

  update public.patient_connection_requests request
  set status = decision_status,
      decided_at = now(),
      updated_at = now()
  where request.id = request_row.id;

  update public.notifications notification
  set is_read = true,
      data = coalesce(notification.data, '{}'::jsonb)
        || pg_catalog.jsonb_build_object(
          'status', decision_status,
          'access_expires_at', case
            when approve_request then access_expires_at
            else null
          end
        )
  where notification.notification_type = 'access_request'
    and notification.reference_id = request_row.id
    and notification.user_id = patient_auth_id;

  select app_user.auth_user_id into doctor_auth_id
  from public.users app_user
  where app_user.id = request_row.requested_by;

  if doctor_auth_id is not null then
    insert into public.notifications(
      user_id, title, message, notification_type, reference_id, data
    ) values (
      doctor_auth_id,
      case when approve_request
        then 'Patient connection accepted'
        else 'Patient connection declined'
      end,
      case when approve_request
        then 'The patient accepted your connection request. You can now access their authorized care workspace.'
        else 'The patient declined your connection request. No account access was granted.'
      end,
      'access_request_decision',
      request_row.id,
      pg_catalog.jsonb_build_object(
        'connection_request_id', request_row.id,
        'status', decision_status
      )
    );
  end if;

  return pg_catalog.jsonb_build_object(
    'request_id', request_row.id,
    'status', decision_status,
    'access_expires_at', case when approve_request then access_expires_at else null end
  );
end
$function$;

revoke all on function public.decide_patient_connection_request(uuid, boolean)
  from public, anon;
grant execute on function public.decide_patient_connection_request(uuid, boolean)
  to authenticated, service_role;
