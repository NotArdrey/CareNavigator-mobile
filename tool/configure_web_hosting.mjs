import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {connect, management} from './repair_backend.mjs';

const base = new URL(process.argv[2]);
if (base.protocol !== 'https:' || base.username || base.password || base.pathname !== '/') {
  throw new Error('Provide the HTTPS production origin, without a path.');
}

// Confirm the intended live project through MCP before configuring its links.
const client = await connect();
try {
  const result = await client.callTool({
    name: 'execute_sql',
    arguments: {query: "select count(*)::integer as public_table_count from information_schema.tables where table_schema = 'public'"},
  });
  const text = result.content.filter(item => item.type === 'text').map(item => item.text).join('\n');
  const count = text.match(/public_table_count[^0-9]{1,20}(\d+)/)?.[1];
  if (result.isError || !count || Number(count) === 0) throw new Error('Live project MCP verification failed.');
  console.log(`Live project verified through MCP: ${count} public tables.`);
} finally {
  await client.close();
}

const auth = await management('config/auth');
const backupDirectory = '.codex-runtime/vercel-admin';
await mkdir(backupDirectory, {recursive: true});
await writeFile(`${backupDirectory}/auth-links-before.json`, JSON.stringify({
  site_url: auth.site_url, uri_allow_list: auth.uri_allow_list,
}, null, 2));
const urls = new Set((auth.uri_allow_list ?? '').split(',').filter(Boolean));
urls.add(`${base.origin}/reset-password`);
await management('config/auth', {
  method: 'PATCH',
  body: JSON.stringify({site_url: base.origin, uri_allow_list: [...urls].join(',')}),
});
await management('secrets', {
  method: 'POST', body: JSON.stringify([{name: 'APP_BASE_URL', value: base.origin}]),
});
const verified = await management('config/auth');
if (verified.site_url !== base.origin || !verified.uri_allow_list.split(',').includes(`${base.origin}/reset-password`)) {
  throw new Error('Production Auth links did not persist.');
}
const localConfig = await readFile('env', 'utf8');
const updatedConfig = /^APP_BASE_URL\s*=/m.test(localConfig)
  ? localConfig.replace(/^APP_BASE_URL\s*=.*$/m, `APP_BASE_URL=${base.origin}`)
  : `${localConfig.trimEnd()}\nAPP_BASE_URL=${base.origin}\n`;
await writeFile('env', updatedConfig);
console.log(`Verified Auth Site URL, recovery redirect, and server APP_BASE_URL: ${base.origin}`);
