begin;

create sequence if not exists public.patient_number_seq;

alter table public.guest_consultation_requests
  add column if not exists otp_verified_at timestamptz,
  add column if not exists reviewed_by uuid references public.users(id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists rejection_reason text,
  add column if not exists identity_review_status public.verification_status not null default 'pending',
  add column if not exists identity_review_notes text,
  add column if not exists additional_documents_requested text,
  add column if not exists consent_at timestamptz;

alter table public.patients
  add column if not exists profile_status text not null default 'official',
  add column if not exists activation_sent_at timestamptz,
  add column if not exists activated_at timestamptz;

alter table public.consultations
  add column if not exists department_id uuid references public.hospital_departments(id) on delete set null,
  add column if not exists approved_by uuid references public.users(id) on delete set null,
  add column if not exists approved_at timestamptz,
  add column if not exists rejected_at timestamptz,
  add column if not exists rejection_reason text,
  add column if not exists started_at timestamptz,
  add column if not exists follow_up_of uuid references public.consultations(id) on delete set null,
  add column if not exists consultation_summary text;

do $$
begin
  if not exists (select 1 from pg_constraint where conname = 'patients_profile_status_check') then
    alter table public.patients add constraint patients_profile_status_check
      check (profile_status in ('temporary', 'activation_pending', 'official', 'duplicate_review', 'rejected'));
  end if;
end;
$$;

create table if not exists public.guest_request_status_history (
  id bigint generated always as identity primary key,
  request_id uuid not null references public.guest_consultation_requests(id) on delete cascade,
  old_status public.guest_request_status,
  new_status public.guest_request_status not null,
  changed_by uuid references public.users(id) on delete set null,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.consultation_status_history (
  id bigint generated always as identity primary key,
  consultation_id uuid not null references public.consultations(id) on delete cascade,
  old_status public.consultation_status,
  new_status public.consultation_status not null,
  changed_by uuid references public.users(id) on delete set null,
  reason text,
  metadata jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);

create table if not exists public.diagnoses (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete restrict,
  consultation_id uuid not null references public.consultations(id) on delete restrict,
  doctor_id uuid not null references public.doctors(id) on delete restrict,
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  diagnosis text not null check (length(btrim(diagnosis)) between 2 and 4000),
  diagnosis_code text,
  is_primary boolean not null default false,
  confirmed_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.treatment_plans (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete restrict,
  consultation_id uuid not null references public.consultations(id) on delete restrict,
  doctor_id uuid not null references public.doctors(id) on delete restrict,
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  plan text not null check (length(btrim(plan)) between 2 and 10000),
  starts_on date,
  ends_on date,
  status text not null default 'active' check (status in ('planned', 'active', 'completed', 'cancelled')),
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (ends_on is null or starts_on is null or ends_on >= starts_on)
);

create table if not exists public.laboratory_requests (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete restrict,
  consultation_id uuid references public.consultations(id) on delete set null,
  doctor_id uuid not null references public.doctors(id) on delete restrict,
  hospital_id uuid not null references public.hospitals(id) on delete restrict,
  test_name text not null check (length(btrim(test_name)) between 2 and 300),
  instructions text,
  priority text not null default 'routine' check (priority in ('routine', 'urgent', 'stat')),
  status text not null default 'requested' check (status in ('requested', 'scheduled', 'collected', 'completed', 'cancelled')),
  requested_at timestamptz not null default now(),
  due_at timestamptz,
  completed_at timestamptz,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create table if not exists public.medical_documents (
  id uuid primary key default gen_random_uuid(),
  patient_id uuid not null references public.patients(id) on delete cascade,
  consultation_id uuid references public.consultations(id) on delete set null,
  uploaded_by uuid not null references public.users(id) on delete restrict,
  hospital_id uuid references public.hospitals(id) on delete set null,
  document_type text not null,
  title text not null,
  storage_bucket text not null check (storage_bucket in ('laboratory-results', 'scanned-medical-results', 'medical-documents', 'prescriptions', 'consultation-attachments')),
  storage_path text not null,
  mime_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  created_at timestamptz not null default now(),
  unique (storage_bucket, storage_path)
);

create table if not exists public.consultation_attachments (
  id uuid primary key default gen_random_uuid(),
  consultation_id uuid not null references public.consultations(id) on delete cascade,
  patient_id uuid references public.patients(id) on delete cascade,
  guest_request_id uuid references public.guest_consultation_requests(id) on delete cascade,
  uploaded_by uuid not null references auth.users(id) on delete restrict,
  storage_path text not null unique,
  file_name text not null,
  mime_type text,
  size_bytes bigint check (size_bytes is null or size_bytes >= 0),
  created_at timestamptz not null default now(),
  check (num_nonnulls(patient_id, guest_request_id) = 1)
);

alter table public.laboratory_results
  add column if not exists ocr_provider text,
  add column if not exists ocr_confidence numeric(5,4),
  add column if not exists ocr_completed_at timestamptz,
  add column if not exists ai_analyzed_at timestamptz,
  add column if not exists reviewed_by uuid references public.doctors(id) on delete set null,
  add column if not exists reviewed_at timestamptz,
  add column if not exists rejection_reason text,
  add column if not exists source_document_id uuid references public.medical_documents(id) on delete set null,
  add column if not exists confirmed_by uuid references public.doctors(id) on delete set null;

alter table public.medical_records
  add column if not exists source_laboratory_result_id uuid references public.laboratory_results(id) on delete set null,
  add column if not exists confirmed_by uuid references public.doctors(id) on delete set null,
  add column if not exists is_ai_assisted boolean not null default false;

alter table public.prescriptions add column if not exists hospital_id uuid references public.hospitals(id) on delete restrict;
update public.prescriptions prescription
set hospital_id = consultation.hospital_id
from public.consultations consultation
where consultation.id = prescription.consultation_id and prescription.hospital_id is null;

create unique index if not exists departments_id_hospital_key on public.hospital_departments (id, hospital_id);
create unique index if not exists consultations_id_patient_hospital_key on public.consultations (id, patient_id, hospital_id);
create index if not exists guest_status_history_request_idx on public.guest_request_status_history (request_id, created_at);
create index if not exists consultation_status_history_consultation_idx on public.consultation_status_history (consultation_id, created_at);
create index if not exists diagnoses_patient_idx on public.diagnoses (patient_id, confirmed_at desc);
create unique index if not exists diagnoses_one_primary_idx on public.diagnoses (consultation_id) where is_primary;
create index if not exists treatment_plans_patient_idx on public.treatment_plans (patient_id, created_at desc);
create index if not exists laboratory_requests_patient_idx on public.laboratory_requests (patient_id, requested_at desc);
create index if not exists laboratory_requests_doctor_status_idx on public.laboratory_requests (doctor_id, status, due_at);
create index if not exists medical_documents_patient_idx on public.medical_documents (patient_id, created_at desc);
create index if not exists consultation_attachments_consultation_idx on public.consultation_attachments (consultation_id, created_at);

create or replace function private.is_consultation_participant(target_consultation_id uuid)
returns boolean language sql stable security definer set search_path = ''
as $$
  select coalesce(exists (
    select 1 from public.consultations consultation
    where consultation.id = target_consultation_id and (
      consultation.patient_id = private.current_patient_id()
      or consultation.doctor_id = private.current_doctor_id()
      or (consultation.guest_request_id is not null and private.can_access_guest_request(consultation.guest_request_id))
      or private.is_hospital_admin_for(consultation.hospital_id)
    )
  ), false)
$$;

create or replace function public.set_patient_number()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if new.patient_number is null or btrim(new.patient_number) = '' then
    new.patient_number := format('CNPH-%s-%s', to_char(current_date, 'YYYY'), lpad(nextval('public.patient_number_seq')::text, 7, '0'));
  end if;
  return new;
end;
$$;

drop trigger if exists set_patient_number_before_insert on public.patients;
create trigger set_patient_number_before_insert before insert on public.patients
for each row execute function public.set_patient_number();

create or replace function public.enforce_consultation_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare actor_role text := private.current_role();
begin
  if tg_op = 'UPDATE' then
    if new.patient_id is distinct from old.patient_id or new.guest_request_id is distinct from old.guest_request_id
      or new.doctor_id is distinct from old.doctor_id or new.hospital_id is distinct from old.hospital_id
      or new.consultation_type is distinct from old.consultation_type or new.created_at is distinct from old.created_at then
      raise exception 'Consultation ownership fields are immutable';
    end if;
    if new.status is distinct from old.status and not (
      (old.status = 'pending' and new.status in ('approved','rejected','scheduled','cancelled'))
      or (old.status = 'approved' and new.status in ('scheduled','in_progress','cancelled'))
      or (old.status = 'scheduled' and new.status in ('in_progress','cancelled'))
      or (old.status = 'in_progress' and new.status in ('completed','cancelled'))
    ) then raise exception 'Invalid consultation status transition from % to %', old.status, new.status; end if;
    if actor_role = 'patient' then
      if not (old.status in ('pending','approved','scheduled') and new.status = 'cancelled')
        or (to_jsonb(new) - array['status','updated_at']) is distinct from (to_jsonb(old) - array['status','updated_at']) then
        raise exception 'Patients may only cancel their own pending consultation';
      end if;
    elsif actor_role = 'hospital_admin' and (
      new.doctor_notes is distinct from old.doctor_notes or new.confirmed_diagnosis is distinct from old.confirmed_diagnosis
      or new.treatment_plan is distinct from old.treatment_plan or new.consultation_summary is distinct from old.consultation_summary
    ) then raise exception 'Hospital administrators cannot modify clinical content'; end if;
    if new.status = 'completed' and new.completed_at is null then new.completed_at := now(); end if;
    if new.status = 'in_progress' and new.started_at is null then new.started_at := now(); end if;
    if new.status = 'approved' and new.approved_at is null then new.approved_at := now(); end if;
  end if;
  return new;
end;
$$;

create or replace function public.validate_consultation_relationships()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if not exists (select 1 from public.doctors d where d.id=new.doctor_id and d.hospital_id=new.hospital_id) then
    raise exception 'Consultation doctor must belong to the consultation hospital';
  end if;
  if new.department_id is not null and not exists (
    select 1 from public.hospital_departments d where d.id=new.department_id and d.hospital_id=new.hospital_id
  ) then raise exception 'Consultation department must belong to the consultation hospital'; end if;
  if new.guest_request_id is not null and not exists (
    select 1 from public.guest_consultation_requests g where g.id=new.guest_request_id
      and g.preferred_hospital_id=new.hospital_id and (g.assigned_doctor_id is null or g.assigned_doctor_id=new.doctor_id)
  ) then raise exception 'Guest request, doctor, and hospital do not match'; end if;
  return new;
end;
$$;

drop trigger if exists validate_consultation_relationships_before_write on public.consultations;
create trigger validate_consultation_relationships_before_write before insert or update on public.consultations
for each row execute function public.validate_consultation_relationships();

create or replace function public.validate_clinical_relationships()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare consultation_patient uuid; consultation_guest uuid; consultation_hospital uuid; consultation_doctor uuid;
begin
  if not exists (select 1 from public.doctors d where d.id=new.doctor_id and d.hospital_id=new.hospital_id) then
    raise exception 'Clinical record doctor must belong to its hospital';
  end if;
  if new.consultation_id is not null then
    select c.patient_id,c.guest_request_id,c.hospital_id,c.doctor_id into consultation_patient,consultation_guest,consultation_hospital,consultation_doctor
    from public.consultations c where c.id=new.consultation_id;
    if consultation_hospital is null
      or (consultation_patient is distinct from new.patient_id and not (
        consultation_patient is null and consultation_guest is not null and exists(
          select 1 from public.patients p where p.id=new.patient_id and p.guest_request_id=consultation_guest
        )
      ))
      or consultation_hospital is distinct from new.hospital_id or consultation_doctor is distinct from new.doctor_id then
      raise exception 'Clinical record does not match its consultation';
    end if;
  end if;
  return new;
end;
$$;

drop trigger if exists validate_medical_record_relationships on public.medical_records;
create trigger validate_medical_record_relationships before insert or update on public.medical_records for each row execute function public.validate_clinical_relationships();
drop trigger if exists validate_laboratory_result_relationships on public.laboratory_results;
create trigger validate_laboratory_result_relationships before insert or update on public.laboratory_results for each row execute function public.validate_clinical_relationships();
drop trigger if exists validate_diagnosis_relationships on public.diagnoses;
create trigger validate_diagnosis_relationships before insert or update on public.diagnoses for each row execute function public.validate_clinical_relationships();
drop trigger if exists validate_treatment_plan_relationships on public.treatment_plans;
create trigger validate_treatment_plan_relationships before insert or update on public.treatment_plans for each row execute function public.validate_clinical_relationships();
drop trigger if exists validate_laboratory_request_relationships on public.laboratory_requests;
create trigger validate_laboratory_request_relationships before insert or update on public.laboratory_requests for each row execute function public.validate_clinical_relationships();

create or replace function public.validate_prescription_relationships()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare consultation_row public.consultations;
begin
  select * into consultation_row from public.consultations where id=new.consultation_id;
  if not found or consultation_row.patient_id is distinct from new.patient_id
    or consultation_row.doctor_id is distinct from new.doctor_id then
    raise exception 'Prescription does not match its consultation';
  end if;
  new.hospital_id := consultation_row.hospital_id;
  return new;
end;
$$;

drop trigger if exists validate_prescription_relationships_before_write on public.prescriptions;
create trigger validate_prescription_relationships_before_write before insert or update on public.prescriptions
for each row execute function public.validate_prescription_relationships();

create or replace function public.enforce_guest_request_change()
returns trigger language plpgsql security definer set search_path = ''
as $$
declare actor_role text := private.current_role();
begin
  if new.submitted_by is distinct from old.submitted_by or new.reference_number is distinct from old.reference_number
    or new.created_at is distinct from old.created_at then raise exception 'Guest request ownership fields are immutable'; end if;
  if new.request_status is distinct from old.request_status and not (
    (old.request_status='pending_verification' and new.request_status in ('otp_verified','cancelled'))
    or (old.request_status='otp_verified' and new.request_status in ('pending_doctor_review','approved','rejected','cancelled'))
    or (old.request_status='pending_doctor_review' and new.request_status in ('approved','rejected','cancelled'))
    or (old.request_status='approved' and new.request_status in ('temporary_patient_created','consultation_scheduled','cancelled'))
    or (old.request_status='temporary_patient_created' and new.request_status in ('account_activation_pending','consultation_scheduled','cancelled'))
    or (old.request_status='account_activation_pending' and new.request_status in ('consultation_scheduled','cancelled'))
    or (old.request_status='consultation_scheduled' and new.request_status in ('consultation_completed','cancelled'))
  ) then raise exception 'Invalid guest request status transition from % to %',old.request_status,new.request_status; end if;
  if actor_role='guest' and not (new.request_status='cancelled' and old.submitted_by=(select auth.uid())) then
    raise exception 'Guests may only cancel their own request';
  end if;
  return new;
end;
$$;

drop trigger if exists enforce_guest_request_change_before_update on public.guest_consultation_requests;
create trigger enforce_guest_request_change_before_update before update on public.guest_consultation_requests
for each row execute function public.enforce_guest_request_change();

drop trigger if exists enforce_consultation_change_before_write on public.consultations;
create trigger enforce_consultation_change_before_write before update on public.consultations
for each row execute function public.enforce_consultation_change();

create or replace function public.record_consultation_status_history()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.consultation_status_history (consultation_id, old_status, new_status, changed_by, reason)
    values (new.id, case when tg_op = 'UPDATE' then old.status else null end, new.status, private.current_user_id(), new.rejection_reason);
  end if;
  return new;
end;
$$;

drop trigger if exists record_consultation_status_after_write on public.consultations;
create trigger record_consultation_status_after_write after insert or update on public.consultations
for each row execute function public.record_consultation_status_history();

create or replace function public.record_guest_status_history()
returns trigger language plpgsql security definer set search_path = ''
as $$
begin
  if tg_op = 'INSERT' or new.request_status is distinct from old.request_status then
    insert into public.guest_request_status_history (request_id, old_status, new_status, changed_by, reason)
    values (new.id, case when tg_op = 'UPDATE' then old.request_status else null end, new.request_status, private.current_user_id(), new.rejection_reason);
  end if;
  return new;
end;
$$;

drop trigger if exists record_guest_status_after_write on public.guest_consultation_requests;
create trigger record_guest_status_after_write after insert or update on public.guest_consultation_requests
for each row execute function public.record_guest_status_history();

create or replace function public.book_consultation(booking_payload jsonb)
returns uuid language plpgsql security invoker set search_path = ''
as $$
declare
  target_patient uuid := private.current_patient_id();
  target_doctor uuid := nullif(booking_payload ->> 'doctor_id','')::uuid;
  target_hospital uuid := nullif(booking_payload ->> 'hospital_id','')::uuid;
  booked_id uuid;
begin
  if target_patient is null then raise exception 'An active patient profile is required'; end if;
  if not exists (select 1 from public.doctors d where d.id = target_doctor and d.hospital_id = target_hospital and d.availability_status <> 'unavailable') then
    raise exception 'Doctor is not available at the selected hospital';
  end if;
  if not exists (
    select 1 from public.doctor_schedules schedule
    where schedule.doctor_id=target_doctor and schedule.is_active
      and schedule.consultation_type=coalesce(nullif(booking_payload ->> 'consultation_type',''),'online')::public.consultation_type
      and schedule.day_of_week=extract(dow from (booking_payload ->> 'appointment_date')::timestamptz)::integer
      and ((booking_payload ->> 'appointment_date')::timestamptz)::time >= schedule.starts_at
      and ((booking_payload ->> 'appointment_date')::timestamptz)::time + make_interval(mins=>schedule.slot_minutes) <= schedule.ends_at
  ) then raise exception 'The requested time is outside the doctor schedule'; end if;
  if exists (
    select 1 from public.consultations c where c.doctor_id = target_doctor
      and c.appointment_date = (booking_payload ->> 'appointment_date')::timestamptz
      and c.status not in ('rejected','cancelled')
  ) then raise exception 'The selected appointment slot is no longer available'; end if;
  insert into public.consultations (patient_id, doctor_id, hospital_id, department_id, consultation_type, appointment_date, status, chief_complaint,follow_up_of)
  select target_patient, d.id, d.hospital_id, d.department_id,
    coalesce(nullif(booking_payload ->> 'consultation_type',''),'online')::public.consultation_type,
    (booking_payload ->> 'appointment_date')::timestamptz, 'pending', btrim(booking_payload ->> 'chief_complaint'),
    nullif(booking_payload ->> 'follow_up_of','')::uuid
  from public.doctors d where d.id = target_doctor
  returning id into booked_id;
  return booked_id;
end;
$$;

create or replace function public.available_doctor_slots(
  target_doctor_id uuid,target_date date,target_type public.consultation_type default 'online'
)
returns table(slot_start timestamptz,slot_end timestamptz)
language sql stable security invoker set search_path = ''
as $$
  select generated.slot_start::timestamptz,
    (generated.slot_start+make_interval(mins=>schedule.slot_minutes))::timestamptz
  from public.doctor_schedules schedule
  cross join lateral generate_series(
    target_date+schedule.starts_at,
    target_date+schedule.ends_at-make_interval(mins=>schedule.slot_minutes),
    make_interval(mins=>schedule.slot_minutes)
  ) generated(slot_start)
  join public.doctors doctor on doctor.id=schedule.doctor_id
  join public.hospitals hospital on hospital.id=doctor.hospital_id
  where schedule.doctor_id=target_doctor_id and schedule.day_of_week=extract(dow from target_date)::integer
    and schedule.consultation_type=target_type and schedule.is_active and doctor.availability_status<>'unavailable'
    and hospital.verification_status='verified' and hospital.operating_status in ('open','limited')
    and generated.slot_start>now()
    and not exists(select 1 from public.consultations consultation where consultation.doctor_id=target_doctor_id
      and consultation.appointment_date=generated.slot_start::timestamptz and consultation.status not in ('rejected','cancelled'))
  order by generated.slot_start
$$;

create or replace function public.link_guest_patient_account(target_request_id uuid,target_user_id uuid)
returns uuid language plpgsql security invoker set search_path = ''
as $$
declare patient_id uuid; request_row public.guest_consultation_requests;
begin
  select * into request_row from public.guest_consultation_requests where id=target_request_id for update;
  if not found or request_row.assigned_doctor_id<>private.current_doctor_id() then raise exception 'Only the assigned doctor may complete conversion'; end if;
  if not exists(select 1 from public.users app_user join public.roles role on role.id=app_user.role_id
    where app_user.id=target_user_id and role.role_name='patient' and app_user.account_status in ('pending','active')) then
    raise exception 'A patient user profile prepared by the account service is required';
  end if;
  update public.patients set user_id=target_user_id,profile_status='official',account_activation_status='active',activated_at=now(),
    converted_from_guest=true,converted_at=coalesce(converted_at,now())
  where guest_request_id=target_request_id returning id into patient_id;
  if patient_id is null then raise exception 'Temporary patient profile was not found'; end if;
  return patient_id;
end;
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
  temporary_patient_id uuid;
  created_consultation_id uuid;
begin
  select * into request_row from public.guest_consultation_requests where id = target_request_id for update;
  if not found then raise exception 'Guest consultation request was not found'; end if;
  if not (private.is_hospital_admin_for(request_row.preferred_hospital_id) or request_row.assigned_doctor_id = private.current_doctor_id()) then
    raise exception 'Not authorized to review this request';
  end if;
  if decision not in ('approved','rejected') then raise exception 'Decision must be approved or rejected'; end if;
  if decision = 'rejected' then
    update public.guest_consultation_requests set request_status='rejected', reviewed_by=private.current_user_id(), reviewed_at=now(),
      rejection_reason=nullif(btrim(review_notes),''), identity_review_notes=review_notes where id=target_request_id;
    return jsonb_build_object('request_id',target_request_id,'patient_id',null,'consultation_id',null,'status','rejected');
  end if;
  chosen_doctor := coalesce(target_doctor_id, request_row.assigned_doctor_id, private.current_doctor_id());
  if not exists (select 1 from public.doctors d where d.id=chosen_doctor and d.hospital_id=request_row.preferred_hospital_id) then
    raise exception 'Assigned doctor must belong to the preferred hospital';
  end if;
  if private.current_role() = 'hospital_admin' and target_doctor_id is null then raise exception 'A doctor must be assigned'; end if;
  update public.guest_consultation_requests set request_status='approved', assigned_doctor_id=chosen_doctor,
    reviewed_by=private.current_user_id(), reviewed_at=now(), identity_review_status='verified', identity_review_notes=review_notes
  where id=target_request_id;
  select id into temporary_patient_id from public.patients where guest_request_id=target_request_id;
  if temporary_patient_id is null then
    insert into public.patients (created_by_doctor,guest_request_id,primary_hospital_id,allergies,existing_conditions,
      identity_verification_status,account_activation_status,converted_from_guest,profile_status)
    values (chosen_doctor,target_request_id,request_row.preferred_hospital_id,request_row.allergies,request_row.existing_conditions,
      'verified','pending',true,'temporary') returning id into temporary_patient_id;
  end if;
  insert into public.doctor_patient_assignments (doctor_id,patient_id,notes)
  values (chosen_doctor,temporary_patient_id,'Created from guest consultation '||request_row.reference_number)
  on conflict do nothing;
  insert into public.consultations (patient_id,guest_request_id,doctor_id,hospital_id,department_id,consultation_type,appointment_date,status,chief_complaint,approved_by,approved_at)
  values (null,target_request_id,chosen_doctor,request_row.preferred_hospital_id,request_row.preferred_department_id,'guest_online',
    coalesce(target_appointment_date,request_row.preferred_schedule,now()+interval '1 day'),'scheduled',request_row.consultation_reason,
    private.current_user_id(),now()) returning id into created_consultation_id;
  update public.guest_consultation_requests set request_status='consultation_scheduled' where id=target_request_id;
  return jsonb_build_object('request_id',target_request_id,'patient_id',temporary_patient_id,'consultation_id',created_consultation_id,'status','consultation_scheduled');
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
  select * into result_row from public.consultations where id=target_consultation_id for update;
  if not found or not private.is_consultation_participant(target_consultation_id) then raise exception 'Consultation was not found or is not accessible'; end if;
  update public.consultations set status=target_status,
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
    update public.guest_consultation_requests set request_status=case target_status
      when 'completed' then 'consultation_completed'::public.guest_request_status
      when 'cancelled' then 'cancelled'::public.guest_request_status
      else request_status end where id=result_row.guest_request_id;
  end if;
  return jsonb_build_object('id',result_row.id,'status',result_row.status,'appointment_date',result_row.appointment_date,'completed_at',result_row.completed_at);
end;
$$;

create or replace function public.confirm_medical_result(
  target_result_id uuid,
  confirmed_findings text,
  interpretation text default null,
  create_record boolean default true
)
returns jsonb language plpgsql security invoker set search_path = ''
as $$
declare result_row public.laboratory_results; record_id uuid; final_status public.medical_result_status;
begin
  select * into result_row from public.laboratory_results where id=target_result_id for update;
  if not found or result_row.doctor_id <> private.current_doctor_id() or not private.can_access_patient(result_row.patient_id) then
    raise exception 'Only the responsible doctor may confirm this result';
  end if;
  if result_row.verification_status not in ('pending_doctor_review','doctor_modified') then raise exception 'Result is not awaiting doctor confirmation'; end if;
  update public.laboratory_results set doctor_confirmed_findings=btrim(confirmed_findings), professional_interpretation=nullif(btrim(interpretation),''),
    verification_status=case when interpretation is null then 'doctor_confirmed'::public.medical_result_status else 'doctor_modified'::public.medical_result_status end,
    confirmed_by=private.current_doctor_id(),reviewed_by=private.current_doctor_id(),reviewed_at=now(),confirmed_at=now()
  where id=target_result_id;
  final_status := case when interpretation is null then 'doctor_confirmed'::public.medical_result_status else 'doctor_modified'::public.medical_result_status end;
  if create_record then
    insert into public.medical_records (patient_id,doctor_id,hospital_id,consultation_id,record_type,title,description,record_date,
      source_laboratory_result_id,confirmed_by,is_ai_assisted)
    values (result_row.patient_id,result_row.doctor_id,result_row.hospital_id,result_row.consultation_id,'laboratory_result',result_row.test_name,
      coalesce(interpretation,confirmed_findings),current_date,target_result_id,result_row.doctor_id,true)
    returning id into record_id;
    update public.laboratory_results set verification_status='saved_to_patient_record' where id=target_result_id;
    final_status := 'saved_to_patient_record';
  end if;
  return jsonb_build_object('laboratory_result_id',target_result_id,'medical_record_id',record_id,'status',final_status);
end;
$$;

alter table public.guest_request_status_history enable row level security;
alter table public.consultation_status_history enable row level security;
alter table public.diagnoses enable row level security;
alter table public.treatment_plans enable row level security;
alter table public.laboratory_requests enable row level security;
alter table public.medical_documents enable row level security;
alter table public.consultation_attachments enable row level security;

create policy guest_status_history_read on public.guest_request_status_history for select to authenticated using (private.can_access_guest_request(request_id));
create policy consultation_status_history_read on public.consultation_status_history for select to authenticated using (private.is_consultation_participant(consultation_id));
create policy diagnoses_care_team_read on public.diagnoses for select to authenticated using (private.can_access_patient(patient_id));
create policy diagnoses_doctor_insert on public.diagnoses for insert to authenticated with check (doctor_id=private.current_doctor_id() and private.can_access_patient(patient_id));
create policy treatment_plans_care_team_read on public.treatment_plans for select to authenticated using (private.can_access_patient(patient_id));
create policy treatment_plans_doctor_manage on public.treatment_plans for all to authenticated using (doctor_id=private.current_doctor_id()) with check (doctor_id=private.current_doctor_id() and private.can_access_patient(patient_id));
create policy laboratory_requests_care_team_read on public.laboratory_requests for select to authenticated using (private.can_access_patient(patient_id));
create policy laboratory_requests_doctor_manage on public.laboratory_requests for all to authenticated using (doctor_id=private.current_doctor_id()) with check (doctor_id=private.current_doctor_id() and private.can_access_patient(patient_id));
create policy medical_documents_care_team_read on public.medical_documents for select to authenticated using (private.can_access_patient(patient_id));
create policy medical_documents_participant_insert on public.medical_documents for insert to authenticated with check (uploaded_by=private.current_user_id() and private.can_access_patient(patient_id));
create policy consultation_attachments_participant_read on public.consultation_attachments for select to authenticated using (private.is_consultation_participant(consultation_id));
create policy consultation_attachments_participant_insert on public.consultation_attachments for insert to authenticated with check (uploaded_by=(select auth.uid()) and private.is_consultation_participant(consultation_id));

create policy patients_hospital_admin_temporary_insert on public.patients for insert to authenticated with check (
  profile_status='temporary' and user_id is null and private.is_hospital_admin_for(primary_hospital_id)
);

create policy consultations_guest_reviewer_insert on public.consultations for insert to authenticated with check (
  guest_request_id is not null and patient_id is null and status in ('approved','scheduled')
  and exists (select 1 from public.guest_consultation_requests g where g.id=guest_request_id
    and g.preferred_hospital_id=consultations.hospital_id and g.assigned_doctor_id=consultations.doctor_id
    and (g.assigned_doctor_id=private.current_doctor_id() or private.is_hospital_admin_for(g.preferred_hospital_id)))
);

drop policy if exists consultations_patient_insert on public.consultations;
create policy consultations_patient_insert on public.consultations for insert to authenticated with check (
  patient_id=private.current_patient_id() and guest_request_id is null and status='pending'
  and exists (select 1 from public.doctors d where d.id=doctor_id and d.hospital_id=consultations.hospital_id)
  and doctor_notes is null and confirmed_diagnosis is null and treatment_plan is null and meeting_link is null
  and approved_by is null and completed_at is null and appointment_date > now()
  and (follow_up_of is null or exists(select 1 from public.consultations previous
    where previous.id=follow_up_of and previous.patient_id=private.current_patient_id() and previous.status='completed'))
);

grant select on public.guest_request_status_history,public.consultation_status_history,public.diagnoses,public.treatment_plans,
  public.laboratory_requests,public.medical_documents,public.consultation_attachments to authenticated;
grant insert,update on public.diagnoses,public.treatment_plans,public.laboratory_requests,public.medical_documents,public.consultation_attachments to authenticated;
revoke all on function public.set_patient_number(),public.enforce_consultation_change(),public.validate_consultation_relationships(),
  public.validate_clinical_relationships(),public.validate_prescription_relationships(),public.enforce_guest_request_change(),
  public.record_consultation_status_history(),public.record_guest_status_history() from public,anon,authenticated;
revoke all on function public.book_consultation(jsonb),public.review_guest_consultation(uuid,text,uuid,timestamptz,text),
  public.available_doctor_slots(uuid,date,public.consultation_type),public.link_guest_patient_account(uuid,uuid),
  public.transition_consultation(uuid,public.consultation_status,text,timestamptz,jsonb),public.confirm_medical_result(uuid,text,text,boolean) from public,anon;
grant execute on function public.book_consultation(jsonb),public.review_guest_consultation(uuid,text,uuid,timestamptz,text),
  public.available_doctor_slots(uuid,date,public.consultation_type),public.link_guest_patient_account(uuid,uuid),
  public.transition_consultation(uuid,public.consultation_status,text,timestamptz,jsonb),public.confirm_medical_result(uuid,text,text,boolean) to authenticated;
grant execute on function public.available_doctor_slots(uuid,date,public.consultation_type) to anon;
revoke all on function private.is_consultation_participant(uuid) from public,anon;
grant execute on function private.is_consultation_participant(uuid) to authenticated;

do $$ declare table_name text; begin
  foreach table_name in array array['consultations','guest_consultation_requests','patients','doctor_patient_assignments','laboratory_results','medical_records','prescriptions'] loop
    if not exists (select 1 from pg_publication_tables where pubname='supabase_realtime' and schemaname='public' and tablename=table_name) then
      execute format('alter publication supabase_realtime add table public.%I',table_name);
    end if;
  end loop;
end $$;

insert into supabase_migrations.schema_migrations (version, statements, name)
values ('20260716200000', array[]::text[], 'care_lifecycle_and_clinical_integrity')
on conflict (version) do nothing;

commit;
