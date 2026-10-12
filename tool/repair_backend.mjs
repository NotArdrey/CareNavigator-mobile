// Project-scoped backend tooling. Credentials remain in the ignored local env.
import { readFile, writeFile, mkdir, readdir } from 'node:fs/promises';
import { Client } from './node_modules/@modelcontextprotocol/sdk/dist/esm/client/index.js';
import { StreamableHTTPClientTransport } from './node_modules/@modelcontextprotocol/sdk/dist/esm/client/streamableHttp.js';

export const env = Object.fromEntries((await readFile('env', 'utf8')).split(/\r?\n/)
  .map(line => line.match(/^\s*([\w]+)\s*=\s*(.*?)\s*$/))
  .filter(Boolean).map(m => [m[1], m[2].replace(/^(['"])(.*)\1$/, '$2')]));
export const project = env.SUPABASE_PROJECT_ID;
if (process.env.SUPABASE_ACCESS_TOKEN) env.SUPABASE_ACCESS_TOKEN = process.env.SUPABASE_ACCESS_TOKEN;
if (!project || !env.SUPABASE_ACCESS_TOKEN) throw new Error('Project access is not configured');
export async function management(path, options = {}) {
  const response = await fetch(`https://api.supabase.com/v1/projects/${project}/${path}`, {
    ...options, headers: { Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}`,
      'Content-Type': 'application/json', ...options.headers },
  });
  const body = await response.text();
  if (!response.ok) {
    let detail = body;
    for (const value of Object.values(env)) if (value && value.length > 8) detail = detail.replaceAll(value, '[REDACTED]');
    throw new Error(`Management request ${path} failed: HTTP ${response.status}: ${detail.slice(0, 1600)}`);
  }
  return body ? JSON.parse(body) : null;
}
export async function connect() {
  const client = new Client({ name: 'care-navigator-repair', version: '1.0.0' }, { capabilities: {} });
  await client.connect(new StreamableHTTPClientTransport(
    new URL(`https://mcp.supabase.com/mcp?project_ref=${project}`),
    { requestInit: { headers: { Authorization: `Bearer ${env.SUPABASE_ACCESS_TOKEN}` } } },
  ));
  return client;
}
export function unpack(raw) {
  const text = raw.content.filter(c => c.type === 'text').map(c => c.text).join('\n');
  let value;
  try { value = JSON.parse(text); } catch { value = text; }
  if (raw.isError) throw new Error(typeof value === 'string' ? value : JSON.stringify(value));
  if (typeof value.result === 'string') {
    const match = value.result.match(/<untrusted-data-[^>]+>\s*([\s\S]*?)\s*<\/untrusted-data-/);
    if (match) return JSON.parse(match[1]);
  }
  return value.result ?? value;
}
export async function sql(query) { return management('database/query', {
  method: 'POST', body: JSON.stringify({ query }),
}); }

if (process.argv[1]?.endsWith('repair_backend.mjs')) {
  const [mode, path] = process.argv.slice(2);
  if (mode === 'query') console.log(JSON.stringify(await sql(await readFile(path, 'utf8')), null, 2));
  else if (mode === 'snapshot') {
    const query = `select json_build_object(
      'columns',(select json_agg(row_to_json(c)) from (select table_schema,table_name,column_name,data_type,column_default,is_nullable from information_schema.columns where table_schema in ('public','private') order by table_name,ordinal_position) c),
      'functions',(select json_agg(json_build_object('schema',n.nspname,'name',p.proname,'definition',pg_get_functiondef(p.oid))) from pg_proc p join pg_namespace n on n.oid=p.pronamespace where n.nspname in ('public','private') and p.prokind='f'),
      'triggers',(select json_agg(json_build_object('table',c.relname,'definition',pg_get_triggerdef(t.oid))) from pg_trigger t join pg_class c on c.oid=t.tgrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private') and not t.tgisinternal),
      'enums',(select json_agg(row_to_json(e)) from (select t.typname,enumlabel from pg_enum e join pg_type t on t.oid=e.enumtypid order by t.typname,e.enumsortorder) e),
      'constraints',(select json_agg(json_build_object('table',c.relname,'name',co.conname,'definition',pg_get_constraintdef(co.oid))) from pg_constraint co join pg_class c on c.oid=co.conrelid join pg_namespace n on n.oid=c.relnamespace where n.nspname in ('public','private')),
      'policies',(select json_agg(row_to_json(p)) from pg_policies p where schemaname in ('public','private','storage'))
    ) as schema;`;
    const data = await sql(query);
    await mkdir('.codex-runtime', { recursive: true });
    await writeFile('.codex-runtime/repair-schema.json', JSON.stringify(data[0].schema, null, 2));
    console.log('Saved current schema catalog (no patient data).');
  } else if (mode === 'deploy') {
    const client = await connect();
    try {
      const files = await Promise.all((await readdir(`supabase/functions/${path}`))
        .filter(name=>name.endsWith('.ts') && !name.endsWith('_test.ts'))
        .map(async name=>({name,content:await readFile(`supabase/functions/${path}/${name}`,'utf8')})));
      const result = unpack(await client.callTool({ name: 'deploy_edge_function', arguments: {
        name: path, entrypoint_path: 'index.ts', verify_jwt: !['dispatch-notifications','care-navigator-chat','analyze-symptoms'].includes(path),
        files,
      }}));
      console.log(JSON.stringify({ deployed: path, status: result.status, version: result.version }));
    } finally { await client.close(); }
  } else if (mode === 'apply') {
    const client = await connect();
    try {
      unpack(await client.callTool({ name: 'apply_migration', arguments: {
        name: path.split(/[\\/]/).pop().replace(/^\d+_|\.sql$/g, ''), query: await readFile(path, 'utf8'),
      }}));
      console.log(`Applied ${path}`);
    } finally { await client.close(); }
  } else throw new Error('Use snapshot, query <file>, apply <migration>, or deploy <function>');
}
