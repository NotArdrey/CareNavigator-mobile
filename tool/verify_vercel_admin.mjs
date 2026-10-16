import {mkdir, readFile, writeFile} from 'node:fs/promises';
import {chromium} from 'playwright';

const base = new URL(process.argv[2]);
if (base.protocol !== 'https:') throw new Error('Provide the production HTTPS URL.');
// Supply an optional local credential file to exercise authenticated sessions.
// Retired or banned fixture accounts must never be re-enabled by verification.
const accounts = process.argv[3] ? JSON.parse(await readFile(process.argv[3], 'utf8')) : null;
const directory = '.codex-runtime/vercel-admin';
await mkdir(directory, {recursive: true});
const browser = await chromium.launch({headless: true,
  executablePath: process.env.CNPH_BROWSER_PATH ?? 'C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe'});
const results = [];
async function enable(page) {
  await page.locator('flt-semantics-placeholder').waitFor({timeout: 60000});
  await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
  await page.getByRole('textbox', {name: 'Email address', exact: true}).waitFor({timeout: 30000});
}
try {
  for (const [role, route] of [['super_admin', '/super-admin'], ['hospital_admin', '/hospital-admin']]) {
    const context = await browser.newContext({viewport: {width: 1440, height: 1000}, timezoneId: 'Asia/Manila'});
    const page = await context.newPage();
    const errors = [];
    page.on('pageerror', error => errors.push(error.message));
    await page.goto(new URL(route, base).href);
    await enable(page);
    if (new URL(page.url()).pathname !== '/sign-in') throw new Error(`${role}: missing signed-out guard`);
    if (!accounts) {
      await page.screenshot({path: `${directory}/${role}-signed-out.png`});
      if (errors.length) throw new Error(`${role}: browser runtime errors: ${errors.join('; ')}`);
      results.push({role, signedOutGuard: true, signInForm: true, runtimeErrors: 0});
      await context.close();
      continue;
    }
    const account = accounts.accounts.find(account => account.role === role);
    await page.getByRole('textbox', {name: 'Email address', exact: true}).click();
    await page.keyboard.type(account.email, {delay: 5});
    await page.keyboard.press('Tab');
    await page.keyboard.type(account.password ?? accounts.password, {delay: 5});
    await page.keyboard.press('Tab');
    await page.getByRole('button', {name: 'Sign in', exact: true}).click();
    await page.waitForURL(url => url.pathname.startsWith(route), {timeout: 60000});
    await page.getByRole('button', {name: 'Sign out', exact: true}).waitFor({timeout: 30000});
    await page.screenshot({path: `${directory}/${role}.png`});
    await page.reload();
    await page.locator('flt-semantics-placeholder').waitFor({timeout: 60000});
    await page.locator('flt-semantics-placeholder').evaluate(element => element.click());
    await page.getByRole('button', {name: 'Sign out', exact: true}).waitFor({timeout: 30000});
    if (!new URL(page.url()).pathname.startsWith(route)) throw new Error(`${role}: session not retained on reload`);
    await page.getByRole('button', {name: 'Sign out', exact: true}).click();
    await page.goto(new URL(route, base).href);
    await enable(page);
    if (new URL(page.url()).pathname !== '/sign-in') throw new Error(`${role}: sign-out failed`);
    if (errors.length) throw new Error(`${role}: browser runtime errors: ${errors.join('; ')}`);
    results.push({role, signedOutGuard: true, signedIn: true, reload: true, signedOut: true, runtimeErrors: 0});
    await context.close();
  }
  await writeFile(`${directory}/browser-verification.json`, JSON.stringify({base: base.origin, results}, null, 2));
  console.log(JSON.stringify(results, null, 2));
} finally {
  await browser.close();
}
