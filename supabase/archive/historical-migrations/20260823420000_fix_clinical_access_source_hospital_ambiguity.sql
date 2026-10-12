-- Avoid a PL/pgSQL variable/column name collision when recording access to
-- secure clinical files. The function contract and authorization behavior
-- remain unchanged.

create or replace function public.record_clinical_access(
  target_resource_type text,
  target_resource_id uuid,
  target_action text
)
returns bigint
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_patient_id uuid;
  record_source_hospital_id uuid;
  target_category text;
  matching_grant public.patient_access_grants;
  created_log_id bigint;
begin
  if private.current_user_id() is null then
    raise exception 'An active account is required';
  end if;
  if target_action not in ('view', 'download') then
    raise exception 'Clinical access action must be view or download';
  end if;

  case target_resource_type
    when 'medical_record' then
      select record.patient_id, record.hospital_id, 'medical_records'
      into target_patient_id, record_source_hospital_id, target_category
      from public.medical_records record
      where record.id = target_resource_id;
    when 'laboratory_result' then
      select result.patient_id, result.hospital_id, 'laboratory_results'
      into target_patient_id, record_source_hospital_id, target_category
      from public.laboratory_results result
      where result.id = target_resource_id;
    when 'medical_document' then
      select document.patient_id, document.hospital_id, 'medical_documents'
      into target_patient_id, record_source_hospital_id, target_category
      from public.medical_documents document
      where document.id = target_resource_id;
    when 'consultation_attachment' then
      select coalesce(attachment.patient_id, consultation.patient_id),
             consultation.hospital_id, 'consultations'
      into target_patient_id, record_source_hospital_id, target_category
      from public.consultation_attachments attachment
      join public.consultations consultation
        on consultation.id = attachment.consultation_id
      where attachment.id = target_resource_id;
    when 'prescription' then
      select prescription.patient_id, prescription.hospital_id, 'prescriptions'
      into target_patient_id, record_source_hospital_id, target_category
      from public.prescriptions prescription
      where prescription.id = target_resource_id;
    when 'diagnosis' then
      select diagnosis.patient_id, diagnosis.hospital_id, 'diagnoses'
      into target_patient_id, record_source_hospital_id, target_category
      from public.diagnoses diagnosis
      where diagnosis.id = target_resource_id;
    when 'laboratory_request' then
      select request.patient_id, request.hospital_id, 'laboratory_requests'
      into target_patient_id, record_source_hospital_id, target_category
      from public.laboratory_requests request
      where request.id = target_resource_id;
    when 'treatment_plan' then
      select plan.patient_id, plan.hospital_id, 'treatment_plans'
      into target_patient_id, record_source_hospital_id, target_category
      from public.treatment_plans plan
      where plan.id = target_resource_id;
    when 'consultation' then
      select consultation.patient_id, consultation.hospital_id, 'consultations'
      into target_patient_id, record_source_hospital_id, target_category
      from public.consultations consultation
      where consultation.id = target_resource_id;
    else
      raise exception 'Unsupported clinical resource type';
  end case;

  if target_patient_id is null or not private.can_access_clinical_record(
    target_patient_id, record_source_hospital_id,
    target_category, target_resource_id, target_action
  ) then
    raise exception 'Clinical resource was not found or is not authorized for this action';
  end if;

  select grant_row.* into matching_grant
  from public.patient_access_grants grant_row
  join public.patient_access_scopes scope on scope.grant_id = grant_row.id
  where grant_row.patient_id = target_patient_id
    and grant_row.receiving_doctor_id = private.current_doctor_id()
    and (
      grant_row.source_hospital_id = record_source_hospital_id
      or (
        record_source_hospital_id is null
        and target_category = 'medical_documents'
      )
    )
    and grant_row.status = 'active'
    and grant_row.expires_at > now()
    and grant_row.revoked_at is null
    and scope.record_category = target_category
  order by grant_row.activated_at desc
  limit 1;

  insert into public.medical_record_access_logs(
    patient_id, actor_user_id, actor_role, resource_type, resource_id,
    access_type, metadata, grant_id, care_relationship_id,
    source_hospital_id, receiving_hospital_id, success
  ) values (
    target_patient_id, private.current_user_id(), private.current_role(),
    target_resource_type, target_resource_id, target_action,
    jsonb_build_object('category', target_category),
    matching_grant.id, matching_grant.care_relationship_id,
    record_source_hospital_id, matching_grant.receiving_hospital_id, true
  ) returning id into created_log_id;
  return created_log_id;
end
$function$;

