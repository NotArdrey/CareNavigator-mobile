import {writeFile} from 'node:fs/promises';
import {launch,signIn,goto,controls} from './repair_browser_helpers.mjs';
const out='.codex-runtime/repair-browser';
const browser=await launch();
try{
  const doctor=await signIn(browser,'doctor');
  await goto(doctor.page,'/doctor/prescriptions');
  await doctor.page.getByRole('button',{name:'Issue prescription',exact:true}).click();
  await doctor.page.waitForTimeout(1200);
  await writeFile(`${out}/prescription-dialog.json`,JSON.stringify(await controls(doctor.page),null,2));
  const patient=await signIn(browser,'patient');
  await goto(patient.page,'/patient/profile');
  await writeFile(`${out}/patient-profile.json`,JSON.stringify(await controls(patient.page),null,2));
  await patient.page.getByRole('button',{name:'Manage record sharing',exact:true}).click();
  await patient.page.waitForTimeout(800);
  await writeFile(`${out}/sharing-dialog.json`,JSON.stringify(await controls(patient.page),null,2));
  console.log('Prescription, preference and sharing controls saved.');
}finally{await browser.close();}
