-- Patients may rename or delete only the lab-result and prescription files
-- they uploaded themselves. Care-team files remain readable but immutable to
-- the patient, and storage mutations are restricted to the original uploader.

create or replace function private.is_storage_upload_owner(object_name text)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    (select auth.uid()) is not null
    and private.current_user_id() is not null
    and (storage.foldername(object_name))[2] = (select auth.uid())::text,
    false
  )
$function$;

revoke all on function private.is_storage_upload_owner(text)
  from public, anon, authenticated;

drop policy if exists "cnph_patient_documents_participant_update"
  on storage.objects;
create policy "cnph_patient_documents_uploader_update"
on storage.objects for update to authenticated
using (
  bucket_id = any (array[
    'laboratory-results',
    'scanned-medical-results',
    'medical-documents',
    'prescriptions',
    'consultation-attachments'
  ]::text[])
  and private.is_storage_upload_owner(name)
)
with check (
  bucket_id = any (array[
    'laboratory-results',
    'scanned-medical-results',
    'medical-documents',
    'prescriptions',
    'consultation-attachments'
  ]::text[])
  and private.is_storage_upload_owner(name)
);

drop policy if exists "cnph_patient_documents_participant_delete"
  on storage.objects;
create policy "cnph_patient_documents_uploader_delete"
on storage.objects for delete to authenticated
using (
  bucket_id = any (array[
    'laboratory-results',
    'scanned-medical-results',
    'medical-documents',
    'prescriptions',
    'consultation-attachments'
  ]::text[])
  and private.is_storage_upload_owner(name)
);

create or replace function public.rename_own_medical_document(
  target_document_id uuid,
  target_title text
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if private.current_role() <> 'patient'
    or target_document_id is null
    or nullif(btrim(target_title), '') is null
    or length(btrim(target_title)) > 180 then
    raise exception 'A patient file and a title of 1 to 180 characters are required';
  end if;

  update public.medical_documents
  set title = btrim(target_title)
  where id = target_document_id
    and uploaded_by = private.current_user_id()
    and patient_id = private.current_patient_id()
    and document_type in ('lab_result', 'prescription');

  if not found then
    raise exception 'Patients may edit only lab or prescription files they uploaded themselves';
  end if;
end;
$function$;

create or replace function public.delete_own_medical_document(
  target_document_id uuid
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  deleted_document public.medical_documents;
begin
  if private.current_role() <> 'patient' or target_document_id is null then
    raise exception 'An authenticated patient file is required';
  end if;

  delete from public.medical_documents
  where id = target_document_id
    and uploaded_by = private.current_user_id()
    and patient_id = private.current_patient_id()
    and document_type in ('lab_result', 'prescription')
  returning * into deleted_document;

  if not found then
    raise exception 'Patients may delete only lab or prescription files they uploaded themselves';
  end if;

  return jsonb_build_object(
    'storage_bucket', deleted_document.storage_bucket,
    'storage_path', deleted_document.storage_path
  );
end;
$function$;

revoke all on function public.rename_own_medical_document(uuid, text)
  from public, anon;
grant execute on function public.rename_own_medical_document(uuid, text)
  to authenticated, service_role;

revoke all on function public.delete_own_medical_document(uuid)
  from public, anon;
grant execute on function public.delete_own_medical_document(uuid)
  to authenticated, service_role;
