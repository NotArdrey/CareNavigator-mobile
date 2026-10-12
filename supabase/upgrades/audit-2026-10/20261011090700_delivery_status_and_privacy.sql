alter table public.notifications add column email_delivery_status text not null default 'disabled'
check(email_delivery_status in ('disabled','queued','sent','failed'));
create or replace function private.sync_email_delivery_status()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
 update public.notifications set email_delivery_status=case new.status
   when 'delivered' then 'sent' when 'failed' then 'failed' when 'cancelled' then 'disabled' else 'queued' end
 where id=new.notification_id;
 return new;
end $$;
create trigger sync_email_delivery_status after insert or update of status on public.notification_outbox
for each row execute function private.sync_email_delivery_status();
revoke all on function private.sync_email_delivery_status() from public;
update public.notifications n set email_delivery_status=case o.status
 when 'delivered' then 'sent' when 'failed' then 'failed' when 'cancelled' then 'disabled' else 'queued' end
from public.notification_outbox o where o.notification_id=n.id;

-- Source documents remain patient-authored even after an official review is added.
create or replace function private.guard_source_document_record()
returns trigger language plpgsql security definer set search_path = '' as $$
begin
 if new.source_document_id is not null and not exists(select 1 from public.medical_documents d
   where d.id=new.source_document_id and d.patient_id=new.patient_id and d.review_state='approved'
     and d.reviewed_by=private.current_user_id() and new.doctor_id=private.current_doctor_id()) then
  raise exception 'Official supporting-document entries require an authorized doctor review'; end if;
 return new;
end $$;
create trigger guard_source_document_record before insert on public.medical_records
for each row execute function private.guard_source_document_record();
revoke all on function private.guard_source_document_record() from public;
