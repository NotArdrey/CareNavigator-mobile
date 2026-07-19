begin;

insert into auth.users(
  id,aud,role,email,email_confirmed_at,raw_app_meta_data,raw_user_meta_data
) values(
  '13000000-0000-4000-8000-000000000001',
  'authenticated','authenticated','email-only@example.invalid',now(),
  '{"provider":"email","providers":["email"]}',
  '{"first_name":"Email","last_name":"Only"}'
);

insert into public.notification_preferences(user_id,email_enabled)
values('13000000-0000-4000-8000-000000000001',true)
on conflict(user_id) do update set email_enabled=excluded.email_enabled;

insert into public.notifications(
  user_id,title,message,notification_type,dedupe_key
) values(
  '13000000-0000-4000-8000-000000000001',
  'Email-only rollback test','Synthetic delivery','system',
  'email-only-rollback-test'
);

do $$
begin
  if exists(
    select 1 from information_schema.columns
    where table_schema='public'
      and table_name='notification_preferences'
      and column_name in('sms_enabled','push_enabled')
  ) then
    raise exception 'Removed external channel columns still exist';
  end if;
  if to_regclass('public.device_tokens') is not null then
    raise exception 'Push device-token storage still exists';
  end if;
  if not exists(
    select 1 from public.notification_outbox outbox
    join public.notifications notification
      on notification.id=outbox.notification_id
    where notification.dedupe_key='email-only-rollback-test'
      and outbox.channel='email'
  ) then
    raise exception 'Email delivery was not queued';
  end if;
  if exists(select 1 from public.notification_outbox where channel<>'email') then
    raise exception 'A non-email delivery channel remains';
  end if;
end
$$;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub','13000000-0000-4000-8000-000000000001',true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"13000000-0000-4000-8000-000000000001","role":"authenticated","email":"email-only@example.invalid"}',
  true
);

insert into public.guest_consultation_requests(
  submitted_by,reference_number,full_name,birth_date,sex,mobile_number,
  email,address,symptoms,symptom_duration,consultation_reason,
  identification_file_path
) values(
  '13000000-0000-4000-8000-000000000001',
  'EMAIL-ONLY-ROLLBACK','Email Only Guest','1990-01-01','prefer_not_to_say',
  '+639170000000','email-only@example.invalid','Rollback test address',
  'Rollback test symptom','one day','Rollback policy verification',
  '13000000-0000-4000-8000-000000000001/test-id.pdf'
);

select set_config(
  'request.jwt.claims',
  '{"sub":"13000000-0000-4000-8000-000000000001","role":"authenticated"}',
  true
);

do $$
declare
  missing_email_rejected boolean := false;
begin
  begin
    insert into public.guest_consultation_requests(
      submitted_by,reference_number,full_name,birth_date,sex,mobile_number,
      email,address,symptoms,symptom_duration,consultation_reason,
      identification_file_path
    ) values(
      '13000000-0000-4000-8000-000000000001',
      'EMAIL-MISSING-ROLLBACK','Unverified Guest','1990-01-01',
      'prefer_not_to_say','+639170000000',null,'Rollback test address',
      'Rollback test symptom','one day','Rollback policy rejection',
      '13000000-0000-4000-8000-000000000001/test-id-2.pdf'
    );
  exception when insufficient_privilege then
    missing_email_rejected := true;
  end;
  if not missing_email_rejected then
    raise exception 'A session without verified email could submit a request';
  end if;
end
$$;

reset role;
rollback;
