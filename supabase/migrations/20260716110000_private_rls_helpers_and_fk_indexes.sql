begin;

create schema if not exists private;
revoke all on schema private from public, anon;
grant usage on schema private to authenticated;

alter function public.current_user_id() set schema private;
alter function public.current_role() set schema private;
alter function public.current_hospital_id() set schema private;
alter function public.current_doctor_id() set schema private;
alter function public.current_patient_id() set schema private;
alter function public.is_super_admin() set schema private;
alter function public.is_hospital_admin_for(uuid) set schema private;
alter function public.can_access_patient(uuid) set schema private;
alter function public.can_access_guest_request(uuid) set schema private;
alter function public.can_access_conversation(uuid) set schema private;
alter function public.can_view_user(uuid) set schema private;
alter function public.storage_path_owner(text) set schema private;
alter function public.can_access_patient_storage(text) set schema private;

create or replace function private.current_user_id()
returns uuid language sql stable security definer set search_path = ''
as $$
  select u.id from public.users u where u.auth_user_id = (select auth.uid()) limit 1
$$;

create or replace function private.current_role()
returns text language sql stable security definer set search_path = ''
as $$
  select r.role_name
  from public.users u
  join public.roles r on r.id = u.role_id
  where u.auth_user_id = (select auth.uid())
  limit 1
$$;

create or replace function private.current_hospital_id()
returns uuid language sql stable security definer set search_path = ''
as $$
  select u.hospital_id from public.users u where u.auth_user_id = (select auth.uid()) limit 1
$$;

create or replace function private.current_doctor_id()
returns uuid language sql stable security definer set search_path = ''
as $$
  select d.id from public.doctors d where d.user_id = private.current_user_id() limit 1
$$;

create or replace function private.current_patient_id()
returns uuid language sql stable security definer set search_path = ''
as $$
  select p.id from public.patients p where p.user_id = private.current_user_id() limit 1
$$;

create or replace function private.is_super_admin()
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(private.current_role() = 'super_admin', false)
$$;

