import {readFile} from 'node:fs/promises';
import {sql,management,env} from './repair_backend.mjs';
const accounts=JSON.parse(await readFile('.codex-runtime/repair-test-accounts.json','utf8'));
const patient=accounts.accounts.find(a=>a.role==='patient');
if(!patient.email.startsWith('repair-')||!patient.email.endsWith('@example.test'))throw new Error('Owned fixture required');
const objects=await sql(`select name,owner_id from storage.objects where bucket_id='medical-documents'
  and owner_id='${patient.id}' and name ~ '^[0-9a-f-]{36}/[0-9]+_e2e[.]pdf$'`);
if(objects.length){
  const service=(await management('api-keys')).find(k=>k.name==='service_role')?.api_key;
  const result=await fetch(`${env.NEXT_PUBLIC_SUPABASE_URL}/storage/v1/object/medical-documents`,{
    method:'DELETE',headers:{apikey:service,Authorization:`Bearer ${service}`,'Content-Type':'application/json'},
    body:JSON.stringify({prefixes:objects.map(o=>o.name)})});
  if(!result.ok)throw new Error(`Synthetic storage cleanup HTTP ${result.status}`);
}
// Recover only closed, pending hospital fixtures created by this E2E harness.
const superadmin=accounts.accounts.find(a=>a.role==='super_admin');
const hospitals=await sql(`select id from public.hospitals where hospital_name like 'SYNTHETIC E2E % isolated hospital'
  and created_by='${superadmin.id}' and verification_status='pending' and operating_status='closed'
  and not exists(select 1 from public.users u where u.hospital_id=hospitals.id)`);
for(const h of hospitals){
  const [{count}]=await sql(`select count(*)::int count from public.doctors where hospital_id='${h.id}'`);
  if(count)throw new Error('Refusing hospital cleanup with a remaining doctor');
  await sql(`begin;
    delete from public.hospital_services where hospital_id='${h.id}';
    delete from public.hospital_beds where hospital_id='${h.id}';
    delete from public.hospital_rooms where hospital_id='${h.id}';
    delete from public.hospital_facility_status where hospital_id='${h.id}';
    delete from public.emergency_room_status where hospital_id='${h.id}';
    delete from public.hospital_departments where hospital_id='${h.id}';
    delete from public.hospitals where id='${h.id}';commit;`);
}
console.log(JSON.stringify({removedMalformedSyntheticUploads:objects.length,removedInactiveIsolatedHospitals:hospitals.length}));
