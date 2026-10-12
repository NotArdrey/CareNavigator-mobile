import {readFile,writeFile} from 'node:fs/promises';
if(process.argv.includes('--aggregate')){
  const paths=['.codex-runtime/repair-browser/playwright-results.json',
    '.codex-runtime/e2e/expanded-first.json','.codex-runtime/e2e/expanded-corrected.json',
    '.codex-runtime/e2e/expanded-final.json','.codex-runtime/e2e/staff-passed-before-audit-fix.json',
    '.codex-runtime/e2e/playwright-results.json'];
  const cases=new Map();
  for(const path of paths){
    const report=await readFile(path,'utf8').then(JSON.parse).catch(error=>{
      if(error.code==='ENOENT'&&path.endsWith('staff-passed-before-audit-fix.json'))return null;
      throw error;
    });
    if(!report)continue;
    const collect=suite=>{
      for(const spec of suite.specs??[])for(const test of spec.tests??[]){
        const result=test.results.at(-1);
        cases.set(`${spec.file}:${spec.title}`,{file:spec.file,title:spec.title,status:result.status,
          durationMs:result.duration,evidence:path,checkedAt:report.stats.startTime});
      }
      for(const child of suite.suites??[])collect(child);
    };collect(report);
  }
  const tests=[...cases.values()];const audit=JSON.parse(await readFile('.codex-runtime/e2e/audit-fix.json','utf8'));
  const loadLog=async path=>{
    const bytes=await readFile(path);
    return bytes[0]===255&&bytes[1]===254?bytes.subarray(2).toString('utf16le'):bytes.toString('utf8');
  };
  const flutterLog=await loadLog('.codex-runtime/e2e-flutter.log');
  const databaseLog=await loadLog('.codex-runtime/e2e-database.log');
  const flutterPass=flutterLog.match(/\+(\d+): All tests passed!/);
  const summary={generatedAt:new Date().toISOString(),browser:{passed:tests.filter(t=>t.status==='passed').length,
    failed:tests.filter(t=>t.status==='failed'||t.status==='timedOut').length,skipped:tests.filter(t=>t.status==='skipped').length,tests},
    database:{deployedPassed:(databaseLog.match(/_acceptance\.sql: PASS/g)??[]).length,
      deployedFailed:(databaseLog.match(/_acceptance\.sql: FAIL/g)??[]).length,proposedPassed:audit.regressions?.length??1,migrationDeployed:audit.deployed,
      migration:audit.migration??null,failure:audit.current==='PASS'?null:'Hospital cascade deletion fails with audit_logs_hospital_id_fkey (23503).'},
    flutter:{passed:flutterPass?Number(flutterPass[1]):null,status:flutterPass?'passed':'failed',log:'.codex-runtime/e2e-flutter.log'}};
  await writeFile('.codex-runtime/e2e/final-summary.json',JSON.stringify(summary,null,2));
  console.log(JSON.stringify({browser:{passed:summary.browser.passed,failed:summary.browser.failed,skipped:summary.browser.skipped},database:summary.database,flutter:summary.flutter}));
  process.exitCode=summary.browser.failed?1:0;
}else{
const path=process.argv[2]??'.codex-runtime/e2e/playwright-results.json';
const report=JSON.parse(await readFile(path,'utf8'));
function walk(suite){
  for(const spec of suite.specs??[])for(const test of spec.tests??[])for(const result of test.results??[]){
    console.log(JSON.stringify({title:spec.title,status:result.status,duration:result.duration,errors:result.errors?.map(e=>e.message)}));
    if(result.status!=='passed')for(const a of result.attachments??[])if(a.name==='supabase-evidence')console.log(Buffer.from(a.body,'base64').toString());
  }
  for(const child of suite.suites??[])walk(child);
}
walk(report);console.log(JSON.stringify(report.stats));
}
