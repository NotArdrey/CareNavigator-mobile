begin;

-- Supabase Cron invokes the protected dispatcher. The token itself is never
-- stored in this migration; deployments provision it in Vault under the name
-- used below. If the secret has not been provisioned yet, the scheduled query
-- safely becomes a no-op.
create extension if not exists pg_cron;
create extension if not exists pg_net;

do $$
declare
  existing_job_id bigint;
begin
  select jobid
  into existing_job_id
  from cron.job
  where jobname = 'carenavigator-dispatch-notifications'
  limit 1;

  if existing_job_id is not null then
    perform cron.unschedule(existing_job_id);
  end if;
end
$$;

select cron.schedule(
  'carenavigator-dispatch-notifications',
  '*/5 * * * *',
  $cron$
    with dispatch_config as (
      select decrypted_secret as dispatch_token
      from vault.decrypted_secrets
      where name = 'carenavigator_notification_dispatch_token'
        and nullif(decrypted_secret, '') is not null
      limit 1
    )
    select net.http_post(
      url := 'https://crhsbpkuteyqbxjpozrp.supabase.co/functions/v1/dispatch-notifications',
      headers := jsonb_build_object(
        'content-type', 'application/json',
        'x-dispatch-token', dispatch_token
      ),
      body := jsonb_build_object(
        'batch_size', 100,
        'reminder_window_hours', 24
      ),
      timeout_milliseconds := 15000
    )
    from dispatch_config;
  $cron$
);

commit;
