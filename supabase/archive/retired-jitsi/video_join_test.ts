import { signedJitsiJoinUrl } from './video_join.ts';
const config = { baseUrl: 'https://stage.example.test', appId: 'cnph-staging', secret: 'synthetic-fixture-key-32-characters-minimum' };
function assert(value: unknown, message: string): asserts value { if (!value) throw new Error(message); }
Deno.test('Jitsi token verifies, is room-specific and expires within the authorized window', async () => {
  const url = new URL(await signedJitsiJoinUrl(config, 'cnph-synthetic-room', 'synthetic-patient', 'patient', 1100, 1000));
  const [header, body, signature] = url.searchParams.get('jwt')!.split('.');
  const bytes = (s: string) => Uint8Array.from(atob(s.replaceAll('-', '+').replaceAll('_', '/')), c => c.charCodeAt(0));
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(config.secret), {name:'HMAC',hash:'SHA-256'}, false, ['verify']);
  assert(await crypto.subtle.verify('HMAC', key, bytes(signature), new TextEncoder().encode(`${header}.${body}`)), 'Invalid signature');
  const payload = JSON.parse(new TextDecoder().decode(bytes(body)));
  assert(payload.room === 'cnph-synthetic-room' && payload.exp === 1100 && payload.context.user.moderator === false, 'Unsafe token scope');
});
Deno.test('Jitsi rejects expired windows and insecure or caller-like provider configuration', async () => {
  for (const args of [
    {...config,baseUrl:'http://stage.example.test'}, {...config,baseUrl:'https://user:pass@stage.example.test'},
    {...config,baseUrl:'https://stage.example.test?override=1'}, {...config,secret:'short'}, config,
  ]) {
    let rejected = false;
    try { await signedJitsiJoinUrl(args, 'cnph-synthetic-room', 'synthetic', 'doctor', args === config ? 999 : 1300, 1000); }
    catch { rejected = true; }
    assert(rejected, 'Unsafe configuration/window accepted');
  }
});
