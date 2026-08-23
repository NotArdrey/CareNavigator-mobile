-- Doctor-uploaded lab results and prescription documents receive a
-- preliminary Groq summary. The original file remains the clinical source of
-- truth and the summary is intentionally kept separate from confirmed records.

alter table public.medical_documents
  add column if not exists ai_summary text,
  add column if not exists ai_extracted_data jsonb,
  add column if not exists ai_analysis_status text not null default 'not_requested',
  add column if not exists ai_analysis_error text,
  add column if not exists ai_analyzed_at timestamptz;

do $block$
begin
  if not exists (
    select 1
    from pg_constraint
    where conname = 'medical_documents_ai_analysis_status_check'
      and conrelid = 'public.medical_documents'::regclass
  ) then
    alter table public.medical_documents
      add constraint medical_documents_ai_analysis_status_check
      check (
        ai_analysis_status in (
          'not_requested', 'pending', 'processing', 'completed', 'failed'
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
  if new.document_type in ('lab_result', 'prescription')
    and new.author_doctor_id is null then
    raise exception 'Only an authorized treating doctor may upload lab results or prescriptions';
  end if;

  if new.document_type in ('lab_result', 'prescription') then
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

drop trigger if exists zz_set_medical_document_ai_state_before_insert
  on public.medical_documents;
create trigger zz_set_medical_document_ai_state_before_insert
before insert on public.medical_documents
for each row execute function private.set_medical_document_ai_state();

comment on column public.medical_documents.ai_summary is
  'Preliminary Groq-generated summary of a doctor-uploaded document; not a diagnosis or confirmed interpretation.';
comment on column public.medical_documents.ai_extracted_data is
  'Structured facts extracted by Groq from the uploaded source document.';
