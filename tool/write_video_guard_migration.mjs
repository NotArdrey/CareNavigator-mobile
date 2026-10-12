import {readFile,readdir,writeFile} from 'node:fs/promises';
const catalog=JSON.parse(await readFile('supabase/baseline/catalog.json','utf8'));
let definition=catalog.functions.find(f=>f.schema==='public'&&f.name==='get_approved_video_room').definition;
definition=definition.replace('if not is_authorized_participant','if not coalesce(is_authorized_participant, false)');
const path=(await readdir('supabase/migrations')).find(n=>n.endsWith('_close_null_video_authorization.sql'));
await writeFile(`supabase/migrations/${path}`,`-- SQL NULL must never authorize an unrelated video participant.\n${definition};\n`);
console.log(`supabase/migrations/${path}`);
