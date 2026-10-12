// Keep each report intact; summarize the latest actual result for each scenario.
import {readFile,writeFile} from 'node:fs/promises';
const names=['full-suite-results.json','playwright-results.json'];
const scenarios=new Map(),runs=[];
for(const name of names){
  const report=JSON.parse(await readFile(`.codex-runtime/repair-browser/${name}`,'utf8'));
  runs.push({source:name,stats:report.stats});
  function visit(suite){
    for(const spec of suite.specs??[])for(const test of spec.tests??[]){
      const result=test.results.at(-1);
      scenarios.set(`${spec.file}:${spec.title}:${test.projectName}`,{file:spec.file,title:spec.title,status:result?.status??'unexecuted',source:name});
    }
    for(const child of suite.suites??[])visit(child);
  }
  for(const suite of report.suites??[])visit(suite);
}
const results=[...scenarios.values()],counts={};
for(const result of results)counts[result.status]=(counts[result.status]??0)+1;
const summary={checkedAt:new Date().toISOString(),runs,latestScenarioCounts:counts,results,complete:results.every(r=>r.status==='passed')};
await writeFile('.codex-runtime/repair-browser/verification-summary.json',JSON.stringify(summary,null,2));
console.log(JSON.stringify({latestScenarioCounts:counts,complete:summary.complete,unresolved:results.filter(r=>r.status!=='passed').map(r=>r.title)}));
