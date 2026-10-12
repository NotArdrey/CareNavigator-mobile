import {env} from './repair_backend.mjs';
import {readFile,readdir} from 'node:fs/promises';
import {execFileSync} from 'node:child_process';
const keys=['SMTP_PASSWORD','GROQ_API_KEY','ADMIN_BOOTSTRAP_TOKEN','NOTIFICATION_DISPATCH_TOKEN','SUPABASE_ACCESS_TOKEN','SUPABASE_DB_PASSWORD','SUPABASE_SERVICE_ROLE_KEY'];
const files=execFileSync('git',['ls-files','--cached','--others','--exclude-standard','-z'],{encoding:'utf8'}).split('\0').filter(Boolean);
const findings=[];
for(const name of files){let source;try{source=await readFile(name,'utf8');}catch{continue;}
  for(const key of keys)if(env[key]?.length>8&&source.includes(env[key]))findings.push({file:name,key});}
for(const name of await readdir('build/web'))if(name.endsWith('.js')){
  const source=await readFile(`build/web/${name}`,'utf8');
  for(const key of keys)if(env[key]?.length>8&&source.includes(env[key]))findings.push({file:`build/web/${name}`,key});
}
console.log(JSON.stringify({checkedFiles:files.length,secretLiteralFindings:findings}));
if(findings.length)process.exit(1);
