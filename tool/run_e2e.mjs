// Run from the repository root: node tool/run_e2e.mjs
// Requires ignored env and owned repair-test-accounts.json; never prints keys.
import {spawn} from 'node:child_process';
import {mkdir,readFile,writeFile} from 'node:fs/promises';
import {env} from './repair_backend.mjs';
const summary={startedAt:new Date().toISOString(),checks:[]};let server;
await mkdir('.codex-runtime/e2e',{recursive:true});
async function run(name,command,args,options={}){
  console.log(`Checking ${name}`);
  const code=await new Promise((resolve,reject)=>{
    const child=spawn(command,args,{stdio:'inherit',...options});
    child.on('error',reject);child.on('exit',code=>resolve(code??1));
  });
  summary.checks.push({name,exitCode:code});
  return code;
}
try {
  if(await run('synthetic fixture activation',process.execPath,['tool/reactivate_repair_fixtures.mjs']))throw new Error('Fixture activation failed');
  await run('Flutter analysis','flutter',['analyze'],{shell:process.platform==='win32'});
  await run('Flutter full suite with a fresh live relationship',process.execPath,['tool/repair_live_tests.mjs']);
  // Preserve all failures and continue independent suites.
  await run('live database acceptance (all suites roll back)',process.execPath,['tool/database_live_acceptance.mjs']);
  await run('hospital cascade: deployed defect and proposed transactional fix',process.execPath,['tool/e2e_verify_audit_fix.mjs','--all']);
  const url=env.NEXT_PUBLIC_SUPABASE_URL,key=env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
  if(!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(url)||!/^[A-Za-z0-9_.-]+$/.test(key))throw new Error('Invalid public build configuration');
  if(await run('fresh release web build','flutter',['build','web','--release',`--dart-define=NEXT_PUBLIC_SUPABASE_URL=${url}`,`--dart-define=NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=${key}`],{shell:process.platform==='win32'}))throw new Error('Web build failed');
  const serving=await fetch('http://127.0.0.1:3000').then(r=>r.ok).catch(()=>false);
  if(!serving){
    server=spawn('python',['tool/serve_release.py'],{stdio:'ignore'});
    for(let i=0;i<20;i++){
      if(await fetch('http://127.0.0.1:3000').then(r=>r.ok).catch(()=>false))break;
      await new Promise(resolve=>setTimeout(resolve,500));
    }
  }
  await run('existing clinical/auth/Meet browser journeys',process.execPath,['tool/node_modules/@playwright/test/cli.js','test','--config=tool/playwright.config.mjs']);
  await run('expanded CRUD, staff and every-screen fetching',process.execPath,['tool/node_modules/@playwright/test/cli.js','test','--config=tool/playwright.e2e.config.mjs']);
  await run('assistant history CRUD and account isolation',process.execPath,['tool/repair_history_check.mjs']);
  await run('server-secret exposure check',process.execPath,['tool/check_secret_exposure.mjs']);
}catch(error){summary.error=error.message;console.error(error.message);}
finally{
  // Also recover the hospital assignment if the browser process was interrupted.
  const state=await readFile('.codex-runtime/e2e/isolation.json','utf8').then(JSON.parse).catch(()=>null);
  if(state&&!state.restored){
    const {restoreHospital}=await import('./e2e_support.mjs');
    const {fixture}=await import('./repair_fixture_api.mjs');
    await restoreHospital({...state,originalHospitalId:fixture.hospital_id}).catch(e=>{summary.cleanupError=e.message;});
  }
  await run('owned E2E fixture cleanup',process.execPath,['tool/e2e_cleanup.mjs']);
  await run('synthetic identity retirement',process.execPath,['tool/retire_repair_fixtures.mjs']);
  await run('post-retirement fixture verification',process.execPath,['tool/e2e_cleanup_verify.mjs']);
  server?.kill();summary.finishedAt=new Date().toISOString();
  await writeFile('.codex-runtime/e2e/run-summary.json',JSON.stringify(summary,null,2));
  process.exitCode=summary.error||summary.cleanupError||summary.checks.some(c=>c.exitCode)?1:0;
}
