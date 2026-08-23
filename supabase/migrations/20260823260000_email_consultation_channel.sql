-- Replace the SMS-assisted consultation contact path with email delivery.
-- Confirmed email-channel requests enqueue the existing SMTP notification
-- outbox, which is dispatched by the deployed dispatch-notifications worker.

alter table public.online_consultation_requests
  drop constraint if exists online_consultation_requests_consultation_channel_check;

update public.online_consultation_requests
set consultation_channel = 'email',
    updated_at = now()
where consultation_channel = 'sms_assisted';

alter table public.online_consultation_requests
  add constraint online_consultation_requests_consultation_channel_check
  check (consultation_channel in ('call', 'email', 'video'));

create or replace function public.review_online_consultation_request(
  target_request_id uuid,
  decision text,
  target_doctor_id uuid default null,
  target_confirmed_schedule timestamptz default null,
  target_channel text default null,
  review_notes text default null
)
returns jsonb
language plpgsql
security definer
set search_path to ''
as $function$
declare
  request_row public.online_consultation_requests;
  chosen_doctor_id uuid;
  chosen_schedule timestamptz;
  normalized_decision text := lower(btrim(coalesce(decision, '')));
  normalized_channel text := nullif(lower(btrim(coalesce(target_channel, ''))), '');
  consultation_id uuid;
begin
  -- Accept the retired wire value during a rolling client deployment, but
  -- persist and act on it as email only.
  if normalized_channel = 'sms_assisted' then
    normalized_channel := 'email';
  end if;

  if (select auth.uid()) is null or private.current_user_id() is null then
    raise exception 'An authenticated reviewer is required';
  end if;

  select * into request_row
  from public.online_consultation_requests
  where id = target_request_id
  for update;

  if not found then
    raise exception 'Online consultation request was not found';
  end if;
  if not private.is_hospital_admin_for(request_row.hospital_id) then
    raise exception 'Hospital acceptance is required for this request';
  end if;
  if request_row.request_status in ('confirmed', 'completed', 'rejected', 'cancelled') then
    raise exception 'This request is already in a terminal or confirmed state';
  end if;

  if normalized_decision = 'under_review' then
    update public.online_consultation_requests
    set request_status = 'under_review', reviewed_by = private.current_user_id(),
        reviewed_at = now(), updated_at = now()
    where id = request_row.id;
  elsif normalized_decision = 'more_information_required' then
    if nullif(btrim(review_notes), '') is null then
      raise exception 'Describe the additional information required';
    end if;
    update public.online_consultation_requests
    set request_status = 'more_information_required',
        additional_information_request = btrim(review_notes),
        reviewed_by = private.current_user_id(), reviewed_at = now(), updated_at = now()
    where id = request_row.id;
  elsif normalized_decision = 'schedule_proposed' then
    chosen_doctor_id := coalesce(target_doctor_id, request_row.requested_doctor_id);
    chosen_schedule := coalesce(target_confirmed_schedule, request_row.preferred_schedule);
    if normalized_channel is not null
      and normalized_channel not in ('call', 'email', 'video') then
      raise exception 'Choose call, email, or video consultation';
    end if;
    if chosen_doctor_id is null or chosen_schedule is null
      or not private.is_doctor_slot_available(
        chosen_doctor_id, request_row.hospital_id, 'online', chosen_schedule, null
      ) then
      raise exception 'Choose an eligible doctor and currently available proposal';
    end if;
    update public.online_consultation_requests
    set request_status = 'schedule_proposed',
        assigned_doctor_id = chosen_doctor_id,
        proposed_schedule = chosen_schedule,
        consultation_channel = coalesce(normalized_channel, consultation_channel, 'video'),
        reviewed_by = private.current_user_id(), reviewed_at = now(), updated_at = now()
    where id = request_row.id;
  elsif normalized_decision in ('rejected', 'cancelled', 'patient_unreachable', 'face_to_face_recommended') then
    if normalized_decision = 'rejected' and nullif(btrim(review_notes), '') is null then
      raise exception 'A rejection reason is required';
    end if;
    update public.online_consultation_requests
    set request_status = normalized_decision,
        rejection_reason = case when normalized_decision = 'rejected' then btrim(review_notes) else rejection_reason end,
        cancellation_reason = case when normalized_decision = 'cancelled' then btrim(review_notes) else cancellation_reason end,
        reviewed_by = private.current_user_id(), reviewed_at = now(), updated_at = now()
    where id = request_row.id;
    perform private.revoke_relationship_access(
      request_row.care_relationship_id, normalized_decision, review_notes
    );
  elsif normalized_decision = 'confirmed' then
    chosen_doctor_id := coalesce(target_doctor_id, request_row.assigned_doctor_id, request_row.requested_doctor_id);
    chosen_schedule := coalesce(
      target_confirmed_schedule, request_row.proposed_schedule, request_row.preferred_schedule
    );
    if normalized_channel is null
      or normalized_channel not in ('call', 'email', 'video') then
      raise exception 'Choose call, email, or video consultation';
    end if;
    if normalized_channel = 'email'
      and nullif(btrim(request_row.profile_email), '') is null then
      raise exception 'The patient must have a registered email address for email contact';
    end if;
    if chosen_doctor_id is null or chosen_schedule is null then
      raise exception 'A verified doctor and confirmed schedule are required';
    end if;
    if not exists (
      select 1
      from public.doctors doctor
      join public.doctor_hospital_employments employment
        on employment.doctor_id = doctor.id
       and employment.hospital_id = request_row.hospital_id
      where doctor.id = chosen_doctor_id
        and doctor.department_id = request_row.requested_department_id
        and doctor.availability_status <> 'unavailable'
        and employment.employment_status = 'active'
        and employment.is_verified
        and employment.starts_at <= now()
        and (employment.ends_at is null or employment.ends_at > now())
    ) then
      raise exception 'The selected doctor is not verified and active at this hospital';
    end if;

    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(chosen_doctor_id::text || ':' || chosen_schedule::date::text, 0)
    );
    if not private.is_doctor_slot_available(
      chosen_doctor_id, request_row.hospital_id, 'online', chosen_schedule, null
    ) then
      raise exception 'The selected appointment slot is no longer available';
    end if;

    insert into public.consultations(
      patient_id, doctor_id, hospital_id, department_id,
      consultation_type, appointment_date, status, chief_complaint,
      approved_by, approved_at
    ) values (
      request_row.patient_id, chosen_doctor_id, request_row.hospital_id,
      request_row.requested_department_id, 'online', chosen_schedule,
      'scheduled', request_row.medical_concern,
      private.current_user_id(), now()
    ) returning id into consultation_id;

    perform private.activate_relationship_access(
      request_row.care_relationship_id,
      request_row.consent_id,
      chosen_doctor_id,
      consultation_id,
      request_row.selected_records
    );

    update public.online_consultation_requests
    set request_status = 'confirmed',
        assigned_doctor_id = chosen_doctor_id,
        confirmed_schedule = chosen_schedule,
        consultation_channel = normalized_channel,
        official_consultation_id = consultation_id,
        reviewed_by = private.current_user_id(), reviewed_at = now(), updated_at = now()
    where id = request_row.id;
  else
    raise exception 'Unsupported online request decision';
  end if;

  select * into request_row
  from public.online_consultation_requests
  where id = target_request_id;

  return jsonb_build_object(
    'request_id', request_row.id,
    'reference_number', request_row.reference_number,
    'status', request_row.request_status,
    'consultation_id', request_row.official_consultation_id,
    'assigned_doctor_id', request_row.assigned_doctor_id,
    'confirmed_schedule', request_row.confirmed_schedule,
    'channel', request_row.consultation_channel,
    'slot_reserved', request_row.official_consultation_id is not null
  );
