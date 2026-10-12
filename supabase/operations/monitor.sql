-- Privileged read-only aggregate checks. No names, contact details or clinical text.
select 'request_consultation_mismatch' metric,count(*) value
from public.online_consultation_requests r join public.consultations c on c.id=r.official_consultation_id
where (r.request_status='completed' and c.status<>'completed')
   or (r.request_status in ('cancelled','rejected','no_show','patient_unreachable','face_to_face_recommended')
       and c.status not in ('cancelled','rejected'));

select 'confirmed_schedule_mismatch' metric,count(*) value
from public.online_consultation_requests r join public.consultations c on c.id=r.official_consultation_id
where r.request_status in ('confirmed','awaiting_contact','video_ready','in_progress')
and r.confirmed_schedule is distinct from c.appointment_date;

select 'terminal_consultation_active_grants' metric,count(*) value
from public.patient_access_grants g join public.consultations c on c.id=g.consultation_id
where c.status in ('completed','cancelled','rejected') and g.status='active' and g.expires_at>now();

select 'outbox_'||status metric,count(*) value from public.notification_outbox
where created_at>now()-interval '24 hours' group by status;

select 'duplicate_daily_summary' metric,count(*) value from
(select patient_id,local_date from public.medication_summary_days group by patient_id,local_date having count(*)>1) d;

select 'activation_missing_identity' metric,count(*) value from public.patients
where account_activation_status='active' and user_id is null;

select 'duplicate_patient_profile' metric,count(*) value from
(select user_id from public.patients where user_id is not null group by user_id having count(*)>1) d;

select 'authorization_failures_24h' metric,count(*) value from public.security_logs
where not success and created_at>now()-interval '24 hours';
