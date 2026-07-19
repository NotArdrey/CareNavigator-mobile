begin;

-- A revoked/deactivated application account must lose all helper-based RLS
-- access immediately, even while its Auth JWT is otherwise still valid.
create or replace function private.current_user_id()
returns uuid language sql stable security definer set search_path = ''
as $$
  select app_user.id
  from public.users app_user
  where app_user.auth_user_id = (select auth.uid())
    and app_user.account_status = 'active'
  limit 1
$$;

create or replace function private.current_role()
returns text language sql stable security definer set search_path = ''
as $$
  select role.role_name
  from public.users app_user
  join public.roles role on role.id = app_user.role_id
  where app_user.auth_user_id = (select auth.uid())
    and app_user.account_status = 'active'
  limit 1
$$;

create or replace function private.current_hospital_id()
returns uuid language sql stable security definer set search_path = ''
as $$
  select app_user.hospital_id
  from public.users app_user
  where app_user.auth_user_id = (select auth.uid())
    and app_user.account_status = 'active'
  limit 1
$$;

create or replace function private.can_access_guest_request(target_request_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(
    exists (
      select 1 from public.guest_consultation_requests guest_request
      where guest_request.id=target_request_id
        and guest_request.submitted_by=(select auth.uid())
        and private.current_user_id() is not null
    )
    or exists (
      select 1 from public.guest_consultation_requests guest_request
      where guest_request.id=target_request_id
        and guest_request.assigned_doctor_id=private.current_doctor_id()
    )
    or exists (
      select 1 from public.guest_consultation_requests guest_request
      where guest_request.id=target_request_id
        and private.is_hospital_admin_for(guest_request.preferred_hospital_id)
    ),false
  )
$$;

create or replace function private.storage_path_owner(object_name text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(
    private.current_user_id() is not null
    and (storage.foldername(object_name))[1]=(select auth.uid())::text,
    false
  )
$$;

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
        or (
          conversation.guest_request_id is not null
          and guest_request.submitted_by=(select auth.uid())
          and private.current_user_id() is not null
          and guest_request.request_status in (
            'approved','temporary_patient_created','account_activation_pending',
            'consultation_scheduled','consultation_completed'
          )
        )
      )
      and (
        consultation.status in ('approved','scheduled','in_progress','completed')
        or exists (
          select 1 from public.doctor_patient_assignments assignment
          where assignment.doctor_id=conversation.doctor_id
            and assignment.patient_id=conversation.patient_id
            and assignment.ended_at is null
        )
      )
  ),false)
$$;

create or replace function private.has_permission(target_permission text)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(exists (
    select 1
    from public.users app_user
    join public.role_permissions permission on permission.role_id = app_user.role_id
    where app_user.auth_user_id = (select auth.uid())
      and app_user.account_status = 'active'
      and permission.permission = target_permission
      and permission.is_allowed
  ),false)
$$;

insert into public.role_permissions(role_id,permission,is_allowed)
select role.id,permission_name,true
from public.roles role
cross join (values ('analytics.hospital.read'),('analytics.platform.read')) permission(permission_name)
where (role.role_name in ('doctor','hospital_admin') and permission_name='analytics.hospital.read')
   or (role.role_name='super_admin' and permission_name='analytics.platform.read')
on conflict(role_id,permission) do update set is_allowed=excluded.is_allowed,updated_at=now();

create or replace function public.current_permissions()
returns text[] language sql stable security invoker set search_path = ''
as $$
  select coalesce(array_agg(permission.permission order by permission.permission),'{}'::text[])
  from public.users app_user
  join public.role_permissions permission on permission.role_id=app_user.role_id
  where app_user.auth_user_id=(select auth.uid())
    and app_user.account_status='active'
    and permission.is_allowed
$$;

-- Keep notification storage as the canonical delivery event while exposing the
-- app route contract consumed by the Flutter client and delivery dispatcher.
alter table public.notifications
  add column if not exists action_path text,
  add column if not exists dedupe_key text;

alter table public.notification_preferences
  add column if not exists in_app_enabled boolean not null default true,
  alter column push_enabled set default false,
  alter column email_enabled set default false,
  alter column sms_enabled set default false;

update public.notifications
set action_path = coalesce(
  nullif(action_path, ''),
  case when action_url like '/%' and action_url not like '//%' then action_url end,
  case
    when notification_type = 'message' and data->>'conversation_id' is not null
      then '/messages/' || (data->>'conversation_id')
    when notification_type in ('consultation_update','account_activation','appointment_reminder','medical_result','prescription')
      then '/care'
    when notification_type = 'hospital_alert' then '/hospitals'
    else '/notifications'
  end
)
where action_path is null or action_path = '';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'notifications_action_path_check'
  ) then
    alter table public.notifications add constraint notifications_action_path_check
      check (action_path is null or (action_path like '/%' and action_path not like '//%'));
  end if;
end;
$$;

drop index if exists public.notifications_dedupe_key_idx;
create unique index notifications_dedupe_key_idx
  on public.notifications (user_id,dedupe_key) where dedupe_key is not null;
create index if not exists consultations_upcoming_reminders_idx
  on public.consultations (appointment_date, id)
  where status in ('approved','scheduled');
create unique index if not exists consultations_one_active_start_idx
  on public.consultations (doctor_id,appointment_date)
  where status not in ('rejected','cancelled');

create table if not exists public.appointment_reminder_jobs (
  consultation_id uuid not null references public.consultations(id) on delete cascade,
  appointment_date timestamptz not null,
  processed_at timestamptz not null default now(),
  primary key (consultation_id,appointment_date)
);
alter table public.appointment_reminder_jobs enable row level security;

