import {spawn} from 'node:child_process';
import {readFile,writeFile} from 'node:fs/promises';
import {env,sql} from '../../tool/repair_backend.mjs';
import {accounts,fixture,rpc} from '../../tool/repair_fixture_api.mjs';
const root='tmp/documentation_accuracy_20261016/';
const summary={startedAt:new Date().toISOString(),checks:[],limits:[
  'No real email delivery, OTP delivery, valid recovery email or provider media tested.',
  'Google Meet browser fixture tests omitted because their preparation temporarily disables live reservation triggers. Meet authorization is covered by rolled-back SQL acceptance.',
]};
let server;
async function run(name,command,args,options={}){
  console.log(`Checking ${name}`);
  const exitCode=await new Promise((resolve,reject)=>{
    const child=spawn(command,args,{stdio:'inherit',windowsHide:true,...options});
    child.on('error',reject);child.on('exit',code=>resolve(code??1));
  });
  summary.checks.push({name,exitCode});return exitCode;
}
try{
  if(!accounts.accounts.every(a=>a.email.startsWith('repair-')&&a.email.endsWith('@example.test')))throw new Error('Owned synthetic actors required');
  if(await run('owned synthetic fixture activation',process.execPath,['tool/reactivate_repair_fixtures.mjs']))throw new Error('Fixture activation failed');
  const slots=await rpc('patient','list_available_consultation_slots',{target_doctor_id:fixture.id,target_type:'online',horizon_days:14});
  if(!slots.length)throw new Error('No synthetic slots available');
  const booking=await rpc('patient','book_consultation_v2',{booking_payload:{doctor_id:fixture.id,hospital_id:fixture.hospital_id,
    consultation_type:'online',appointment_date:slots[0].starts_at,chief_complaint:'SYNTHETIC documentation accuracy verification',symptom_duration:'One day'}});
  if(booking.slot_reserved!==false)throw new Error('New online booking unexpectedly reserved a slot');
  const confirmed=await rpc('hospital_admin','review_online_consultation_request',{target_request_id:booking.request_id,
    decision:'confirmed',target_doctor_id:fixture.id,target_confirmed_schedule:slots[0].starts_at,target_channel:'call'});
  console.log('Verified review-before-reservation and confirmed a synthetic appointment.');
  const runtimeEnv={...process.env,CNPH_TEST_SUPABASE_URL:env.NEXT_PUBLIC_SUPABASE_URL,
    CNPH_TEST_SUPABASE_PUBLISHABLE_KEY:env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY,
    CNPH_TEST_PASSWORD:accounts.password,CNPH_TEST_ACCOUNTS:JSON.stringify(accounts.accounts),CNPH_TEST_CONSULTATION_ID:confirmed.consultation_id};
  const names={patient:'PATIENT',doctor:'DOCTOR',super_admin:'SUPERADMINISTRATOR',hospital_admin:'HOSPITALADMINISTRATOR',guest:'GUEST'};
  for(const a of accounts.accounts)runtimeEnv[`CNPH_TEST_${names[a.role]}_EMAIL`]=a.email;
  await run('11 live repository checks', 'C:/Users/Neila/devtools/flutter/bin/flutter.bat',
    ['test','test/repositories','--no-pub','--reporter','expanded'],{shell:true,env:runtimeEnv});
  if(await fetch('http://127.0.0.1:3000').then(()=>true).catch(()=>false))throw new Error('Port 3000 already occupied; refusing to test an unknown build');
  server=spawn('C:/Users/Neila/AppData/Local/Programs/Python/Python312/python.exe',['tool/serve_release.py'],{stdio:'ignore',windowsHide:true});
  for(let i=0;i<40;i++){
    if(await fetch('http://127.0.0.1:3000').then(r=>r.ok).catch(()=>false))break;
    await new Promise(resolve=>setTimeout(resolve,250));
  }
  await run('10 role, clinical, sharing and upload browser checks',process.execPath,
    ['tool/node_modules/@playwright/test/cli.js','test','--config=tool/playwright.config.mjs','--grep-invert','Google Meet']);
  await run('18 CRUD, staff and workspace-fetch browser checks',process.execPath,
    ['tool/node_modules/@playwright/test/cli.js','test','--config=tool/playwright.e2e.config.mjs']);
}catch(error){summary.error=error.message;console.error(error.message);}
finally{
  const state=await readFile('.codex-runtime/e2e/isolation.json','utf8').then(JSON.parse).catch(()=>null);
  if(state&&!state.restored){
    try{const {restoreHospital}=await import('../../tool/e2e_support.mjs');await restoreHospital({...state,originalHospitalId:fixture.hospital_id});}
    catch(error){summary.cleanupError=error.message;console.error(error.message);}
  }
  await run('owned temporary object cleanup',process.execPath,['tool/e2e_cleanup.mjs']);
  await run('synthetic fixture retirement',process.execPath,['tool/retire_repair_fixtures.mjs']);
  await run('cleanup verification',process.execPath,['tool/e2e_cleanup_verify.mjs']);
  server?.kill();summary.finishedAt=new Date().toISOString();
  await writeFile(root+'browser-run-summary.json',JSON.stringify(summary,null,2));
  process.exitCode=summary.error||summary.cleanupError||summary.checks.some(c=>c.exitCode)?1:0;
}
