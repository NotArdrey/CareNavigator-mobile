import {readFile,writeFile} from 'node:fs/promises';
import {fixture,rpc,api} from './repair_fixture_api.mjs';
import {launch,signIn,goto,controls,fill} from './repair_browser_helpers.mjs';
const out='.codex-runtime/repair-browser';
const slots=JSON.parse(await readFile(`${out}/slots.json`,'utf8'));
const slot=slots[5];
console.log('Slot fields:',Object.keys(slot));
const appointment=slot.starts_at;
if(!appointment)throw new Error('Inspect slot contract');
const saved=await readFile(`${out}/journey.json`,'utf8').then(JSON.parse).catch(()=>null);
const outcome=saved?.outcome??await rpc('patient','book_consultation_v2',{booking_payload:{doctor_id:fixture.id,hospital_id:fixture.hospital_id,
  consultation_type:'online',appointment_date:appointment,chief_complaint:'Playwright synthetic review journey',
  symptom_duration:'One day',shared_categories:['medical_documents','medical_records','prescriptions']}});
await writeFile(`${out}/journey.json`,JSON.stringify({outcome,slot},null,2));
const browser=await launch();
try{
  const {page}=await signIn(browser,'hospital_admin');
  await goto(page,`/hospital-admin/appointments/online-request~${outcome.request_id}`);
  await writeFile(`${out}/hospital-detail.json`,JSON.stringify(await controls(page),null,2));
  console.log('Hospital detail controls saved.');
  if(await page.getByRole('button',{name:'Start review',exact:true}).count())await page.getByRole('button',{name:'Start review',exact:true}).click();
  await page.getByRole('button',{name:'Request information',exact:true}).click();
  await writeFile(`${out}/information-dialog.json`,JSON.stringify(await controls(page),null,2));
  await fill(page,page.getByRole('textbox',{name:'Decision note',exact:true}),'Please describe the synthetic test symptom duration.');
  await page.getByRole('button',{name:'Request information',exact:true}).click();
  await page.waitForTimeout(800);
  const patient=await signIn(browser,'patient');
  await goto(patient.page,`/patient/appointments/online-request~${outcome.request_id}`);
  await writeFile(`${out}/patient-information.json`,JSON.stringify(await controls(patient.page),null,2));
  await patient.page.getByRole('button',{name:'Respond to hospital',exact:true}).click();
  await fill(patient.page,patient.page.getByRole('textbox',{name:'Decision note',exact:true}),'Synthetic symptoms began one day ago.');
  await patient.page.getByRole('button',{name:'Send response',exact:true}).click();
  await goto(page,`/hospital-admin/appointments/online-request~${outcome.request_id}`);
  await page.getByRole('button',{name:'Propose schedule',exact:true}).click();
  await writeFile(`${out}/proposal-dialog.json`,JSON.stringify(await controls(page),null,2));
  console.log('Information request and patient response submitted; proposal dialog saved.');
}finally{await browser.close();}
