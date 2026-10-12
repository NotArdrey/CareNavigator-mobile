-- Store structured metadata for laboratory, imaging, pathology, and other
-- diagnostic result documents without changing historical lab_result rows.

alter table public.medical_documents
  add column if not exists result_category text,
  add column if not exists test_procedure_name text,
  add column if not exists performed_or_collected_date date,
  add column if not exists result_date date,
  add column if not exists facility text,
  add column if not exists requesting_doctor text,
  add column if not exists findings_impression text,
  add column if not exists notes text;

do $block$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'medical_documents_result_category_check'
      and conrelid = 'public.medical_documents'::regclass
  ) then
    alter table public.medical_documents
      add constraint medical_documents_result_category_check
      check (
        result_category is null
        or result_category in (
          'laboratory', 'x_ray', 'ct_scan', 'mri', 'ultrasound', 'ecg',
          'pathology', 'other'
        )
      );
  end if;

  if not exists (
    select 1
    from pg_constraint
    where conname = 'medical_documents_diagnostic_result_details_check'
      and conrelid = 'public.medical_documents'::regclass
  ) then
    alter table public.medical_documents
      add constraint medical_documents_diagnostic_result_details_check
      check (
        document_type <> 'diagnostic_result'
        or (
          result_category is not null
          and nullif(btrim(test_procedure_name), '') is not null
          and performed_or_collected_date is not null
          and result_date is not null
          and result_date >= performed_or_collected_date
          and nullif(btrim(facility), '') is not null
          and nullif(btrim(requesting_doctor), '') is not null
        )
      );
  end if;
end
$block$;

create or replace function private.set_medical_document_ai_state()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  -- This trigger is named to run after the provenance trigger, which fills
  -- author_doctor_id for an authorized doctor upload.
  if new.document_type in ('lab_result', 'diagnostic_result', 'prescription')
    and new.author_doctor_id is null then
    raise exception 'Only an authorized treating doctor may upload diagnostic results or prescriptions';
  end if;

  if new.document_type in ('lab_result', 'diagnostic_result', 'prescription') then
    new.ai_analysis_status := 'pending';
  else
    new.ai_analysis_status := 'not_requested';
  end if;
  new.ai_summary := null;
  new.ai_extracted_data := null;
  new.ai_analysis_error := null;
  new.ai_analyzed_at := null;
  return new;
end
$function$;

comment on column public.medical_documents.result_category is
  'Diagnostic result category: laboratory, x_ray, ct_scan, mri, ultrasound, ecg, pathology, or other.';
comment on column public.medical_documents.test_procedure_name is
  'Name of the diagnostic test or procedure.';
comment on column public.medical_documents.performed_or_collected_date is
  'Date the procedure was performed or the specimen was collected.';
comment on column public.medical_documents.result_date is
  'Date the diagnostic result was issued.';
comment on column public.medical_documents.facility is
  'Facility that performed or issued the diagnostic result.';
comment on column public.medical_documents.requesting_doctor is
  'Doctor who requested the diagnostic test or procedure.';
comment on column public.medical_documents.findings_impression is
  'Optional findings or impression transcribed from the diagnostic result.';
comment on column public.medical_documents.notes is
  'Optional uploader notes about the diagnostic result.';
