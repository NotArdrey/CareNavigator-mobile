begin;

-- CareNavigator keeps in-app notifications and uses email as its only
-- external delivery channel. Remove all historical/non-email outbox rows
-- before narrowing the channel constraint.
drop trigger if exists queue_notification_deliveries_after_insert
on public.notifications;

delete from public.notification_outbox where channel <> 'email';

create or replace function public.queue_notification_deliveries()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  category_enabled boolean;
begin
  if new.user_id is null then return new; end if;
  category_enabled := case
    when new.notification_type in ('consultation_update','account_activation')
      then coalesce((select consultation_updates from public.notification_preferences where user_id=new.user_id),true)
    when new.notification_type='appointment_reminder'
      then coalesce((select appointment_reminders from public.notification_preferences where user_id=new.user_id),true)
    when new.notification_type='medical_result'
      then coalesce((select medical_results from public.notification_preferences where user_id=new.user_id),true)
    when new.notification_type='prescription'
      then coalesce((select prescriptions from public.notification_preferences where user_id=new.user_id),true)
    when new.notification_type='message'
      then coalesce((select messages from public.notification_preferences where user_id=new.user_id),true)
    when new.notification_type='hospital_alert'
      then coalesce((select hospital_alerts from public.notification_preferences where user_id=new.user_id),true)
    else true
  end;
  if not category_enabled then return new; end if;

  if coalesce((
    select email_enabled from public.notification_preferences
    where user_id=new.user_id
  ),false) then
    insert into public.notification_outbox(notification_id,user_id,channel)
    values(new.id,new.user_id,'email')
    on conflict do nothing;
  end if;
  return new;
end;
$$;

alter table public.notification_preferences
  drop column if exists sms_enabled,
  drop column if exists push_enabled;

drop table if exists public.device_tokens;

alter table public.notification_outbox
  drop constraint if exists notification_outbox_channel_check;
alter table public.notification_outbox
  add constraint notification_outbox_channel_check check(channel='email');

create trigger queue_notification_deliveries_after_insert
after insert on public.notifications
for each row execute function public.queue_notification_deliveries();

-- First-time consultation identities are now verified by email OTP. A mobile
-- number remains request contact data and is never used as an auth channel.
drop policy if exists guest_requests_owner_insert
on public.guest_consultation_requests;
create policy guest_requests_owner_insert
on public.guest_consultation_requests
for insert to authenticated with check (
  submitted_by=(select auth.uid())
  and private.current_user_id() is not null
  and nullif((select auth.jwt())->>'email','') is not null
);

commit;
