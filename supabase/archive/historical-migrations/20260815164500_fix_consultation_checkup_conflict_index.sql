drop index if exists public.medical_records_consultation_checkup_unique;

create unique index medical_records_consultation_checkup_unique
  on public.medical_records (consultation_id)
  where record_type = 'consultation_checkup';

comment on index public.medical_records_consultation_checkup_unique is
  'Supports idempotent consultation-completion checkup upserts; NULL consultation IDs remain non-conflicting.';
