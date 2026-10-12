revoke execute on function public.record_patient_checkup(uuid, jsonb, timestamptz)
  from public, anon;

grant execute on function public.record_patient_checkup(uuid, jsonb, timestamptz)
  to authenticated, service_role;
