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
 elsif message_kind='medication_reminder' and target_order_id is not null then raise exception 'Daily summaries are filtered by the current Manila date';
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
