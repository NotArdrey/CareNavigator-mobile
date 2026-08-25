-- Doctor-patient assignments remain valid clinical context after a
-- consultation ends. Allow the assigned doctor to add a medical document
-- without broadening read access or access for ended assignments.

create or replace function private.can_create_assigned_patient_document(
  target_patient_id uuid,
  target_hospital_id uuid
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $function$
  select coalesce(exists (
    select 1
    from public.doctor_patient_assignments assignment
    where assignment.patient_id = target_patient_id
      and assignment.doctor_id = private.current_doctor_id()
      and assignment.hospital_id = target_hospital_id
      and assignment.assignment_status = 'active'
      and assignment.ended_at is null
      and private.has_active_doctor_employment(
        assignment.doctor_id,
        assignment.hospital_id
      )
  ), false)
$function$;

revoke all on function private.can_create_assigned_patient_document(uuid, uuid)
  from public, anon;
grant execute on function private.can_create_assigned_patient_document(uuid, uuid)
  to authenticated, service_role;

create or replace function private.set_medical_document_provenance()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  current_doctor public.doctors;
begin
  if new.uploaded_by is distinct from private.current_user_id() then
    raise exception 'Medical document author must match the authenticated application user';
  end if;

  select * into current_doctor
  from public.doctors doctor
  where doctor.id = private.current_doctor_id();

  if current_doctor.id is not null then
    new.author_doctor_id := current_doctor.id;
    new.hospital_id := current_doctor.hospital_id;
    new.origin_type := 'hospital_generated';
    if not (
      private.can_access_clinical_record(
        new.patient_id, current_doctor.hospital_id,
        'medical_documents', null, 'create'
      )
      or private.can_create_assigned_patient_document(
        new.patient_id, current_doctor.hospital_id
      )
    ) then
      raise exception 'The doctor is not authorized to add a document for this care relationship';
    end if;
  elsif new.patient_id = private.current_patient_id() then
    new.author_doctor_id := null;
    new.hospital_id := null;
    new.origin_type := 'patient_supplied';
  else
    raise exception 'Only the patient or an authorized treating doctor may upload this document';
  end if;
  return new;
end
$function$;

create or replace function private.can_upload_patient_storage(
  object_name text,
  object_bucket text
)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  folder text := (storage.foldername(object_name))[1];
  target_patient_id uuid;
  doctor_row public.doctors;
  category text;
begin
  if folder is null
    or folder !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return false;
  end if;
  target_patient_id := folder::uuid;
  if target_patient_id = private.current_patient_id() then return true; end if;

  select * into doctor_row
  from public.doctors doctor
  where doctor.id = private.current_doctor_id();
  if doctor_row.id is null then return false; end if;

  category := case
    when object_bucket in ('laboratory-results', 'scanned-medical-results') then 'laboratory_results'
    when object_bucket = 'prescriptions' then 'prescriptions'
    else 'medical_documents'
  end;

  if category = 'medical_documents'
    and private.can_create_assigned_patient_document(
      target_patient_id, doctor_row.hospital_id
    ) then
    return true;
  end if;

  return private.can_access_clinical_record(
    target_patient_id, doctor_row.hospital_id, category, null, 'create'
  );
end
$function$;

drop policy if exists medical_documents_scoped_insert
  on public.medical_documents;
create policy medical_documents_scoped_insert
on public.medical_documents for insert to authenticated
with check (
  (
    patient_id = private.current_patient_id()
    and uploaded_by = private.current_user_id()
    and author_doctor_id is null
    and origin_type = 'patient_supplied'
  )
  or (
    author_doctor_id = private.current_doctor_id()
    and uploaded_by = private.current_user_id()
    and hospital_id is not null
    and (
      private.can_access_clinical_record(
        patient_id, hospital_id, 'medical_documents', null, 'create'
      )
      or private.can_create_assigned_patient_document(patient_id, hospital_id)
    )
  )
);