create or replace function private.is_hospital_admin_for(target_hospital_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(
    private.is_super_admin()
    or (
      private.current_role() = 'hospital_admin'
      and private.current_hospital_id() = target_hospital_id
    ),
    false
  )
$$;

create or replace function private.can_access_patient(target_patient_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(
    target_patient_id = private.current_patient_id()
    or exists (
      select 1 from public.doctor_patient_assignments a
      where a.patient_id = target_patient_id
        and a.doctor_id = private.current_doctor_id()
        and a.ended_at is null
    )
    or exists (
      select 1 from public.consultations c
      where c.patient_id = target_patient_id
        and c.doctor_id = private.current_doctor_id()
        and c.status in ('approved', 'scheduled', 'in_progress', 'completed')
    ),
    false
  )
$$;

create or replace function private.can_access_guest_request(target_request_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(
    exists (
      select 1 from public.guest_consultation_requests g
      where g.id = target_request_id and g.submitted_by = (select auth.uid())
    )
    or exists (
      select 1 from public.guest_consultation_requests g
      where g.id = target_request_id and g.assigned_doctor_id = private.current_doctor_id()
    )
    or exists (
      select 1 from public.guest_consultation_requests g
      where g.id = target_request_id and private.is_hospital_admin_for(g.preferred_hospital_id)
    ),
    false
  )
$$;

create or replace function private.can_access_conversation(target_conversation_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(exists (
    select 1
    from public.chat_conversations c
    where c.id = target_conversation_id
      and (
        c.doctor_id = private.current_doctor_id()
        or (c.patient_id is not null and c.patient_id = private.current_patient_id())
        or (c.guest_request_id is not null and private.can_access_guest_request(c.guest_request_id))
      )
  ), false)
$$;

create or replace function private.can_view_user(target_user_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(
    target_user_id = private.current_user_id()
    or private.is_super_admin()
    or exists (
      select 1 from public.users target
      where target.id = target_user_id
        and private.current_role() = 'hospital_admin'
        and target.hospital_id = private.current_hospital_id()
    )
    or exists (
      select 1 from public.patients p
      where p.user_id = target_user_id and private.can_access_patient(p.id)
    ),
    false
  )
$$;

create or replace function private.storage_path_owner(object_name text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce((storage.foldername(object_name))[1] = (select auth.uid())::text, false)
$$;

create or replace function private.can_access_patient_storage(object_name text)
returns boolean language plpgsql stable security definer set search_path = ''
as $$
declare
  folder text := (storage.foldername(object_name))[1];
begin
  if folder is null or folder !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return false;
  end if;
  return private.can_access_patient(folder::uuid);
end;
$$;

revoke all on all functions in schema private from public, anon;
grant execute on all functions in schema private to authenticated;

create or replace function public.protect_user_privileges()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  actor_role text := private.current_role();
begin
  if (select auth.uid()) is null or actor_role = 'super_admin' then
    return new;
  end if;

  if actor_role = 'hospital_admin' and old.hospital_id = private.current_hospital_id() then
    if new.auth_user_id is distinct from old.auth_user_id
       or new.role_id is distinct from old.role_id
       or new.hospital_id is distinct from old.hospital_id then
      raise exception 'Hospital administrators cannot change identity, role, or hospital assignment directly';
    end if;
    return new;
  end if;

  if old.auth_user_id = (select auth.uid()) then
    if new.auth_user_id is distinct from old.auth_user_id
       or new.role_id is distinct from old.role_id
       or new.hospital_id is distinct from old.hospital_id
       or new.account_status is distinct from old.account_status then
      raise exception 'Role, hospital, identity, and account status are protected';
    end if;
    return new;
  end if;

  raise exception 'Not authorized to update this user';
end;
$$;

create or replace function public.log_audit_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  target_hospital_id uuid;
begin
  target_hospital_id := coalesce(
    nullif(row_data ->> 'hospital_id', '')::uuid,
    nullif(row_data ->> 'preferred_hospital_id', '')::uuid,
    nullif(row_data ->> 'primary_hospital_id', '')::uuid
  );

  insert into public.audit_logs (user_id, hospital_id, action, module, record_id)
  values (
    private.current_user_id(),
    target_hospital_id,
    lower(tg_op),
    tg_table_name,
    nullif(row_data ->> 'id', '')::uuid
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.protect_user_privileges(), public.log_audit_event() from public, anon, authenticated;

drop policy if exists guest_requests_owner_insert on public.guest_consultation_requests;
create policy guest_requests_owner_insert on public.guest_consultation_requests
  for insert to authenticated
  with check (
    submitted_by = (select auth.uid())
    and nullif((select auth.jwt()) ->> 'phone', '') is not null
  );

create index ai_assessments_guest_request_idx on public.ai_assessments (guest_request_id) where guest_request_id is not null;
create index ai_assessments_recommended_hospital_idx on public.ai_assessments (recommended_hospital_id) where recommended_hospital_id is not null;
create index chat_conversations_doctor_idx on public.chat_conversations (doctor_id);
create index chat_conversations_guest_request_idx on public.chat_conversations (guest_request_id) where guest_request_id is not null;
create index chat_conversations_patient_idx on public.chat_conversations (patient_id) where patient_id is not null;
create index chat_messages_sender_idx on public.chat_messages (sender_id, sent_at desc);
create index consultations_guest_request_idx on public.consultations (guest_request_id, appointment_date desc) where guest_request_id is not null;
create index doctors_created_by_admin_idx on public.doctors (created_by_admin) where created_by_admin is not null;
create index guest_requests_department_idx on public.guest_consultation_requests (preferred_department_id) where preferred_department_id is not null;
create index announcements_created_by_idx on public.hospital_announcements (created_by) where created_by is not null;
create index hospitals_created_by_idx on public.hospitals (created_by) where created_by is not null;
create index laboratory_results_consultation_idx on public.laboratory_results (consultation_id) where consultation_id is not null;
create index laboratory_results_hospital_idx on public.laboratory_results (hospital_id, uploaded_at desc);
create index medical_records_doctor_idx on public.medical_records (doctor_id, record_date desc);
create index medical_records_hospital_idx on public.medical_records (hospital_id, record_date desc);
create index notifications_guest_request_idx on public.notifications (guest_request_id, created_at desc) where guest_request_id is not null;
create index patients_guest_request_idx on public.patients (guest_request_id) where guest_request_id is not null;
create index prescriptions_doctor_idx on public.prescriptions (doctor_id, created_at desc);

commit;
