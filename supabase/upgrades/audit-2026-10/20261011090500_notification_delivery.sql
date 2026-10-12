alter table public.notification_preferences add column if not exists medication_reminders boolean not null default true;
create table public.medication_summary_days(
  patient_id uuid not null references public.patients(id),local_date date not null,
  notification_id uuid references public.notifications(id),created_at timestamptz not null default now(),
  primary key(patient_id,local_date)
);
alter table public.medication_summary_days enable row level security;
create policy medication_summary_owner_reads on public.medication_summary_days for select to authenticated
using(patient_id=private.current_patient_id());
grant select on public.medication_summary_days to authenticated;

create or replace function private.medication_summary(target_patient uuid,target_date date,target_order uuid default null)
returns text language sql stable security definer set search_path = '' as $$
 select string_agg(concat(p.medication_name,' â€” ',p.exact_dose,'; ',p.route,'; ',
   case when p.is_prn then 'PRN: '||p.prn_reason||'; maximum daily dose: '||p.maximum_daily_dose else p.frequency end,
   '; duration: ',p.duration,case when p.instructions is not null then '; '||p.instructions else '' end),E'\n' order by p.created_at,p.id)
 from public.prescriptions p join public.prescription_orders o on o.id=p.order_id
 where p.patient_id=target_patient and o.status='issued' and p.electronically_signed_by is not null
   and ((target_order is not null and o.id=target_order) or
     (target_order is null and p.start_date<=target_date and (p.end_date is null or p.end_date>=target_date)));
$$;
revoke all on function private.medication_summary(uuid,date,uuid) from public;

create or replace function public.queue_notification_deliveries()
returns trigger language plpgsql security definer set search_path = '' as $$
declare pref public.notification_preferences; allowed boolean;
begin
 if new.user_id is null then return new; end if;
 select * into pref from public.notification_preferences where user_id=new.user_id;
 allowed:=case new.notification_type
   when 'consultation_update' then coalesce(pref.consultation_updates,true)
   when 'account_activation' then coalesce(pref.consultation_updates,true)
   when 'appointment_reminder' then coalesce(pref.appointment_reminders,true)
   when 'medical_result' then coalesce(pref.medical_results,true)
   when 'prescription' then coalesce(pref.prescriptions,true)
   when 'medication_reminder' then coalesce(pref.medication_reminders,true)
   when 'message' then coalesce(pref.messages,true)
   when 'hospital_alert' then coalesce(pref.hospital_alerts,true) else true end;
 if coalesce((new.data->>'authorized_manual_email')::boolean,false) or (allowed and coalesce(pref.email_enabled,false)) then
  insert into public.notification_outbox(notification_id,user_id,channel) values(new.id,new.user_id,'email') on conflict do nothing;
 end if;
 return new;
end $$;

create or replace function private.notification_delivery_status(notification_id uuid)
returns text language sql stable security definer set search_path = '' as $$
 select coalesce((select case o.status when 'delivered' then 'sent' when 'failed' then 'failed'
   when 'cancelled' then 'disabled' else 'queued' end from public.notification_outbox o where o.notification_id=$1 and o.channel='email'),'disabled');
$$;
revoke all on function private.notification_delivery_status(uuid) from public;

create or replace function private.queue_prescription_order_notification(target_order uuid)
returns text language plpgsql security definer set search_path = '' as $$
declare o public.prescription_orders; recipient uuid; notification_id uuid; content text;
begin
 select * into o from public.prescription_orders where id=target_order;
 select u.auth_user_id into recipient from public.patients p join public.users u on u.id=p.user_id where p.id=o.patient_id;
 content:=private.medication_summary(o.patient_id,(now() at time zone 'Asia/Manila')::date,o.id);
 notification_id:=private.enqueue_notification(recipient,'New prescription order',coalesce(content,'The official prescription record is available in CareNavigator.'),
   'prescription',o.id,jsonb_build_object('order_id',o.id,'dedupe_key','prescription_order:'||o.id::text));
 return private.notification_delivery_status(notification_id);
end $$;
revoke all on function private.queue_prescription_order_notification(uuid) from public;

