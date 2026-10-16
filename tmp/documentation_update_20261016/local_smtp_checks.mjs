import net from 'node:net';
import assert from 'node:assert/strict';
import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {stripTypeScriptTypes} from 'node:module';
import {pathToFileURL} from 'node:url';
import {resolve} from 'node:path';
const messages=[];let rejectRecipient=false;
const smtp=net.createServer(socket=>{
  socket.setEncoding('utf8');socket.write('220 localhost SYNTHETIC SMTP sink\r\n');
  let buffer='',inData=false,lines=[];
  socket.on('data',chunk=>{
    buffer+=chunk;
    while(buffer.includes('\r\n')){
      const end=buffer.indexOf('\r\n');const line=buffer.slice(0,end);buffer=buffer.slice(end+2);
      if(inData){if(line==='.'){
        messages.push(lines.join('\r\n'));lines=[];inData=false;socket.write('250 2.0.0 accepted locally\r\n');
      }else lines.push(line.startsWith('..')?line.slice(1):line);continue;}
      if(/^EHLO|^HELO/i.test(line))socket.write('250-localhost\r\n250-AUTH PLAIN\r\n250 SIZE 1000000\r\n');
      else if(/^AUTH PLAIN/i.test(line))socket.write('235 2.7.0 synthetic authentication accepted\r\n');
      else if(/^MAIL FROM:/i.test(line))socket.write('250 sender OK\r\n');
      else if(/^RCPT TO:/i.test(line))socket.write(!rejectRecipient&&/^RCPT TO:<fixture@example\.test>/i.test(line)?'250 recipient OK\r\n':'550 synthetic recipient rejection\r\n');
      else if(/^DATA$/i.test(line)){inData=true;socket.write('354 end with dot\r\n');}
      else if(/^QUIT$/i.test(line)){socket.end('221 bye\r\n');}
      else if(/^RSET|^NOOP/i.test(line))socket.write('250 OK\r\n');
      else socket.write('500 unsupported synthetic command\r\n');
    }
  });
});
await new Promise(resolve=>smtp.listen(0,'127.0.0.1',resolve));
const env={SMTP_HOST:'127.0.0.1',SMTP_PORT:String(smtp.address().port),SMTP_USERNAME:'synthetic',SMTP_PASSWORD:'synthetic-local-only',
  NOTIFICATION_FROM_EMAIL:'sender@example.test',APP_BASE_URL:'https://example.test',NOTIFICATION_DISPATCH_TOKEN:'synthetic-dispatch-token',
  SUPABASE_URL:'https://example.test',SUPABASE_SERVICE_ROLE_KEY:'synthetic-local-only'};
const job={id:42,notification_id:'synthetic-notification',user_id:'synthetic-auth-user',channel:'email'};
let state;
function reset(){state={allowed:true,verified:true,rpcCalls:[],completions:[],updates:[]};rejectRecipient=false;env.SMTP_PASSWORD='synthetic-local-only';}
reset();
const admin={rpc:async(name,args)=>{
  state.rpcCalls.push({name,args});
  if(name==='claim_notification_outbox')return {data:[job],error:null};
  if(name==='notification_email_allowed')return {data:state.allowed,error:null};
  if(name==='complete_notification_delivery')state.completions.push(args);
  return {data:0,error:null};
},auth:{admin:{getUserById:async()=>({data:{user:{email:'fixture@example.test',email_confirmed_at:state.verified?'2026-10-16T00:00:00Z':null,is_anonymous:false}},error:null})}},
  from(table){return {select(){return this},eq(){return this},update(patch){state.updates.push({table,patch});return this},
    async single(){return {data:{id:job.notification_id,title:'SYNTHETIC delivery check',message:'Synthetic <check> & evidence',action_path:'/patient/notifications'},error:null}},
    async maybeSingle(){return {data:{first_name:'Synthetic',last_name:'<Patient>',email:'fixture@example.test'},error:null}},
    then(resolved,rejected){return Promise.resolve({error:null}).then(resolved,rejected)}};}};
