import {readFile,writeFile} from 'node:fs/promises';
import {sql,management} from './repair_backend.mjs';
const source=await readFile('supabase/operations/monitor.sql','utf8');
const results=[];
for(const query of source.split(';').filter(q=>q.trim()))results.push(...await sql(query));
await writeFile('.codex-runtime/repair-workflow-monitor.json',JSON.stringify({checkedAt:new Date().toISOString(),results},null,2));
console.log(JSON.stringify(results));
