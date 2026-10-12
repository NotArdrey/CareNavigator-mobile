-- Remove the remaining legacy global patient-linking RPC overload.
-- Patient identity resolution must begin from a patient-initiated request,
-- verified referral, or explicitly authorized administrative workflow.

drop function if exists public.search_existing_patients(text);
drop function if exists public.link_existing_patient(text);
drop function if exists public.link_existing_patient(uuid);
