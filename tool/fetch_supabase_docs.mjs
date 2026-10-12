import {writeFile} from 'node:fs/promises';
for (const path of ['changelog','docs/guides/auth/redirect-urls','docs/reference/cli/supabase-migration-repair']) {
  const response = await fetch(`https://supabase.com/${path}.md`);
  const source = await response.text();
  await writeFile(`.codex-runtime/supabase-${path.split('/').pop()}.md`,source);
  console.log(path,response.status,source.slice(0,150));
}
