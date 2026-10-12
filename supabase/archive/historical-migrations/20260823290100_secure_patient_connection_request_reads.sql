-- Participant-only visibility for pending directory connection requests.

create index if not exists patient_connection_requests_patient_queue_idx
  on public.patient_connection_requests(patient_id, status, requested_at desc);

create index if not exists patient_connection_requests_hospital_queue_idx
  on public.patient_connection_requests(hospital_id, status, requested_at desc);

create index if not exists patient_connection_requests_requester_idx
  on public.patient_connection_requests(requested_by);

grant select on table public.patient_connection_requests to authenticated;

drop policy if exists patient_connection_requests_participant_read
  on public.patient_connection_requests;
create policy patient_connection_requests_participant_read
on public.patient_connection_requests
for select
to authenticated
using (
  patient_id = private.current_patient_id()
  or doctor_id = private.current_doctor_id()
  or private.is_hospital_admin_for(hospital_id)
);
