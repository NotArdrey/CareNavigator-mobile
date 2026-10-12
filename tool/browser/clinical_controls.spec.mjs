import {test,expect} from '@playwright/test';
import {writeFile} from 'node:fs/promises';
import {accounts,fixture,api,rpc} from '../repair_fixture_api.mjs';
import {sql} from '../repair_backend.mjs';
import {launch,signIn,goto,fill} from '../repair_browser_helpers.mjs';
test('doctor issues an atomic order through preview and patient sees it',async()=>{
  const slots=await rpc('patient','list_available_consultation_slots',{target_doctor_id:fixture.id,target_type:'online',horizon_days:14});
  const care=await rpc('patient','book_consultation_v2',{booking_payload:{doctor_id:fixture.id,hospital_id:fixture.hospital_id,consultation_type:'online',appointment_date:slots[22].starts_at,chief_complaint:'SYNTHETIC UI order authorization fixture',symptom_duration:'One day'}});
  await rpc('hospital_admin','review_online_consultation_request',{target_request_id:care.request_id,decision:'confirmed',target_doctor_id:fixture.id,target_confirmed_schedule:slots[22].starts_at,target_channel:'call'});
  const browser=await launch();try{
    const {page}=await signIn(browser,'doctor');await goto(page,'/doctor/prescriptions');
    await page.getByRole('button',{name:'Issue prescription',exact:true}).click();
    await page.getByRole('button',{name:'Preview prescription',exact:true}).waitFor();
    const medication=`SYNTHETIC UI MEDICATION ${Date.now()}`;
    for(const [name,value]of [['Why it was prescribed','Synthetic browser verification only'],['Medication name',medication],['Medication form and strength','Test tablet 500 mg'],['Route','Oral'],['Exact dose per intake','1 tablet'],['Frequency','Once daily'],['Duration','3 days'],['Total quantity to dispense','3'],['Number of refills','0']]){
      await fill(page,page.getByRole('textbox',{name:new RegExp('^'+name.replace(/[.*+?^${}()|[\]\\]/g,'\\$&'))}),value);
    }
    await page.getByRole('button',{name:'Preview prescription',exact:true}).click();
    await page.getByRole('button',{name:'Confirm & issue',exact:true}).click();
    await expect.poll(async()=>{const r=await api('doctor',`rest/v1/prescriptions?medication_name=eq.${encodeURIComponent(medication)}&select=id,order_id,patient_id`,undefined,'GET');return r.length;}).toBe(1);
    const rows=await api('doctor',`rest/v1/prescriptions?medication_name=eq.${encodeURIComponent(medication)}&select=id,order_id,patient_id`,undefined,'GET');
    expect(rows[0].order_id).toBeTruthy();
    await writeFile('.codex-runtime/repair-browser/prescription-ui-outcome.json',JSON.stringify(rows,null,2));
    const patient=await signIn(browser,'patient');await goto(patient.page,'/patient/prescriptions');
    await expect(patient.page.getByRole('button',{name:new RegExp(medication)}).first()).toBeVisible();
  }finally{await browser.close();}
});
test('medication reminder preference persists through a browser reload',async()=>{
  const browser=await launch();try{
    const {page}=await signIn(browser,'patient');await goto(page,'/patient/profile');
    const toggle=page.getByRole('switch',{name:'Daily medication reminders',exact:true});
    const initial=await toggle.getAttribute('aria-checked');await toggle.click();
    await page.getByRole('button',{name:'Save changes',exact:true}).click();await page.waitForTimeout(700);
    await goto(page,'/patient/profile');
    await expect(page.getByRole('switch',{name:'Daily medication reminders',exact:true})).toHaveAttribute('aria-checked',initial==='true'?'false':'true');
    await page.getByRole('switch',{name:'Daily medication reminders',exact:true}).click();
    await page.getByRole('button',{name:'Save changes',exact:true}).click();
  }finally{await browser.close();}
});
test('patient sees relationship scope and revokes its complete sharing grant',async()=>{
  const browser=await launch();try{
    const {page}=await signIn(browser,'patient');await goto(page,'/patient/profile');
    const before=await rpc('patient','list_patient_sharing_relationships',{});
    expect(before.length).toBeGreaterThan(0);
    await page.getByRole('button',{name:'Manage record sharing',exact:true}).click();
    await page.getByRole('button',{name:'Revoke all sharing for this relationship',exact:true}).first().click();
    await fill(page,page.getByRole('textbox',{name:'Decision note',exact:true}),'Synthetic patient test revokes this complete relationship.');
    await page.getByRole('button',{name:'Revoke relationship sharing',exact:true}).click();
    await expect.poll(async()=> (await rpc('patient','list_patient_sharing_relationships',{})).filter(r=>(r.grants??[]).some(g=>g.status==='active'||g.grant_id)).length).toBeLessThan(before.length);
  }finally{await browser.close();}
});