end
$function$;

revoke all on function public.review_online_consultation_request(
  uuid, text, uuid, timestamptz, text, text
) from public, anon;
grant execute on function public.review_online_consultation_request(
  uuid, text, uuid, timestamptz, text, text
) to authenticated, service_role;

create or replace function private.queue_confirmed_consultation_email()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  recipient_auth_id uuid;
  queued_notification_id uuid;
  notification_message text;
  notification_key text := 'online-consultation-confirmed-email:' || new.id::text;
begin
  if new.request_status <> 'confirmed'
    or new.consultation_channel <> 'email'
    or (
      old.request_status = 'confirmed'
      and old.consultation_channel = 'email'
    ) then
    return new;
  end if;

  select app_user.auth_user_id into recipient_auth_id
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where patient.id = new.patient_id;

  if recipient_auth_id is null then
    raise exception 'The confirmed patient has no registered email account';
  end if;

  notification_message := format(
    'Your online consultation request %s is confirmed for %s. The hospital will contact you through your registered email address.',
    new.reference_number,
    to_char(new.confirmed_schedule at time zone 'Asia/Manila', 'FMMonth DD, YYYY at HH12:MI AM')
  );

  insert into public.notifications(
    user_id, title, message, notification_type, reference_id,
    data, action_path, dedupe_key
  ) values (
    recipient_auth_id,
    'Online consultation confirmed',
    notification_message,
    'consultation_update',
    new.official_consultation_id,
    jsonb_build_object(
      'online_request_id', new.id,
      'reference_number', new.reference_number,
      'confirmed_schedule', new.confirmed_schedule,
      'consultation_channel', 'email',
      'hospital_id', new.hospital_id,
      'department_id', new.requested_department_id,
      'doctor_id', new.assigned_doctor_id
    ),
    '/patient/appointments',
    notification_key
  )
  on conflict (user_id, dedupe_key) where dedupe_key is not null
  do nothing
  returning id into queued_notification_id;

  if queued_notification_id is null then
    select notification.id into queued_notification_id
    from public.notifications notification
    where notification.user_id = recipient_auth_id
      and notification.dedupe_key = notification_key;
  end if;

  insert into public.notification_outbox(
    notification_id, user_id, channel
  ) values (
    queued_notification_id, recipient_auth_id, 'email'
  )
  on conflict (notification_id, channel) do nothing;

  return new;
end
$function$;

revoke all on function private.queue_confirmed_consultation_email()
  from public, anon, authenticated;

drop trigger if exists queue_confirmed_consultation_email_after_update
  on public.online_consultation_requests;
create trigger queue_confirmed_consultation_email_after_update
after update of request_status, consultation_channel
on public.online_consultation_requests
for each row execute function private.queue_confirmed_consultation_email();
