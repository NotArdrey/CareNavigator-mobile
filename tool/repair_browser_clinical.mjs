import {readFile,writeFile} from 'node:fs/promises';
import {sql} from './repair_backend.mjs';
import {fixture,accounts,rpc,api} from './repair_fixture_api.mjs';
import {launch,signIn,goto,controls,fill} from './repair_browser_helpers.mjs';
const out='.codex-runtime/repair-browser';
const request=(JSON.parse(await readFile(`${out}/proposal-outcome.json`,'utf8')))[0];
const id=request.official_consultation_id;
const patient=accounts.accounts.find(a=>a.role==='patient');
// Table locks and a single transaction isolate only this owned historical fixture.
await sql(`begin;lock table public.consultations in share row exclusive mode;
  alter table public.consultations disable trigger enforce_reservation_lead_time;
  alter table public.consultations disable trigger aa_lock_consultation_reservation;
  update public.consultations c set appointment_date=now() where c.id='${id}' and c.doctor_id='${fixture.id}'
    and c.patient_id=(select p.id from public.patients p join public.users u on u.id=p.user_id where u.auth_user_id='${patient.id}');
  alter table public.consultations enable trigger enforce_reservation_lead_time;
  alter table public.consultations enable trigger aa_lock_consultation_reservation;commit;`);
const browser=await launch();
try{
  const doctor=await signIn(browser,'doctor');
  await goto(doctor.page,`/doctor/appointments/online-request~${request.id}`);
  await doctor.page.getByRole('button',{name:'Start consultation',exact:true}).click();
  await doctor.page.getByRole('button',{name:'Start consultation',exact:true}).click();
  await doctor.page.getByRole('button',{name:'Complete checkup',exact:true}).waitFor();
  await doctor.page.getByRole('button',{name:'Complete checkup',exact:true}).click();
  for(const [name,text]of [['Consultation summary','SYNTHETIC browser checkup completed for test verification.'],['Confirmed diagnosis','Synthetic test diagnosis'],['Treatment plan','Synthetic test instructions.'],['Doctor notes','No real clinical care provided; this is a synthetic fixture.']]){
    await fill(doctor.page,doctor.page.getByRole('textbox',{name,exact:true}),text);
  }
  await doctor.page.getByRole('button',{name:'Complete consultation',exact:true}).click();
  await doctor.page.waitForTimeout(1000);
  const rows=await api('doctor',`rest/v1/consultations?id=eq.${id}&select=id,status,confirmed_diagnosis,consultation_summary`,undefined,'GET');
  if(rows[0].status!=='completed')throw new Error('Checkup completion did not commit');
  await writeFile(`${out}/clinical-outcome.json`,JSON.stringify(rows,null,2));
  console.log('Assigned doctor start and structured checkup completion through UI: PASS');
}catch(error){for(const c of browser.contexts())for(const p of c.pages())await writeFile(`${out}/clinical-last.json`,JSON.stringify(await controls(p),null,2));throw error;}
finally{await browser.close();}
