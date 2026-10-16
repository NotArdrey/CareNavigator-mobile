import {writeFile} from 'node:fs/promises';
import {expect} from '../../tool/node_modules/@playwright/test/index.mjs';
import {launch,signIn,goto,fill,controls} from '../../tool/repair_browser_helpers.mjs';
import {fixture,rpc,api} from '../../tool/repair_fixture_api.mjs';
const report={id:'TC_BOOKING_001',checkedAt:new Date().toISOString()};
const complaint=`SYNTHETIC documentation booking ${Date.now()}`;
let browser,page,created;
try{
  const available=await rpc('patient','list_available_consultation_slots',{target_doctor_id:fixture.id,target_type:'face_to_face',horizon_days:30});
  if(!available.length){report.result='NOT EXECUTED';report.reason='Owned synthetic doctor has no published in-person slot';}
  else{
    browser=await launch();
    const patient=await signIn(browser,'patient');page=patient.page;
    await goto(page,`/patient/appointments?reserve=true&hospitalId=${fixture.hospital_id}&doctorId=${fixture.id}`);
    const dialog=page.locator('[role="dialog"], [role="alertdialog"]');
    await expect(dialog).toBeVisible({timeout:15000});
    await dialog.getByRole('button',{name:/^Care mode(?: |$)/}).click();
    await page.getByRole('menuitem',{name:'In person',exact:true}).click();
    await fill(page,dialog.getByRole('textbox',{name:/^Primary care concern/}),complaint);
    const reserve=dialog.getByRole('button',{name:'Reserve consultation',exact:true});
    await expect(reserve).toBeEnabled({timeout:15000});
    const saved=page.waitForResponse(r=>r.url().includes('/rpc/book_consultation_v2')&&r.request().method()==='POST');
    await reserve.click();const response=await saved;
    expect(response.ok()).toBe(true);const result=await response.json();created=result.consultation_id;
    expect(result.slot_reserved).toBe(true);expect(created).toBeTruthy();
    const rows=await api('patient',`rest/v1/consultations?id=eq.${created}&select=id,patient_id,doctor_id,hospital_id,consultation_type,status,appointment_date,chief_complaint`,undefined,'GET');
    expect(rows).toHaveLength(1);const row=rows[0];
    expect(row.doctor_id).toBe(fixture.id);expect(row.hospital_id).toBe(fixture.hospital_id);
    expect(row.consultation_type).toBe('face_to_face');expect(row.status).toBe(result.status);expect(row.chief_complaint).toBe(complaint);
    expect(Date.parse(row.appointment_date)-Date.now()).toBeGreaterThan(24*60*60*1000);
    const after=await rpc('patient','list_available_consultation_slots',{target_doctor_id:fixture.id,target_type:'face_to_face',horizon_days:30});
    expect(after.some(s=>Date.parse(s.starts_at)===Date.parse(row.appointment_date))).toBe(false);
    await goto(page,'/patient/appointments');
    await expect(page.getByRole('button',{name:new RegExp(complaint,'i')}).first()).toBeVisible({timeout:15000});
    report.result='PASS';report.scope='Actual browser in-person booking, persisted values, visible appointment, occupied slot removed';
    report.fixture='Owned synthetic doctor/patient, next published slot at least 24 hours away; not fixed exactly 48 hours';
  }
}catch(error){
  report.result='FAIL';report.error=error.message;process.exitCode=1;
  if(page&&!page.isClosed()){
    report.controls=await controls(page);
    await page.screenshot({path:'tmp/documentation_accuracy_20261016/booking-positive-failure.png'});
  }
}finally{
  // Cancel only this uniquely labelled synthetic appointment through the app RPC.
  if(created){
    try{await rpc('patient','cancel_consultation',{target_consultation_id:created});report.cleanup='Synthetic reservation cancelled';}
    catch(error){report.cleanupError=error.message;process.exitCode=1;}
  }
  await browser?.close();
  await writeFile('tmp/documentation_accuracy_20261016/document-booking-positive-result.json',JSON.stringify(report,null,2));
  console.log(JSON.stringify(report,null,2));
}
