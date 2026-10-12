import { sql,connect,unpack } from './repair_backend.mjs';
import {writeFile} from 'node:fs/promises';
console.log(JSON.stringify(await sql("select column_name,data_type from information_schema.columns where table_schema='supabase_migrations' and table_name='schema_migrations'")));
const client=await connect();
try {
  const result=unpack(await client.callTool({name:'get_advisors',arguments:{type:'security'}}));
  await writeFile('.codex-runtime/repair-security-advisors.json',JSON.stringify(result,null,2));
  console.log('Saved security advisors (review separately).');
}finally{await client.close();}
