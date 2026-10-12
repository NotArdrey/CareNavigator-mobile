begin;

-- Doctor/patient messaging belongs to the durable care assignment. A
-- consultation remains useful context, but is no longer required to chat.
alter table public.chat_conversations
  alter column consultation_id drop not null;

update public.chat_conversations conversation
set doctor_id = coalesce(conversation.doctor_id, consultation.doctor_id),
    patient_id = coalesce(conversation.patient_id, consultation.patient_id)
from public.consultations consultation
where consultation.id = conversation.consultation_id
  and (conversation.doctor_id is null or conversation.patient_id is null);

create unique index if not exists chat_conversations_direct_relationship_uidx
  on public.chat_conversations(doctor_id, patient_id)
  where consultation_id is null;

create index if not exists chat_conversations_relationship_idx
  on public.chat_conversations(doctor_id, patient_id, updated_at desc);

create or replace function public.validate_conversation_relationships()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  consultation_row public.consultations;
begin
  if new.consultation_id is null then
    if new.patient_id is null
      or new.guest_request_id is not null
      or not exists (
        select 1
        from public.doctor_patient_assignments assignment
        where assignment.doctor_id = new.doctor_id
          and assignment.patient_id = new.patient_id
          and assignment.assignment_status = 'active'
          and assignment.ended_at is null
      ) then
      raise exception 'Direct conversation participants must have an active assignment';
    end if;
    return new;
  end if;

  select *
  into consultation_row
  from public.consultations
  where id = new.consultation_id;
  if not found
    or consultation_row.doctor_id is distinct from new.doctor_id
    or consultation_row.patient_id is distinct from new.patient_id
    or consultation_row.guest_request_id is distinct from new.guest_request_id then
    raise exception 'Conversation participants must match the consultation';
  end if;
  return new;
end
$function$;

