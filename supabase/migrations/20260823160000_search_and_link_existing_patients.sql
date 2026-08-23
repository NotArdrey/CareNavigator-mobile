-- Retired before deployment: name/email patient discovery and doctor-created
-- links conflict with consent-gated care relationships. Identity resolution
-- must start from a patient-initiated request, verified referral, or explicitly
-- authorized administrative workflow.

drop function if exists public.search_existing_patients(text);
drop function if exists public.link_existing_patient(text);
drop function if exists public.link_existing_patient(uuid);
