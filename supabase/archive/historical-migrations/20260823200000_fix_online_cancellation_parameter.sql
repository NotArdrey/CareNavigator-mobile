create or replace function public.cancel_online_consultation_request(
  target_request_id uuid,
  cancellation_reason text
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  request_row public.online_consultation_requests;
  normalized_reason text := nullif(btrim($2), '');
begin
  select * into request_row
  from public.online_consultation_requests
  where id = target_request_id
  for update;

  if not found
    or request_row.patient_id is distinct from private.current_patient_id()
    or request_row.submitted_by is distinct from private.current_user_id() then
    raise exception 'The online request was not found for the current patient';
  end if;
  if request_row.request_status in (
    'completed', 'rejected', 'cancelled', 'no_show', 'in_progress'
  ) then
    raise exception 'This online request can no longer be cancelled';
  end if;
  if normalized_reason is null then
    raise exception 'A cancellation reason is required';
  end if;

  update public.online_consultation_requests request
  set request_status = 'cancelled',
      cancellation_reason = normalized_reason,
      updated_at = now()
  where request.id = request_row.id;

  if request_row.official_consultation_id is not null then
    update public.consultations consultation
    set status = 'cancelled', updated_at = now()
    where consultation.id = request_row.official_consultation_id
      and consultation.status in ('pending', 'approved', 'scheduled');
  end if;

  perform private.revoke_relationship_access(
    request_row.care_relationship_id, 'cancelled', normalized_reason
  );

  return jsonb_build_object(
    'request_id', request_row.id,
    'reference_number', request_row.reference_number,
    'status', 'cancelled'
  );
end
$function$;

revoke all on function public.cancel_online_consultation_request(uuid, text)
  from public, anon;
grant execute on function public.cancel_online_consultation_request(uuid, text)
  to authenticated, service_role;
