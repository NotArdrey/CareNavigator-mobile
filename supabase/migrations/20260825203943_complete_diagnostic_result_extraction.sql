-- Preserve the full, doctor-reviewed diagnostic report extraction. Fields are
-- nullable because many report types legitimately omit dates, facilities,
-- referring clinicians, reference ranges, or recommendations.

alter table public.medical_documents
  add column if not exists test_procedure_name_ai_generated boolean not null default false,
  add column if not exists performed_or_collected_date_text text,
  add column if not exists result_date_text text,
  add column if not exists patient_name_on_report text,
  add column if not exists procedure_details text,
  add column if not exists result_details text,
  add column if not exists official_findings_impression text,
  add column if not exists report_recommendations text,
  add column if not exists technical_summary text,
  add column if not exists patient_friendly_summary text,
  add column if not exists verification_notes text;

alter table public.medical_documents
  drop constraint if exists medical_documents_diagnostic_result_details_check;

alter table public.medical_documents
  add constraint medical_documents_diagnostic_result_details_check
  check (
    document_type <> 'diagnostic_result'
    or (
      result_category is not null
      and nullif(btrim(test_procedure_name), '') is not null
      and (
        performed_or_collected_date is null
        or result_date is null
        or result_date >= performed_or_collected_date
      )
    )
  );

comment on column public.medical_documents.test_procedure_name_ai_generated is
  'True only when the displayed procedure label was suggested by AI because the exact report title was missing.';
comment on column public.medical_documents.performed_or_collected_date_text is
  'Procedure or collection date exactly as printed, retained for ambiguous-date verification.';
comment on column public.medical_documents.result_date_text is
  'Result date exactly as printed, retained for ambiguous-date verification.';
comment on column public.medical_documents.patient_name_on_report is
  'Patient name visibly printed on the source report for assignment review.';
comment on column public.medical_documents.procedure_details is
  'Type-specific source details such as imaging technique/comparison, pathology specimen/grade/margins/biomarkers, or cardiac rhythm/rate/measurements.';
comment on column public.medical_documents.result_details is
  'Doctor-reviewed transcription of all readable results, values, units, reference ranges, and flags.';
comment on column public.medical_documents.official_findings_impression is
  'Doctor-reviewed report-authored findings and impression.';
comment on column public.medical_documents.report_recommendations is
  'Recommendations explicitly stated in the source report.';
comment on column public.medical_documents.technical_summary is
  'Editable technical summary produced from report-stated information.';
comment on column public.medical_documents.patient_friendly_summary is
  'Editable plain-language summary produced from report-stated information.';
comment on column public.medical_documents.verification_notes is
  'Missing, ambiguous, or unreadable source details that require human verification.';