create or replace function public.queue_patient_email(target_patient_id uuid default null,target_order_id uuid default null,message_kind text default 'medication_reminder')
returns jsonb language plpgsql security definer set search_path = '' as $$
declare patient_id uuid:=coalesce(target_patient_id,private.current_patient_id()); recipient uuid; content text; notification_id uuid;
  today date:=(now() at time zone 'Asia/Manila')::date; doctor public.doctors;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null and not coalesce(is_anonymous,false)) then
   raise exception 'A verified account is required' using errcode='42501'; end if;
 select * into doctor from public.doctors where id=private.current_doctor_id();
 if patient_id is null or (patient_id is distinct from private.current_patient_id() and
   (doctor.id is null or not private.has_active_doctor_employment(doctor.id,doctor.hospital_id)
    or not (private.can_access_clinical_record(patient_id,doctor.hospital_id,'prescriptions',null,'view')
      or private.can_create_assigned_patient_document(patient_id,doctor.hospital_id)))) then
   raise exception 'This patient is not accessible to the caller' using errcode='42501'; end if;
 select u.auth_user_id into recipient from public.patients p join public.users u on u.id=p.user_id
   join auth.users a on a.id=u.auth_user_id where p.id=patient_id and u.account_status='active' and a.email_confirmed_at is not null;
 if recipient is null then raise exception 'The patient does not have a verified active email account'; end if;
 if message_kind='prescription' then
   if target_order_id is null or not exists(select 1 from public.prescription_orders where id=target_order_id and prescription_orders.patient_id=queue_patient_email.patient_id and status='issued') then
     raise exception 'An official prescription order is required'; end if;
 elsif message_kind<>'medication_reminder' then raise exception 'Unsupported email action'; end if;
 content:=private.medication_summary(patient_id,today,target_order_id);
 if content is null then raise exception 'No eligible official prescriptions are available'; end if;
 notification_id:=private.enqueue_notification(recipient,case when message_kind='prescription' then 'Prescription order' else 'Daily medication summary' end,
   content,message_kind,target_order_id,jsonb_build_object('authorized_manual_email',true,'requested_by',auth.uid(),
     'dedupe_key','manual:'||message_kind||':'||patient_id::text||':'||coalesce(target_order_id::text,today::text)));
 -- An earlier automatic notification must not authorize a manual send implicitly.
 insert into public.notification_outbox(notification_id,user_id,channel) values(notification_id,recipient,'email') on conflict do nothing;
 return jsonb_build_object('notification_id',notification_id,'status',private.notification_delivery_status(notification_id));
end $$;
revoke all on function public.queue_patient_email(uuid,uuid,text) from public,anon;
grant execute on function public.queue_patient_email(uuid,uuid,text) to authenticated;

create or replace function public.enqueue_due_medication_summaries(batch_size integer default 100)
returns integer language plpgsql security definer set search_path = '' as $$
declare p record; today date:=(now() at time zone 'Asia/Manila')::date; content text; notification_id uuid; processed integer:=0;
begin
 if (now() at time zone 'Asia/Manila')::time<time '08:00' then return 0; end if;
 for p in select patient.id,u.auth_user_id from public.patients patient join public.users u on u.id=patient.user_id
   join auth.users a on a.id=u.auth_user_id join public.notification_preferences pref on pref.user_id=u.auth_user_id
   where u.account_status='active' and a.email_confirmed_at is not null and pref.medication_reminders and pref.email_enabled
     and not exists(select 1 from public.medication_summary_days d where d.patient_id=patient.id and d.local_date=today)
   order by patient.id limit least(greatest(batch_size,1),500)
 loop
  content:=private.medication_summary(p.id,today);
  if content is null then continue; end if;
  insert into public.medication_summary_days(patient_id,local_date) values(p.id,today) on conflict do nothing;
  if not found then continue; end if;
  notification_id:=private.enqueue_notification(p.auth_user_id,'Daily medication summary',content,'medication_reminder',p.id,
    jsonb_build_object('summary_date',today,'dedupe_key','daily-medications:'||p.id::text||':'||today::text));
  update public.medication_summary_days set notification_id=enqueue_due_medication_summaries.notification_id where patient_id=p.id and local_date=today;
  processed:=processed+1;
 end loop;
 return processed;
