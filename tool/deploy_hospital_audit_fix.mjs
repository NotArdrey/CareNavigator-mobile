// Apply only the reviewed audit correction to the project from ignored env.
// Saves schema-only backup/evidence; never prints credentials or clinical data.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {sql,connect,unpack,project} from './repair_backend.mjs';
const migrationPath=process.argv[2]??'supabase/migrations/20261012005203_preserve_audit_during_hospital_delete.sql';
const source=await readFile(migrationPath,'utf8');
const name='preserve_audit_during_hospital_delete';
const catalog=await sql(`select json_build_object(
  'functions',(select json_agg(json_build_object('schema',n.nspname,'name',p.proname,'definition',pg_get_functiondef(p.oid),'acl',p.proacl))
    from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname,p.proname) in
    (('public','log_audit_event'),('private','audit_multi_hospital_change'))),
  'columns',(select json_agg(json_build_object('column',column_name,'type',data_type)) from information_schema.columns
    where table_schema='public' and table_name='audit_logs'),
  'constraints',(select json_agg(json_build_object('name',conname,'definition',pg_get_constraintdef(oid)))
    from pg_constraint where conrelid='public.audit_logs'::regclass),
  'migrations',(select json_agg(json_build_object('version',version,'name',name)) from supabase_migrations.schema_migrations)
) catalog`);
const before=catalog[0].catalog;
if(before.functions?.length!==2||!before.columns?.some(c=>c.column==='metadata'&&c.type==='jsonb'))
  throw new Error('Current audit schema differs from the reviewed contract.');
if(!before.constraints?.some(c=>c.name==='audit_logs_hospital_id_fkey'&&c.definition.includes('ON DELETE SET NULL')))
  throw new Error('Current audit foreign key differs from the reviewed contract.');
await mkdir('.codex-runtime/e2e',{recursive:true});
const backupPath='.codex-runtime/e2e/audit-pre-deployment.json';
const original=await readFile(backupPath,'utf8').then(JSON.parse).catch(()=>null);
if(!original)await writeFile(backupPath,JSON.stringify(before,null,2));
console.log('Inspected both current audit functions, audit table/FK and migration ledger; saved schema-only backup.');
if(!before.migrations?.some(m=>m.name===name)){
  const client=await connect();
  try{unpack(await client.callTool({name:'apply_migration',arguments:{name,query:source}}));}
  finally{await client.close();}
  console.log('Applied the reviewed audit correction.');
}else console.log('The audit correction is already recorded; verifying deployed definitions.');
const migrations=await sql(`select version,name from supabase_migrations.schema_migrations where name='${name}' order by version desc`);
if(migrations.length!==1)throw new Error('Expected exactly one applied audit migration.');
const after=await sql(`select n.nspname schema,p.proname name,pg_get_functiondef(p.oid) definition,to_json(p.proacl) acl
  from pg_proc p join pg_namespace n on n.oid=p.pronamespace where (n.nspname,p.proname) in
  (('public','log_audit_event'),('private','audit_multi_hospital_change')) order by n.nspname`);
for(const f of after){
  if(!f.definition.includes('source_hospital_id')||!f.definition.toLowerCase().includes('for key share'))
    throw new Error(`Deployed ${f.schema}.${f.name} is missing the reviewed correction.`);
  if(JSON.stringify(f.acl)!==JSON.stringify((original??before).functions.find(b=>b.schema===f.schema&&b.name===f.name).acl))
    throw new Error(`Function privileges changed for ${f.schema}.${f.name}.`);
}
const evidence={verifiedAt:new Date().toISOString(),projectRef:project,migration:migrations[0],sourceSha256:createHash('sha256').update(source).digest('hex'),
  functions:after.map(f=>({schema:f.schema,name:f.name,sha256:createHash('sha256').update(f.definition).digest('hex'),privilegesPreserved:true}))};
await writeFile('.codex-runtime/e2e/audit-deployment.json',JSON.stringify(evidence,null,2));
console.log(JSON.stringify({migration:migrations[0],functionCount:after.length,privilegesPreserved:true}));
