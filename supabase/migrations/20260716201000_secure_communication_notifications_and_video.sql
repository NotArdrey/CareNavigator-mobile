begin;

alter table public.chat_messages
  add column if not exists message_type text not null default 'text',
  add column if not exists edited_at timestamptz,
  add column if not exists deleted_at timestamptz;

do $$ begin
  if not exists (select 1 from pg_constraint where conname='chat_messages_message_type_check') then
    alter table public.chat_messages add constraint chat_messages_message_type_check
      check (message_type in ('text','image','document','system'));
  end if;
end $$;

create table if not exists public.chat_message_attachments (
  id uuid primary key default gen_random_uuid(),
  message_id uuid not null references public.chat_messages(id) on delete cascade,
  uploaded_by uuid not null references auth.users(id) on delete restrict,
  storage_path text not null unique,
  file_name text not null,
  mime_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  created_at timestamptz not null default now()
);

alter table public.notifications
  add column if not exists data jsonb not null default '{}'::jsonb,
  add column if not exists action_url text,
  add column if not exists read_at timestamptz;

create table if not exists public.notification_preferences (
  user_id uuid primary key references auth.users(id) on delete cascade,
  consultation_updates boolean not null default true,
  appointment_reminders boolean not null default true,
  medical_results boolean not null default true,
  prescriptions boolean not null default true,
  messages boolean not null default true,
  hospital_alerts boolean not null default true,
  push_enabled boolean not null default true,
  email_enabled boolean not null default true,
  sms_enabled boolean not null default false,
  quiet_hours_start time,
  quiet_hours_end time,
  updated_at timestamptz not null default now()
);

create table if not exists public.device_tokens (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  token text not null unique,
  platform text not null check (platform in ('android','ios','web')),
  is_active boolean not null default true,
  last_seen_at timestamptz not null default now(),
  created_at timestamptz not null default now()
);

create table if not exists public.notification_outbox (
  id bigint generated always as identity primary key,
  notification_id uuid not null references public.notifications(id) on delete cascade,
  user_id uuid not null references auth.users(id) on delete cascade,
  channel text not null check (channel in ('push','email','sms')),
  status text not null default 'pending' check (status in ('pending','processing','delivered','failed','cancelled')),
  attempt_count integer not null default 0 check (attempt_count >= 0),
  next_attempt_at timestamptz not null default now(),
  provider_message_id text,
  last_error text,
  delivered_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (notification_id, channel)
);

create table if not exists public.video_sessions (
  id uuid primary key default gen_random_uuid(),
  consultation_id uuid not null unique references public.consultations(id) on delete cascade,
  provider text not null,
  room_name text not null,
  join_url text not null,
  status text not null default 'pending' check (status in ('pending','ready','active','ended','cancelled','failed')),
  provider_metadata jsonb not null default '{}'::jsonb,
  created_by uuid not null references auth.users(id) on delete restrict,
  starts_at timestamptz,
  started_at timestamptz,
  ended_at timestamptz,
  expires_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (provider,room_name),
  check (ended_at is null or started_at is null or ended_at >= started_at)
);

create index if not exists chat_attachments_message_idx on public.chat_message_attachments (message_id,created_at);
create index if not exists device_tokens_user_active_idx on public.device_tokens (user_id,is_active);
create index if not exists notification_outbox_delivery_idx on public.notification_outbox (status,next_attempt_at) where status in ('pending','failed');
create index if not exists video_sessions_status_starts_idx on public.video_sessions (status,starts_at);

