import {sql} from './repair_backend.mjs';
import {readFile,readdir} from 'node:fs/promises';
for(const name of (await readdir('supabase/tests')).filter(n=>n.endsWith('_acceptance.sql')).sort()){
  try {
    await sql(await readFile(`supabase/tests/${name}`,'utf8'));
    console.log(`${name}: PASS (rolled back)`);
  }catch(error){
    console.error(`${name}: FAIL: ${error.message}`);
    process.exitCode=1;
  }
}
