import {readFile,readdir,writeFile} from 'node:fs/promises';
const c=JSON.parse(await readFile('supabase/baseline/catalog.json','utf8'));
let source=c.functions.find(f=>f.schema==='public'&&f.name==='review_guest_consultation').definition;
source=source.replace(/if not \(\s*private\.is_hospital_admin_for\(request_row\.preferred_hospital_id\)\s*or request_row\.assigned_doctor_id = private\.current_doctor_id\(\)\s*\) then/,
  'if not coalesce(private.is_hospital_admin_for(request_row.preferred_hospital_id) or request_row.assigned_doctor_id = private.current_doctor_id(), false) then');
source=source.replace('  if chosen_doctor is null',`  if target_type='guest_online' and not private.is_hospital_admin_for(request_row.preferred_hospital_id) then
    raise exception 'Hospital confirmation is required for every new online guest appointment';
  end if;
  if chosen_doctor is null`);
const name=(await readdir('supabase/migrations')).find(n=>n.endsWith('_require_hospital_guest_online_confirmation.sql'));
await writeFile(`supabase/migrations/${name}`,'-- Online guest reservations require hospital confirmation; NULL cannot authorize review.\n'+source+';\n');
console.log(`supabase/migrations/${name}`);
