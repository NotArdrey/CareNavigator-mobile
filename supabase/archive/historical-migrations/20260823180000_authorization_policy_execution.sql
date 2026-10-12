-- RLS expressions execute with the querying role and therefore require
-- EXECUTE on their predicate functions. The private schema is not exposed by
-- PostgREST; these grants permit policy evaluation without creating RPCs.

grant execute on function private.valid_record_category(text)
  to authenticated, service_role;
grant execute on function private.has_active_doctor_employment(uuid, uuid)
  to authenticated, service_role;
grant execute on function private.is_active_care_relationship(uuid, uuid, uuid, uuid)
  to authenticated, service_role;
grant execute on function private.can_access_clinical_record(uuid, uuid, text, uuid, text)
  to authenticated, service_role;
grant execute on function private.can_access_patient(uuid)
  to authenticated, service_role;
grant execute on function private.can_access_online_request(uuid)
  to authenticated, service_role;
grant execute on function private.can_access_patient_storage(text, text, text)
  to authenticated, service_role;
grant execute on function private.can_upload_patient_storage(text, text)
  to authenticated, service_role;

drop policy if exists clinical_record_quarantine_no_client_access
  on public.clinical_record_quarantine;
create policy clinical_record_quarantine_no_client_access
on public.clinical_record_quarantine
as restrictive
for all
to authenticated
using (false)
with check (false);
