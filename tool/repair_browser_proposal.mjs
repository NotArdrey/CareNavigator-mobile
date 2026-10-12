import {readFile,writeFile} from 'node:fs/promises';
import {api} from './repair_fixture_api.mjs';
import {launch,signIn,goto,controls} from './repair_browser_helpers.mjs';
const out='.codex-runtime/repair-browser';
const {outcome}=JSON.parse(await readFile(`${out}/journey.json`,'utf8'));
const browser=await launch();
try{
  const hospital=await signIn(browser,'hospital_admin');
  hospital.page.on('response',async response=>{if(response.url().includes('/rest/')&&response.status()>=400)console.log('API failure:',response.status(),response.url().split('/rest/')[1],(await response.text()).slice(0,400));});
  await goto(hospital.page,`/hospital-admin/appointments/online-request~${outcome.request_id}`);
  await hospital.page.getByRole('button',{name:'Propose schedule',exact:true}).click();
  await hospital.page.getByRole('button',{name:'OK',exact:true}).waitFor({timeout:15000});
  await hospital.page.getByRole('button',{name:'OK',exact:true}).click();
  await hospital.page.getByRole('button',{name:'OK',exact:true}).click();
  await hospital.page.getByText('Video',{exact:true}).click();
  await hospital.page.getByRole('button',{name:'Send proposal',exact:true}).click();
  await hospital.page.waitForTimeout(1200);
  const patient=await signIn(browser,'patient');
  await goto(patient.page,`/patient/appointments/online-request~${outcome.request_id}`);
  await writeFile(`${out}/proposal-patient.json`,JSON.stringify(await controls(patient.page),null,2));
  await patient.page.getByRole('button',{name:'Accept proposed schedule',exact:true}).click();
  await patient.page.waitForTimeout(1000);
  const rows=await api('patient',`rest/v1/online_consultation_requests?id=eq.${outcome.request_id}&select=id,request_status,official_consultation_id,confirmed_schedule,patient_response`,undefined,'GET');
  await writeFile(`${out}/proposal-outcome.json`,JSON.stringify(rows,null,2));
  if(rows[0].request_status!=='confirmed' || !rows[0].official_consultation_id)throw new Error('Proposal acceptance did not confirm');
  console.log('Hospital proposed through UI; patient accepted through UI; official consultation confirmed.');
}catch(error){
  for(const context of browser.contexts())for(const page of context.pages())await writeFile(`${out}/proposal-last-${browser.contexts().indexOf(context)}.json`,JSON.stringify(await controls(page),null,2));
  for(const context of browser.contexts())for(const page of context.pages())await page.screenshot({path:`${out}/proposal-failure.png`});
  throw error;
}finally{await browser.close();}