create or replace function private.can_participate_conversation(target_conversation_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(exists (
    select 1
    from public.chat_conversations conversation
    join public.consultations consultation on consultation.id=conversation.consultation_id
    left join public.guest_consultation_requests guest_request on guest_request.id=conversation.guest_request_id
    where conversation.id=target_conversation_id
      and conversation.status in ('pending','active','closed')
      and (
        conversation.doctor_id=private.current_doctor_id()
        or conversation.patient_id=private.current_patient_id()
        or (conversation.guest_request_id is not null
          and guest_request.submitted_by=(select auth.uid())
          and guest_request.request_status in ('approved','temporary_patient_created','account_activation_pending','consultation_scheduled','consultation_completed'))
      )
      and (consultation.status in ('approved','scheduled','in_progress','completed') or exists (
        select 1 from public.doctor_patient_assignments assignment
        where assignment.doctor_id=conversation.doctor_id and assignment.patient_id=conversation.patient_id and assignment.ended_at is null
      ))
  ),false)
$$;

create or replace function private.can_send_to_conversation(target_conversation_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(private.can_participate_conversation(target_conversation_id) and exists (
    select 1 from public.chat_conversations conversation
    join public.consultations consultation on consultation.id=conversation.consultation_id
    where conversation.id=target_conversation_id and conversation.status='active'
      and consultation.status in ('approved','scheduled','in_progress')
  ),false)
$$;

create or replace function public.validate_conversation_relationships()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare consultation_row public.consultations;
begin
  select * into consultation_row from public.consultations where id=new.consultation_id;
  if not found or consultation_row.doctor_id is distinct from new.doctor_id
    or consultation_row.patient_id is distinct from new.patient_id
    or consultation_row.guest_request_id is distinct from new.guest_request_id then
    raise exception 'Conversation participants must match the consultation';
  end if;
  return new;
end;
$$;

drop trigger if exists validate_conversation_relationships_before_write on public.chat_conversations;
create trigger validate_conversation_relationships_before_write before insert or update on public.chat_conversations
for each row execute function public.validate_conversation_relationships();

create or replace function public.protect_chat_message()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.conversation_id is distinct from old.conversation_id or new.sender_id is distinct from old.sender_id
    or new.message is distinct from old.message or new.attachment_path is distinct from old.attachment_path
    or new.sent_at is distinct from old.sent_at or new.message_type is distinct from old.message_type then
    raise exception 'Sent message content and ownership are immutable';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_chat_message_before_update on public.chat_messages;
create trigger protect_chat_message_before_update before update on public.chat_messages
for each row execute function public.protect_chat_message();

create or replace function public.ensure_consultation_conversation(target_consultation_id uuid)
returns uuid language plpgsql security invoker set search_path = ''
as $$
declare consultation_row public.consultations; conversation_id uuid;
begin
  select * into consultation_row from public.consultations where id=target_consultation_id for update;
  if not found or consultation_row.status not in ('approved','scheduled','in_progress') then raise exception 'An approved consultation is required'; end if;
  if consultation_row.doctor_id<>private.current_doctor_id() then raise exception 'Only the assigned doctor may open this conversation'; end if;
  select id into conversation_id from public.chat_conversations where consultation_id=target_consultation_id;
  if conversation_id is not null then
    update public.chat_conversations set status=case when status='pending' then 'active' else status end where id=conversation_id;
    return conversation_id;
  end if;
  conversation_id := gen_random_uuid();
  insert into public.chat_conversations (id,patient_id,guest_request_id,doctor_id,consultation_id,status)
  values (conversation_id,consultation_row.patient_id,consultation_row.guest_request_id,consultation_row.doctor_id,consultation_row.id,'active');
  return conversation_id;
end;
$$;

create or replace function public.send_chat_message(
  target_conversation_id uuid,
  message_body text default null,
  attachment_paths text[] default '{}'::text[]
)
returns uuid language plpgsql security invoker set search_path = ''
as $$
declare new_message_id uuid; path text;
begin
  if not private.can_send_to_conversation(target_conversation_id) then raise exception 'Conversation is not active or accessible'; end if;
  if nullif(btrim(message_body),'') is null and cardinality(coalesce(attachment_paths,'{}'::text[]))=0 then raise exception 'Message or attachment is required'; end if;
  insert into public.chat_messages (conversation_id,sender_id,message,attachment_path,message_type)
  values (target_conversation_id,(select auth.uid()),nullif(btrim(message_body),''),
    case when cardinality(coalesce(attachment_paths,'{}'::text[]))=1 then attachment_paths[1] else null end,
    case when cardinality(coalesce(attachment_paths,'{}'::text[]))>0 and nullif(btrim(message_body),'') is null then 'document' else 'text' end)
  returning id into new_message_id;
  foreach path in array coalesce(attachment_paths,'{}'::text[]) loop
    insert into public.chat_message_attachments (message_id,uploaded_by,storage_path,file_name)
    values (new_message_id,(select auth.uid()),path,coalesce(nullif(regexp_replace(path,'^.*/',''),''),'attachment'));
  end loop;
  return new_message_id;
end;
$$;

create or replace function public.mark_conversation_read(target_conversation_id uuid)
returns integer language plpgsql security invoker set search_path = ''
as $$
declare changed integer;
begin
  if not private.can_participate_conversation(target_conversation_id) then raise exception 'Conversation is not accessible'; end if;
  update public.chat_messages set delivered_at=coalesce(delivered_at,now()),read_at=coalesce(read_at,now())
  where conversation_id=target_conversation_id and sender_id<>(select auth.uid()) and read_at is null;
  get diagnostics changed=row_count;
  return changed;
end;
$$;

create or replace function private.enqueue_notification(
  target_user_id uuid,target_title text,target_message text,target_type text,target_reference_id uuid default null,target_data jsonb default '{}'::jsonb
)
returns uuid language plpgsql security definer set search_path = ''
as $$
declare notification_id uuid;
begin
  if target_user_id is null then return null; end if;
  insert into public.notifications (user_id,title,message,notification_type,reference_id,data)
  values (target_user_id,target_title,target_message,target_type,target_reference_id,target_data)
  returning id into notification_id;
  return notification_id;
end;
$$;

create or replace function public.queue_notification_deliveries()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare category_enabled boolean;
begin
  if new.user_id is null then return new; end if;
  category_enabled := case
    when new.notification_type in ('consultation_update','account_activation') then coalesce((select consultation_updates from public.notification_preferences where user_id=new.user_id),true)
    when new.notification_type='appointment_reminder' then coalesce((select appointment_reminders from public.notification_preferences where user_id=new.user_id),true)
    when new.notification_type='medical_result' then coalesce((select medical_results from public.notification_preferences where user_id=new.user_id),true)
    when new.notification_type='prescription' then coalesce((select prescriptions from public.notification_preferences where user_id=new.user_id),true)
    when new.notification_type='message' then coalesce((select messages from public.notification_preferences where user_id=new.user_id),true)
    when new.notification_type='hospital_alert' then coalesce((select hospital_alerts from public.notification_preferences where user_id=new.user_id),true)
    else true end;
  if not category_enabled then return new; end if;
  if coalesce((select push_enabled from public.notification_preferences where user_id=new.user_id),true) then
    insert into public.notification_outbox(notification_id,user_id,channel) values(new.id,new.user_id,'push') on conflict do nothing;
  end if;
  if coalesce((select email_enabled from public.notification_preferences where user_id=new.user_id),true) then
    insert into public.notification_outbox(notification_id,user_id,channel) values(new.id,new.user_id,'email') on conflict do nothing;
  end if;
  if coalesce((select sms_enabled from public.notification_preferences where user_id=new.user_id),false) then
    insert into public.notification_outbox(notification_id,user_id,channel) values(new.id,new.user_id,'sms') on conflict do nothing;
  end if;
  return new;
end;
$$;

create or replace function public.notify_chat_message()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare conversation_row public.chat_conversations; recipient uuid;
begin
  select * into conversation_row from public.chat_conversations where id=new.conversation_id;
  if new.sender_id=(select app_user.auth_user_id from public.doctors d join public.users app_user on app_user.id=d.user_id where d.id=conversation_row.doctor_id) then
    if conversation_row.patient_id is not null then
      select app_user.auth_user_id into recipient from public.patients patient join public.users app_user on app_user.id=patient.user_id where patient.id=conversation_row.patient_id;
    else select submitted_by into recipient from public.guest_consultation_requests where id=conversation_row.guest_request_id; end if;
  else
    select app_user.auth_user_id into recipient from public.doctors d join public.users app_user on app_user.id=d.user_id where d.id=conversation_row.doctor_id;
  end if;
  perform private.enqueue_notification(recipient,'New message','You received a consultation message','message',new.id,
    jsonb_build_object('conversation_id',new.conversation_id));
  return new;
end;
$$;

drop trigger if exists notify_chat_message_after_insert on public.chat_messages;
create trigger notify_chat_message_after_insert after insert on public.chat_messages
for each row execute function public.notify_chat_message();

create or replace function public.claim_notification_outbox(batch_size integer default 50)
returns setof public.notification_outbox language plpgsql security definer set search_path = ''
as $$
begin
  return query
  update public.notification_outbox outbox set status='processing',attempt_count=attempt_count+1,updated_at=now()
  where outbox.id in (
    select queued.id from public.notification_outbox queued
    where queued.status in ('pending','failed') and queued.next_attempt_at<=now()
    order by queued.created_at for update skip locked limit least(greatest(batch_size,1),500)
  ) returning outbox.*;
end;
$$;

create or replace function public.complete_notification_delivery(
  target_outbox_id bigint,delivered boolean,provider_id text default null,error_message text default null
)
returns void language plpgsql security definer set search_path = ''
as $$
begin
  update public.notification_outbox set status=case when delivered then 'delivered' else 'failed' end,
    provider_message_id=provider_id,last_error=case when delivered then null else error_message end,
    delivered_at=case when delivered then now() else null end,
    next_attempt_at=case when delivered then next_attempt_at else now()+make_interval(mins=>least(60,power(2,least(attempt_count,5))::integer)) end,
    updated_at=now() where id=target_outbox_id;
  if not found then raise exception 'Outbox delivery was not found'; end if;
end;
$$;

drop trigger if exists queue_notification_deliveries_after_insert on public.notifications;
create trigger queue_notification_deliveries_after_insert after insert on public.notifications
for each row execute function public.queue_notification_deliveries();

create or replace function public.notify_consultation_status_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare recipient uuid;
begin
  if tg_op='UPDATE' and new.status is not distinct from old.status then return new; end if;
  if new.patient_id is not null then
    select app_user.auth_user_id into recipient from public.patients p join public.users app_user on app_user.id=p.user_id where p.id=new.patient_id;
  elsif new.guest_request_id is not null then
    select submitted_by into recipient from public.guest_consultation_requests where id=new.guest_request_id;
  end if;
  perform private.enqueue_notification(recipient,'Consultation update','Your consultation is now '||replace(new.status::text,'_',' '),
    'consultation_update',new.id,jsonb_build_object('status',new.status));
  return new;
end;
$$;

drop trigger if exists notify_consultation_status_after_write on public.consultations;
create trigger notify_consultation_status_after_write after insert or update of status on public.consultations
for each row execute function public.notify_consultation_status_change();

create or replace function public.mark_notification_read(target_notification_id uuid)
returns void language plpgsql security invoker set search_path = ''
as $$
begin
  update public.notifications set is_read=true,read_at=coalesce(read_at,now())
  where id=target_notification_id and user_id=(select auth.uid());
  if not found then raise exception 'Notification was not found'; end if;
end;
$$;

create or replace function public.ensure_video_session(target_consultation_id uuid,target_provider text default 'jitsi')
returns uuid language plpgsql security invoker set search_path = ''
as $$
declare consultation_row public.consultations; session_id uuid; generated_room text; generated_url text;
begin
  select * into consultation_row from public.consultations where id=target_consultation_id for update;
  if not found or consultation_row.doctor_id<>private.current_doctor_id() or consultation_row.consultation_type not in ('online','guest_online')
    or consultation_row.status not in ('approved','scheduled','in_progress') then raise exception 'An approved online consultation assigned to this doctor is required'; end if;
  generated_room := 'cnph-'||replace(target_consultation_id::text,'-','');
  generated_url := case when lower(target_provider)='jitsi' then 'https://meet.jit.si/'||generated_room else 'provider://' || lower(target_provider) || '/' || generated_room end;
  insert into public.video_sessions(consultation_id,provider,room_name,join_url,status,created_by,starts_at,expires_at)
  values(target_consultation_id,lower(target_provider),generated_room,generated_url,'ready',(select auth.uid()),consultation_row.appointment_date,consultation_row.appointment_date+interval '4 hours')
  on conflict(consultation_id) do update set starts_at=excluded.starts_at,expires_at=excluded.expires_at
  returning id,join_url into session_id,generated_url;
  update public.consultations set meeting_link=generated_url where id=target_consultation_id;
  return session_id;
end;
$$;

alter table public.chat_message_attachments enable row level security;
alter table public.notification_preferences enable row level security;
alter table public.device_tokens enable row level security;
alter table public.notification_outbox enable row level security;
alter table public.video_sessions enable row level security;

drop policy if exists conversations_participant_read on public.chat_conversations;
create policy conversations_participant_read on public.chat_conversations for select to authenticated using (private.can_participate_conversation(id));
drop policy if exists conversations_doctor_insert on public.chat_conversations;
create policy conversations_doctor_insert on public.chat_conversations for insert to authenticated with check (doctor_id=private.current_doctor_id());
drop policy if exists messages_participant_read on public.chat_messages;
create policy messages_participant_read on public.chat_messages for select to authenticated using (private.can_participate_conversation(conversation_id));
drop policy if exists messages_participant_insert on public.chat_messages;
create policy messages_participant_insert on public.chat_messages for insert to authenticated with check (sender_id=(select auth.uid()) and private.can_send_to_conversation(conversation_id));
drop policy if exists messages_participant_update on public.chat_messages;
create policy messages_receipt_update on public.chat_messages for update to authenticated using (private.can_participate_conversation(conversation_id)) with check (private.can_participate_conversation(conversation_id));
create policy chat_attachments_participant_read on public.chat_message_attachments for select to authenticated using (
  exists(select 1 from public.chat_messages m where m.id=message_id and private.can_participate_conversation(m.conversation_id))
);
create policy chat_attachments_sender_insert on public.chat_message_attachments for insert to authenticated with check (
  uploaded_by=(select auth.uid()) and exists(select 1 from public.chat_messages m where m.id=message_id and m.sender_id=(select auth.uid()))
);
create policy notification_preferences_owner_manage on public.notification_preferences for all to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy device_tokens_owner_manage on public.device_tokens for all to authenticated using (user_id=(select auth.uid())) with check (user_id=(select auth.uid()));
create policy notification_outbox_super_admin_read on public.notification_outbox for select to authenticated using (private.is_super_admin());
create policy video_sessions_participant_read on public.video_sessions for select to authenticated using (private.is_consultation_participant(consultation_id));
create policy video_sessions_doctor_insert on public.video_sessions for insert to authenticated with check (
  created_by=(select auth.uid()) and exists(select 1 from public.consultations c where c.id=consultation_id and c.doctor_id=private.current_doctor_id())
);
create policy video_sessions_doctor_update on public.video_sessions for update to authenticated using (
  exists(select 1 from public.consultations c where c.id=consultation_id and c.doctor_id=private.current_doctor_id())
) with check (exists(select 1 from public.consultations c where c.id=consultation_id and c.doctor_id=private.current_doctor_id()));

revoke update on public.chat_messages from authenticated;
grant update(delivered_at,read_at) on public.chat_messages to authenticated;
grant select,insert on public.chat_message_attachments to authenticated;
grant select,insert,update,delete on public.notification_preferences,public.device_tokens to authenticated;
grant select on public.notification_outbox to authenticated;
grant select,insert,update on public.video_sessions to authenticated;

revoke all on function private.can_participate_conversation(uuid),private.can_send_to_conversation(uuid),private.enqueue_notification(uuid,text,text,text,uuid,jsonb) from public,anon;
grant execute on function private.can_participate_conversation(uuid),private.can_send_to_conversation(uuid) to authenticated;
revoke all on function public.validate_conversation_relationships(),public.protect_chat_message(),public.queue_notification_deliveries(),
  public.notify_consultation_status_change(),public.notify_chat_message() from public,anon,authenticated;
revoke all on function public.ensure_consultation_conversation(uuid),public.send_chat_message(uuid,text,text[]),public.mark_conversation_read(uuid),
  public.mark_notification_read(uuid),public.ensure_video_session(uuid,text) from public,anon;
grant execute on function public.ensure_consultation_conversation(uuid),public.send_chat_message(uuid,text,text[]),public.mark_conversation_read(uuid),
  public.mark_notification_read(uuid),public.ensure_video_session(uuid,text) to authenticated;
revoke all on function public.claim_notification_outbox(integer),public.complete_notification_delivery(bigint,boolean,text,text) from public,anon,authenticated;
grant execute on function public.claim_notification_outbox(integer),public.complete_notification_delivery(bigint,boolean,text,text) to service_role;

create or replace function private.can_access_consultation_storage(object_name text)
returns boolean language plpgsql stable security definer set search_path = ''
as $$
declare folder text := (storage.foldername(object_name))[1];
begin
  if folder is null or folder !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then return false; end if;
  return private.is_consultation_participant(folder::uuid);
end;
$$;

create or replace function private.can_access_guest_storage(object_name text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(private.storage_path_owner(object_name) or exists(
    select 1 from public.guest_consultation_requests g
    where (g.identification_file_path=object_name or object_name like g.id::text||'/%') and private.can_access_guest_request(g.id)
  ),false)
$$;

create or replace function private.can_manage_hospital_storage(object_name text)
returns boolean language plpgsql stable security definer set search_path = ''
as $$
declare folder text := (storage.foldername(object_name))[1];
begin
  if private.is_super_admin() then return true; end if;
  if folder is null or folder !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then return false; end if;
  return private.is_hospital_admin_for(folder::uuid);
end;
$$;

revoke all on function private.can_access_consultation_storage(text),private.can_access_guest_storage(text),private.can_manage_hospital_storage(text) from public,anon;
grant execute on function private.can_access_consultation_storage(text),private.can_access_guest_storage(text),private.can_manage_hospital_storage(text) to authenticated;

drop policy if exists cnph_guest_documents_owner_read on storage.objects;
create policy cnph_guest_documents_authorized_read on storage.objects for select to authenticated using (
  bucket_id in ('valid-identification','guest-consultation-documents') and private.can_access_guest_storage(name)
);
drop policy if exists cnph_patient_documents_doctor_insert on storage.objects;
create policy cnph_patient_documents_participant_insert on storage.objects for insert to authenticated with check (
  bucket_id in ('laboratory-results','scanned-medical-results','medical-documents','prescriptions','consultation-attachments')
  and (private.can_access_patient_storage(name) or private.can_access_consultation_storage(name))
);
create policy cnph_patient_documents_participant_update on storage.objects for update to authenticated using (
  bucket_id in ('laboratory-results','scanned-medical-results','medical-documents','prescriptions','consultation-attachments')
  and (private.can_access_patient_storage(name) or private.can_access_consultation_storage(name))
) with check (bucket_id in ('laboratory-results','scanned-medical-results','medical-documents','prescriptions','consultation-attachments')
  and (private.can_access_patient_storage(name) or private.can_access_consultation_storage(name)));
create policy cnph_patient_documents_participant_delete on storage.objects for delete to authenticated using (
  bucket_id in ('laboratory-results','scanned-medical-results','medical-documents','prescriptions','consultation-attachments')
  and (private.can_access_patient_storage(name) or private.can_access_consultation_storage(name))
);
drop policy if exists cnph_admin_documents_read on storage.objects;
drop policy if exists cnph_admin_documents_insert on storage.objects;
create policy cnph_admin_documents_scoped_read on storage.objects for select to authenticated using (
  bucket_id in ('doctor-documents','hospital-accreditation-documents') and private.can_manage_hospital_storage(name)
);
create policy cnph_admin_documents_scoped_insert on storage.objects for insert to authenticated with check (
  bucket_id in ('doctor-documents','hospital-accreditation-documents') and private.can_manage_hospital_storage(name)
);
create policy cnph_admin_documents_scoped_update on storage.objects for update to authenticated using (
  bucket_id in ('doctor-documents','hospital-accreditation-documents') and private.can_manage_hospital_storage(name)
) with check (bucket_id in ('doctor-documents','hospital-accreditation-documents') and private.can_manage_hospital_storage(name));
create policy cnph_admin_documents_scoped_delete on storage.objects for delete to authenticated using (
  bucket_id in ('doctor-documents','hospital-accreditation-documents') and private.can_manage_hospital_storage(name)
);

do $$ declare table_name text; begin
  foreach table_name in array array['chat_conversations','chat_messages','notifications','video_sessions','hospital_facility_status','doctors'] loop
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=table_name) then
      execute format('alter publication supabase_realtime add table public.%I',table_name);
    end if;
  end loop;
end $$;

insert into supabase_migrations.schema_migrations (version, statements, name)
values ('20260716201000', array[]::text[], 'secure_communication_notifications_and_video')
on conflict (version) do nothing;

commit;
