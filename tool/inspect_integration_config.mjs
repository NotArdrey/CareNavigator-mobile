import {env,management,sql} from './repair_backend.mjs';
console.log('Relevant env keys:',Object.keys(env).filter(k=>/JITSI|VIDEO|BASE_URL|SITE_URL|SMTP|NOTIFICATION_FROM/.test(k)));
const secrets=await management('secrets');
console.log('Relevant server secret names:',secrets.map(s=>s.name).filter(k=>/JITSI|VIDEO|BASE_URL|SITE_URL|SMTP|NOTIFICATION_FROM/.test(k)));
console.log('Video/public application setting keys:',await sql("select key from public.system_settings where key ilike '%jitsi%' or key ilike '%video%' or key ilike '%url%'"));
console.log('Vault configuration names:',await sql("select name from vault.secrets where name ilike '%jitsi%' or name ilike '%video%' or name ilike '%url%'"));
