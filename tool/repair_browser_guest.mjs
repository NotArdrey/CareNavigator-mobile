import {readFile,writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {accounts,fixture,rpc,api} from './repair_fixture_api.mjs';
import {launch,signIn,goto,controls} from './repair_browser_helpers.mjs';
const out='.codex-runtime/repair-browser';
const account=accounts.accounts.find(a=>a.role==='guest');
const slots=await rpc('guest','list_available_consultation_slots',{target_doctor_id:fixture.id,target_type:'guest_online',horizon_days:14});
const slot=slots[10];
const saved=await readFile(`${out}/guest-journey.json`,'utf8').then(JSON.parse).catch(()=>null);
const request_id=saved?.request_id??await rpc('guest','submit_guest_consultation_request',{request_payload:{first_name:'Repair',last_name:'Guest browser fixture',birth_date:'1990-01-01',
  sex:'male',mobile_number:'+639171234567',email:account.email,address:'Synthetic browser test address',symptoms:'SYNTHETIC browser guest care concern',symptom_duration:'One day',
  preferred_hospital_id:fixture.hospital_id,preferred_department_id:fixture.department_id,preferred_consultation_type:'guest_online',preferred_schedule:slot.starts_at},idempotency_key:randomUUID()});
await writeFile(`${out}/guest-journey.json`,JSON.stringify({request_id,slot},null,2));
const browser=await launch();
try{
  const hospital=await signIn(browser,'hospital_admin');
  await goto(hospital.page,`/hospital-admin/appointments/guest-request~${request_id}`);
  await hospital.page.getByRole('button',{name:'Approve',exact:true}).click();
  await hospital.page.getByRole('button',{name:'Approve and schedule',exact:true}).click();
  const doctorOption=hospital.page.getByRole('button',{name:'Dr Repair Fixture Test only',exact:true});
  await doctorOption.waitFor();await doctorOption.click();
  await hospital.page.waitForTimeout(1000);
  const guest=await signIn(browser,'guest');
  await goto(guest.page,`/consultation/confirmation/${request_id}`);
  await writeFile(`${out}/guest-approved-controls.json`,JSON.stringify(await controls(guest.page),null,2));
  await guest.page.getByRole('button',{name:'Activate patient account',exact:true}).click();
  await guest.page.getByRole('button',{name:'Set or update my password',exact:true}).waitFor();
  const result=await rpc('guest','activate_approved_guest',{target_request_id:request_id});
  if(result.status!=='active')throw new Error('Guest activation failed');
  await writeFile(`${out}/guest-activation-outcome.json`,JSON.stringify(result,null,2));
  console.log('Guest hospital approval, tracking, in-place activation and idempotent retry: PASS');
}catch(error){for(const c of browser.contexts())for(const p of c.pages())await writeFile(`${out}/guest-last-${browser.contexts().indexOf(c)}.json`,JSON.stringify(await controls(p),null,2));throw error;}
finally{await browser.close();}
