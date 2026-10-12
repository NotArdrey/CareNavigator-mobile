import {env} from './repair_backend.mjs';
import {readFile} from 'node:fs/promises';
import {spawn} from 'node:child_process';
import {accounts,fixture,rpc} from './repair_fixture_api.mjs';
const fixtures=JSON.parse(await readFile('.codex-runtime/repair-test-accounts.json','utf8'));
// A prior verification run retires its appointments and sharing grants. Build
// a fresh relationship through the same patient/hospital RPCs as the app.
if(!accounts.accounts.every(a=>a.email.startsWith('repair-')&&a.email.endsWith('@example.test')))
  throw new Error('Live mutations require the owned synthetic actors.');
const slots=await rpc('patient','list_available_consultation_slots',{
  target_doctor_id:fixture.id,target_type:'online',horizon_days:14});
if(!slots.length)throw new Error('No available synthetic consultation slot.');
const booking=await rpc('patient','book_consultation_v2',{booking_payload:{
  doctor_id:fixture.id,hospital_id:fixture.hospital_id,consultation_type:'online',
  appointment_date:slots[0].starts_at,chief_complaint:'SYNTHETIC live repository verification',symptom_duration:'One day'}});
const confirmed=await rpc('hospital_admin','review_online_consultation_request',{
  target_request_id:booking.request_id,decision:'confirmed',target_doctor_id:fixture.id,
  target_confirmed_schedule:slots[0].starts_at,target_channel:'call'});
console.log('Prepared a fresh synthetic doctor/patient relationship for live repository tests.');
const runtimeEnv={...process.env,CNPH_TEST_SUPABASE_URL:env.NEXT_PUBLIC_SUPABASE_URL,
  CNPH_TEST_SUPABASE_PUBLISHABLE_KEY:env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
  CNPH_TEST_PASSWORD:fixtures.password,CNPH_TEST_ACCOUNTS:JSON.stringify(fixtures.accounts)};
const names={patient:'PATIENT',doctor:'DOCTOR',super_admin:'SUPERADMINISTRATOR',hospital_admin:'HOSPITALADMINISTRATOR',guest:'GUEST'};
for(const account of fixtures.accounts)runtimeEnv[`CNPH_TEST_${names[account.role]}_EMAIL`]=account.email;
runtimeEnv.CNPH_TEST_CONSULTATION_ID=confirmed.consultation_id;
const child=spawn('C:/Users/Neila/devtools/flutter/bin/flutter.bat',['test','--reporter','expanded'],{shell:true,env:runtimeEnv,stdio:'inherit'});
child.on('exit',code=>process.exit(code??1));