let handler;
globalThis.Deno={env:{get:name=>env[name]},serve:callback=>{handler=callback;}};
globalThis.__syntheticCreateClient=()=>admin;
const source=await readFile('supabase/functions/dispatch-notifications/index.ts','utf8');
const imports=`import nodemailer from ${JSON.stringify(pathToFileURL(resolve('tmp/documentation_update_20261016/smtp-runtime/node_modules/nodemailer/lib/nodemailer.js')).href)};\nconst createClient=globalThis.__syntheticCreateClient;\n`;
const transformed=imports+stripTypeScriptTypes(source.replace(/^import[^\n]*\n/gm,''),{mode:'transform'});
await import('data:text/javascript;base64,'+Buffer.from(transformed).toString('base64'));
const cases=[];
async function invoke(token=env.NOTIFICATION_DISPATCH_TOKEN){return handler(new Request('http://127.0.0.1/synthetic-dispatch',{method:'POST',headers:{'x-dispatch-token':token,'content-type':'application/json'},body:'{}'}));}
async function check(name,fn){reset();const before=messages.length;try{await fn(before);cases.push({name,result:'PASS'});}catch(error){cases.push({name,result:'FAIL',error:error.message});process.exitCode=1;}}
try{
  await check('Invalid dispatcher token cannot claim or send',async before=>{assert.equal((await invoke('wrong')).status,403);assert.equal(state.rpcCalls.length,0);assert.equal(messages.length,before);});
  await check('Real SMTP transport delivers MIME email to local-only inbox and records success',async before=>{
    const result=await (await invoke()).json();assert.equal(result.outcomes[0].delivered,true);assert.equal(messages.length,before+1);
    assert.equal(state.completions[0].delivered,true);assert.equal(state.completions[0].provider_id,'<carenavigator-notification-42@carenavigator.local>');
    const raw=messages.at(-1);
    const decoded=raw.replace(/=\r\n/g,'').replace(/=([A-F0-9]{2})/gi,(_,hex)=>String.fromCharCode(parseInt(hex,16)));
    assert.match(raw,/To: fixture@example.test/);assert.match(decoded,/Synthetic &lt;Patient&gt;/);assert.match(decoded,/Synthetic &lt;check&gt; &amp; evidence/);assert.match(decoded,/https:\/\/example.test\/patient\/notifications/);
    await writeFile('tmp/documentation_update_20261016/synthetic-received-email.eml',raw);
  });
  await check('Disabled email preference cancels delivery without SMTP',async before=>{state.allowed=false;const result=await (await invoke()).json();assert.equal(result.outcomes[0].status,'cancelled');assert.equal(state.updates[0].patch.status,'cancelled');assert.equal(messages.length,before);});
  await check('Unverified recipient is rejected without SMTP',async before=>{state.verified=false;const result=await (await invoke()).json();assert.equal(result.outcomes[0].delivered,false);assert.equal(state.completions[0].delivered,false);assert.equal(messages.length,before);});
  await check('Missing SMTP password records failed delivery',async before=>{delete env.SMTP_PASSWORD;const result=await (await invoke()).json();assert.equal(result.outcomes[0].delivered,false);assert.match(result.outcomes[0].error,/not configured/);assert.equal(messages.length,before);});
  await check('SMTP recipient rejection records failure and accepts no message',async before=>{rejectRecipient=true;const result=await (await invoke()).json();assert.equal(result.outcomes[0].delivered,false);assert.equal(state.completions[0].delivered,false);assert.equal(messages.length,before);});
  await check('Retry of the same job preserves Message-ID and succeeds after SMTP recovery',async before=>{rejectRecipient=true;assert.equal((await (await invoke()).json()).outcomes[0].delivered,false);rejectRecipient=false;assert.equal((await (await invoke()).json()).outcomes[0].delivered,true);assert.equal(messages.length,before+1);assert.match(messages.at(-1),/Message-ID: <carenavigator-notification-42@carenavigator.local>/i);});
}finally{
  await new Promise(resolve=>smtp.close(resolve));
  const report={checkedAt:new Date().toISOString(),source:'supabase/functions/dispatch-notifications/index.ts',sourceSha256:createHash('sha256').update(source).digest('hex'),
    scope:'Production handler body with Node TypeScript stripping, actual Nodemailer 9.0.3 and a loopback SMTP receiver; Supabase calls use controlled fixtures. No external email sent.',cases};
  await writeFile('tmp/documentation_update_20261016/smtp-results.json',JSON.stringify(report,null,2));console.log(JSON.stringify(report,null,2));
}
