import pg from 'pg';
import {readFile,readdir} from 'node:fs/promises';
const client=new pg.Client({connectionString:'postgresql://postgres@127.0.0.1:55439/cnph_upgrade_verified'});
await client.connect();
try{
  for(const name of (await readdir('supabase/migrations')).filter(n=>n.endsWith('.sql')&&!n.includes('application_baseline')).sort())await client.query(await readFile(`supabase/migrations/${name}`,'utf8'));
  for(const name of (await readdir('supabase/tests')).filter(n=>n.endsWith('_acceptance.sql')).sort()){
    await client.query(await readFile(`supabase/tests/${name}`,'utf8'));console.log(`${name}: upgraded schema PASS`);
  }
}finally{await client.end();}
