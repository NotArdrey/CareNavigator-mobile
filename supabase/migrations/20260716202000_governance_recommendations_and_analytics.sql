begin;

create table if not exists public.system_settings (
  key text primary key,
  value jsonb not null,
  description text,
  is_public boolean not null default false,
  updated_by uuid references public.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

create table if not exists public.ai_configurations (
  id uuid primary key default gen_random_uuid(),
  configuration_key text not null unique,
  purpose text not null,
  provider text not null default 'groq',
  model_name text not null,
  prompt_template text,
  configuration jsonb not null default '{}'::jsonb,
  is_active boolean not null default true,
  updated_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.role_permissions (
  id uuid primary key default gen_random_uuid(),
  role_id smallint not null references public.roles(id) on delete cascade,
  permission text not null,
  is_allowed boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  unique (role_id,permission)
);

create table if not exists public.maintenance_windows (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  message text not null,
  starts_at timestamptz not null,
  ends_at timestamptz not null,
  is_active boolean not null default true,
  created_by uuid references public.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_at > starts_at)
);

create table if not exists public.patient_consents (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  consent_type text not null,
  consent_version text not null default '1',
  is_granted boolean not null,
  granted_at timestamptz,
  revoked_at timestamptz,
  captured_by uuid not null references auth.users(id) on delete restrict,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check ((is_granted and granted_at is not null and revoked_at is null) or (not is_granted)),
  unique (patient_id,consent_type,consent_version)
);

create table if not exists public.medical_record_access_logs (
  id bigint generated always as identity primary key,
  patient_id uuid not null references public.patients(id) on delete cascade,
  actor_user_id uuid references public.users(id) on delete set null,
  actor_role text,
  resource_type text not null,
  resource_id uuid,
  access_type text not null check (access_type in ('list','view','download','export')),
  reason text,
  ip_address inet,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.security_logs (
  id bigint generated always as identity primary key,
  actor_auth_user_id uuid references auth.users(id) on delete set null,
  event_type text not null,
  severity text not null default 'info' check (severity in ('info','warning','critical')),
  success boolean not null default true,
  ip_address inet,
  user_agent text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.document_processing_jobs (
  id uuid primary key default gen_random_uuid(),
  medical_document_id uuid references public.medical_documents(id) on delete cascade,
  laboratory_result_id uuid references public.laboratory_results(id) on delete cascade,
  requested_by uuid not null references public.doctors(id) on delete restrict,
  status text not null default 'queued' check (status in ('queued','ocr_processing','ai_analysis_pending','pending_doctor_review','completed','failed','cancelled')),
  ocr_provider text,
  ai_provider text not null default 'groq',
  model_name text,
  attempt_count integer not null default 0 check (attempt_count >= 0),
  last_error text,
  started_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (num_nonnulls(medical_document_id,laboratory_result_id) >= 1)
);

create table if not exists public.ai_assessment_recommendations (
  id uuid primary key default gen_random_uuid(),
  assessment_id uuid not null references public.ai_assessments(id) on delete cascade,
  hospital_id uuid not null references public.hospitals(id) on delete cascade,
  rank integer not null check (rank > 0),
  score numeric(8,3) not null,
  reasons text[] not null default '{}',
  distance_km numeric(10,3),
  created_at timestamptz not null default now(),
  unique (assessment_id,hospital_id),
  unique (assessment_id,rank)
);

insert into public.system_settings(key,value,description,is_public) values
  ('medical_disclaimer',to_jsonb('AI guidance is preliminary and is not a confirmed diagnosis.'::text),'Required AI medical-safety disclaimer',true),
  ('maintenance_mode','false'::jsonb,'Temporarily restrict non-administrator application access',true),
  ('guest_consultation_enabled','true'::jsonb,'Allow verified guests to request consultations',true)
on conflict(key) do nothing;

insert into public.role_permissions(role_id,permission,is_allowed)
select role.id,permission,true from public.roles role cross join (values
  ('hospital.directory.read'),('ai.symptoms.use'),('consultations.read_own'),('records.read_own'),('chat.use'),
  ('patients.manage'),('records.write'),('hospital.manage'),('platform.manage')
) p(permission)
where (role.role_name='guest' and permission in ('hospital.directory.read','ai.symptoms.use'))
   or (role.role_name='patient' and permission in ('hospital.directory.read','ai.symptoms.use','consultations.read_own','records.read_own','chat.use'))
   or (role.role_name='doctor' and permission in ('hospital.directory.read','consultations.read_own','patients.manage','records.write','chat.use'))
   or (role.role_name='hospital_admin' and permission in ('hospital.directory.read','hospital.manage'))
   or role.role_name='super_admin'
on conflict(role_id,permission) do nothing;

create index if not exists system_settings_public_idx on public.system_settings(is_public,key);
create index if not exists ai_configurations_active_idx on public.ai_configurations(purpose,is_active);
create index if not exists role_permissions_role_idx on public.role_permissions(role_id,is_allowed);
create index if not exists maintenance_windows_active_idx on public.maintenance_windows(is_active,starts_at,ends_at);
create index if not exists patient_consents_patient_idx on public.patient_consents(patient_id,consent_type);
create index if not exists medical_access_logs_patient_idx on public.medical_record_access_logs(patient_id,created_at desc);
create index if not exists medical_access_logs_actor_idx on public.medical_record_access_logs(actor_user_id,created_at desc);
create index if not exists security_logs_event_idx on public.security_logs(severity,event_type,created_at desc);
create index if not exists document_jobs_queue_idx on public.document_processing_jobs(status,created_at) where status in ('queued','ocr_processing','ai_analysis_pending','failed');
create index if not exists assessment_recommendations_assessment_idx on public.ai_assessment_recommendations(assessment_id,rank);
create index if not exists hospitals_coordinates_idx on public.hospitals(latitude,longitude) where latitude is not null and longitude is not null;

create or replace function public.validate_hospital_department_relationship()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.department_id is not null and not exists (
    select 1 from public.hospital_departments department where department.id=new.department_id and department.hospital_id=new.hospital_id
  ) then raise exception 'Department must belong to the same hospital'; end if;
  return new;
end;
$$;

create or replace function public.validate_doctor_user_relationship()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.users app_user join public.roles role on role.id=app_user.role_id
    where app_user.id=new.user_id and app_user.hospital_id=new.hospital_id and role.role_name='doctor'
  ) then raise exception 'Doctor profile must reference a doctor user in the same hospital'; end if;
  return new;
end;
$$;

drop trigger if exists validate_doctor_user_before_write on public.doctors;
create trigger validate_doctor_user_before_write before insert or update on public.doctors
for each row execute function public.validate_doctor_user_relationship();

drop trigger if exists validate_service_department_before_write on public.hospital_services;
create trigger validate_service_department_before_write before insert or update on public.hospital_services for each row execute function public.validate_hospital_department_relationship();
drop trigger if exists validate_doctor_department_before_write on public.doctors;
create trigger validate_doctor_department_before_write before insert or update on public.doctors for each row execute function public.validate_hospital_department_relationship();
drop trigger if exists validate_bed_department_before_write on public.hospital_beds;
create trigger validate_bed_department_before_write before insert or update on public.hospital_beds for each row execute function public.validate_hospital_department_relationship();

create or replace function public.validate_guest_hospital_relationships()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.preferred_department_id is not null and not exists (
    select 1 from public.hospital_departments d where d.id=new.preferred_department_id and d.hospital_id=new.preferred_hospital_id
  ) then raise exception 'Preferred department must belong to the preferred hospital'; end if;
  if new.assigned_doctor_id is not null and not exists (
    select 1 from public.doctors d where d.id=new.assigned_doctor_id and d.hospital_id=new.preferred_hospital_id
  ) then raise exception 'Assigned doctor must belong to the preferred hospital'; end if;
  return new;
end;
$$;

drop trigger if exists validate_guest_hospital_relationships_before_write on public.guest_consultation_requests;
create trigger validate_guest_hospital_relationships_before_write before insert or update on public.guest_consultation_requests
for each row execute function public.validate_guest_hospital_relationships();

create or replace function public.protect_laboratory_confirmation()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.verification_status in ('doctor_confirmed','doctor_modified','saved_to_patient_record') and (
    new.confirmed_by is null or new.confirmed_by<>new.doctor_id or new.doctor_confirmed_findings is null or new.confirmed_at is null
  ) then raise exception 'Doctor confirmation is required before this result becomes official'; end if;
  if (select auth.uid()) is not null and new.verification_status in ('doctor_confirmed','doctor_modified','saved_to_patient_record')
    and new.confirmed_by<>private.current_doctor_id() then raise exception 'Only the responsible doctor may confirm this result'; end if;
  return new;
end;
$$;

create or replace function public.set_system_setting_actor()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  new.updated_by := private.current_user_id();
  new.updated_at := now();
  return new;
end;
$$;

drop trigger if exists set_system_setting_actor_before_write on public.system_settings;
create trigger set_system_setting_actor_before_write before insert or update on public.system_settings
for each row execute function public.set_system_setting_actor();

drop trigger if exists protect_laboratory_confirmation_before_write on public.laboratory_results;
create trigger protect_laboratory_confirmation_before_write before insert or update on public.laboratory_results
for each row execute function public.protect_laboratory_confirmation();

create or replace function public.get_patient_medical_records(target_patient_id uuid)
returns setof public.medical_records language plpgsql security invoker set search_path = ''
as $$
begin
  if not private.can_access_patient(target_patient_id) then raise exception 'Patient record access is not authorized'; end if;
  insert into public.medical_record_access_logs(patient_id,actor_user_id,actor_role,resource_type,access_type)
  values(target_patient_id,private.current_user_id(),private.current_role(),'medical_records','list');
  return query select record.* from public.medical_records record where record.patient_id=target_patient_id order by record.record_date desc,record.created_at desc;
end;
$$;

create or replace function public.recommend_hospitals(
  user_latitude double precision,
  user_longitude double precision,
  required_department text default null,
  required_services text[] default '{}'::text[],
  required_specialization text default null,
  requires_emergency boolean default false,
  radius_km double precision default 100,
  result_limit integer default 10
)
returns table(
  hospital_id uuid,hospital_name text,classification_name text,address text,distance_km double precision,
  match_score numeric,match_reasons text[],er_status text,available_beds bigint,available_rooms bigint
)
language sql stable security invoker set search_path = ''
as $$
  with candidates as (
    select h.*,classification.classification_name,
      6371*acos(least(1,greatest(-1,
        cos(radians(user_latitude))*cos(radians(h.latitude::double precision))*cos(radians(h.longitude::double precision)-radians(user_longitude))
        +sin(radians(user_latitude))*sin(radians(h.latitude::double precision))))) as distance,
      er.status::text as er_state,
      coalesce((select sum(b.available_beds)::bigint from public.hospital_beds b where b.hospital_id=h.id),0) beds,
      coalesce((select sum(r.available_rooms)::bigint from public.hospital_rooms r where r.hospital_id=h.id),0) rooms,
      exists(select 1 from public.hospital_departments d where d.hospital_id=h.id and d.availability_status<>'unavailable'
        and (required_department is null or d.department_name ilike '%'||required_department||'%')) department_match,
      exists(select 1 from public.doctors d where d.hospital_id=h.id and d.availability_status<>'unavailable'
        and (required_specialization is null or d.specialization ilike '%'||required_specialization||'%')) specialist_match,
      coalesce((select count(*) from unnest(coalesce(required_services,'{}'::text[])) requested
        where exists(select 1 from public.hospital_services s where s.hospital_id=h.id and s.availability_status<>'unavailable'
          and (s.service_name ilike '%'||requested||'%' or requested=any(s.tags)))),0) service_matches
    from public.hospitals h
    left join public.hospital_classifications classification on classification.id=h.classification_id
    left join public.emergency_room_status er on er.hospital_id=h.id
    where h.verification_status='verified' and h.operating_status in ('open','limited') and h.latitude is not null and h.longitude is not null
  )
  select id,hospital_name,classification_name,address,distance,
    round((greatest(0,20*(1-least(distance/greatest(radius_km,0.001),1)))
      +case when required_department is null or department_match then 20 else 0 end
      +case when cardinality(coalesce(required_services,'{}'::text[]))=0 then 20 else 20*service_matches::numeric/cardinality(required_services) end
      +case when required_specialization is null or specialist_match then 20 else 0 end
      +case when not requires_emergency or er_state in ('available','limited') then 20 else 0 end)::numeric,3),
    array_remove(array[
      case when required_department is not null and department_match then 'Required department available' end,
      case when cardinality(coalesce(required_services,'{}'::text[]))>0 and service_matches>0 then service_matches||' required service(s) matched' end,
      case when required_specialization is not null and specialist_match then 'Required specialist available' end,
      case when requires_emergency and er_state in ('available','limited') then 'Emergency room accepting patients' end,
      case when beds>0 then beds||' bed(s) available' end
    ],null)::text[],er_state,beds,rooms
  from candidates
  where distance<=greatest(radius_km,0) and (not requires_emergency or er_state in ('available','limited'))
  order by 6 desc,distance
  limit least(greatest(result_limit,1),50)
$$;

create or replace function public.hospital_analytics()
returns jsonb language plpgsql stable security invoker set search_path = ''
as $$
declare target_hospital uuid := private.current_hospital_id(); result jsonb;
begin
  if private.current_role() not in ('hospital_admin','doctor','super_admin') then raise exception 'Hospital analytics access is required'; end if;
  if private.current_role()='doctor' then select hospital_id into target_hospital from public.doctors where id=private.current_doctor_id(); end if;
  select jsonb_build_object(
    'hospital_id',target_hospital,
    'consultations_total',(select count(*) from public.consultations c where target_hospital is null or c.hospital_id=target_hospital),
    'consultations_by_status',(select coalesce(jsonb_object_agg(status,total),'{}'::jsonb) from (
      select c.status::text status,count(*) total from public.consultations c where target_hospital is null or c.hospital_id=target_hospital group by c.status
    ) grouped),
    'active_doctors',(select count(*) from public.doctors d where (target_hospital is null or d.hospital_id=target_hospital) and d.availability_status<>'unavailable'),
    'patients',(select count(*) from public.patients p where target_hospital is null or p.primary_hospital_id=target_hospital),
    'available_beds',(select coalesce(sum(b.available_beds),0) from public.hospital_beds b where target_hospital is null or b.hospital_id=target_hospital),
    'available_rooms',(select coalesce(sum(r.available_rooms),0) from public.hospital_rooms r where target_hospital is null or r.hospital_id=target_hospital),
    'er',(select coalesce(jsonb_agg(to_jsonb(e)),'[]'::jsonb) from public.emergency_room_status e where target_hospital is null or e.hospital_id=target_hospital),
    'generated_at',now()
  ) into result;
  return result;
end;
$$;

create or replace function public.platform_analytics()
returns jsonb language plpgsql stable security invoker set search_path = ''
as $$
begin
  if not private.is_super_admin() then raise exception 'Super administrator access is required'; end if;
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

alter table public.system_settings enable row level security;
alter table public.ai_configurations enable row level security;
alter table public.role_permissions enable row level security;
alter table public.maintenance_windows enable row level security;
alter table public.patient_consents enable row level security;
alter table public.medical_record_access_logs enable row level security;
alter table public.security_logs enable row level security;
alter table public.document_processing_jobs enable row level security;
alter table public.ai_assessment_recommendations enable row level security;

create policy system_settings_anon_public_read on public.system_settings for select to anon using(is_public);
create policy system_settings_authenticated_read on public.system_settings for select to authenticated using(is_public or private.is_super_admin());
create policy system_settings_super_manage on public.system_settings for all to authenticated using(private.is_super_admin()) with check(private.is_super_admin());
create policy ai_configurations_super_manage on public.ai_configurations for all to authenticated using(private.is_super_admin()) with check(private.is_super_admin());
create policy role_permissions_authenticated_read on public.role_permissions for select to authenticated using(true);
create policy role_permissions_super_manage on public.role_permissions for all to authenticated using(private.is_super_admin()) with check(private.is_super_admin());
create policy maintenance_windows_anon_read on public.maintenance_windows for select to anon using(is_active and now() between starts_at and ends_at);
create policy maintenance_windows_authenticated_read on public.maintenance_windows for select to authenticated using((is_active and now() between starts_at and ends_at) or private.is_super_admin());
create policy maintenance_windows_super_manage on public.maintenance_windows for all to authenticated using(private.is_super_admin()) with check(private.is_super_admin());
create policy patient_consents_care_team_read on public.patient_consents for select to authenticated using(private.can_access_patient(patient_id));
create policy patient_consents_patient_manage on public.patient_consents for all to authenticated using(patient_id=private.current_patient_id()) with check(patient_id=private.current_patient_id() and captured_by=(select auth.uid()));
create policy medical_access_logs_patient_read on public.medical_record_access_logs for select to authenticated using(patient_id=private.current_patient_id() or private.is_super_admin());
create policy medical_access_logs_authorized_insert on public.medical_record_access_logs for insert to authenticated with check(actor_user_id=private.current_user_id() and private.can_access_patient(patient_id));
create policy security_logs_super_read on public.security_logs for select to authenticated using(private.is_super_admin());
create policy document_jobs_care_team_read on public.document_processing_jobs for select to authenticated using(
  exists(select 1 from public.laboratory_results r where r.id=laboratory_result_id and private.can_access_patient(r.patient_id))
  or exists(select 1 from public.medical_documents d where d.id=medical_document_id and private.can_access_patient(d.patient_id))
);
create policy document_jobs_doctor_manage on public.document_processing_jobs for all to authenticated using(requested_by=private.current_doctor_id()) with check(requested_by=private.current_doctor_id());
create policy assessment_recommendations_owner_read on public.ai_assessment_recommendations for select to authenticated using(
  exists(select 1 from public.ai_assessments a where a.id=assessment_id and (
    a.user_id=(select auth.uid()) or (a.patient_id is not null and private.can_access_patient(a.patient_id)) or (a.guest_request_id is not null and private.can_access_guest_request(a.guest_request_id))
  ))
);
create policy assessment_recommendations_owner_insert on public.ai_assessment_recommendations for insert to authenticated with check(
  exists(select 1 from public.ai_assessments a where a.id=assessment_id and a.user_id=(select auth.uid()))
);

grant select on public.system_settings to anon,authenticated;
grant insert,update,delete on public.system_settings to authenticated;
grant select,insert,update,delete on public.ai_configurations,public.role_permissions,public.maintenance_windows to authenticated;
grant select,insert,update on public.patient_consents,public.document_processing_jobs,public.ai_assessment_recommendations to authenticated;
grant select,insert on public.medical_record_access_logs to authenticated;
grant select on public.security_logs to authenticated;

revoke all on function public.validate_hospital_department_relationship(),public.validate_doctor_user_relationship(),
  public.validate_guest_hospital_relationships(),public.protect_laboratory_confirmation(),public.set_system_setting_actor() from public,anon,authenticated;
revoke all on function public.get_patient_medical_records(uuid),public.hospital_analytics(),public.platform_analytics() from public,anon;
grant execute on function public.get_patient_medical_records(uuid),public.hospital_analytics(),public.platform_analytics() to authenticated;
revoke all on function public.recommend_hospitals(double precision,double precision,text,text[],text,boolean,double precision,integer) from public;
grant execute on function public.recommend_hospitals(double precision,double precision,text,text[],text,boolean,double precision,integer) to anon,authenticated;

revoke update on public.notifications from authenticated;
grant update(is_read,read_at) on public.notifications to authenticated;

do $$ declare table_name text; trigger_name text; begin
  foreach table_name in array array['diagnoses','treatment_plans','laboratory_requests','notification_preferences','notification_outbox','video_sessions','ai_configurations','role_permissions','maintenance_windows','patient_consents','document_processing_jobs'] loop
    trigger_name := 'set_'||table_name||'_updated_at';
    if not exists(select 1 from pg_trigger where tgname=trigger_name and tgrelid=('public.'||table_name)::regclass) then
      execute format('create trigger %I before update on public.%I for each row execute function public.set_updated_at()',trigger_name,table_name);
    end if;
  end loop;
end $$;

do $$ declare table_name text; trigger_name text; begin
  foreach table_name in array array['users','patients','doctor_patient_assignments','doctor_schedules','hospital_facility_status','hospital_announcements',
    'chat_conversations','chat_messages','notifications','ai_assessments','diagnoses','treatment_plans','laboratory_requests','medical_documents',
    'consultation_attachments','video_sessions','ai_configurations','role_permissions','maintenance_windows','patient_consents','document_processing_jobs'] loop
    trigger_name := 'audit_'||table_name;
    if not exists(select 1 from pg_trigger where tgname=trigger_name and tgrelid=('public.'||table_name)::regclass) then
      execute format('create trigger %I after insert or update or delete on public.%I for each row execute function public.log_audit_event()',trigger_name,table_name);
    end if;
  end loop;
end $$;

do $$ declare table_name text; begin
  foreach table_name in array array['laboratory_results','medical_records','prescriptions','document_processing_jobs'] loop
    if not exists(select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=table_name) then
      execute format('alter publication supabase_realtime add table public.%I',table_name);
    end if;
  end loop;
end $$;

insert into supabase_migrations.schema_migrations (version, statements, name)
values ('20260716202000', array[]::text[], 'governance_recommendations_and_analytics')
on conflict (version) do nothing;

commit;
