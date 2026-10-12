-- Allow clinical actions to use the durable doctor-patient assignment when
-- there is no currently active consultation.

alter table public.prescriptions
  add column if not exists assignment_id uuid
    references public.doctor_patient_assignments(id) on delete restrict;

alter table public.prescriptions
  alter column consultation_id drop not null;

alter table public.prescriptions
  drop constraint if exists prescriptions_clinical_context_required;
alter table public.prescriptions
  add constraint prescriptions_clinical_context_required
  check (consultation_id is not null or assignment_id is not null);

create index if not exists prescriptions_assignment_idx
  on public.prescriptions(assignment_id)
  where assignment_id is not null;

create or replace function public.validate_prescription_relationships()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  consultation_row public.consultations;
  assignment_row public.doctor_patient_assignments;
begin
  if new.assignment_id is not null then
    select * into assignment_row
    from public.doctor_patient_assignments assignment
    where assignment.id = new.assignment_id
      and assignment.assignment_status = 'active'
      and assignment.ended_at is null;

    if not found
      or assignment_row.patient_id is distinct from new.patient_id
      or assignment_row.doctor_id is distinct from new.doctor_id
      or assignment_row.hospital_id is null then
      raise exception 'Prescription does not match an active doctor-patient assignment';
    end if;
    new.hospital_id := assignment_row.hospital_id;
  end if;

  if new.consultation_id is not null then
    select * into consultation_row
    from public.consultations consultation
    where consultation.id = new.consultation_id;

    if not found
      or consultation_row.patient_id is distinct from new.patient_id
      or consultation_row.doctor_id is distinct from new.doctor_id then
      raise exception 'Prescription does not match its consultation';
    end if;
    if new.assignment_id is not null
      and consultation_row.hospital_id is distinct from assignment_row.hospital_id then
      raise exception 'Prescription consultation and assignment hospitals do not match';
    end if;
    new.hospital_id := consultation_row.hospital_id;
  elsif new.assignment_id is null then
    raise exception 'Prescription requires a consultation or active assignment';
  end if;

  return new;
end
$function$;

create or replace function public.notify_prescription_created()
returns trigger
language plpgsql
security definer
set search_path = ''
as $function$
declare
  recipient uuid;
begin
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
$function$;
