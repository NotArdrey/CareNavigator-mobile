alter table public.medical_documents add column review_state text not null default 'unreviewed'
  check(review_state in ('unreviewed','approved','rejected')),
  add column reviewed_by uuid references public.users(id), add column reviewed_at timestamptz,
  add column review_rejection_reason text;
alter table public.medical_records add column source_document_id uuid references public.medical_documents(id);

create or replace function private.set_medical_document_ai_state()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
  if new.origin_type='patient_supplied' then
    new.review_state:='unreviewed'; new.reviewed_by:=null; new.reviewed_at:=null; new.review_rejection_reason:=null;
  end if;
  new.ai_analysis_status:=case when new.document_type in ('lab_result','diagnostic_result','prescription') then 'pending' else 'not_requested' end;
  new.ai_summary:=null; new.ai_extracted_data:=null; new.ai_analysis_error:=null; new.ai_analyzed_at:=null;
  return new;
end $$;

create or replace function public.review_patient_document(target_document_id uuid,decision text,review_notes text default null)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare d public.medical_documents; doctor public.doctors; record_id uuid;
begin
  select * into d from public.medical_documents where id=target_document_id for update;
  select * into doctor from public.doctors where id=private.current_doctor_id();
  if d.id is null or d.origin_type<>'patient_supplied' or doctor.id is null
    or not private.has_active_doctor_employment(doctor.id,doctor.hospital_id)
    or not (private.can_access_clinical_record(d.patient_id,doctor.hospital_id,'medical_documents',d.id,'view')
      or private.can_create_assigned_patient_document(d.patient_id,doctor.hospital_id)) then
    raise exception 'An authorized active treating doctor must review this patient document'; end if;
  if d.review_state<>'unreviewed' then
    return jsonb_build_object('document_id',d.id,'review_state',d.review_state,'already_reviewed',true);
  end if;
  if decision not in ('approved','rejected') then raise exception 'Choose approve or reject'; end if;
  if decision='rejected' and nullif(btrim(review_notes),'') is null then raise exception 'A rejection reason is required'; end if;
  update public.medical_documents set review_state=decision,reviewed_by=private.current_user_id(),reviewed_at=now(),
    review_rejection_reason=case when decision='rejected' then btrim(review_notes) else null end where id=d.id;
  if decision='approved' then
    insert into public.medical_records(patient_id,doctor_id,hospital_id,record_type,title,description,record_date,source_document_id)
    values(d.patient_id,doctor.id,doctor.hospital_id,'document_review','Reviewed supporting document: '||d.title,
      coalesce(nullif(btrim(review_notes),''),'Doctor reviewed the original patient-supplied document. AI extraction remains preliminary.'),now(),d.id)
    returning id into record_id;
  end if;
  return jsonb_build_object('document_id',d.id,'review_state',decision,'medical_record_id',record_id);
end $$;
revoke all on function public.review_patient_document(uuid,text,text) from public,anon;
grant execute on function public.review_patient_document(uuid,text,text) to authenticated;

create table public.prescription_orders(
  id uuid primary key default gen_random_uuid(),patient_id uuid not null references public.patients(id),
  doctor_id uuid not null references public.doctors(id),hospital_id uuid not null references public.hospitals(id),
  consultation_id uuid references public.consultations(id),assignment_id uuid references public.doctor_patient_assignments(id),
  issued_by uuid references public.users(id),issued_at timestamptz not null default now(),
  diagnosis_reason text, idempotency_key text, payload_fingerprint text,
  status text not null default 'issued' check(status in ('issued','voided')),
  legacy_import boolean not null default false,
  unique(doctor_id,idempotency_key)
);
alter table public.prescription_orders enable row level security;
create policy prescription_order_reads on public.prescription_orders for select to authenticated using (
  patient_id=private.current_patient_id() or private.can_access_clinical_record(patient_id,hospital_id,'prescriptions',id,'view')
  or (doctor_id=private.current_doctor_id() and private.can_create_assigned_patient_document(patient_id,hospital_id))
);
grant select on public.prescription_orders to authenticated;
revoke all on public.prescription_orders from anon;
alter table public.prescriptions add column order_id uuid references public.prescription_orders(id);
-- Legacy grouping is deliberately one record per order. No time or consultation heuristic.
insert into public.prescription_orders(id,patient_id,doctor_id,hospital_id,consultation_id,assignment_id,issued_by,issued_at,diagnosis_reason,legacy_import)
select p.id,p.patient_id,p.doctor_id,p.hospital_id,p.consultation_id,p.assignment_id,p.electronically_signed_by,
  p.created_at,p.diagnosis_reason,true from public.prescriptions p where p.hospital_id is not null;
update public.prescriptions set order_id=id where hospital_id is not null;
create index prescriptions_order_idx on public.prescriptions(order_id);

