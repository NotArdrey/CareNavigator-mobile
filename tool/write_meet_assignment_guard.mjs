import {readFile,readdir,writeFile} from 'node:fs/promises';
const catalog=JSON.parse(await readFile('supabase/baseline/catalog.json','utf8'));
let save=catalog.functions.find(f=>f.schema==='public'&&f.name==='set_consultation_meet_link').definition;
let get=catalog.functions.find(f=>f.schema==='public'&&f.name==='get_approved_video_room').definition;
if(!save.includes("v.id is not null and v.provider='google_meet'")||!get.includes("and expires_at>now();"))throw new Error('Meeting function definition changed unexpectedly');
save=save.replace("v.id is not null and v.provider='google_meet'","v.id is not null and v.created_by=auth.uid() and v.provider='google_meet'");
get=get.replace('where id=target_consultation_id;','where id=target_consultation_id for share;');
get=get.replace('and expires_at>now();',`and expires_at>now()
    and created_by=(select u.auth_user_id from public.doctors d join public.users u on u.id=d.user_id
      where d.id=c.doctor_id and u.account_status='active')
    and exists(select 1 from public.doctor_hospital_employments e where e.doctor_id=c.doctor_id and e.hospital_id=c.hospital_id
      and e.employment_status='active' and e.is_verified and coalesce(e.starts_at,e.created_at)<=now()
      and (e.ends_at is null or e.ends_at>now()));`);
const file=(await readdir('supabase/migrations')).find(n=>n.endsWith('_meet_link_assignment_guard.sql'));
await writeFile(`supabase/migrations/${file}`,`-- Require a link supplied under the current active doctor assignment.\n${save};\n${get};\n`);
console.log('Meeting assignment guard written.');
