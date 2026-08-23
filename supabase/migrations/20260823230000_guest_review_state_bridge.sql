-- Preserve the existing guarded guest status machine: approval must be
-- recorded before the official scheduled consultation transition.

create or replace function private.mark_guest_request_approved_for_consultation()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.guest_request_id is not null
    and new.status in ('approved', 'scheduled') then
    update public.guest_consultation_requests request
    set request_status = 'approved',
        assigned_doctor_id = new.doctor_id,
        reviewed_by = coalesce(request.reviewed_by, private.current_user_id()),
        reviewed_at = coalesce(request.reviewed_at, now()),
        identity_review_status = 'verified',
        updated_at = now()
    where request.id = new.guest_request_id
      and request.request_status in ('otp_verified', 'pending_doctor_review');
  end if;
  return new;
end
$function$;

revoke all on function private.mark_guest_request_approved_for_consultation()
  from public, anon, authenticated;

drop trigger if exists mark_guest_request_approved_before_consultation
  on public.consultations;
create trigger mark_guest_request_approved_before_consultation
before insert on public.consultations
for each row execute function private.mark_guest_request_approved_for_consultation();