create or replace function private.is_doctor_slot_available(
  target_doctor_id uuid,
  target_hospital_id uuid,
  target_type public.consultation_type,
  target_start timestamptz,
  excluded_consultation_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select coalesce(
    target_start>now()
    and exists(
      select 1
      from public.doctors doctor
      join public.hospitals hospital on hospital.id=doctor.hospital_id
      where doctor.id=target_doctor_id
        and doctor.hospital_id=target_hospital_id
        and doctor.availability_status<>'unavailable'
        and hospital.verification_status='verified'
        and hospital.operating_status in ('open','limited')
    )
    and exists(
      select 1
      from public.doctor_schedules schedule
      where schedule.doctor_id=target_doctor_id
        and schedule.is_active
        and (
          schedule.consultation_type=target_type
          or (target_type='guest_online' and schedule.consultation_type='online')
        )
        and schedule.day_of_week=extract(dow from target_start)::integer
        and target_start::time>=schedule.starts_at
        and target_start::time+make_interval(mins=>schedule.slot_minutes)<=schedule.ends_at
        and not exists(
          select 1
          from public.consultations consultation
          where consultation.doctor_id=target_doctor_id
            and consultation.id is distinct from excluded_consultation_id
            and consultation.status not in ('rejected','cancelled')
            and consultation.appointment_date < target_start+make_interval(mins=>schedule.slot_minutes)
            and consultation.appointment_date > target_start-make_interval(mins=>schedule.slot_minutes)
        )
    ),false
  )
$$;

create or replace function public.review_guest_consultation(
  target_request_id uuid,
  decision text,
  target_doctor_id uuid default null,
  target_appointment_date timestamptz default null,
  review_notes text default null
)
returns jsonb language plpgsql security invoker set search_path = ''
as $$
declare
  request_row public.guest_consultation_requests;
  chosen_doctor uuid;
  scheduled_time timestamptz;
  temporary_patient_id uuid;
  created_consultation_id uuid;
begin
  if not (private.has_permission('patients.manage') or private.has_permission('hospital.manage')) then
    raise exception 'Guest consultation review permission is required';
  end if;
  select * into request_row
  from public.guest_consultation_requests where id=target_request_id for update;
  if not found then raise exception 'Guest consultation request was not found'; end if;
  if not (
    private.is_hospital_admin_for(request_row.preferred_hospital_id)
    or request_row.assigned_doctor_id=private.current_doctor_id()
  ) then raise exception 'Not authorized to review this request'; end if;
  if decision not in ('approved','rejected') then
    raise exception 'Decision must be approved or rejected';
  end if;
  if decision='rejected' then
    update public.guest_consultation_requests
    set request_status='rejected',reviewed_by=private.current_user_id(),reviewed_at=now(),
      rejection_reason=nullif(btrim(review_notes),''),identity_review_notes=review_notes
    where id=target_request_id;
    return jsonb_build_object(
      'request_id',target_request_id,'patient_id',null,'consultation_id',null,'status','rejected'
    );
  end if;

  chosen_doctor:=coalesce(target_doctor_id,request_row.assigned_doctor_id,private.current_doctor_id());
  scheduled_time:=coalesce(target_appointment_date,request_row.preferred_schedule);
  if private.current_role()='hospital_admin' and target_doctor_id is null then
    raise exception 'A doctor must be assigned';
  end if;
  if chosen_doctor is null or scheduled_time is null then
    raise exception 'An available doctor and future appointment time are required';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(chosen_doctor::text||':'||scheduled_time::date::text,0)
  );
  if not private.is_doctor_slot_available(
    chosen_doctor,request_row.preferred_hospital_id,'guest_online',scheduled_time,null
  ) then raise exception 'The selected appointment slot is unavailable'; end if;

  update public.guest_consultation_requests
  set request_status='approved',assigned_doctor_id=chosen_doctor,
    reviewed_by=private.current_user_id(),reviewed_at=now(),identity_review_status='verified',
    identity_review_notes=review_notes
  where id=target_request_id;

  select id into temporary_patient_id
  from public.patients where guest_request_id=target_request_id;
  if temporary_patient_id is null then
    insert into public.patients(
      created_by_doctor,guest_request_id,primary_hospital_id,allergies,existing_conditions,
      identity_verification_status,account_activation_status,converted_from_guest,profile_status
    ) values(
      chosen_doctor,target_request_id,request_row.preferred_hospital_id,
      request_row.allergies,request_row.existing_conditions,'verified','pending',true,'temporary'
    ) returning id into temporary_patient_id;
  end if;
  insert into public.doctor_patient_assignments(doctor_id,patient_id,notes)
  values(
    chosen_doctor,temporary_patient_id,
    'Created from guest consultation '||request_row.reference_number
  ) on conflict do nothing;
  insert into public.consultations(
    patient_id,guest_request_id,doctor_id,hospital_id,department_id,consultation_type,
    appointment_date,status,chief_complaint,approved_by,approved_at
  ) values(
    null,target_request_id,chosen_doctor,request_row.preferred_hospital_id,
    request_row.preferred_department_id,'guest_online',scheduled_time,'scheduled',
    request_row.consultation_reason,private.current_user_id(),now()
  ) returning id into created_consultation_id;
  update public.guest_consultation_requests
  set request_status='consultation_scheduled' where id=target_request_id;
  return jsonb_build_object(
    'request_id',target_request_id,'patient_id',temporary_patient_id,
    'consultation_id',created_consultation_id,'status','consultation_scheduled'
  );
end;
$$;

