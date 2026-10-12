// Metadata-only reconciliation. This never executes the baseline on existing tables.
import {readFile,writeFile,readdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {spawnSync} from 'node:child_process';
import {sql,project} from './repair_backend.mjs';
const check=spawnSync(process.execPath,['tool/export_schema_baseline.mjs','--check'],{stdio:'inherit'});
if(check.status!==0)throw new Error('Schema reconciliation failed');
const rows=await sql('select * from supabase_migrations.schema_migrations order by version');
await writeFile(`.codex-runtime/migration-ledger-full-backup-${Date.now()}.json`,JSON.stringify(rows,null,2));
const active=await Promise.all((await readdir('supabase/migrations')).filter(n=>n.endsWith('.sql')).sort().map(async name=>({
  version:name.split('_')[0],name:name.replace(/^\d+_|\.sql$/g,''),
  sha256:createHash('sha256').update(await readFile(`supabase/migrations/${name}`)).digest('hex'),
})));
const manifest={project,verifiedAt:new Date().toISOString(),baseline:'20261011100000',
  baselineSha256:createHash('sha256').update(await readFile('supabase/migrations/20261011100000_application_baseline.sql')).digest('hex'),
  active,previous:rows.map(r=>({version:r.version,name:r.name,statementsSha256:createHash('sha256').update(JSON.stringify(r.statements)).digest('hex')}))};
const prior=await readFile('supabase/baseline/deployment_reconciliation.json','utf8').then(JSON.parse).catch(()=>null);
const retained=prior?{...prior,events:[...(prior.events??[]),manifest]}:manifest;
await writeFile('supabase/baseline/deployment_reconciliation.json',JSON.stringify(retained,null,2));
if(!process.argv.includes('--record')){
  console.log('Read-only reconciliation saved; use --record for metadata reconciliation after a verified match.');
}else{
  const expected=rows.map(r=>`'${r.version.replaceAll("'","''")}'`).join(',');
  await sql(`begin;
    lock table supabase_migrations.schema_migrations in exclusive mode;
    do $$ begin
      if (select count(*) from supabase_migrations.schema_migrations)<>${rows.length}
        or exists(select 1 from supabase_migrations.schema_migrations where version not in (${expected})) then
        raise exception 'Migration ledger changed during reconciliation';
      end if;
    end $$;
    delete from supabase_migrations.schema_migrations;
    insert into supabase_migrations.schema_migrations(version,name,statements)
    values ${active.map(m=>`('${m.version}','${m.name}',ARRAY['-- Active migration reconciled against actual schema; no application DDL replayed. SHA256 ${m.sha256}'])`).join(',')};
    commit;`);
  console.log('Recorded reconciled baseline; historical ledger retained in sanitized manifest and ignored complete backup. Application data unchanged.');
}
