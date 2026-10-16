import {management,sql} from '../../tool/repair_backend.mjs';
import {writeFile} from 'node:fs/promises';
const auth=await management('config/auth');
const secrets=await management('secrets');
const names=new Set(secrets.map(x=>x.name));
const result={checkedAt:new Date().toISOString(),authSmtpHostConfigured:!!auth.smtp_host,
  authSmtpPasswordConfigured:!!auth.smtp_pass,siteUrl:auth.site_url,
  recoveryRedirects:(auth.uri_allow_list??'').split(',').filter(x=>x.includes('reset-password')),
  edgeSmtpPasswordConfigured:names.has('SMTP_PASSWORD'),controlledRecipientConfigured:names.has('SMTP_TEST_RECIPIENT'),
  edgeAppUrlConfigured:names.has('APP_BASE_URL'),
  dispatcher:await sql("select jobname,schedule,active,command like '%vault.%' as references_vault from cron.job where command like '%dispatch-notifications%'")};
await writeFile('tmp/documentation_update_20261016/integration-config.json',JSON.stringify(result,null,2));
console.log(JSON.stringify(result,null,2));