create or replace function public.transition_consultation(
  target_consultation_id uuid,
  target_status public.consultation_status,
  transition_notes text default null,
  scheduled_for timestamptz default null,
  clinical_payload jsonb default '{}'::jsonb
)
returns jsonb language plpgsql security invoker set search_path = ''
as $$
declare result_row public.consultations;
begin
  if not (private.has_permission('consultations.read_own') or private.has_permission('hospital.manage')) then
    raise exception 'Consultation workflow permission is required';
  end if;
  select * into result_row
  from public.consultations where id=target_consultation_id for update;
  if not found or not private.is_consultation_participant(target_consultation_id) then
    raise exception 'Consultation was not found or is not accessible';
  end if;

  if scheduled_for is not null and scheduled_for is distinct from result_row.appointment_date then
    if target_status not in ('approved','scheduled') then
      raise exception 'Only an approved or scheduled consultation may be rescheduled';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(result_row.doctor_id::text||':'||scheduled_for::date::text,0)
    );
    if not private.is_doctor_slot_available(
      result_row.doctor_id,result_row.hospital_id,result_row.consultation_type,
      scheduled_for,result_row.id
    ) then raise exception 'The selected appointment slot is unavailable'; end if;
  end if;

  update public.consultations
  set status=target_status,
    appointment_date=coalesce(scheduled_for,appointment_date),
    rejection_reason=case when target_status='rejected' then nullif(btrim(transition_notes),'') else rejection_reason end,
    doctor_notes=case when private.current_doctor_id()=doctor_id then coalesce(clinical_payload->>'doctor_notes',doctor_notes) else doctor_notes end,
    confirmed_diagnosis=case when private.current_doctor_id()=doctor_id then coalesce(clinical_payload->>'confirmed_diagnosis',confirmed_diagnosis) else confirmed_diagnosis end,
    treatment_plan=case when private.current_doctor_id()=doctor_id then coalesce(clinical_payload->>'treatment_plan',treatment_plan) else treatment_plan end,
    consultation_summary=case when private.current_doctor_id()=doctor_id then coalesce(clinical_payload->>'consultation_summary',consultation_summary) else consultation_summary end,
    approved_by=case when target_status in ('approved','scheduled') then private.current_user_id() else approved_by end,
    approved_at=case when target_status in ('approved','scheduled') then coalesce(approved_at,now()) else approved_at end,
    rejected_at=case when target_status='rejected' then now() else rejected_at end
  where id=target_consultation_id returning * into result_row;
  if result_row.guest_request_id is not null then
    update public.guest_consultation_requests
    set request_status=case target_status
      when 'completed' then 'consultation_completed'::public.guest_request_status
      when 'cancelled' then 'cancelled'::public.guest_request_status
      else request_status end
    where id=result_row.guest_request_id;
  end if;
  return jsonb_build_object(
    'id',result_row.id,'status',result_row.status,
    'appointment_date',result_row.appointment_date,'completed_at',result_row.completed_at
  );
end;
$$;

-- Identify treatment plans synchronized from the consultation completion RPC
-- without constraining legitimate manually-authored plans.
alter table public.diagnoses
  add column if not exists source text not null default 'manual';
alter table public.treatment_plans
  add column if not exists source text not null default 'manual';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'diagnoses_source_check'
  ) then
    alter table public.diagnoses add constraint diagnoses_source_check
      check (source in ('manual','consultation_completion'));
  end if;
  if not exists (
    select 1 from pg_constraint where conname = 'treatment_plans_source_check'
  ) then
    alter table public.treatment_plans add constraint treatment_plans_source_check
      check (source in ('manual','consultation_completion'));
  end if;
end;
$$;

create unique index if not exists treatment_plans_consultation_completion_idx
  on public.treatment_plans (consultation_id)
  where source = 'consultation_completion';

-- Allow only one nonterminal processing attempt per result. Historical rows
-- remain intact; duplicate nonterminal rows are safely cancelled before the
-- concurrency guard is created.
with ranked_jobs as (
  select id,
    row_number() over (
      partition by laboratory_result_id
      order by created_at desc, id desc
    ) as position
  from public.document_processing_jobs
  where laboratory_result_id is not null
    and status in ('queued','ocr_processing','ai_analysis_pending','pending_doctor_review')
)
update public.document_processing_jobs job
set status = 'cancelled',
    last_error = coalesce(job.last_error, 'Superseded by a newer processing attempt'),
    completed_at = coalesce(job.completed_at, now()),
    updated_at = now()
from ranked_jobs ranked
where job.id = ranked.id and ranked.position > 1;

create unique index if not exists document_jobs_one_active_result_idx
  on public.document_processing_jobs (laboratory_result_id)
  where laboratory_result_id is not null
    and status in ('queued','ocr_processing','ai_analysis_pending','pending_doctor_review');

create or replace function private.notification_action_path(
  target_type text,
  target_data jsonb
)
returns text
language sql
immutable
set search_path = ''
as $$
  select case
    when target_type = 'message'
      and coalesce(target_data->>'conversation_id','') ~ '^[0-9a-fA-F-]{36}$'
      then '/messages/' || (target_data->>'conversation_id')
    when target_type in ('consultation_update','account_activation','appointment_reminder','medical_result','prescription')
      then '/care'
    when target_type = 'hospital_alert' then '/hospitals'
    else '/notifications'
  end
$$;

create or replace function private.enqueue_notification(
  target_user_id uuid,
  target_title text,
  target_message text,
  target_type text,
  target_reference_id uuid default null,
  target_data jsonb default '{}'::jsonb
)
returns uuid
language plpgsql
security definer
set search_path = ''
as $$
declare
  notification_id uuid;
  generated_dedupe_key text;
begin
  if target_user_id is null then return null; end if;

  generated_dedupe_key := nullif(target_data->>'dedupe_key','');
  if generated_dedupe_key is null and target_reference_id is not null then
    generated_dedupe_key := concat_ws(
      ':',
      target_type,
      target_reference_id::text,
      coalesce(nullif(target_data->>'event_key',''), nullif(target_data->>'status',''), 'event')
    );
  end if;

  insert into public.notifications (
    user_id,title,message,notification_type,reference_id,data,action_path,dedupe_key
  ) values (
    target_user_id,
    target_title,
    target_message,
    target_type,
    target_reference_id,
    coalesce(target_data,'{}'::jsonb) - 'dedupe_key',
    private.notification_action_path(target_type,coalesce(target_data,'{}'::jsonb)),
    generated_dedupe_key
  )
  on conflict (user_id,dedupe_key) where dedupe_key is not null do nothing
  returning id into notification_id;

  if notification_id is null and generated_dedupe_key is not null then
    select id into notification_id
    from public.notifications
    where user_id=target_user_id and dedupe_key=generated_dedupe_key;
  end if;
  return notification_id;
