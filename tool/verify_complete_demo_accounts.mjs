import { readFile } from 'node:fs/promises';

const projectRoot = new URL('../', import.meta.url);
const credentials = JSON.parse(
  await readFile(new URL('.codex-runtime/demo-account-credentials.json', projectRoot), 'utf8'),
);
const envText = await readFile(new URL('env', projectRoot), 'utf8');
const config = Object.fromEntries(
  envText
    .split(/\r?\n/)
    .map((line) => line.match(/^\s*([^#=][^=]*)=(.*)$/))
    .filter(Boolean)
    .map((match) => [match[1].trim(), match[2].trim()]),
);
const supabaseUrl = config.NEXT_PUBLIC_SUPABASE_URL;
const publishableKey = config.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
if (!supabaseUrl || !publishableKey) throw new Error('Public Supabase configuration is missing from env.');

const failures = [];
let succeeded = 0;
for (const account of credentials.accounts) {
  const response = await fetch(`${supabaseUrl}/auth/v1/token?grant_type=password`, {
    method: 'POST',
    headers: { apikey: publishableKey, 'Content-Type': 'application/json' },
    body: JSON.stringify({ email: account.email, password: credentials.password }),
  });
  if (response.ok) succeeded += 1;
  else failures.push({ email: account.email, status: response.status });
}

console.log(JSON.stringify({
  attempted: credentials.accounts.length,
  succeeded,
  failures,
}, null, 2));
if (failures.length > 0) process.exitCode = 1;
