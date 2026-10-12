// Generate local server configuration without printing or committing credentials.
import {readFile,writeFile,mkdir} from 'node:fs/promises';
import {randomBytes} from 'node:crypto';
import {env} from './repair_backend.mjs';
const release=JSON.parse(await readFile('infra/jitsi/release.json','utf8'));
const base=env.JITSI_BASE_URL??'https://jitsi-staging.example.test';
const parsed=new URL(base);
if(parsed.protocol!=='https:'||parsed.username||parsed.password||parsed.search||parsed.hash||parsed.pathname!=='/')throw new Error('JITSI_BASE_URL must be an HTTPS origin');
const secret=env.JITSI_APP_SECRET??randomBytes(48).toString('hex');
await mkdir('.codex-runtime/jitsi',{recursive:true});
await writeFile('.codex-runtime/jitsi/.env',[
  'CONFIG=/opt/carenavigator-jitsi/config',`JITSI_IMAGE_VERSION=${release.tag}`,
  `PUBLIC_URL=${parsed.origin}`,'HTTP_PORT=80','HTTPS_PORT=443','TZ=Asia/Manila',
  'ENABLE_LETSENCRYPT=1',`LETSENCRYPT_DOMAIN=${parsed.hostname}`,`LETSENCRYPT_EMAIL=${env.SMTP_USERNAME??''}`,
  'ENABLE_AUTH=1','AUTH_TYPE=jwt','JWT_ALLOW_EMPTY=0',
  `JWT_APP_ID=${env.JITSI_APP_ID??'carenavigator-staging'}`,`JWT_APP_SECRET=${secret}`,
  `JWT_ACCEPTED_ISSUERS=${env.JITSI_APP_ID??'carenavigator-staging'}`,
  `JWT_ACCEPTED_AUDIENCES=${env.JITSI_APP_ID??'carenavigator-staging'}`,
  'JWT_ENABLE_DOMAIN_VERIFICATION=1','ENABLE_PREJOIN_PAGE=1','ENABLE_WELCOME_PAGE=0',
  ...['JICOFO_AUTH_PASSWORD','JVB_AUTH_PASSWORD','JIGASI_XMPP_PASSWORD','JIBRI_RECORDER_PASSWORD','JIBRI_XMPP_PASSWORD'].map(k=>`${k}=${randomBytes(32).toString('hex')}`),
].join('\n')+'\n');
await writeFile('.codex-runtime/jitsi/supabase-secrets.env',[
  `JITSI_BASE_URL=${parsed.origin}`,`JITSI_APP_ID=${env.JITSI_APP_ID??'carenavigator-staging'}`,`JITSI_APP_SECRET=${secret}`,
  'JITSI_STAGING_CONSULTATION_IDS=',
].join('\n')+'\n');
console.log(`Staging configuration generated for ${parsed.hostname}. Credentials remain ignored. ${parsed.hostname.endsWith('.example.test')?'A real host/DNS address is still required.':'Host ready for deployment.'}`);
