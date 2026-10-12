import {test,expect} from '@playwright/test';
import {readFile,writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {sql} from '../repair_backend.mjs';
import {accounts,fixture,rpc,api} from '../repair_fixture_api.mjs';
import {launch,signIn,goto,fill} from '../repair_browser_helpers.mjs';

const meeting='https://meet.google.com/xyz-abcd-efg';
async function assertHandoff(page,context,button){
  // Verify the app's actual external navigation; this does not simulate a call.
  await context.route('https://meet.google.com/**',route=>route.fulfill({status:200,contentType:'text/html',body:'<title>Controlled Google Meet handoff</title>'}));
  const popup=context.waitForEvent('page');await button.click();
  const external=await popup;await external.waitForURL(meeting);
  expect(external.url()).toBe(meeting);await external.close();
}

test('doctor updates Google Meet link and patient opens the authorized external link',async()=>{
  await import(`../repair_video_access_check.mjs?fixture=${Date.now()}`);
  const care=JSON.parse(await readFile('.codex-runtime/repair-fixture-media.json','utf8'));
  const browser=await launch();try{
    const doctor=await signIn(browser,'doctor');await goto(doctor.page,`/doctor/appointments/online-request~${care.request_id}`);
    await doctor.page.getByRole('button',{name:'Set Google Meet link',exact:true}).click();
    await fill(doctor.page,doctor.page.getByRole('textbox',{name:/^Google Meet link/}),meeting+'?authuser=1');
    await doctor.page.getByRole('button',{name:'Save meeting link',exact:true}).click();
    await expect.poll(async()=> (await api('patient','functions/v1/care-workflows',{action:'get_video_join_url',consultation_id:care.consultation_id})).join_url).toBe(meeting);
    await assertHandoff(doctor.page,doctor.context,doctor.page.getByRole('button',{name:'Join Google Meet',exact:true}));
    const patient=await signIn(browser,'patient');await goto(patient.page,`/patient/appointments/online-request~${care.request_id}`);
    await expect(patient.page.getByRole('button',{name:'Set Google Meet link',exact:true})).toHaveCount(0);
    await assertHandoff(patient.page,patient.context,patient.page.getByRole('button',{name:'Join Google Meet',exact:true}));
    await writeFile('.codex-runtime/repair-browser/google-meet-handoff.json',JSON.stringify({doctor:true,patient:true,provider:'google_meet',actualProviderMediaTested:false}));
  }finally{await browser.close();}
});

test('approved guest opens Google Meet without activating another patient account',async()=>{
  const account=accounts.accounts.find(a=>a.role==='guest');
  const slots=await rpc('guest','list_available_consultation_slots',{target_doctor_id:fixture.id,target_type:'guest_online',horizon_days:14});
  const requestId=await rpc('guest','submit_guest_consultation_request',{request_payload:{first_name:'Repair',last_name:'Google Meet guest fixture',birth_date:'1990-01-01',sex:'male',mobile_number:'+639171234567',email:account.email,address:'Synthetic Google Meet test address',symptoms:'SYNTHETIC Google Meet guest concern',symptom_duration:'One day',preferred_hospital_id:fixture.hospital_id,preferred_department_id:fixture.department_id,preferred_consultation_type:'guest_online',preferred_schedule:slots[24].starts_at},idempotency_key:randomUUID()});
  const outcome=await rpc('hospital_admin','review_guest_consultation',{target_request_id:requestId,decision:'approved',target_doctor_id:fixture.id,target_appointment_date:slots[24].starts_at,review_notes:'Synthetic Google Meet browser review'});
  await sql(`begin;lock table public.consultations in share row exclusive mode;
    alter table public.consultations disable trigger enforce_reservation_lead_time;
    alter table public.consultations disable trigger aa_lock_consultation_reservation;
    update public.consultations c set appointment_date=now() where c.id='${outcome.consultation_id}' and c.doctor_id='${fixture.id}'
      and c.guest_request_id='${requestId}' and exists(select 1 from public.guest_consultation_requests g where g.id=c.guest_request_id and g.submitted_by='${account.id}');
    alter table public.consultations enable trigger enforce_reservation_lead_time;
    alter table public.consultations enable trigger aa_lock_consultation_reservation;commit;`);
  await rpc('doctor','set_consultation_meet_link',{target_consultation_id:outcome.consultation_id,meeting_url:meeting});
  const browser=await launch();try{
    const guest=await signIn(browser,'guest');await goto(guest.page,`/consultation/confirmation/${requestId}`);
    await assertHandoff(guest.page,guest.context,guest.page.getByRole('button',{name:'Join Google Meet / retry',exact:true}));
  }finally{await browser.close();}
});
