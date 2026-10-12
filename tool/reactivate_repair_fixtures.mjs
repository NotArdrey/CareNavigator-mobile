// Reuse only the verified synthetic identities from the prior owned test run.
import {readFile} from 'node:fs/promises';
import {env,sql,management} from './repair_backend.mjs';
const fixtures=JSON.parse(await readFile('.codex-runtime/repair-test-accounts.json','utf8'));
const accounts=fixtures.accounts;
const scopedAccounts=[...accounts,...(fixtures.additionalAccounts??[])];
const service=(await management('api-keys')).find(k=>k.name==='service_role')?.api_key;
if(!service)throw new Error('Fixture admin access unavailable');
for(const a of scopedAccounts){
  if(!/^[0-9a-f-]{36}$/.test(a.id)||!a.email.startsWith('repair-')||!a.email.endsWith('@example.test'))throw new Error('Fixture scope check failed');
  const response=await fetch(`${env.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/admin/users/${a.id}`,{headers:{apikey:service,Authorization:`Bearer ${service}`}});
  const u=await response.json();if(!response.ok||u.email!==a.email)throw new Error('Fixture identity mismatch');
}
const ids=accounts.map(a=>`'${a.id}'`).join(',');
const scopedIds=scopedAccounts.map(a=>`'${a.id}'`).join(',');
await sql(`begin;
  do $$ begin if exists(select 1 from public.consultations c join public.doctors d on d.id=c.doctor_id join public.users u on u.id=d.user_id
    where u.auth_user_id in (${ids})
    and not exists(select 1 from public.patients p join public.users pu on pu.id=p.user_id where p.id=c.patient_id and pu.auth_user_id in (${scopedIds}))
    and not exists(select 1 from public.guest_consultation_requests g where g.id=c.guest_request_id and g.submitted_by in (${scopedIds})))
    then raise exception 'Fixture doctor has a patient outside the owned test scope'; end if; end $$;
  update public.users set account_status='active' where auth_user_id in (${ids});
  update public.doctors set availability_status='available' where user_id in(select id from public.users where auth_user_id in (${ids}));
  update public.doctor_hospital_employments set employment_status='active',ends_at=null
    where doctor_id in(select d.id from public.doctors d join public.users u on u.id=d.user_id where u.auth_user_id in (${ids}));
  update public.doctor_schedules set is_active=true where doctor_id in(select d.id from public.doctors d join public.users u on u.id=d.user_id where u.auth_user_id in (${ids}));
  commit;`);
for(const a of accounts){
  const response=await fetch(`${env.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/admin/users/${a.id}`,{method:'PUT',headers:{apikey:service,Authorization:`Bearer ${service}`,'Content-Type':'application/json'},body:JSON.stringify({ban_duration:'none'})});
  if(!response.ok)throw new Error(`Fixture reactivation HTTP ${response.status}`);
}
console.log(`Reactivated ${accounts.length} verified synthetic actors; old appointments and grants remain closed.`);
