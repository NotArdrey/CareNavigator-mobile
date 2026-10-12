// Preserve synthetic clinical provenance, retire only verified fixture identities.
import {readFile,writeFile} from 'node:fs/promises';
import {sql,management,env} from './repair_backend.mjs';
const fixtures=JSON.parse(await readFile('.codex-runtime/repair-test-accounts.json','utf8'));
const accounts=[...fixtures.accounts,...(fixtures.additionalAccounts??[])];
const keys=await management('api-keys');const service=keys.find(k=>k.name==='service_role')?.api_key;
if(!service)throw new Error('Fixture retirement admin access unavailable');
const alreadyBanned=new Set();
for(const account of accounts){
  if(!/^[0-9a-f-]{36}$/i.test(account.id)||!account.email.startsWith('repair-')||!account.email.endsWith('@example.test'))throw new Error('Fixture identity scope check failed');
  const response=await fetch(`${env.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/admin/users/${account.id}`,{headers:{apikey:service,Authorization:`Bearer ${service}`}});
  const user=await response.json();if(!response.ok||user.email!==account.email)throw new Error('Fixture Auth identity mismatch');
  if(Date.parse(user.banned_until)>Date.now())alreadyBanned.add(account.id);
}
const ids=accounts.map(a=>`'${a.id}'`).join(',');
const report=await sql(`begin;
  do $$ begin
    if exists(select 1 from public.consultations c join public.doctors d on d.id=c.doctor_id join public.users u on u.id=d.user_id
      where u.auth_user_id in (${ids})
      and not exists(select 1 from public.patients p join public.users pu on pu.id=p.user_id where p.id=c.patient_id and pu.auth_user_id in (${ids}))
      and not exists(select 1 from public.guest_consultation_requests g where g.id=c.guest_request_id and g.submitted_by in (${ids}))) then
      raise exception 'A fixture doctor has an appointment outside the owned test scope'; end if;
  end $$;
  update public.consultations set status='cancelled',outcome_reason='synthetic_test_retired'
    where doctor_id in(select d.id from public.doctors d join public.users u on u.id=d.user_id where u.auth_user_id in (${ids}))
    and status not in ('completed','cancelled','rejected');
  update public.online_consultation_requests set request_status='cancelled',cancellation_reason='Synthetic verification fixture retired'
    where patient_id in(select p.id from public.patients p join public.users u on u.id=p.user_id where u.auth_user_id in (${ids}))
    and request_status not in ('completed','cancelled','rejected','no_show','patient_unreachable','face_to_face_recommended');
  update public.guest_consultation_requests set request_status=case
      when exists(select 1 from public.consultations c where c.guest_request_id=guest_consultation_requests.id and c.status='completed')
      then 'consultation_completed'::public.guest_request_status else 'cancelled'::public.guest_request_status end
    where submitted_by in (${ids}) and request_status not in ('consultation_completed','cancelled','rejected');
  update public.notification_outbox set status='cancelled',last_error='Synthetic verification fixture retired'
    where user_id in (${ids}) and status in ('pending','processing','failed');
  update public.doctors set availability_status='unavailable' where user_id in(select id from public.users where auth_user_id in (${ids}));
  update public.doctor_schedules set is_active=false where doctor_id in(select d.id from public.doctors d join public.users u on u.id=d.user_id where u.auth_user_id in (${ids}));
  update public.doctor_hospital_employments set employment_status='ended',ends_at=now()
    where doctor_id in(select d.id from public.doctors d join public.users u on u.id=d.user_id where u.auth_user_id in (${ids}));
  update public.users set account_status='inactive' where auth_user_id in (${ids});
  commit;
  select count(*) retired_app_users from public.users where auth_user_id in (${ids}) and account_status='inactive';`);
for(const account of accounts){
  if(alreadyBanned.has(account.id))continue;
  const login=await fetch(`${env.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/token?grant_type=password`,{method:'POST',headers:{apikey:env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,'Content-Type':'application/json'},body:JSON.stringify({email:account.email,password:fixtures.password})});
  const session=await login.json();
  if(!session.access_token)throw new Error(`Fixture global session revocation cannot be verified: login HTTP ${login.status}`);
  const logout=await fetch(`${env.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/logout?scope=global`,{method:'POST',headers:{apikey:service,Authorization:`Bearer ${session.access_token}`}});
  if(!logout.ok)throw new Error(`Fixture global session revocation failed: HTTP ${logout.status}`);
  const response=await fetch(`${env.NEXT_PUBLIC_SUPABASE_URL}/auth/v1/admin/users/${account.id}`,{method:'PUT',headers:{apikey:service,Authorization:`Bearer ${service}`,'Content-Type':'application/json'},body:JSON.stringify({ban_duration:'876000h'})});
  if(!response.ok)throw new Error(`Fixture Auth retirement failed: HTTP ${response.status}`);
  const retired=await response.json();
  if(!retired.banned_until||Date.parse(retired.banned_until)<=Date.now())throw new Error('Fixture Auth ban was not confirmed');
}
await writeFile('.codex-runtime/repair-fixture-retirement.json',JSON.stringify({retiredAt:new Date().toISOString(),report,accountCount:accounts.length,clinicalHistory:'retained as clearly labelled synthetic provenance'},null,2));
console.log(`Retired ${accounts.length} verified test identities, cancelled their open reservations and queued jobs, and removed the test doctor from published availability. Synthetic clinical history retained.`);
