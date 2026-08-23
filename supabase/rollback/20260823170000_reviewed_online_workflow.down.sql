-- Operational rollback for the reviewed-online pilot.
--
-- This deliberately preserves requests, consent, grants, provenance, and audit
-- history. Disabling the hospital flag sends future online bookings through the
-- legacy consultation path retained by public.book_consultation.

begin;

lock table public.online_consultation_requests in share row exclusive mode;

do $block$
declare
  unresolved_count bigint;
begin
  select count(*)
  into unresolved_count
  from public.online_consultation_requests
  where request_status not in (
    'completed', 'patient_unreachable', 'rejected', 'cancelled', 'no_show',
    'face_to_face_recommended'
  );

  if unresolved_count > 0 then
    raise exception
      'Reviewed-online rollback stopped: % non-terminal request(s) require reconciliation',
      unresolved_count;
  end if;
end
$block$;

update public.hospitals
set online_request_workflow_enabled = false,
    updated_at = now()
where online_request_workflow_enabled;

commit;
