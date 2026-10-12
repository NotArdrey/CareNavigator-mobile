import {readFile,writeFile,readdir} from 'node:fs/promises';
import {sql} from './repair_backend.mjs';
const acceptance=await readFile('supabase/tests/hospital_cascade_audit_acceptance.sql','utf8');
const migration=await readFile('supabase/migrations/20261012005203_preserve_audit_during_hospital_delete.sql','utf8');
const applied=await sql("select version,name from supabase_migrations.schema_migrations where name='preserve_audit_during_hospital_delete'");
const report={deployed:applied.length===1,migration:applied[0]??null,checkedAt:new Date().toISOString()};
try{await sql(acceptance);report.current='PASS';}
catch(error){report.current='FAIL';report.error=error.message;}
await sql('BEGIN;\n'+migration+'\n'+acceptance.replace(/^BEGIN;$/m,'').replace(/^ROLLBACK;$/m,'')+'\nROLLBACK;');
report.proposed='PASS (DDL and fixtures rolled back)';
if(process.argv.includes('--all')){
  report.regressions=[];
  for(const name of (await readdir('supabase/tests')).filter(n=>n.endsWith('_acceptance.sql')).sort()){
    const source=(await readFile(`supabase/tests/${name}`,'utf8')).replace(/^\s*begin;\s*$/im,'').replace(/\brollback;\s*$/i,'');
    await sql('BEGIN;\n'+migration+'\n'+source+'\nROLLBACK;');
    report.regressions.push({name,status:'PASS (rolled back)'});
    console.log(`${name}: PASS with proposed audit correction (rolled back)`);
  }
}
await writeFile('.codex-runtime/e2e/audit-fix.json',JSON.stringify(report,null,2));
console.log(JSON.stringify(report,null,2));
if(report.current!=='PASS'&&report.deployed)process.exitCode=1;
