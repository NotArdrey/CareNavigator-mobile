// Read-only discovery in a separate browser, using only isolated fixture credentials.
import { chromium } from 'playwright';
import { readFile, mkdir, writeFile } from 'node:fs/promises';
const fixture = JSON.parse(await readFile('.codex-runtime/repair-test-accounts.json', 'utf8'));
const out = '.codex-runtime/repair-browser';
await mkdir(out, { recursive: true });
const browser = await chromium.launch({
  executablePath: process.env.CNPH_BROWSER_PATH ?? 'C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe',
  headless: true,
  args: ['--use-fake-ui-for-media-stream', '--use-fake-device-for-media-stream'],
});
const report = {};
async function semantics(page) {
  await page.locator('flt-semantics-placeholder').waitFor({timeout:30000});
  await page.locator('flt-semantics-placeholder').evaluate(e => e.click());
}
async function controls(page) {
  return page.locator('flt-semantics').evaluateAll(nodes => nodes.map(e => ({
    role:e.getAttribute('role'),label:e.getAttribute('aria-label'),text:e.innerText,
  })).filter(e=>e.role || e.label));
}
try {
  for (const account of fixture.accounts) {
    const context = await browser.newContext({viewport:{width:1440,height:1000}});
    const page = await context.newPage();
    await page.goto('http://127.0.0.1:3000/sign-in');
    await semantics(page);
    await page.getByRole('textbox',{name:'Email address',exact:true}).click();
    await page.waitForTimeout(300);
    await page.keyboard.type(account.email,{delay:10});
    await page.keyboard.press('Tab');
    await page.waitForTimeout(300);
    await page.keyboard.type(fixture.password,{delay:10});
    await page.keyboard.press('Tab');
    await page.waitForTimeout(300);
    await page.getByRole('button',{name:'Sign in',exact:true}).click();
    try {
      await page.waitForURL(url=>url.pathname!='/sign-in',{timeout:30000});
    } catch (error) {
      report[account.role] = {url:page.url(),controls:await controls(page)};
      await page.screenshot({path:`${out}/sign-in-failure.png`});
      throw error;
    }
    await page.waitForTimeout(2500);
    const role = account.role;
    report[role] = {url:page.url(),controls:await controls(page)};
    const prefix = {patient:'/patient',doctor:'/doctor',hospital_admin:'/hospital-admin',super_admin:'/super-admin',guest:''}[role];
    const sections = role==='patient'?['appointments','records','prescriptions','profile']:
      role==='doctor'?['appointments','patients','prescriptions']:
      role==='hospital_admin'?['consultations']:[];
    for (const section of sections) {
      await page.goto(`http://127.0.0.1:3000${prefix}/${section}`);
      await semantics(page);
      await page.waitForTimeout(2000);
      report[role][section] = await controls(page);
    }
    await context.close();
    console.log(`${role}: signed in; routes inspected`);
  }
} finally {
  await browser.close();
  await writeFile(`${out}/discovery.json`,JSON.stringify(report,null,2));
}
