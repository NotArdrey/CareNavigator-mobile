// Advance only the expected function definitions; keep applied baseline DDL immutable.
import {readFile,writeFile} from 'node:fs/promises';
import {spawn} from 'node:child_process';
const path='supabase/baseline/catalog.json';
const original=await readFile(path,'utf8');const before=JSON.parse(original);
await writeFile('.codex-runtime/e2e/audit-catalog-before.json',original);
const code=await new Promise((resolve,reject)=>{
  const child=spawn(process.execPath,['tool/export_schema_baseline.mjs','--catalog-only'],{stdio:'inherit'});
  child.on('error',reject);child.on('exit',code=>resolve(code??1));
});
if(code)throw new Error('Catalog export failed.');
const after=JSON.parse(await readFile(path,'utf8'));
const changed=[];
try {
  for(const key of new Set([...Object.keys(before),...Object.keys(after)])){
    if(key==='functions')continue;
    const normalize=items=>[...(items??[])].sort((a,b)=>JSON.stringify(a).localeCompare(JSON.stringify(b)));
    if(JSON.stringify(normalize(before[key]))!==JSON.stringify(normalize(after[key])))throw new Error(`Unexpected ${key} schema changes.`);
  }
  if(before.functions.length!==after.functions.length)throw new Error('Unexpected function count change.');
  for(const f of after.functions){
    const old=before.functions.find(b=>b.schema===f.schema&&b.name===f.name&&b.identity===f.identity);
    if(!old)throw new Error('Unexpected function added.');
    if(JSON.stringify(old)!==JSON.stringify(f)){
      if(!['public.log_audit_event','private.audit_multi_hospital_change'].includes(`${f.schema}.${f.name}`))throw new Error('Unexpected function change.');
      const {definition:oldDef,...oldRest}=old;const {definition:newDef,...newRest}=f;
      if(JSON.stringify(oldRest)!==JSON.stringify(newRest))throw new Error('Unexpected function grant/identity change.');
      changed.push(`${f.schema}.${f.name}`);
    }
  }
}catch(error){await writeFile(path,original);throw error;}
console.log(JSON.stringify({catalogAdvanced:true,changedFunctions:changed,baselineSqlRewritten:false}));
