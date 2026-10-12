begin;

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

commit;
