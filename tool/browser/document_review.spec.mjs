import {test,expect} from '@playwright/test';
import {readFile} from 'node:fs/promises';
import {launch,signIn,goto,fill,controls} from '../repair_browser_helpers.mjs';
import {writeFile} from 'node:fs/promises';
import {api,rpc,fixture} from '../repair_fixture_api.mjs';
test('patient shares supporting upload and scoped doctor reviews original provenance',async()=>{
  // Other tests revoke complete relationships. Obtain new patient consent for
  // this case through booking and hospital confirmation before sharing a file.
  const slots=await rpc('patient','list_available_consultation_slots',{target_doctor_id:fixture.id,target_type:'online',horizon_days:14});
  const startsAt=slots[20].starts_at;
  const care=await rpc('patient','book_consultation_v2',{booking_payload:{doctor_id:fixture.id,hospital_id:fixture.hospital_id,consultation_type:'online',appointment_date:startsAt,chief_complaint:'SYNTHETIC document review consent fixture',symptom_duration:'One day',shared_categories:['consultations','medical_records','medical_documents']}});
  expect(care.slot_reserved).toBe(false);
  await rpc('hospital_admin','review_online_consultation_request',{target_request_id:care.request_id,decision:'confirmed',target_doctor_id:fixture.id,target_confirmed_schedule:startsAt,target_channel:'call'});
  await import(`../prepare_review_upload.mjs?fixture=${Date.now()}`);
  const review=JSON.parse(await readFile('.codex-runtime/repair-review-upload-fixture.json','utf8'));
  expect((await rpc('patient','list_patient_sharing_relationships',{})).some(r=>(r.grants??[]).some(g=>g.categories?.includes('medical_documents')))).toBe(true);
  const browser=await launch();let currentPage;try{
    const patient=await signIn(browser,'patient');currentPage=patient.page;await goto(patient.page,'/patient/prescriptions');
    await patient.page.getByRole('button',{name:new RegExp(review.title)}).first().waitFor();
    const patientSearch=patient.page.getByRole('textbox',{name:'Search visible records',exact:true});
    if(await patientSearch.count())await fill(patient.page,patientSearch,review.title);
    await patient.page.waitForTimeout(500);
    await patient.page.getByRole('button',{name:'Share for doctor review',exact:true}).first().click();
    await expect(patient.page.getByRole('dialog')).toBeVisible({timeout:10000});
    await patient.page.getByRole('dialog').getByRole('button',{name:/Dr Repair Fixture/}).click();
    await patient.page.getByRole('button',{name:'Share for review',exact:true}).click();
    const doctor=await signIn(browser,'doctor');currentPage=doctor.page;await goto(doctor.page,'/doctor/prescriptions');
    await doctor.page.getByRole('button',{name:new RegExp(review.title)}).first().waitFor();
    const doctorSearch=doctor.page.getByRole('textbox',{name:'Search visible records',exact:true});
    if(await doctorSearch.count())await fill(doctor.page,doctorSearch,review.title);
    await doctor.page.getByRole('button',{name:'Approve supporting document',exact:true}).first().click();
    await fill(doctor.page,doctor.page.getByRole('textbox',{name:'Decision note',exact:true}),'SYNTHETIC original document reviewed for the browser acceptance test.');
    await doctor.page.getByRole('button',{name:'Approve',exact:true}).click();
    await expect.poll(async()=>{
      const rows=await api('patient',`rest/v1/medical_documents?id=eq.${review.document_id}&select=origin_type,review_state,reviewed_by,reviewed_at`,undefined,'GET');
      expect(rows[0].origin_type).toBe('patient_supplied');return rows[0].review_state;
    }).toBe('approved');
  }catch(error){
    if(currentPage&&!currentPage.isClosed())await writeFile('.codex-runtime/repair-browser/review-controls.json',JSON.stringify(await controls(currentPage),null,2));
    if(currentPage&&!currentPage.isClosed())await currentPage.screenshot({path:'.codex-runtime/repair-browser/review-failure.png'});
    throw error;
  }finally{await browser.close();}
});
