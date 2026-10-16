import {spawnSync} from 'node:child_process';
import {env} from '../../tool/repair_backend.mjs';
const url=env.NEXT_PUBLIC_SUPABASE_URL;
const key=env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY;
if(!/^https:\/\/[a-z0-9]+\.supabase\.co$/.test(url)||!/^[A-Za-z0-9_.-]+$/.test(key))throw new Error('Invalid public build configuration');
const child=spawnSync('C:/Users/Neila/devtools/flutter/bin/flutter.bat',[
  'build','web','--release','--no-pub',
  `--dart-define=NEXT_PUBLIC_SUPABASE_URL=${url}`,
  `--dart-define=NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY=${key}`,
],{shell:true,stdio:'inherit'});
if(child.error)throw child.error;
process.exitCode=child.status??1;
