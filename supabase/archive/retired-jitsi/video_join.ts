// Provider credentials stay server-side. Tokens authorize one existing room.
export type JitsiConfiguration = { baseUrl: string; appId: string; secret: string };

export async function signedJitsiJoinUrl(
  config: JitsiConfiguration,
  room: string,
  userId: string,
  role: 'doctor' | 'patient' | 'guest',
  windowEndSeconds: number,
  nowSeconds = Math.floor(Date.now() / 1000),
): Promise<string> {
  const base = new URL(config.baseUrl);
  if (base.protocol !== 'https:' || base.username || base.password || base.search || base.hash ||
      base.pathname !== '/' || !config.appId || config.secret.length < 32 ||
      !/^cnph-[a-z0-9-]+$/i.test(room)) {
    throw new Error('Jitsi server configuration is invalid');
  }
  const expiry = Math.min(nowSeconds + 300, windowEndSeconds);
  if (!Number.isFinite(expiry) || expiry <= nowSeconds) throw new Error('The video window has closed');
  const payload = { aud: config.appId, iss: config.appId, sub: 'meet.jitsi', room,
    iat: nowSeconds, nbf: nowSeconds - 5, exp: expiry,
    context: { user: { id: userId, name: role === 'doctor' ? 'Doctor' : 'Patient', moderator: role === 'doctor' } } };
  const encoded = `${base64url(JSON.stringify({ alg: 'HS256', typ: 'JWT' }))}.${base64url(JSON.stringify(payload))}`;
  const key = await crypto.subtle.importKey('raw', new TextEncoder().encode(config.secret),
    { name: 'HMAC', hash: 'SHA-256' }, false, ['sign']);
  const signature = await crypto.subtle.sign('HMAC', key, new TextEncoder().encode(encoded));
  const token = `${encoded}.${base64url(new Uint8Array(signature))}`;
  const url = new URL(`/${room}`, base);
  url.searchParams.set('jwt', token);
  return url.href;
}

function base64url(value: string | Uint8Array) {
  const bytes = typeof value === 'string' ? new TextEncoder().encode(value) : value;
  return btoa(String.fromCharCode(...bytes)).replaceAll('+', '-').replaceAll('/', '_').replace(/=+$/, '');
}
