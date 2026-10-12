import {writeFile} from 'node:fs/promises';
import assert from 'node:assert/strict';
import {accounts,fixture,rpc,api,base,publicKey} from './repair_fixture_api.mjs';
import {sql} from './repair_backend.mjs';
const slots=await rpc('patient','list_available_consultation_slots',{target_doctor_id:fixture.id,target_type:'online',horizon_days:14});
const care=await rpc('patient','book_consultation_v2',{booking_payload:{doctor_id:fixture.id,hospital_id:fixture.hospital_id,consultation_type:'online',appointment_date:slots[25].starts_at,chief_complaint:'SYNTHETIC isolated media fixture',symptom_duration:'One day'}});
const outcome=await rpc('hospital_admin','review_online_consultation_request',{target_request_id:care.request_id,decision:'confirmed',target_doctor_id:fixture.id,target_confirmed_schedule:slots[25].starts_at,target_channel:'video'});
const patient=accounts.accounts.find(a=>a.role==='patient');
await sql(`begin;lock table public.consultations in share row exclusive mode;
  alter table public.consultations disable trigger enforce_reservation_lead_time;
  alter table public.consultations disable trigger aa_lock_consultation_reservation;
  update public.consultations c set appointment_date=now() where c.id='${outcome.consultation_id}' and c.doctor_id='${fixture.id}'
    and c.patient_id=(select p.id from public.patients p join public.users u on u.id=p.user_id where u.auth_user_id='${patient.id}');
  alter table public.consultations enable trigger enforce_reservation_lead_time;
  alter table public.consultations enable trigger aa_lock_consultation_reservation;commit;`);
await assert.rejects(()=>api('patient','functions/v1/care-workflows',{action:'get_video_join_url',consultation_id:outcome.consultation_id}),/HTTP 403/);
for(const role of ['patient','guest','hospital_admin']){
  await assert.rejects(()=>rpc(role,'set_consultation_meet_link',{target_consultation_id:outcome.consultation_id,meeting_url:'https://meet.google.com/abc-defg-hij'}),/HTTP 400/);
}
await rpc('doctor','set_consultation_meet_link',{target_consultation_id:outcome.consultation_id,meeting_url:'https://meet.google.com/abc-defg-hij?authuser=1'});
await rpc('doctor','ensure_video_session',{target_consultation_id:outcome.consultation_id});
for(const role of ['doctor','patient']){
  const result=await api(role,'functions/v1/care-workflows',{action:'get_video_join_url',consultation_id:outcome.consultation_id});
  assert.equal(new URL(result.join_url).origin,result.provider_origin);
  assert.equal(result.join_url,'https://meet.google.com/abc-defg-hij');
}
for(const role of ['guest','hospital_admin']){
  await assert.rejects(()=>api(role,'functions/v1/care-workflows',{action:'get_video_join_url',consultation_id:outcome.consultation_id}),/HTTP 403/);
}
const anon=await fetch(`${base}/functions/v1/care-workflows`,{method:'POST',headers:{apikey:publicKey,Authorization:`Bearer ${publicKey}`,'Content-Type':'application/json'},body:JSON.stringify({action:'get_video_join_url',consultation_id:outcome.consultation_id})});
assert.equal(anon.status,401);
await writeFile('.codex-runtime/repair-fixture-media.json',JSON.stringify(outcome,null,2));
console.log('Google Meet: only assigned doctor saves; patient waits for link; doctor/patient join; unrelated guest, hospital admin and public key rejected.');
