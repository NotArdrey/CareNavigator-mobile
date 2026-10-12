import {readFile,writeFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import {connect,unpack,management} from './repair_backend.mjs';
const names=['admin-users','analyze-medical-result','analyze-symptoms','care-workflows','dispatch-notifications','care-navigator-chat'];
const functions=await management('functions');
const client=await connect();const report=[];
try{
  const metadata=(await client.listTools()).tools.find(t=>t.name==='get_edge_function');
  console.log('Source verification tool schema:',JSON.stringify(metadata?.inputSchema));
  for(const name of names){
    const deployed=functions.find(f=>f.slug===name||f.name===name);
    const remote=unpack(await client.callTool({name:'get_edge_function',arguments:{function_slug:name}}));
    await writeFile(`.codex-runtime/deployed-${name}.json`,JSON.stringify(remote));
    const files=remote.files??[];
    const hashes=[];
    for(const file of files){
      const fileName=file.name.split(/[\\/]/).pop();
      if(!fileName.endsWith('.ts'))continue;
      const local=await readFile(`supabase/functions/${name}/${fileName}`,'utf8');
      const actual=file.content;
      if(typeof actual!=='string')throw new Error('Inspect remote file contract');
      const equal=local.replaceAll('\r\n','\n')===actual.replaceAll('\r\n','\n');
      if(!equal)throw new Error(`Deployed source differs: ${name}/${fileName}`);
      hashes.push({name:fileName,sha256:createHash('sha256').update(local).digest('hex')});
    }
    report.push({name,version:deployed?.version,status:deployed?.status,verify_jwt:deployed?.verify_jwt,files:hashes,remoteKeys:Object.keys(remote)});
  }
  await writeFile('supabase/baseline/function_deployment.json',JSON.stringify({verifiedAt:new Date().toISOString(),functions:report},null,2));
  console.log(JSON.stringify(report));
}finally{await client.close();}
