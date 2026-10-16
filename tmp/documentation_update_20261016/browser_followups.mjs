import {spawn} from 'node:child_process';
import {writeFile} from 'node:fs/promises';
import {writeFileSync} from 'node:fs';
import {randomUUID} from 'node:crypto';
import {expect} from '../../tool/node_modules/@playwright/test/index.mjs';
import {env,management,sql} from '../../tool/repair_backend.mjs';
import {accounts,fixture,base,publicKey,rpc,api} from '../../tool/repair_fixture_api.mjs';
import {launch,signIn,goto,fill,enable} from '../../tool/repair_browser_helpers.mjs';
const root='tmp/documentation_update_20261016/';
const cases=[];let server,browser,service;
const patient=accounts.accounts.find(a=>a.role==='patient');
const secretValues=[accounts.password];
function safeError(error){let text=String(error?.message??error);for(const secret of secretValues)if(secret)text=text.replaceAll(secret,'[REDACTED]');return text.replace(/Bearer\s+[^\s]+/gi,'Bearer [REDACTED]').replace(/https?:\/\/[^\s"']+/g,'[URL REDACTED]').slice(0,1800);}
async function runScript(file){
  const code=await new Promise((resolve,reject)=>{const child=spawn(process.execPath,[file],{stdio:'inherit',windowsHide:true});child.on('error',reject);child.on('exit',resolve);});
  if(code)throw new Error(`${file} failed`);
}
async function adminUser(method,body){
  const response=await fetch(`${base}/auth/v1/admin/users/${patient.id}`,{method,headers:{apikey:service,Authorization:`Bearer ${service}`,'content-type':'application/json'},...(body?{body:JSON.stringify(body)}:{})});
  if(!response.ok)throw new Error(`Synthetic Auth admin HTTP ${response.status}`);return response.json();
}
async function login(password){return fetch(`${base}/auth/v1/token?grant_type=password`,{method:'POST',headers:{apikey:publicKey,'content-type':'application/json'},body:JSON.stringify({email:patient.email,password})});}
async function check(name,body){try{const details=await body();cases.push({name,result:'PASS',...details});}catch(error){cases.push({name,result:'FAIL',error:safeError(error)});process.exitCode=1;}
  writeFileSync(root+'browser-followup-results.json',JSON.stringify({checkedAt:new Date().toISOString(),cases},null,2));
  console.log(`${name}: ${cases.at(-1).result}`);
}
const meeting='https://meet.google.com/xyz-abcd-efg';
async function controlledHandoff(page,context,button,consultationId){
  // Only the successful time-window response is controlled; real time denial
  // and authorization are verified separately, without changing live timestamps.
  await context.route('**/functions/v1/care-workflows',async route=>{
    try{
    const body=route.request().postDataJSON();
    if(body?.action==='get_video_join_url'&&body.consultation_id===consultationId)
      await route.fulfill({status:200,contentType:'application/json',headers:{'access-control-allow-origin':'*'},body:JSON.stringify({join_url:meeting,provider_origin:'https://meet.google.com'})});
    else await route.continue();
    }catch{await route.abort().catch(()=>{});}
  });
  await context.route('https://meet.google.com/**',route=>route.fulfill({status:200,contentType:'text/html',body:'<title>Synthetic Google Meet destination</title>'}));
  // The real UI also disables early joining. Supply an in-window display time
  // only in this browser's scoped read response; do not edit the live record.
  await context.route('**/rest/v1/online_consultation_requests*',async route=>{
    try{
    const response=await route.fetch();const value=await response.json();
    if(Array.isArray(value))for(const row of value)if(row.official_consultation_id===consultationId)row.confirmed_schedule=new Date().toISOString();
    await route.fulfill({response,json:value});
    }catch{await route.abort().catch(()=>{});}
  });
  await goto(page,new URL(page.url()).pathname);
  await expect(button).toBeEnabled({timeout:10000});
  const [external]=await Promise.all([context.waitForEvent('page'),button.click()]);
  await external.waitForURL(meeting);assertNoUnsafeOrigin(external.url());await external.close();
}
function assertNoUnsafeOrigin(url){expect(new URL(url).origin).toBe('https://meet.google.com');}
try{
  if(!accounts.accounts.every(a=>a.email.startsWith('repair-')&&a.email.endsWith('@example.test')))throw new Error('Owned synthetic fixtures required');
  await runScript('tool/reactivate_repair_fixtures.mjs');
  service=(await management('api-keys')).find(k=>k.name==='service_role')?.api_key;if(!service)throw new Error('Synthetic admin access unavailable');secretValues.push(service);
  const actual=await adminUser('GET');expect(actual.email).toBe(patient.email);
  if(await fetch('http://127.0.0.1:3000').then(()=>true).catch(()=>false))throw new Error('Port 3000 already occupied');
  server=spawn('C:/Users/Neila/AppData/Local/Programs/Python/Python312/python.exe',['tool/serve_release.py'],{stdio:'ignore',windowsHide:true});
  for(let i=0;i<40;i++){if(await fetch('http://127.0.0.1:3000').then(r=>r.ok).catch(()=>false))break;await new Promise(resolve=>setTimeout(resolve,250));}
  browser=await launch();
  await check('Valid recovery link changes password through the real app and real Auth',async()=>{
    const temporary=`SyntheticReset1!${randomUUID()}`;secretValues.push(temporary);
    const context=await browser.newContext({viewport:{width:1440,height:1100},timezoneId:'Asia/Manila'});
    let page;const network=[];
    try{
      const response=await fetch(`${base}/auth/v1/admin/generate_link`,{method:'POST',headers:{apikey:service,Authorization:`Bearer ${service}`,'content-type':'application/json'},
        body:JSON.stringify({type:'recovery',email:patient.email,redirect_to:'http://127.0.0.1:3000/reset-password'})});
      expect(response.status).toBe(200);const generated=await response.json();const link=generated.action_link??generated.properties?.action_link;
      if(!link)throw new Error('Auth did not return a recovery link');secretValues.push(link);
      expect(new URL(link).origin).toBe(base);
      page=await context.newPage();
      page.on('response',response=>{const url=new URL(response.url());if(url.pathname.startsWith('/auth/'))network.push({path:url.pathname,method:response.request().method(),status:response.status()});});
      await page.goto(link);await page.waitForURL(/\/reset-password/,{timeout:30000});await enable(page);
      // Use native tab navigation for Flutter's password editing overlays.
      // Clicking the semantic textbox can leave the real editing input empty.
      await page.getByRole('button',{name:'Show password',exact:true}).click();
      await page.keyboard.press('Shift+Tab');
      await page.keyboard.press('Control+A');await page.keyboard.type(temporary,{delay:5});
      await page.keyboard.press('Tab');await page.keyboard.press('Tab');
      await page.keyboard.press('Control+A');await page.keyboard.type(temporary,{delay:5});
      await page.keyboard.press('Tab');
      const changed=page.waitForResponse(r=>new URL(r.url()).pathname==='/auth/v1/user'&&r.request().method()==='PUT',{timeout:8000});
      await page.getByRole('button',{name:'Update password',exact:true}).click();expect((await changed).status()).toBe(200);
      await expect(page.getByText('Password updated successfully.',{exact:true}).last()).toBeVisible();
      expect((await login(temporary)).status).toBe(200);expect((await login(accounts.password)).status).toBe(400);
      return {scope:'Real generated recovery token, redirect/event handling, password form, Auth update and new/old password checks. Link retrieved through admin API; email delivery not tested.'};
    }catch(error){
      const diagnostics={network,error:safeError(error)};
      if(page&&!page.isClosed()){
        diagnostics.storage=await page.evaluate(()=>Object.entries(localStorage).map(([key,value])=>({key,hasAccessToken:value.includes('access_token')})));
        diagnostics.ui=(await page.locator('flt-semantics').allTextContents()).map(value=>value.replaceAll(temporary,'[SYNTHETIC PASSWORD]')).filter(value=>/expired|match|success|valid|characters|recovery|password/i.test(value)).slice(-25);
      }
      writeFileSync(root+'recovery-diagnostics.json',JSON.stringify(diagnostics,null,2));throw error;
    }finally{await context.close();await adminUser('PUT',{password:accounts.password});expect((await login(accounts.password)).status).toBe(200);}
  });
  if(!process.argv.includes('--recovery-only')){
  const slots=await rpc('patient','list_available_consultation_slots',{target_doctor_id:fixture.id,target_type:'online',horizon_days:14});expect(slots.length).toBeGreaterThan(1);
  const booking=await rpc('patient','book_consultation_v2',{booking_payload:{doctor_id:fixture.id,hospital_id:fixture.hospital_id,consultation_type:'online',appointment_date:slots[0].starts_at,chief_complaint:'SYNTHETIC safe Meet future booking',symptom_duration:'One day'}});
  const care=await rpc('hospital_admin','review_online_consultation_request',{target_request_id:booking.request_id,decision:'confirmed',target_doctor_id:fixture.id,target_confirmed_schedule:slots[0].starts_at,target_channel:'video'});
  const doctor=await signIn(browser,'doctor');await goto(doctor.page,`/doctor/appointments/online-request~${booking.request_id}`);
  await check('Assigned doctor saves canonical Google Meet link and early real access is denied',async()=>{
    await doctor.page.getByRole('button',{name:'Set Google Meet link',exact:true}).click();
    await fill(doctor.page,doctor.page.getByRole('textbox',{name:/^Google Meet link/}),meeting+'?authuser=1');
    const saved=doctor.page.waitForResponse(r=>r.url().includes('/rpc/set_consultation_meet_link')&&r.request().method()==='POST');
    await doctor.page.getByRole('button',{name:'Save meeting link',exact:true}).click();expect((await saved).ok()).toBe(true);
    const rows=await sql(`select provider,join_url from public.video_sessions where consultation_id='${care.consultation_id}'`);expect(rows[0].provider).toBe('google_meet');expect(rows[0].join_url).toBe(meeting);
    for(const role of ['patient','guest','hospital_admin'])await expect(rpc(role,'set_consultation_meet_link',{target_consultation_id:care.consultation_id,meeting_url:meeting})).rejects.toThrow();
    for(const role of ['patient','doctor'])await expect(api(role,'functions/v1/care-workflows',{action:'get_video_join_url',consultation_id:care.consultation_id})).rejects.toThrow(/HTTP 403/);
    return {scope:'Live future appointment and canonical persisted link; patient/guest/admin cannot set it; real early joins rejected. Live timestamps and triggers unchanged.'};
  });
  await check('Doctor and patient open the canonical external Meet destination with a controlled in-window response',async()=>{
    await controlledHandoff(doctor.page,doctor.context,doctor.page.getByRole('button',{name:'Join Google Meet',exact:true}),care.consultation_id);
    const signed=await signIn(browser,'patient');await goto(signed.page,`/patient/appointments/online-request~${booking.request_id}`);
    await expect(signed.page.getByRole('button',{name:'Set Google Meet link',exact:true})).toHaveCount(0);
    await controlledHandoff(signed.page,signed.context,signed.page.getByRole('button',{name:'Join Google Meet',exact:true}),care.consultation_id);
    await signed.context.close();return {scope:'Real UI external popup; displayed in-window schedule, successful authorization response and provider page controlled. No real provider admission or media claimed.'};
  });
  await check('Approved guest opens Meet without activating another patient account using a controlled in-window response',async()=>{
    const account=accounts.accounts.find(a=>a.role==='guest');
    const guestSlots=await rpc('guest','list_available_consultation_slots',{target_doctor_id:fixture.id,target_type:'guest_online',horizon_days:14});
    const requestId=await rpc('guest','submit_guest_consultation_request',{request_payload:{first_name:'Repair',last_name:'Safe Meet guest',birth_date:'1990-01-01',sex:'male',mobile_number:'+639171234567',email:account.email,address:'Synthetic address',symptoms:'SYNTHETIC safe Meet guest concern',symptom_duration:'One day',preferred_hospital_id:fixture.hospital_id,preferred_department_id:fixture.department_id,preferred_consultation_type:'guest_online',preferred_schedule:guestSlots[1].starts_at},idempotency_key:randomUUID()});
    const outcome=await rpc('hospital_admin','review_guest_consultation',{target_request_id:requestId,decision:'approved',target_doctor_id:fixture.id,target_appointment_date:guestSlots[1].starts_at,review_notes:'Synthetic future appointment; no clock or trigger changes'});
    await rpc('doctor','set_consultation_meet_link',{target_consultation_id:outcome.consultation_id,meeting_url:meeting});
    const guest=await signIn(browser,'guest');await goto(guest.page,`/consultation/confirmation/${requestId}`);
    await controlledHandoff(guest.page,guest.context,guest.page.getByRole('button',{name:'Join Google Meet / retry',exact:true}),outcome.consultation_id);
    await guest.context.close();return {scope:'Actual approved future guest request and real tracking UI; controlled join response and destination; activation was not invoked.'};
  });
  }
}catch(error){cases.push({name:'Follow-up orchestration',result:'FAIL',error:safeError(error)});process.exitCode=1;}
finally{
  await browser?.close();server?.kill();
  for(const file of ['tool/retire_repair_fixtures.mjs','tool/e2e_cleanup_verify.mjs'])try{await runScript(file);}catch(error){cases.push({name:'Cleanup',result:'FAIL',error:safeError(error)});process.exitCode=1;}
  const report={checkedAt:new Date().toISOString(),cases};await writeFile(root+'browser-followup-results.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
}