end $$;
revoke all on function public.enqueue_due_medication_summaries(integer) from public,anon,authenticated;
grant execute on function public.enqueue_due_medication_summaries(integer) to service_role;

create or replace function public.notification_email_allowed(target_notification uuid)
returns boolean language plpgsql security definer set search_path = '' as $$
declare n public.notifications; pref public.notification_preferences; allowed boolean;
begin
 select * into n from public.notifications where id=target_notification;
 if n.id is null then return false; end if;
 if coalesce((n.data->>'authorized_manual_email')::boolean,false) then return true; end if;
 select * into pref from public.notification_preferences where user_id=n.user_id;
 if not coalesce(pref.email_enabled,false) then return false; end if;
 allowed:=case n.notification_type when 'medication_reminder' then coalesce(pref.medication_reminders,false)
  when 'prescription' then coalesce(pref.prescriptions,true) when 'appointment_reminder' then coalesce(pref.appointment_reminders,true)
  when 'medical_result' then coalesce(pref.medical_results,true) when 'consultation_update' then coalesce(pref.consultation_updates,true)
  when 'account_activation' then coalesce(pref.consultation_updates,true) when 'message' then coalesce(pref.messages,true)
  when 'hospital_alert' then coalesce(pref.hospital_alerts,true) else true end;
 if not allowed then return false; end if;
 if n.notification_type='medication_reminder' and n.data ? 'summary_date' then
  return (n.data->>'summary_date')::date=(now() at time zone 'Asia/Manila')::date;
 end if;
 return true;
end $$;
revoke all on function public.notification_email_allowed(uuid) from public,anon,authenticated;
grant execute on function public.notification_email_allowed(uuid) to service_role;

CREATE OR REPLACE FUNCTION public.notify_prescription_created()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  recipient uuid;
begin
  if new.order_id is not null then return new; end if;
  select app_user.auth_user_id into recipient
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where patient.id = new.patient_id;
  perform private.enqueue_notification(
    recipient,
    'New prescription',
    'A doctor added a prescription to your care record.',
    'prescription',
    new.id,
    jsonb_build_object(
      'consultation_id', new.consultation_id,
      'assignment_id', new.assignment_id,
      'event_key', 'created'
    )
  );
  return new;
end
$function$
;



create table if not exists public.care_assistant_conversations (
  id text not null,
  user_id uuid not null references public.users(id) on delete cascade,
  title text not null,
  is_pinned boolean not null default false,
  is_title_edited boolean not null default false,
  payload jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  primary key (user_id, id),
  constraint care_assistant_conversations_id_length
    check (char_length(id) between 1 and 160),
  constraint care_assistant_conversations_title_length
    check (char_length(btrim(title)) between 1 and 60),
  constraint care_assistant_conversations_payload_object
    check (jsonb_typeof(payload) = 'object')
);

create index if not exists care_assistant_conversations_user_history_idx
  on public.care_assistant_conversations(
    user_id,
    is_pinned desc,
    updated_at desc
  );

alter table public.care_assistant_conversations enable row level security;

drop policy if exists "Account owners read assistant conversations"
  on public.care_assistant_conversations;
create policy "Account owners read assistant conversations"
  on public.care_assistant_conversations
  for select
  to authenticated
  using (user_id = private.current_user_id());

drop policy if exists "Account owners create assistant conversations"
  on public.care_assistant_conversations;
create policy "Account owners create assistant conversations"
  on public.care_assistant_conversations
  for insert
  to authenticated
  with check (user_id = private.current_user_id());

drop policy if exists "Account owners update assistant conversations"
  on public.care_assistant_conversations;
create policy "Account owners update assistant conversations"
  on public.care_assistant_conversations
  for update
  to authenticated
  using (user_id = private.current_user_id())
  with check (user_id = private.current_user_id());

drop policy if exists "Account owners delete assistant conversations"
  on public.care_assistant_conversations;
create policy "Account owners delete assistant conversations"
  on public.care_assistant_conversations
  for delete
  to authenticated
  using (user_id = private.current_user_id());

revoke all on table public.care_assistant_conversations from anon;
grant select, insert, update, delete
  on table public.care_assistant_conversations to authenticated;

comment on table public.care_assistant_conversations is
  'Private per-account CareNavigator assistant conversation history. Image bytes are not retained.';


