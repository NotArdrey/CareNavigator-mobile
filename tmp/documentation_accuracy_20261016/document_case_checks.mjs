import {writeFile} from 'node:fs/promises';
import {expect} from '../../tool/node_modules/@playwright/test/index.mjs';
import {launch,goto,fill,signIn,controls} from '../../tool/repair_browser_helpers.mjs';
import {accounts} from '../../tool/repair_fixture_api.mjs';
const report={checkedAt:new Date().toISOString(),cases:[]};
const browser=await launch();
let currentPage;
try{
  const context=await browser.newContext({viewport:{width:1440,height:1100},timezoneId:'Asia/Manila'});
  const page=await context.newPage();
  currentPage=page;
  await goto(page,'/sign-in');
  await fill(page,page.getByRole('textbox',{name:'Email address',exact:true}),accounts.accounts.find(a=>a.role==='patient').email);
  // Flutter does not expose its masked password input as an AX textbox.
  // The email helper tabs into that input, matching the repository harness.
  await page.keyboard.type('IncorrectSyntheticPassword2026!',{delay:5});
  await page.keyboard.press('Tab');
  const denied=page.waitForResponse(r=>r.url().includes('/auth/v1/token')&&r.request().method()==='POST');
  await page.getByRole('button',{name:'Sign in',exact:true}).click();
  expect((await denied).status()).toBe(400);
  await expect(page).toHaveURL(/\/sign-in/);
  await goto(page,'/patient/appointments');
  await expect(page).toHaveURL(/\/sign-in\?from=/);
  await expect(page.getByRole('button',{name:'Sign out',exact:true})).toHaveCount(0);
  report.cases.push({id:'TC_AUTH_002',result:'PASS',fixture:'Existing owned synthetic patient; incorrect password',scope:'Real Auth rejection and browser route guard'});
  await context.close();
  const patient=await signIn(browser,'patient');
  currentPage=patient.page;
  await goto(patient.page,'/patient/appointments');
  await expect(patient.page.getByRole('button',{name:'Sign out',exact:true})).toBeVisible();
  report.cases.push({id:'TC_AUTH_001',result:'PASS',fixture:'Existing owned synthetic patient',scope:'Real sign-in and protected patient appointment page'});
  let bookingRequests=0;
  patient.page.on('request',r=>{if(r.url().includes('/rpc/book_consultation')&&r.method()==='POST')bookingRequests++;});
  await patient.page.route('**/rest/v1/rpc/list_available_consultation_slots',route=>route.fulfill({status:200,contentType:'application/json',body:'[]'}));
  await patient.page.getByRole('button',{name:'Reserve consultation',exact:true}).click();
  const dialog=patient.page.locator('[role="dialog"], [role="alertdialog"]');
  await expect(dialog).toBeVisible({timeout:15000});
  // The current default clinician must offer the mode in this documented case.
  await dialog.getByRole('button',{name:/^Care mode(?: |$)/}).click();
  const mode=patient.page.getByRole('menuitem',{name:'In person',exact:true});
  if(await mode.count()===0){
    await patient.page.keyboard.press('Escape');
    report.cases.push({id:'TC_BOOKING_002',result:'NOT EXECUTED',reason:'Default clinician does not publish in-person care; no fixture schedule was modified'});
  }else{
    await mode.click();
    await expect(dialog.getByText('No reservable appointment times are published for this clinician and care mode in the next 30 days. Reservations require at least 24 hours of notice.',{exact:true})).toBeVisible();
    await expect(dialog.getByRole('button',{name:'Reserve consultation',exact:true})).toBeDisabled();
    expect(bookingRequests).toBe(0);
    report.cases.push({id:'TC_BOOKING_002',result:'PASS WITH CONTROLLED RESPONSE',scope:'Browser received an empty availability response; 24-hour notice shown, submit disabled, zero booking requests. No real no-slot backend fixture claimed.'});
  }
}catch(error){
  report.error=error.message;process.exitCode=1;
  if(currentPage&&!currentPage.isClosed()){
    report.controls=await controls(currentPage);
    await currentPage.screenshot({path:'tmp/documentation_accuracy_20261016/document-case-failure.png'});
  }
}
finally{
  await browser.close();
  await writeFile('tmp/documentation_accuracy_20261016/document-case-results.json',JSON.stringify(report,null,2));
  console.log(JSON.stringify(report,null,2));
}
