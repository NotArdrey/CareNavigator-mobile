import {writeFile,mkdir} from 'node:fs/promises';
import {createHash} from 'node:crypto';
const releaseResponse=await fetch('https://api.github.com/repos/jitsi/docker-jitsi-meet/releases/latest');
if(!releaseResponse.ok)throw new Error(`Jitsi release lookup: HTTP ${releaseResponse.status}`);
const release=await releaseResponse.json();
const asset=release.assets.find(a=>a.name==='docker-jitsi-meet.zip')??{
  browser_download_url:`https://github.com/jitsi/docker-jitsi-meet/archive/refs/tags/${release.tag_name}.zip`,
};
const response=await fetch(asset.browser_download_url);if(!response.ok)throw new Error('Archive download failed');
const bytes=Buffer.from(await response.arrayBuffer());
await mkdir('infra/jitsi',{recursive:true});
await writeFile('.codex-runtime/docker-jitsi-meet.zip',bytes);
await writeFile('infra/jitsi/release.json',JSON.stringify({tag:release.tag_name,url:asset.browser_download_url,sha256:createHash('sha256').update(bytes).digest('hex'),publishedAt:release.published_at},null,2));
console.log('Pinned official Jitsi release',release.tag_name,bytes.length,'bytes');
const guide=await fetch('https://raw.githubusercontent.com/jitsi/handbook/master/docs/devops-guide/docker.md');
await writeFile('.codex-runtime/jitsi-docker-guide.md',await guide.text());
