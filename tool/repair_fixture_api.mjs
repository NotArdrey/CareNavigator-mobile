import {readFile,writeFile} from 'node:fs/promises';
import {env,sql} from './repair_backend.mjs';
export const fixture=JSON.parse(await readFile('.codex-runtime/repair-fixture.json','utf8'));
export const accounts=JSON.parse(await readFile('.codex-runtime/repair-test-accounts.json','utf8'));
export const publicKey=env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
export const base=env.NEXT_PUBLIC_SUPABASE_URL;
export const sessions={};
export async function signIn(role){
  const account=accounts.accounts.find(a=>a.role===role);
  const response=await fetch(`${base}/auth/v1/token?grant_type=password`,{method:'POST',headers:{apikey:publicKey,'Content-Type':'application/json'},body:JSON.stringify({email:account.email,password:accounts.password})});
  const body=await response.json();
  if(!response.ok)throw new Error(`Fixture sign-in ${role}: HTTP ${response.status}`);
  sessions[role]=body.access_token;
  return body;
}
export async function api(role,path,body,method='POST'){
  if(!sessions[role])await signIn(role);
  const response=await fetch(`${base}/${path}`,{method,headers:{apikey:publicKey,Authorization:`Bearer ${sessions[role]}`,'Content-Type':'application/json'},...(body!==undefined?{body:JSON.stringify(body)}:{})});
  const text=await response.text();let result;try{result=JSON.parse(text);}catch{result=text;}
  if(!response.ok)throw new Error(`${path}: HTTP ${response.status}: ${JSON.stringify(result).slice(0,500)}`);
  return result;
}
export async function rpc(role,name,body){return api(role,`rest/v1/rpc/${name}`,body);}
if(process.argv.includes('--prepare')){
  const slots=await rpc('patient','list_available_consultation_slots',{target_doctor_id:fixture.id,target_type:'online',horizon_days:14});
  await writeFile('.codex-runtime/repair-browser/slots.json',JSON.stringify(slots,null,2));
  console.log('Available fixture slots saved:',slots.length);
}
