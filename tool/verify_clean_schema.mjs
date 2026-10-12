// A PostgreSQL application-schema proof, explicitly not a full Supabase stack.
import pg from 'pg';
import {readFile,readdir} from 'node:fs/promises';
const url=new URL(process.env.CNPH_SCRATCH_ADMIN_URL??'postgresql://postgres@127.0.0.1:55439/postgres');
if(!['localhost','127.0.0.1'].includes(url.hostname))throw new Error('This scaffold proof is restricted to a local scratch server.');
const db=`cnph_verification_${Date.now()}`;
const admin=new pg.Client({connectionString:url.href});await admin.connect();
await admin.query(`create database "${db}"`);await admin.end();
url.pathname='/'+db;
const client=new pg.Client({connectionString:url.href});await client.connect();
try{
  await client.query(await readFile('supabase/tests/platform_stub.sql','utf8'));
  for(const name of (await readdir('supabase/migrations')).filter(n=>n.endsWith('.sql')).sort()) {
    await client.query(await readFile(`supabase/migrations/${name}`,'utf8'));
  }
  await client.query(await readFile('supabase/baseline/reference_seed.sql','utf8'));
  await client.query(await readFile('supabase/baseline/storage_seed.sql','utf8'));
  // Compile every function again with body checking enabled.
  const {rows}=await client.query("select pg_get_functiondef(p.oid) definition from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.prokind='f'");
  for(const row of rows)await client.query(row.definition);
  await client.query(await readFile('supabase/tests/local_fixture_seed.sql','utf8'));
  for(const name of (await readdir('supabase/tests')).filter(n=>n.endsWith('_acceptance.sql')).sort()){
    await client.query(await readFile(`supabase/tests/${name}`,'utf8'));console.log(`${name}: PASS`);
  }
  const suiteCount=(await readdir('supabase/tests')).filter(n=>n.endsWith('_acceptance.sql')).length;
  console.log(`Clean application schema proof passed in ${db}: ${rows.length} functions compiled; ${suiteCount} suites passed. Platform servers were not tested.`);
}finally{await client.end();}
