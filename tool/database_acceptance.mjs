// All suites rollback. The fixture seed is restricted to an empty test database.
import pg from 'pg';
import {readFile,readdir} from 'node:fs/promises';
const databaseUrl=process.env.CNPH_TEST_DATABASE_URL;
if(!databaseUrl)throw new Error('Set CNPH_TEST_DATABASE_URL to an isolated test database.');
const client=new pg.Client({connectionString:databaseUrl});
await client.connect();
try {
  for(const name of (await readdir('supabase/tests')).filter(n=>n.endsWith('_acceptance.sql')).sort()){
    try {
      await client.query(await readFile(`supabase/tests/${name}`,'utf8'));
      console.log(`${name}: PASS`);
    }catch(error){await client.query('rollback');throw new Error(`${name}: ${error.message}`,{cause:error});}
  }
}finally{await client.end();}
