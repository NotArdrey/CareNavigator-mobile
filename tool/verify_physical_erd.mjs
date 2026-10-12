import {readFile,writeFile} from 'node:fs/promises';
import {sql} from './repair_backend.mjs';
const columns=await sql("select table_name,column_name from information_schema.columns where table_schema='public'");
const tables=new Map();
for(const column of columns){if(!tables.has(column.table_name))tables.set(column.table_name,new Set());tables.get(column.table_name).add(column.column_name);}
const erd=await readFile('docs/defense/database_erd.mmd','utf8');
const missing=[];let checkedEntities=0,checkedColumns=0;
for(const match of erd.matchAll(/^\s{4}([A-Z_]+)\s*\{([\s\S]*?)^\s{4}\}/gm)){
  checkedEntities++;const table=match[1].toLowerCase(),names=tables.get(table);
  if(!names){missing.push({table,missingTable:true});continue;}
  for(const field of match[2].matchAll(/^\s+\S+\s+(\w+)/gm)){
    checkedColumns++;if(!names.has(field[1]))missing.push({table,missingColumn:field[1]});
  }
}
if(!checkedEntities)throw new Error('No ERD entities were parsed');
const result={checkedAt:new Date().toISOString(),checkedEntities,checkedColumns,missing};
await writeFile('.codex-runtime/repair-erd-verification.json',JSON.stringify(result,null,2));
console.log(JSON.stringify(result));if(missing.length)process.exitCode=1;
