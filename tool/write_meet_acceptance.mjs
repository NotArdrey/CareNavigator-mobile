import {readFile,writeFile} from 'node:fs/promises';
let setup=(await readFile('supabase/tests/clinical_completion_acceptance.sql','utf8')).split('  outcome:=public.book_consultation_v2')[0];
setup=setup.replace('valid_med jsonb;','invalid_url text; session_id uuid; notification_count bigint; valid_med jsonb;');
const checks=`
  outcome:=public.book_consultation_v2(jsonb_build_object('doctor_id',doctor_row.id,'hospital_id',hospital_row.id,
    'consultation_type','online','appointment_date',preferred_time,'chief_complaint','Synthetic Google Meet acceptance fixture','symptom_duration','One day'));
  request_id:=(outcome->>'request_id')::uuid;
  if (outcome->>'slot_reserved')::boolean then raise exception 'Online preference reserved before hospital confirmation'; end if;
  perform set_config('request.jwt.claim.sub',admin_auth::text,true);
  result:=public.review_online_consultation_request(request_id,'confirmed',doctor_row.id,preferred_time,'video');
  select * into request_row from public.online_consultation_requests where id=request_id;
  perform set_config('request.jwt.claim.sub',doctor_auth::text,true);
  session_id:=public.set_consultation_meet_link(request_row.official_consultation_id,' https://meet.google.com/abc-defg-hij/?authuser=1#ignored ');
  if not exists(select 1 from public.video_sessions where id=session_id and provider='google_meet' and join_url='https://meet.google.com/abc-defg-hij' and starts_at=preferred_time) then
    raise exception 'Doctor link did not save before the join window or canonicalize its address'; end if;
  select count(*) into notification_count from public.notifications where reference_id=request_row.official_consultation_id;
  if public.set_consultation_meet_link(request_row.official_consultation_id,'https://meet.google.com/abc-defg-hij')<>session_id
    or (select count(*) from public.notifications where reference_id=request_row.official_consultation_id)<>notification_count then
    raise exception 'Repeated link save created another session or notification'; end if;
  foreach invalid_url in array array['http://meet.google.com/abc-defg-hij','https://evil.test/abc-defg-hij',
    'https://meet.google.com.evil.test/abc-defg-hij','https://user@meet.google.com/abc-defg-hij',
    'https://meet.google.com:443/abc-defg-hij','https://meet.google.com/not-a-meeting','javascript:alert(1)'] loop
    did_fail:=false;
    begin perform public.set_consultation_meet_link(request_row.official_consultation_id,invalid_url); exception when others then did_fail:=true; end;
    if not did_fail then raise exception 'An unsupported meeting link was accepted: %',invalid_url; end if;
  end loop;
  if public.set_consultation_meet_link(request_row.official_consultation_id,'https://meet.google.com/xyz-abcd-efg')<>session_id
    or (select count(*) from public.video_sessions where consultation_id=request_row.official_consultation_id)<>1 then
    raise exception 'Replacing the meeting link duplicated its session'; end if;
  perform set_config('request.jwt.claim.sub',patient_user.auth_user_id::text,true);
  did_fail:=false; begin perform public.set_consultation_meet_link(request_row.official_consultation_id,'https://meet.google.com/abc-defg-hij'); exception when others then did_fail:=true; end;
  if not did_fail then raise exception 'Patient replaced the doctor link'; end if;
  did_fail:=false; begin perform public.get_approved_video_room(request_row.official_consultation_id); exception when others then did_fail:=true; end;
  if not did_fail then raise exception 'Patient retrieved the meeting link before its window'; end if;
  perform set_config('request.jwt.claim.sub',admin_auth::text,true);
  did_fail:=false; begin perform public.set_consultation_meet_link(request_row.official_consultation_id,'https://meet.google.com/abc-defg-hij'); exception when others then did_fail:=true; end;
  if not did_fail then raise exception 'Hospital reviewer replaced the assigned doctor link'; end if;
  if has_table_privilege('authenticated','public.video_sessions','SELECT') then raise exception 'Raw room table bypasses the join window'; end if;
  alter table public.consultations disable trigger enforce_reservation_lead_time;
  alter table public.consultations disable trigger aa_lock_consultation_reservation;
  update public.consultations set appointment_date=now()+interval '15 minutes 1 second' where id=request_row.official_consultation_id;
  perform set_config('request.jwt.claim.sub',doctor_auth::text,true);
  perform public.set_consultation_meet_link(request_row.official_consultation_id,'https://meet.google.com/xyz-abcd-efg');
  perform set_config('request.jwt.claim.sub',patient_user.auth_user_id::text,true);
  did_fail:=false; begin perform public.get_approved_video_room(request_row.official_consultation_id); exception when others then did_fail:=true; end;
  if not did_fail then raise exception 'Meeting link opened before the 15-minute boundary'; end if;
  update public.consultations set appointment_date=now()+interval '15 minutes' where id=request_row.official_consultation_id;
  perform set_config('request.jwt.claim.sub',doctor_auth::text,true);
  perform public.set_consultation_meet_link(request_row.official_consultation_id,'https://meet.google.com/xyz-abcd-efg');
  perform set_config('request.jwt.claim.sub',patient_user.auth_user_id::text,true);
  if public.get_approved_video_room(request_row.official_consultation_id)<>'https://meet.google.com/xyz-abcd-efg' then raise exception 'Patient could not join at the boundary'; end if;
  perform set_config('request.jwt.claim.sub',admin_auth::text,true);
  did_fail:=false; begin perform public.get_approved_video_room(request_row.official_consultation_id); exception when others then did_fail:=true; end;
  if not did_fail then raise exception 'Nonparticipant hospital reviewer retrieved the link'; end if;
  update public.consultations set appointment_date=now()-interval '4 hours' where id=request_row.official_consultation_id;
  perform set_config('request.jwt.claim.sub',doctor_auth::text,true);
  did_fail:=false; begin perform public.set_consultation_meet_link(request_row.official_consultation_id,'https://meet.google.com/abc-defg-hij'); exception when others then did_fail:=true; end;
  if not did_fail then raise exception 'Doctor replaced an expired link'; end if;
  perform set_config('request.jwt.claim.sub',patient_user.auth_user_id::text,true);
  did_fail:=false; begin perform public.get_approved_video_room(request_row.official_consultation_id); exception when others then did_fail:=true; end;
  if not did_fail then raise exception 'Patient joined after expiry'; end if;
  update public.consultations set appointment_date=now() where id=request_row.official_consultation_id;
  alter table public.consultations enable trigger enforce_reservation_lead_time;
  alter table public.consultations enable trigger aa_lock_consultation_reservation;
  perform set_config('request.jwt.claim.sub',doctor_auth::text,true);
  perform public.set_consultation_meet_link(request_row.official_consultation_id,'https://meet.google.com/xyz-abcd-efg');
  perform set_config('request.jwt.claim.sub',patient_user.auth_user_id::text,true);
  perform public.cancel_online_consultation_request(request_id,'Synthetic Google Meet cancellation check');
  did_fail:=false; begin perform public.get_approved_video_room(request_row.official_consultation_id); exception when others then did_fail:=true; end;
  if not did_fail or exists(select 1 from public.video_sessions where consultation_id=request_row.official_consultation_id and status in ('ready','active')) then
    raise exception 'Cancellation left the Google Meet link accessible'; end if;
end $test$;
rollback;
`;
await writeFile('supabase/tests/google_meet_links_acceptance.sql',setup+checks);
console.log('Google Meet ownership, link validation, update/idempotency, timing and terminal-state acceptance written.');
