import {env,management,sql} from './repair_backend.mjs';
const auth=await management('config/auth');
console.log(JSON.stringify({authSMTPConfigured:!!auth.smtp_host,authUsesExposedPassword:!!env.SMTP_PASSWORD&&auth.smtp_pass===env.SMTP_PASSWORD,
  allowedRecoveryRedirects:auth.uri_allow_list?.split(',').filter(x=>x.includes('reset-password')),siteURL:auth.site_url}));
if(env.SMTP_PASSWORD&&auth.smtp_pass===env.SMTP_PASSWORD){
  await management('config/auth',{method:'PATCH',body:JSON.stringify({smtp_pass:''})});
  console.log('Removed the exposed password from Supabase Auth SMTP settings. Owner must revoke and replace it.');
}
const secrets=await management('secrets');
console.log(JSON.stringify({edgeSMTPPasswordConfigured:secrets.some(s=>s.name==='SMTP_PASSWORD'),edgeControlledRecipientConfigured:secrets.some(s=>s.name==='SMTP_TEST_RECIPIENT'),edgeAppURLConfigured:secrets.some(s=>s.name==='APP_BASE_URL')}));
console.log(JSON.stringify(await sql("select jobname,schedule,active,command like '%dispatch-notifications%' as dispatcher,command like '%vault.%' as references_vault from cron.job where command like '%dispatch-notifications%'")));
