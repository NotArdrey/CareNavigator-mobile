import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {management,sql} from '../../tool/repair_backend.mjs';
const catalog=JSON.parse(await readFile('supabase/baseline/catalog.json','utf8'));
const tables=catalog.tables.filter(t=>t.schema==='public');
const erd=await readFile('docs/defense/full_database_erd.mmd','utf8');
const parsed=new Map([...erd.matchAll(/^(\w+)\s*\{\s*\n([\s\S]*?)^\}/gm)].map(m=>[m[1],new Set([...m[2].matchAll(/^\s+\S+\s+(\w+)/gm)].map(x=>x[1]))]));
const missing=[];
for(const table of tables)for(const col of table.columns)if(!parsed.get(table.name)?.has(col.name))missing.push(`${table.name}.${col.name}`);
const required=['care-navigator-chat','analyze-symptoms','analyze-medical-result','care-workflows','admin-users','dispatch-notifications'];
const remote=await management('functions');
const functions=required.map(name=>{const f=remote.find(x=>(x.slug??x.name)===name);return {name,present:!!f,status:f?.status,version:f?.version,verifyJwt:f?.verify_jwt};});
const fixture=await sql("select exists(select 1 from auth.users where lower(email)='qa.patient@carenavigator.test') as documentation_example_account_exists");
const doc=await readFile('output/final_project/MAD_Final_Project_Documentation_CareNavigator_PH.docx');
const result={checkedAt:new Date().toISOString(),documentSha256:createHash('sha256').update(doc).digest('hex'),
  publicTables:tables.length,publicColumns:tables.reduce((n,t)=>n+t.columns.length,0),
  declaredPublicForeignKeys:catalog.constraints.filter(c=>c.schema==='public'&&c.kind==='f').length,
  erdEntities:parsed.size,missingErdColumns:missing,functions,fixture:fixture[0]};
await writeFile('tmp/documentation_accuracy_20261016/evidence.json',JSON.stringify(result,null,2));
console.log(JSON.stringify(result,null,2));