create or replace function private.can_participate_conversation(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(exists (
    select 1
    from public.chat_conversations conversation
    left join public.consultations consultation
      on consultation.id = conversation.consultation_id
    left join public.guest_consultation_requests guest_request
      on guest_request.id = conversation.guest_request_id
    where conversation.id = target_conversation_id
      and conversation.status in ('pending', 'active', 'closed')
      and (
        conversation.patient_id = private.current_patient_id()
        or (
          conversation.doctor_id = private.current_doctor_id()
          and (
            consultation.status in (
              'approved', 'scheduled', 'in_progress', 'completed'
            )
            or exists (
              select 1
              from public.doctor_patient_assignments assignment
              where assignment.doctor_id = conversation.doctor_id
                and assignment.patient_id = conversation.patient_id
                and assignment.assignment_status = 'active'
                and assignment.ended_at is null
            )
          )
        )
        or (
          conversation.guest_request_id is not null
          and guest_request.submitted_by = (select auth.uid())
          and private.current_user_id() is not null
          and guest_request.request_status in (
            'approved', 'temporary_patient_created',
            'account_activation_pending', 'consultation_scheduled',
            'consultation_completed'
          )
        )
      )
  ), false)
$function$;

create or replace function private.can_send_to_conversation(
  target_conversation_id uuid
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    private.can_participate_conversation(target_conversation_id)
    and exists (
      select 1
      from public.chat_conversations conversation
      left join public.consultations consultation
        on consultation.id = conversation.consultation_id
      where conversation.id = target_conversation_id
        and conversation.status = 'active'
        and (
          consultation.status in ('approved', 'scheduled', 'in_progress')
          or exists (
            select 1
            from public.doctor_patient_assignments assignment
            where assignment.doctor_id = conversation.doctor_id
              and assignment.patient_id = conversation.patient_id
              and assignment.assignment_status = 'active'
              and assignment.ended_at is null
          )
        )
    ),
    false
  )
$function$;

revoke all on function private.can_participate_conversation(uuid)
  from public, anon;
revoke all on function private.can_send_to_conversation(uuid)
  from public, anon;
grant execute on function private.can_participate_conversation(uuid)
  to authenticated, service_role;
grant execute on function private.can_send_to_conversation(uuid)
  to authenticated, service_role;

create or replace function public.ensure_patient_conversation(
  target_patient_id uuid
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  actor_doctor_id uuid := private.current_doctor_id();
  conversation_id uuid;
begin
  if actor_doctor_id is null then
    raise exception 'An authenticated doctor is required';
  end if;

  if not exists (
    select 1
    from public.doctor_patient_assignments assignment
    where assignment.doctor_id = actor_doctor_id
      and assignment.patient_id = target_patient_id
      and assignment.assignment_status = 'active'
      and assignment.ended_at is null
  ) then
    raise exception 'An active doctor-patient assignment is required';
  end if;

  select conversation.id
  into conversation_id
  from public.chat_conversations conversation
  where conversation.doctor_id = actor_doctor_id
    and conversation.patient_id = target_patient_id
  order by
    (conversation.consultation_id is null) desc,
    conversation.updated_at desc
  limit 1;

  if conversation_id is not null then
    update public.chat_conversations
    set status = 'active', updated_at = now()
    where id = conversation_id;
    return conversation_id;
  end if;

  begin
    insert into public.chat_conversations(
      doctor_id,
      patient_id,
      consultation_id,
      status
    ) values (
      actor_doctor_id,
      target_patient_id,
      null,
      'active'
    )
    returning id into conversation_id;
  exception
    when unique_violation then
      select conversation.id
      into conversation_id
      from public.chat_conversations conversation
      where conversation.doctor_id = actor_doctor_id
        and conversation.patient_id = target_patient_id
        and conversation.consultation_id is null
      limit 1;
  end;

  return conversation_id;
end
$function$;

revoke all on function public.ensure_patient_conversation(uuid)
  from public, anon;
grant execute on function public.ensure_patient_conversation(uuid)
  to authenticated, service_role;

create or replace function public.send_chat_message(
  target_conversation_id uuid,
  message_body text default null,
  attachment_paths text[] default '{}'::text[]
)
returns uuid
language plpgsql
security definer
set search_path to ''
as $function$
declare
  new_message_id uuid;
  path text;
begin
  if not private.can_send_to_conversation(target_conversation_id) then
    raise exception 'Conversation is not active or accessible';
  end if;
  if nullif(btrim(message_body), '') is null
    and cardinality(coalesce(attachment_paths, '{}'::text[])) = 0 then
    raise exception 'Message or attachment is required';
  end if;

  insert into public.chat_messages(
    conversation_id,
    sender_id,
    message,
    attachment_path,
    message_type
  ) values (
    target_conversation_id,
    (select auth.uid()),
    nullif(btrim(message_body), ''),
    case
      when cardinality(coalesce(attachment_paths, '{}'::text[])) = 1
        then attachment_paths[1]
      else null
    end,
    case
      when cardinality(coalesce(attachment_paths, '{}'::text[])) > 0
        and nullif(btrim(message_body), '') is null then 'document'
      else 'text'
    end
  )
  returning id into new_message_id;

  foreach path in array coalesce(attachment_paths, '{}'::text[]) loop
    insert into public.chat_message_attachments(
      message_id,
      uploaded_by,
      storage_path,
      file_name
    ) values (
      new_message_id,
      (select auth.uid()),
      path,
      coalesce(nullif(regexp_replace(path, '^.*/', ''), ''), 'attachment')
    );
  end loop;

  update public.chat_conversations
  set updated_at = now()
  where id = target_conversation_id;

  return new_message_id;
end
$function$;

revoke all on function public.send_chat_message(uuid, text, text[])
  from public, anon;
grant execute on function public.send_chat_message(uuid, text, text[])
  to authenticated, service_role;

create or replace function public.mark_conversation_read(
  target_conversation_id uuid
)
returns integer
language plpgsql
security definer
set search_path to ''
as $function$
declare
  changed integer;
begin
  if not private.can_participate_conversation(target_conversation_id) then
    raise exception 'Conversation is not accessible';
  end if;

  update public.chat_messages
  set delivered_at = coalesce(delivered_at, now()),
      read_at = coalesce(read_at, now())
  where conversation_id = target_conversation_id
    and sender_id <> (select auth.uid())
    and read_at is null;
  get diagnostics changed = row_count;
  return changed;
end
$function$;

revoke all on function public.mark_conversation_read(uuid)
  from public, anon;
grant execute on function public.mark_conversation_read(uuid)
  to authenticated, service_role;

create or replace function private.can_access_direct_chat_storage(
  object_name text
)
returns boolean
language plpgsql
stable
security definer
set search_path to ''
as $function$
declare
  folders text[] := storage.foldername(object_name);
  conversation_id uuid;
begin
  if coalesce(folders[1], '') <> 'direct' then
    return false;
  end if;
  begin
    conversation_id := folders[3]::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  return private.can_participate_conversation(conversation_id);
end
$function$;

revoke all on function private.can_access_direct_chat_storage(text)
  from public, anon;
grant execute on function private.can_access_direct_chat_storage(text)
  to authenticated, service_role;

drop policy if exists cnph_direct_chat_attachments_read on storage.objects;
create policy cnph_direct_chat_attachments_read
on storage.objects for select to authenticated
using (
  bucket_id = 'consultation-attachments'
  and private.can_access_direct_chat_storage(name)
);

drop policy if exists cnph_direct_chat_attachments_insert on storage.objects;
create policy cnph_direct_chat_attachments_insert
on storage.objects for insert to authenticated
with check (
  bucket_id = 'consultation-attachments'
  and private.can_access_direct_chat_storage(name)
);

drop policy if exists cnph_direct_chat_attachments_delete on storage.objects;
create policy cnph_direct_chat_attachments_delete
on storage.objects for delete to authenticated
using (
  bucket_id = 'consultation-attachments'
  and private.can_access_direct_chat_storage(name)
);

commit;