create or replace function public.issue_prescription_order(order_payload jsonb,idempotency_key text)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare doctor public.doctors; patient_id uuid:=(order_payload->>'patient_id')::uuid;
  consultation_id uuid:=nullif(order_payload->>'consultation_id','')::uuid;
  assignment_id uuid:=nullif(order_payload->>'assignment_id','')::uuid;
  order_row public.prescription_orders; medication jsonb; medication_ids jsonb; notification_status text;
begin
  select * into doctor from public.doctors where id=private.current_doctor_id();
  if doctor.id is null or auth.uid() is null or not private.has_active_doctor_employment(doctor.id,doctor.hospital_id)
    or not (private.can_access_clinical_record(patient_id,doctor.hospital_id,'prescriptions',null,'create')
      or private.can_create_assigned_patient_document(patient_id,doctor.hospital_id)) then
    raise exception 'An authorized active prescriber is required'; end if;
  if not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null and not coalesce(is_anonymous,false)) then
    raise exception 'A verified prescriber account is required'; end if;
  if consultation_id is not null and not exists (select 1 from public.consultations c
    where c.id=consultation_id and c.patient_id=patient_id and c.doctor_id=doctor.id
      and c.hospital_id=doctor.hospital_id and c.status in ('approved','scheduled','in_progress','completed')) then
    raise exception 'The selected consultation is not assigned to this prescriber'; end if;
  if assignment_id is not null and not exists(select 1 from public.doctor_patient_assignments a
    where a.id=assignment_id and a.patient_id=patient_id and a.doctor_id=doctor.id and a.hospital_id=doctor.hospital_id
      and a.assignment_status='active' and a.ended_at is null) then raise exception 'The care assignment is not active'; end if;
  if consultation_id is null and assignment_id is null then raise exception 'A consultation or active care assignment is required'; end if;
  if length(coalesce(idempotency_key,''))<16 or length(idempotency_key)>160 then raise exception 'An issuance idempotency key is required'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(doctor.id::text||':'||idempotency_key,0));
  select * into order_row from public.prescription_orders o where o.doctor_id=doctor.id and o.idempotency_key=$2;
  if found then
    if order_row.payload_fingerprint is distinct from md5(order_payload::text) then raise exception 'This issuance key belongs to a different order'; end if;
  else
    if jsonb_typeof(order_payload->'medications') is distinct from 'array'
      or jsonb_array_length(order_payload->'medications') not between 1 and 50 then raise exception 'Supply the complete medication list'; end if;
    insert into public.prescription_orders(patient_id,doctor_id,hospital_id,consultation_id,assignment_id,issued_by,diagnosis_reason,idempotency_key,payload_fingerprint)
    values(patient_id,doctor.id,doctor.hospital_id,consultation_id,assignment_id,private.current_user_id(),
      btrim(order_payload->>'diagnosis_reason'),$2,md5(order_payload::text)) returning * into order_row;
    for medication in select value from jsonb_array_elements(order_payload->'medications') loop
      if exists(select 1 from unnest(array['medication_name','dosage','frequency','duration','medication_form_strength','route','exact_dose','quantity_to_dispense']) key
        where nullif(btrim(medication->>key),'') is null) then raise exception 'Every medication requires complete dispensing directions'; end if;
      insert into public.prescriptions(order_id,patient_id,doctor_id,hospital_id,consultation_id,assignment_id,
        diagnosis_reason,medication_name,dosage,frequency,duration,medication_form_strength,route,exact_dose,quantity_to_dispense,
        refills,start_date,end_date,is_prn,prn_reason,maximum_daily_dose,instructions)
      values(order_row.id,patient_id,doctor.id,doctor.hospital_id,consultation_id,assignment_id,order_row.diagnosis_reason,
        btrim(medication->>'medication_name'),btrim(medication->>'dosage'),btrim(medication->>'frequency'),btrim(medication->>'duration'),
        btrim(medication->>'medication_form_strength'),btrim(medication->>'route'),btrim(medication->>'exact_dose'),btrim(medication->>'quantity_to_dispense'),
        (medication->>'refills')::integer,(medication->>'start_date')::date,nullif(medication->>'end_date','')::date,
        coalesce((medication->>'is_prn')::boolean,false),nullif(btrim(medication->>'prn_reason'),''),
        nullif(btrim(medication->>'maximum_daily_dose'),''),nullif(btrim(medication->>'instructions'),''));
    end loop;
  end if;
  select jsonb_agg(id order by created_at,id) into medication_ids from public.prescriptions where order_id=order_row.id;
  notification_status:=private.queue_prescription_order_notification(order_row.id);
  return jsonb_build_object('order_id',order_row.id,'medication_ids',medication_ids,'notification_status',notification_status);
end $$;
revoke all on function public.issue_prescription_order(jsonb,text) from public,anon;
grant execute on function public.issue_prescription_order(jsonb,text) to authenticated;
