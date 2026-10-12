import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {randomUUID} from 'node:crypto';
import {expect,test} from '@playwright/test';
import {sql} from './repair_backend.mjs';
import {accounts,fixture,publicKey,base,sessions,signIn as apiSignIn} from './repair_fixture_api.mjs';
import {launch,signIn,goto,fill,controls} from './repair_browser_helpers.mjs';

export {goto,fill,expect,test};
export const prefix=`SYNTHETIC E2E ${Date.now()} ${randomUUID().slice(0,8)}`;
export async function rest(role,table,query='',body,method='GET') {
  if(!sessions[role])await apiSignIn(role);
  const response=await fetch(`${base}/rest/v1/${table}${query?'?'+query:''}`,{
    method,signal:AbortSignal.timeout(20000),headers:{apikey:publicKey,Authorization:`Bearer ${sessions[role]}`,
      'Content-Type':'application/json',Prefer:'return=representation'},
    ...(body!==undefined?{body:JSON.stringify(body)}:{})});
  const value=await response.json().catch(()=>null);
  if(!response.ok)throw new Error(`${method} ${table}: HTTP ${response.status} (${value?.code??'unknown'}) ${value?.message??''}`);
  return value;
}
export async function isolateHospital() {
  const previous=await readFile('.codex-runtime/e2e/isolation.json','utf8').then(JSON.parse).catch(()=>null);
  if(previous&&!previous.restored)await restoreHospital({...previous,originalHospitalId:fixture.hospital_id});
  const actor=accounts.accounts.find(a=>a.role==='hospital_admin');
  if(!actor?.email.startsWith('repair-')||!actor.email.endsWith('@example.test'))throw new Error('Synthetic actor scope required');
  const [user]=await rest('super_admin','users',`auth_user_id=eq.${actor.id}&select=id,hospital_id,email`);
  if(user.email!==actor.email)throw new Error('Synthetic actor identity mismatch');
  const [hospital]=await rest('super_admin','hospitals','',{
    hospital_name:prefix+' isolated hospital',address:prefix+' test address',city:'Test City',
    province:'Test Province',operating_status:'closed',verification_status:'pending',
    created_by:accounts.accounts.find(a=>a.role==='super_admin').id},'POST');
  const state={hospitalId:hospital.id,actorId:actor.id,userId:user.id,originalHospitalId:fixture.hospital_id,prefix};
  await mkdir('.codex-runtime/e2e',{recursive:true});
  await writeFile('.codex-runtime/e2e/isolation.json',JSON.stringify(state,null,2));
  await sql(`update public.users set hospital_id='${hospital.id}' where id='${user.id}' and auth_user_id='${actor.id}';`);
  return state;
}
export async function restoreHospital(state) {
  await sql(`update public.users set hospital_id=${state.originalHospitalId?"'"+state.originalHospitalId+"'":'null'} where id='${state.userId}' and auth_user_id='${state.actorId}';`);
  // Exercise the deployed cascade; the audit entries retain source provenance.
  await rest('super_admin','hospitals',`id=eq.${state.hospitalId}`,undefined,'DELETE');
  await writeFile('.codex-runtime/e2e/isolation.json',JSON.stringify({...state,restored:true},null,2));
}
export async function withRole(role,callback) {
  const browser=await launch();let page;
  const evidence={role,requests:[],errors:[]};
  try {
    const signed=await signIn(browser,role);page=signed.page;
    page.on('response',r=>{if(r.url().startsWith(base))evidence.requests.push({resource:new URL(r.url()).pathname,method:r.request().method(),status:r.status()});});
    page.on('pageerror',e=>evidence.errors.push(e.message));
    page.on('requestfailed',r=>{if(r.url().startsWith(base)&&r.failure()?.errorText!=='net::ERR_ABORTED')
      evidence.errors.push(`${new URL(r.url()).pathname}: ${r.failure()?.errorText}`);});
    await callback(page,signed.context,evidence);
    expect(evidence.errors,'uncaught browser errors').toEqual([]);
    expect(evidence.requests.filter(r=>r.status>=400),'unexpected Supabase failures').toEqual([]);
  }catch(error) {
    if(page&&!page.isClosed()){
      await test.info().attach('failure',{body:await page.screenshot(),contentType:'image/png'});
      evidence.controls=await controls(page);
    }
    throw error;
  }finally{
    await test.info().attach('supabase-evidence',{body:JSON.stringify(evidence,null,2),contentType:'application/json'});
    await browser.close();
  }
}
export async function openSection(page,path,tab) {
  await goto(page,path);
  if(tab){
    await page.getByRole('tab',{name:tab,exact:true}).click();
    // Flutter animates the tab's semantic tree; let the input overlay settle.
    await page.waitForTimeout(400);
  }
}
export async function search(page,value) {
  const field=page.getByRole('textbox',{name:'Search visible records',exact:true});
  await expect.poll(async()=>await field.count()+await page.getByRole('button',{name:'Edit',exact:true}).count()).toBeGreaterThan(0);
  if(await field.count())await fill(page,field,value);
  else await expect(page.getByRole('button',{name:'Edit',exact:true})).toHaveCount(1);
}
export async function submit(page,label,resource) {
  console.log(`Submitting ${label} (${resource})`);
  const [response]=await Promise.all([
    page.waitForResponse(r=>r.url().includes('/'+resource)&&['POST','PATCH','DELETE'].includes(r.request().method()),{timeout:15000}),
    page.locator('[role="dialog"], [role="alertdialog"]').getByRole('button',{name:label,exact:true}).click()
  ]);
  expect(response.status(),`${label} ${resource}`).toBeLessThan(300);
  console.log(`Persisted ${resource}: HTTP ${response.status()}`);
}
export async function deleteVisible(page,table) {
  await page.getByRole('button',{name:'Delete',exact:true}).click();
  await submit(page,'Delete record',table);
  await expect(page.getByRole('button',{name:'Delete',exact:true})).toHaveCount(0);
}
export async function choose(page,label,value) {
  await page.locator('[role="dialog"], [role="alertdialog"]').getByRole('button',{name:new RegExp('^'+label+'(?: |$)')}).click();
  await page.getByRole('menuitem',{name:value,exact:true}).click();
}
