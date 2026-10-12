import {readFile} from 'node:fs/promises';
import {api,accounts} from './repair_fixture_api.mjs';
const c=JSON.parse(await readFile('supabase/baseline/catalog.json','utf8'));
for(const name of ['get_approved_video_room','can_join_video_consultation','can_access_video_session']){
  for(const f of c.functions.filter(f=>f.name===name))console.log(f.definition);
}
console.log('Fixture roles:',accounts.accounts.map(a=>a.role));
