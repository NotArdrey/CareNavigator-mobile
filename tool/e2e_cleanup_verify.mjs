import {readFile,writeFile} from 'node:fs/promises';
import {sql} from './repair_backend.mjs';
const fixtures=JSON.parse(await readFile('.codex-runtime/repair-test-accounts.json','utf8'));
const ids=[...fixtures.accounts,...(fixtures.additionalAccounts??[])].map(a=>{
  if(!/^[0-9a-f-]{36}$/i.test(a.id)||!a.email.startsWith('repair-')||!a.email.endsWith('@example.test'))throw new Error('Invalid fixture scope');
  return `'${a.id}'`;
}).join(',');
const [result]=await sql(`select
  (select count(*)::int from public.users where auth_user_id in (${ids}) and account_status <> 'inactive') active_test_users,
  (select count(*)::int from public.consultations where doctor_id in
    (select d.id from public.doctors d join public.users u on u.id=d.user_id where u.auth_user_id in (${ids}))
    and status not in ('completed','cancelled','rejected')) open_test_consultations,
  (select count(*)::int from public.doctor_schedules where is_active and doctor_id in
    (select d.id from public.doctors d join public.users u on u.id=d.user_id where u.auth_user_id in (${ids}))) active_test_schedules,
  (select count(*)::int from public.notification_outbox where user_id in (${ids}) and status in ('pending','processing','failed')) eligible_test_jobs,
  (select count(*)::int from public.hospitals where hospital_name like 'SYNTHETIC E2E % isolated hospital'
    and created_by in (${ids})) remaining_isolated_hospitals,
  (select count(*)::int from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace
    where n.nspname='public' and t.tgenabled='D' and not t.tgisinternal) disabled_application_triggers`);
await writeFile('.codex-runtime/e2e/cleanup-verification.json',JSON.stringify(result,null,2));
console.log(JSON.stringify(result));
if(Object.values(result).some(v=>v!==0))process.exitCode=1;
