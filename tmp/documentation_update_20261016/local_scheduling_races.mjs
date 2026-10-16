import pg from '../../tool/node_modules/pg/lib/index.js';
import assert from 'node:assert/strict';
import {writeFile} from 'node:fs/promises';
const db=`cnph_concurrency_${Date.now()}`;
const config={host:'127.0.0.1',port:55439,user:'postgres'};
const admin=new pg.Client({...config,database:'postgres'});await admin.connect();
await admin.query(`create database "${db}" template "cnph_verification_1792132670459"`);await admin.end();
const connections=[];const cases=[];
async function connection(){const c=new pg.Client({...config,database:db});await c.connect();connections.push(c);await c.query("set statement_timeout='15s'");return c;}
const setup=await connection();
const [{patient_auth}]=(await setup.query("select auth_user_id patient_auth from public.users where email='patient@example.test'")).rows;
const actors=(await setup.query(`select d.id doctor_id,d.hospital_id,du.auth_user_id doctor_auth,au.auth_user_id admin_auth
  from public.doctors d join public.users du on du.id=d.user_id join public.users au on au.hospital_id=d.hospital_id
  join public.roles r on r.id=au.role_id where r.role_name='hospital_admin' and d.display_name like 'Synthetic Doctor %' order by d.display_name`)).rows;
assert.equal(actors.length,3);
async function identity(c,id,local=false){await c.query('select set_config(\'request.jwt.claim.sub\',$1,$2)',[id,local]);}
async function prepare(actor,offset=0){
  await identity(setup,patient_auth);
  const slot=(await setup.query("select * from public.list_available_consultation_slots($1,'online',14) order by starts_at offset $2 limit 1",[actor.doctor_id,offset])).rows[0];
  assert.ok(slot);
  const {outcome}=(await setup.query('select public.book_consultation_v2($1::jsonb) outcome',[JSON.stringify({doctor_id:actor.doctor_id,hospital_id:actor.hospital_id,
    consultation_type:'online',appointment_date:slot.starts_at,chief_complaint:'SYNTHETIC simultaneous transaction acceptance',symptom_duration:'One day',shared_categories:['consultations']})])).rows[0];
  assert.equal(outcome.slot_reserved,false);
  return {...outcome,slot:slot.starts_at};
}
async function confirm(c,actor,request){return c.query("select public.review_online_consultation_request($1,'confirmed',$2,$3,'call') outcome",[request.request_id,actor.doctor_id,request.slot]);}
async function beginAs(c,auth){await c.query('begin');await identity(c,auth,true);}
async function scheduleFor(actor,slot){return (await setup.query(`select id from public.doctor_schedules where doctor_id=$1 and consultation_type='online'
  and day_of_week=extract(dow from $2::timestamptz at time zone 'Asia/Manila')
  and starts_at<=($2::timestamptz at time zone 'Asia/Manila')::time and ends_at>($2::timestamptz at time zone 'Asia/Manila')::time limit 1`,[actor.doctor_id,slot])).rows[0].id;}
async function waitForLock(c){
  for(let i=0;i<80;i++){
    const {rows}=await setup.query('select wait_event_type,wait_event from pg_stat_activity where pid=$1',[c.processID]);
    if(rows[0]?.wait_event_type==='Lock')return rows[0];
    await new Promise(r=>setTimeout(r,25));
  }
  throw new Error('Competing transaction did not reach a lock wait');
}
try{
  // Both requests target the same currently free slot. Separate connections race.
  const first=await prepare(actors[0]);const second=await prepare(actors[0]);assert.equal(first.slot.getTime(),second.slot.getTime());
  const a=await connection(),b=await connection();
  async function attempt(c,r){try{await beginAs(c,actors[0].admin_auth);const result=await confirm(c,actors[0],r);await new Promise(resolve=>setTimeout(resolve,100));await c.query('commit');return {ok:true,consultationId:result.rows[0].outcome.consultation_id};}
    catch(error){await c.query('rollback');return {ok:false,reason:error.message};}}
  const outcomes=await Promise.all([attempt(a,first),attempt(b,second)]);
  assert.equal(outcomes.filter(x=>x.ok).length,1);
  const {count}=(await setup.query("select count(*)::int count from public.consultations where doctor_id=$1 and appointment_date=$2 and status not in ('cancelled','rejected')",[actors[0].doctor_id,first.slot])).rows[0];assert.equal(count,1);
  cases.push({name:'Two simultaneous confirmations reserve exactly one slot',result:'PASS',successfulConfirmations:1,rejectedConfirmations:1});
  // Deletion holds the shared doctor lock first; a waiting confirmation rechecks.
  const r2=await prepare(actors[1]);const schedule2=await scheduleFor(actors[1],r2.slot);
  const c=await connection(),d=await connection();await beginAs(c,actors[1].doctor_auth);
  await c.query('delete from public.doctor_schedules where id=$1',[schedule2]);
  await beginAs(d,actors[1].admin_auth);
  const pending2=confirm(d,actors[1],r2).then(()=>({ok:true}),error=>({ok:false,reason:error.message}));
  const lock2=await waitForLock(d);await c.query('commit');const result2=await pending2;await d.query('rollback');assert.equal(result2.ok,false);
  const after2=(await setup.query('select official_consultation_id from public.online_consultation_requests where id=$1',[r2.request_id])).rows[0];assert.equal(after2.official_consultation_id,null);
  cases.push({name:'Schedule deletion wins race; waiting confirmation rejects unpublished slot',result:'PASS',observedLock:lock2.wait_event});
  // Confirmation holds the lock first; the waiting deletion sees its reservation.
  const r3=await prepare(actors[2]);const schedule3=await scheduleFor(actors[2],r3.slot);
  const e=await connection(),f=await connection();await beginAs(e,actors[2].admin_auth);await confirm(e,actors[2],r3);
  await beginAs(f,actors[2].doctor_auth);
  const pending3=f.query('delete from public.doctor_schedules where id=$1',[schedule3]).then(()=>({ok:true}),error=>({ok:false,reason:error.message}));
  const lock3=await waitForLock(f);await e.query('commit');const result3=await pending3;await f.query('rollback');assert.equal(result3.ok,false);
  assert.equal((await setup.query('select count(*)::int count from public.doctor_schedules where id=$1',[schedule3])).rows[0].count,1);
  cases.push({name:'Confirmation wins race; waiting schedule deletion preserves reserved availability',result:'PASS',observedLock:lock3.wait_event});
}catch(error){cases.push({result:'FAIL',error:error.message});process.exitCode=1;}
finally{
  await Promise.allSettled(connections.map(c=>c.end()));
  const report={checkedAt:new Date().toISOString(),scope:'Independent PostgreSQL connections in a cloned local synthetic-only database; no live schema or trigger changes',database:db,cases};
  await writeFile('tmp/documentation_update_20261016/scheduling-race-results.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
}