end;
$$;

create or replace function public.queue_notification_deliveries()
returns trigger
language plpgsql
security definer
set search_path = ''
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

  -- No external delivery is implicit. Users explicitly opt in after a provider
  -- has been configured; the in-app notification above remains available.
  if coalesce((select push_enabled from public.notification_preferences where user_id=new.user_id),false) then
    insert into public.notification_outbox(notification_id,user_id,channel) values(new.id,new.user_id,'push') on conflict do nothing;
  end if;
  if coalesce((select email_enabled from public.notification_preferences where user_id=new.user_id),false) then
    insert into public.notification_outbox(notification_id,user_id,channel) values(new.id,new.user_id,'email') on conflict do nothing;
  end if;
  if coalesce((select sms_enabled from public.notification_preferences where user_id=new.user_id),false) then
    insert into public.notification_outbox(notification_id,user_id,channel) values(new.id,new.user_id,'sms') on conflict do nothing;
  end if;
  return new;
end;
$$;

create or replace function public.complete_notification_delivery(
  target_outbox_id bigint,
  delivered boolean,
  provider_id text default null,
  error_message text default null
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.notification_outbox
  set status=case
        when delivered then 'delivered'
        when attempt_count>=5 then 'cancelled'
        else 'failed'
      end,
      provider_message_id=provider_id,
      last_error=case when delivered then null else left(coalesce(error_message,'Delivery failed'),1000) end,
      delivered_at=case when delivered then now() else null end,
      next_attempt_at=case
        when delivered or attempt_count>=5 then next_attempt_at
        else now()+make_interval(mins=>least(60,power(2,least(attempt_count,5))::integer))
      end,
      updated_at=now()
  where id=target_outbox_id and status='processing';
  if not found then raise exception 'Processing outbox delivery was not found'; end if;
end;
$$;

drop policy if exists notifications_owner_read on public.notifications;
create policy notifications_owner_read on public.notifications
for select to authenticated using (
  user_id = (select auth.uid())
  and private.current_user_id() is not null
  and coalesce((
    select preference.in_app_enabled
    from public.notification_preferences preference
    where preference.user_id = (select auth.uid())
  ), true)
);

drop policy if exists notifications_owner_update on public.notifications;
create policy notifications_owner_update on public.notifications
for update to authenticated using (
  user_id=(select auth.uid()) and private.current_user_id() is not null
) with check (
  user_id=(select auth.uid()) and private.current_user_id() is not null
);

drop policy if exists guest_requests_owner_insert on public.guest_consultation_requests;
create policy guest_requests_owner_insert on public.guest_consultation_requests
for insert to authenticated with check (
  submitted_by=(select auth.uid())
  and private.current_user_id() is not null
  and nullif((select auth.jwt())->>'phone','') is not null
);

drop policy if exists ai_assessments_owner_read on public.ai_assessments;
create policy ai_assessments_owner_read on public.ai_assessments
for select to authenticated using (
  private.current_user_id() is not null
  and (
    user_id=(select auth.uid())
    or (patient_id is not null and private.can_access_patient(patient_id))
    or (guest_request_id is not null and private.can_access_guest_request(guest_request_id))
  )
);
drop policy if exists ai_assessments_owner_insert on public.ai_assessments;
create policy ai_assessments_owner_insert on public.ai_assessments
for insert to authenticated with check (
  user_id=(select auth.uid()) and private.current_user_id() is not null
);

drop policy if exists notification_preferences_owner_manage on public.notification_preferences;
create policy notification_preferences_owner_manage on public.notification_preferences
for all to authenticated using (
  user_id=(select auth.uid()) and private.current_user_id() is not null
) with check (
  user_id=(select auth.uid()) and private.current_user_id() is not null
);
drop policy if exists device_tokens_owner_manage on public.device_tokens;
create policy device_tokens_owner_manage on public.device_tokens
for all to authenticated using (
  user_id=(select auth.uid()) and private.current_user_id() is not null
) with check (
  user_id=(select auth.uid()) and private.current_user_id() is not null
);

drop policy if exists chat_attachments_sender_insert on public.chat_message_attachments;
create policy chat_attachments_sender_insert on public.chat_message_attachments
for insert to authenticated with check (
  private.current_user_id() is not null
  and uploaded_by=(select auth.uid())
  and exists(
    select 1 from public.chat_messages message
    where message.id=message_id and message.sender_id=(select auth.uid())
  )
);

drop policy if exists assessment_recommendations_owner_read on public.ai_assessment_recommendations;
create policy assessment_recommendations_owner_read on public.ai_assessment_recommendations
for select to authenticated using (
  private.current_user_id() is not null
  and exists(
    select 1 from public.ai_assessments assessment
    where assessment.id=assessment_id and (
      assessment.user_id=(select auth.uid())
      or (assessment.patient_id is not null and private.can_access_patient(assessment.patient_id))
      or (assessment.guest_request_id is not null and private.can_access_guest_request(assessment.guest_request_id))
    )
  )
);
drop policy if exists assessment_recommendations_owner_insert on public.ai_assessment_recommendations;
create policy assessment_recommendations_owner_insert on public.ai_assessment_recommendations
for insert to authenticated with check (
  private.current_user_id() is not null
  and exists(
    select 1 from public.ai_assessments assessment
    where assessment.id=assessment_id and assessment.user_id=(select auth.uid())
  )
);

create or replace function private.enqueue_hospital_audience(
  target_hospital_id uuid,
  target_title text,
  target_message text,
  target_type text,
  target_reference_id uuid,
  target_data jsonb default '{}'::jsonb
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  recipient record;
  enqueued integer := 0;
begin
  for recipient in
    select distinct audience.auth_user_id
    from (
      select app_user.auth_user_id
      from public.users app_user
      where app_user.account_status = 'active'
        and (target_hospital_id is null or app_user.hospital_id = target_hospital_id)
      union
      select app_user.auth_user_id
      from public.patients patient
      join public.users app_user on app_user.id = patient.user_id
      where app_user.account_status = 'active'
        and (target_hospital_id is null or patient.primary_hospital_id = target_hospital_id)
    ) audience
    where audience.auth_user_id is not null
  loop
    perform private.enqueue_notification(
      recipient.auth_user_id,target_title,target_message,target_type,
      target_reference_id,target_data
    );
    enqueued := enqueued + 1;
  end loop;
  return enqueued;
end;
$$;

create or replace function public.notify_consultation_status_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  patient_recipient uuid;
  doctor_recipient uuid;
  event_key text;
  safe_data jsonb;
begin
  if tg_op = 'UPDATE' then
    if new.status is not distinct from old.status
      and new.appointment_date is not distinct from old.appointment_date then
      return new;
    end if;
  end if;

  if new.patient_id is not null then
    select app_user.auth_user_id into patient_recipient
    from public.patients patient
    join public.users app_user on app_user.id = patient.user_id
    where patient.id = new.patient_id;
  elsif new.guest_request_id is not null then
    select submitted_by into patient_recipient
    from public.guest_consultation_requests
    where id = new.guest_request_id;
  end if;

  select app_user.auth_user_id into doctor_recipient
  from public.doctors doctor
  join public.users app_user on app_user.id = doctor.user_id
  where doctor.id = new.doctor_id;

  event_key := new.status::text || ':' || new.appointment_date::text;
  safe_data := jsonb_build_object(
    'status',new.status,
    'appointment_date',new.appointment_date,
    'hospital_id',new.hospital_id,
    'event_key',event_key
  );

  perform private.enqueue_notification(
    patient_recipient,
    'Consultation update',
    'Your consultation is now ' || replace(new.status::text,'_',' '),
    'consultation_update',new.id,safe_data
  );
  perform private.enqueue_notification(
    doctor_recipient,
    'Consultation assignment update',
    'An assigned consultation is now ' || replace(new.status::text,'_',' '),
    'consultation_update',new.id,safe_data
  );
  return new;
end;
$$;

drop trigger if exists notify_consultation_status_after_write on public.consultations;
create trigger notify_consultation_status_after_write
after insert or update of status, appointment_date on public.consultations
for each row execute function public.notify_consultation_status_change();

create or replace function public.notify_patient_account_activation()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare recipient uuid;
begin
  if new.user_id is null
    or new.account_activation_status <> 'active'
    or new.profile_status <> 'official' then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if old.user_id is not distinct from new.user_id
      and old.account_activation_status is not distinct from new.account_activation_status
      and old.profile_status is not distinct from new.profile_status then
      return new;
    end if;
  end if;
  select auth_user_id into recipient from public.users where id = new.user_id;
  perform private.enqueue_notification(
    recipient,'Patient account activated',
    'Your CareNavigator patient account is active and ready to use.',
    'account_activation',new.id,
    jsonb_build_object('status','active','event_key','active')
  );
  return new;
end;
$$;

drop trigger if exists notify_patient_account_activation_after_write on public.patients;
create trigger notify_patient_account_activation_after_write
after insert or update of user_id, account_activation_status, profile_status on public.patients
for each row execute function public.notify_patient_account_activation();

create or replace function public.notify_prescription_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare recipient uuid;
begin
  select app_user.auth_user_id into recipient
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where patient.id = new.patient_id;
  perform private.enqueue_notification(
    recipient,'New prescription',
    'A doctor added a prescription to your care record.',
    'prescription',new.id,
    jsonb_build_object('consultation_id',new.consultation_id,'event_key','created')
  );
  return new;
end;
$$;

drop trigger if exists notify_prescription_after_insert on public.prescriptions;
create trigger notify_prescription_after_insert
after insert on public.prescriptions
for each row execute function public.notify_prescription_created();

create or replace function public.notify_laboratory_result_ready()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare recipient uuid;
begin
  if tg_op = 'UPDATE' then
    if new.verification_status is not distinct from old.verification_status then
      return new;
    end if;
  end if;
  if new.verification_status not in ('doctor_confirmed','doctor_modified','saved_to_patient_record') then
    return new;
  end if;

  update public.document_processing_jobs
  set status = 'completed',
      completed_at = coalesce(completed_at,now()),
      last_error = null,
      updated_at = now()
  where laboratory_result_id = new.id
    and status in ('queued','ocr_processing','ai_analysis_pending','pending_doctor_review');

  select app_user.auth_user_id into recipient
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where patient.id = new.patient_id;
  perform private.enqueue_notification(
    recipient,'Medical result reviewed',
    'A doctor-reviewed laboratory result is ready in your care record.',
    'medical_result',new.id,
    jsonb_build_object(
      'status',new.verification_status,
      'event_key','doctor_reviewed',
      'dedupe_key','medical_result:' || new.id::text || ':doctor_reviewed'
    )
  );
  return new;
end;
$$;

drop trigger if exists notify_laboratory_result_ready_after_write on public.laboratory_results;
create trigger notify_laboratory_result_ready_after_write
after insert or update of verification_status on public.laboratory_results
for each row execute function public.notify_laboratory_result_ready();

create or replace function public.notify_hospital_announcement()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.published_at > now() or (new.expires_at is not null and new.expires_at <= now()) then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if new.title is not distinct from old.title
      and new.message is not distinct from old.message
      and new.published_at is not distinct from old.published_at
      and new.expires_at is not distinct from old.expires_at then
      return new;
    end if;
  end if;
  perform private.enqueue_hospital_audience(
    new.hospital_id,
    new.title,
    new.message,
    'hospital_alert',
    new.id,
    jsonb_build_object(
      'hospital_id',new.hospital_id,
      'is_global',new.is_global,
      'event_key','announcement:' || new.published_at::text
    )
  );
  return new;
end;
$$;

drop trigger if exists notify_hospital_announcement_after_write on public.hospital_announcements;
create trigger notify_hospital_announcement_after_write
after insert or update of title, message, published_at, expires_at on public.hospital_announcements
for each row execute function public.notify_hospital_announcement();

create or replace function public.notify_hospital_status_alert()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  new_data jsonb := to_jsonb(new);
  old_data jsonb := to_jsonb(old);
  target_hospital uuid;
  new_status text;
  old_status text;
  reference uuid;
begin
  target_hospital := case when tg_table_name = 'hospitals'
    then new.id else (new_data->>'hospital_id')::uuid end;
  reference := new.id;
  new_status := coalesce(new_data->>'operating_status',new_data->>'status');
  old_status := coalesce(old_data->>'operating_status',old_data->>'status');
  if new_status is not distinct from old_status then return new; end if;

  perform private.enqueue_hospital_audience(
    target_hospital,
    'Hospital status update',
    'A hospital availability status changed to ' || replace(new_status,'_',' ') || '.',
    'hospital_alert',
    reference,
    jsonb_build_object(
      'hospital_id',target_hospital,
      'source',tg_table_name,
      'status',new_status,
      'event_key',tg_table_name || ':' || clock_timestamp()::text
    )
  );
  return new;
end;
$$;

drop trigger if exists notify_hospital_operating_status_after_update on public.hospitals;
create trigger notify_hospital_operating_status_after_update
after update of operating_status on public.hospitals
for each row execute function public.notify_hospital_status_alert();
drop trigger if exists notify_emergency_status_after_update on public.emergency_room_status;
create trigger notify_emergency_status_after_update
after update of status on public.emergency_room_status
for each row execute function public.notify_hospital_status_alert();
drop trigger if exists notify_facility_status_after_update on public.hospital_facility_status;
create trigger notify_facility_status_after_update
after update of status on public.hospital_facility_status
for each row execute function public.notify_hospital_status_alert();

-- This service-role RPC is the scheduler-neutral reminder producer. A trusted
-- cron/queue runner can invoke it repeatedly; dedupe keys make retries safe.
create or replace function public.enqueue_due_appointment_reminders(
  batch_size integer default 100,
  reminder_window interval default interval '24 hours'
)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  consultation_row record;
  patient_recipient uuid;
  doctor_recipient uuid;
  processed integer := 0;
  safe_data jsonb;
begin
  if reminder_window <= interval '0 seconds' or reminder_window > interval '14 days' then
    raise exception 'Reminder window must be between zero and fourteen days';
  end if;

  for consultation_row in
    select consultation.id,consultation.patient_id,consultation.guest_request_id,
      consultation.doctor_id,consultation.hospital_id,consultation.appointment_date
    from public.consultations consultation
    where consultation.status in ('approved','scheduled')
      and consultation.appointment_date > now()
      and consultation.appointment_date <= now() + reminder_window
      and not exists (
        select 1 from public.appointment_reminder_jobs reminder_job
        where reminder_job.consultation_id=consultation.id
          and reminder_job.appointment_date=consultation.appointment_date
      )
    order by consultation.appointment_date,consultation.id
    for update skip locked
    limit least(greatest(batch_size,1),500)
  loop
    insert into public.appointment_reminder_jobs(consultation_id,appointment_date)
    values(consultation_row.id,consultation_row.appointment_date)
    on conflict do nothing;
    if not found then continue; end if;

    patient_recipient := null;
    doctor_recipient := null;
    if consultation_row.patient_id is not null then
      select app_user.auth_user_id into patient_recipient
      from public.patients patient
      join public.users app_user on app_user.id = patient.user_id
      where patient.id = consultation_row.patient_id;
    elsif consultation_row.guest_request_id is not null then
      select submitted_by into patient_recipient
      from public.guest_consultation_requests
      where id = consultation_row.guest_request_id;
    end if;
    select app_user.auth_user_id into doctor_recipient
    from public.doctors doctor
    join public.users app_user on app_user.id = doctor.user_id
    where doctor.id = consultation_row.doctor_id;

    safe_data := jsonb_build_object(
      'appointment_date',consultation_row.appointment_date,
      'hospital_id',consultation_row.hospital_id,
      'event_key','appointment:' || consultation_row.appointment_date::text,
      'dedupe_key','appointment_reminder:' || consultation_row.id::text || ':' || consultation_row.appointment_date::text
    );
    perform private.enqueue_notification(
      patient_recipient,'Upcoming consultation',
      'You have an upcoming CareNavigator consultation.',
      'appointment_reminder',consultation_row.id,safe_data
    );
    perform private.enqueue_notification(
      doctor_recipient,'Upcoming assigned consultation',
      'An assigned CareNavigator consultation is approaching.',
      'appointment_reminder',consultation_row.id,
      safe_data || jsonb_build_object(
        'dedupe_key','doctor_appointment_reminder:' || consultation_row.id::text || ':' || consultation_row.appointment_date::text
      )
    );
    processed := processed + 1;
  end loop;
  return processed;
end;
$$;

create or replace function public.sync_completed_consultation_clinical_records()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.status <> 'completed' or new.patient_id is null then return new; end if;

  if nullif(btrim(new.confirmed_diagnosis),'') is not null then
    insert into public.diagnoses (
      patient_id,consultation_id,doctor_id,hospital_id,diagnosis,is_primary,confirmed_at,source
    ) values (
      new.patient_id,new.id,new.doctor_id,new.hospital_id,btrim(new.confirmed_diagnosis),true,
      coalesce(new.completed_at,now()),'consultation_completion'
    )
    on conflict (consultation_id) where is_primary do update
    set diagnosis = excluded.diagnosis,
        doctor_id = excluded.doctor_id,
        hospital_id = excluded.hospital_id,
        confirmed_at = excluded.confirmed_at,
        updated_at = now();
  end if;

  if nullif(btrim(new.treatment_plan),'') is not null then
    insert into public.treatment_plans (
      patient_id,consultation_id,doctor_id,hospital_id,plan,status,source
    ) values (
      new.patient_id,new.id,new.doctor_id,new.hospital_id,btrim(new.treatment_plan),'active','consultation_completion'
    )
    on conflict (consultation_id) where source = 'consultation_completion' do update
    set plan = excluded.plan,
        doctor_id = excluded.doctor_id,
        hospital_id = excluded.hospital_id,
        updated_at = now();
  end if;
  return new;
end;
$$;

drop trigger if exists sync_completed_consultation_clinical_records_after_write on public.consultations;
create trigger sync_completed_consultation_clinical_records_after_write
after insert or update of status, patient_id, confirmed_diagnosis, treatment_plan on public.consultations
for each row execute function public.sync_completed_consultation_clinical_records();

create or replace function public.log_user_security_change()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.account_status is distinct from old.account_status then
    insert into public.security_logs(actor_auth_user_id,event_type,severity,success,metadata)
    values(
      (select auth.uid()),'account_status_changed',
      case when new.account_status='active' then 'info' else 'warning' end,
      true,
      jsonb_build_object(
        'target_user_id',new.id,
        'old_status',old.account_status,
        'new_status',new.account_status
      )
    );
  end if;
  if new.role_id is distinct from old.role_id then
    insert into public.security_logs(actor_auth_user_id,event_type,severity,success,metadata)
    values(
      (select auth.uid()),'account_role_changed','warning',true,
      jsonb_build_object(
        'target_user_id',new.id,
        'old_role_id',old.role_id,
        'new_role_id',new.role_id
      )
    );
  end if;
  return new;
end;
$$;

create or replace function public.protect_hospital_approval_fields()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare actor_role text := private.current_role();
begin
  -- Database/service-role maintenance and super-admin approval workflows keep
  -- full control. Hospital administrators retain their normal scoped profile
  -- update policy but cannot self-approve or transfer the hospital record.
  if (select auth.uid()) is null or actor_role='super_admin' then return new; end if;
  if actor_role<>'hospital_admin' or old.id is distinct from private.current_hospital_id() then
    raise exception 'Hospital update is not authorized';
  end if;
  if new.id is distinct from old.id
    or new.verification_status is distinct from old.verification_status
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at then
    raise exception 'Hospital administrators cannot change approval or ownership fields';
  end if;
  return new;
end;
$$;

drop trigger if exists protect_hospital_approval_fields_before_update on public.hospitals;
create trigger protect_hospital_approval_fields_before_update
before update on public.hospitals
for each row execute function public.protect_hospital_approval_fields();

drop trigger if exists log_user_security_change_after_update on public.users;
create trigger log_user_security_change_after_update
after update of account_status, role_id on public.users
for each row execute function public.log_user_security_change();

create or replace function public.get_patient_medical_records(target_patient_id uuid)
returns setof public.medical_records
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not (
    private.has_permission('records.read_own')
    or private.has_permission('records.write')
  ) then raise exception 'Medical record permission is required'; end if;
  if not private.can_access_patient(target_patient_id) then
    raise exception 'Patient record access is not authorized';
  end if;
  insert into public.medical_record_access_logs(
    patient_id,actor_user_id,actor_role,resource_type,access_type
  ) values(
    target_patient_id,private.current_user_id(),private.current_role(),'medical_records','list'
  );
  return query
  select record.* from public.medical_records record
  where record.patient_id=target_patient_id
  order by record.record_date desc,record.created_at desc;
end;
$$;

create index if not exists medical_access_logs_resource_idx
  on public.medical_record_access_logs(resource_type,resource_id,created_at desc);

create or replace function public.record_clinical_access(
  target_resource_type text,
  target_resource_id uuid,
  target_action text
)
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  target_patient_id uuid;
  created_log_id bigint;
begin
  if private.current_user_id() is null then raise exception 'An active account is required'; end if;
  if target_action not in ('view','download') then
    raise exception 'Clinical access action must be view or download';
  end if;

  case target_resource_type
    when 'medical_record' then
      select patient_id into target_patient_id
      from public.medical_records where id=target_resource_id;
    when 'laboratory_result' then
      select patient_id into target_patient_id
      from public.laboratory_results where id=target_resource_id;
    when 'medical_document' then
      select patient_id into target_patient_id
      from public.medical_documents where id=target_resource_id;
    when 'consultation_attachment' then
      select patient_id into target_patient_id
      from public.consultation_attachments where id=target_resource_id;
    when 'prescription' then
      select patient_id into target_patient_id
      from public.prescriptions where id=target_resource_id;
    else raise exception 'Unsupported clinical resource type';
  end case;

  if target_patient_id is null or not private.can_access_patient(target_patient_id) then
    raise exception 'Clinical resource was not found or is not accessible';
  end if;
  insert into public.medical_record_access_logs(
    patient_id,actor_user_id,actor_role,resource_type,resource_id,access_type,metadata
  ) values(
    target_patient_id,private.current_user_id(),private.current_role(),
    target_resource_type,target_resource_id,target_action,
    jsonb_build_object('hospital_id',private.current_hospital_id())
  ) returning id into created_log_id;
  return created_log_id;
end;
$$;

drop policy if exists medical_access_logs_patient_read on public.medical_record_access_logs;
create policy medical_access_logs_authorized_read on public.medical_record_access_logs
for select to authenticated using (
  patient_id=private.current_patient_id()
  or private.can_access_patient(patient_id)
  or private.is_super_admin()
  or exists(
    select 1 from public.patients patient
    where patient.id=medical_record_access_logs.patient_id
      and private.is_hospital_admin_for(patient.primary_hospital_id)
  )
);

revoke insert on public.medical_record_access_logs from authenticated;

create or replace function public.hospital_analytics()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  target_hospital uuid := private.current_hospital_id();
  result jsonb;
begin
  if private.current_role() = 'doctor' then
    select hospital_id into target_hospital
    from public.doctors where id = private.current_doctor_id();
  end if;
  if private.current_role() not in ('hospital_admin','doctor')
    or not private.has_permission('analytics.hospital.read')
    or target_hospital is null then
    raise exception 'Hospital-scoped analytics access is required';
  end if;

  select jsonb_build_object(
    'hospital_id',target_hospital,
    'consultations_total',(select count(*) from public.consultations c where c.hospital_id=target_hospital),
    'consultations_by_status',(select coalesce(jsonb_object_agg(status,total),'{}'::jsonb) from (
      select c.status::text status,count(*) total
      from public.consultations c where c.hospital_id=target_hospital group by c.status
    ) grouped),
    'consultations_by_doctor',(select coalesce(jsonb_agg(to_jsonb(grouped) order by grouped.consultations desc),'[]'::jsonb) from (
      select d.id doctor_id,d.display_name,count(c.id) consultations
      from public.doctors d
      left join public.consultations c on c.doctor_id=d.id and c.hospital_id=target_hospital
      where d.hospital_id=target_hospital
      group by d.id,d.display_name
    ) grouped),
    'doctor_activity',(select coalesce(jsonb_agg(to_jsonb(grouped) order by grouped.consultation_events desc),'[]'::jsonb) from (
      select d.id doctor_id,d.display_name,
        count(distinct c.id) consultations,
        count(distinct history.id) consultation_events,
        count(distinct audit.id) audit_events
      from public.doctors d
      join public.users app_user on app_user.id=d.user_id
      left join public.consultations c on c.doctor_id=d.id and c.hospital_id=target_hospital
      left join public.consultation_status_history history on history.consultation_id=c.id
      left join public.audit_logs audit on audit.user_id=app_user.id and audit.hospital_id=target_hospital
      where d.hospital_id=target_hospital
      group by d.id,d.display_name
    ) grouped),
    'active_doctors',(select count(*) from public.doctors d where d.hospital_id=target_hospital and d.availability_status<>'unavailable'),
    'patients',(select count(*) from public.patients p where p.primary_hospital_id=target_hospital),
    'available_beds',(select coalesce(sum(b.available_beds),0) from public.hospital_beds b where b.hospital_id=target_hospital),
    'available_rooms',(select coalesce(sum(r.available_rooms),0) from public.hospital_rooms r where r.hospital_id=target_hospital),
    'room_occupancy',(select jsonb_build_object(
      'total',coalesce(sum(r.total_rooms),0),
      'occupied',coalesce(sum(r.occupied_rooms),0),
      'available',coalesce(sum(r.available_rooms),0),
      'utilization_percent',case when coalesce(sum(r.total_rooms),0)=0 then 0
        else round(100.0*sum(r.occupied_rooms)/sum(r.total_rooms),2) end
    ) from public.hospital_rooms r where r.hospital_id=target_hospital),
    'er_utilization',(select coalesce(jsonb_agg(jsonb_build_object(
      'status',e.status,
      'patient_count',e.current_patient_count,
      'capacity',e.maximum_capacity,
      'available_beds',e.available_beds,
      'utilization_percent',case when e.maximum_capacity=0 then 0
        else round(100.0*e.current_patient_count/e.maximum_capacity,2) end
    )),'[]'::jsonb) from public.emergency_room_status e where e.hospital_id=target_hospital),
    'er',(select coalesce(jsonb_agg(to_jsonb(e)),'[]'::jsonb) from public.emergency_room_status e where e.hospital_id=target_hospital),
    'generated_at',now()
  ) into result;
  return result;
end;
$$;

create or replace function public.platform_analytics()
returns jsonb
language plpgsql
stable
security invoker
set search_path = ''
as $$
begin
  if not private.is_super_admin() or not private.has_permission('analytics.platform.read') then
    raise exception 'Platform analytics permission is required';
  end if;
  return jsonb_build_object(
    'hospitals',(select count(*) from public.hospitals),
    'verified_hospitals',(select count(*) from public.hospitals where verification_status='verified'),
    'users',(select count(*) from public.users),
    'doctors',(select count(*) from public.doctors),
    'patients',(select count(*) from public.patients),
    'consultations',(select count(*) from public.consultations),
    'ai_assessments',(select count(*) from public.ai_assessments),
    'messages',(select count(*) from public.chat_messages),
    'generated_at',now()
  );
end;
$$;

revoke all on function private.notification_action_path(text,jsonb),
  private.enqueue_notification(uuid,text,text,text,uuid,jsonb),
  private.enqueue_hospital_audience(uuid,text,text,text,uuid,jsonb),
  private.is_doctor_slot_available(uuid,uuid,public.consultation_type,timestamptz,uuid),
  private.has_permission(text)
from public,anon,authenticated;
grant execute on function private.has_permission(text),
  private.is_doctor_slot_available(uuid,uuid,public.consultation_type,timestamptz,uuid)
to authenticated;
revoke all on function public.notify_consultation_status_change(),
  public.notify_patient_account_activation(),public.notify_prescription_created(),
  public.notify_laboratory_result_ready(),public.notify_hospital_announcement(),
  public.notify_hospital_status_alert(),public.sync_completed_consultation_clinical_records(),
  public.log_user_security_change(),public.protect_hospital_approval_fields()
from public,anon,authenticated;
revoke all on function public.enqueue_due_appointment_reminders(integer,interval) from public,anon,authenticated;
grant execute on function public.enqueue_due_appointment_reminders(integer,interval) to service_role;
revoke all on table public.appointment_reminder_jobs from anon,authenticated;
revoke all on function public.hospital_analytics() from public,anon;
grant execute on function public.hospital_analytics(),public.platform_analytics(),
  public.get_patient_medical_records(uuid),public.current_permissions(),
  public.record_clinical_access(text,uuid,text) to authenticated;
revoke all on function public.current_permissions() from public,anon;
revoke all on function public.record_clinical_access(text,uuid,text) from public,anon;

insert into supabase_migrations.schema_migrations (version, statements, name)
values ('20260716204000', array[]::text[], 'notification_clinical_sync_and_reporting')
on conflict (version) do nothing;

commit;
