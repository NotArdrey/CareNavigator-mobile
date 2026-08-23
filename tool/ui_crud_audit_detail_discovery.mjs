import { mkdir, readFile, writeFile } from 'node:fs/promises';
import { chromium } from '../.codex-runtime/playwright/node_modules/playwright/index.mjs';

const root = new URL('../', import.meta.url);
const state = JSON.parse(
  await readFile(new URL('.codex-runtime/ui-audit-state.json', root), 'utf8'),
);
const artifactDir = new URL('.codex-runtime/ui-audit/', root);
const bravePath =
  'C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe';
const baseUrl = process.env.CNPH_AUDIT_URL ?? 'http://127.0.0.1:7357';
const role = process.argv[2];
const route = process.argv[3];
const actionName = process.argv[4];

if (!state.accounts[role] || !route?.startsWith('/')) {
  throw new Error('Usage: node tool/ui_crud_audit_detail_discovery.mjs <role> </route>');
}

await mkdir(artifactDir, { recursive: true });
const browser = await chromium.launch({
  executablePath: bravePath,
  headless: false,
  args: ['--disable-features=Translate', '--no-default-browser-check'],
});
const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
const page = await context.newPage();
const failedRequests = [];
const consoleErrors = [];
const apiResponses = [];
page.on('requestfailed', (request) => {
  failedRequests.push({ url: request.url(), error: request.failure()?.errorText });
});
page.on('console', (message) => {
  if (message.type() === 'error') consoleErrors.push(message.text());
});
page.on('response', (response) => {
  if (response.url().includes('.supabase.co/')) {
    apiResponses.push({
      method: response.request().method(),
      status: response.status(),
      url: response.url(),
    });
  }
});

try {
  await page.goto(`${baseUrl}/#/sign-in`, { waitUntil: 'domcontentloaded' });
  await page.locator('flutter-view').waitFor({ state: 'attached', timeout: 30_000 });
  const placeholder = page.locator('flt-semantics-placeholder');
  if (await placeholder.count()) {
    await placeholder.evaluate((element) => element.click());
    await page.waitForTimeout(500);
  }
  await page.getByRole('textbox', { name: 'Email address', exact: true }).fill(
    state.accounts[role].email,
  );
  await page.getByRole('textbox', { name: 'Password', exact: true }).fill(
    state.password,
  );
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await page.waitForURL(new RegExp(`#/${roleHome(role).replace(/^\//, '')}$`), {
    timeout: 30_000,
  });
  await page.waitForTimeout(1_200);
  const responseStart = apiResponses.length;
  await page.goto(`${baseUrl}/#${route}`, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(3_000);
  let actionOutcome;
  if (actionName != null) {
    const action = page.getByRole('button', { name: actionName, exact: true }).first();
    if ((await action.count()) === 0 || !(await action.isEnabled())) {
      actionOutcome = 'control absent or disabled';
    } else {
      await action.click();
      const cancel = page.getByRole('button', { name: 'Cancel', exact: true }).last();
      try {
        await cancel.waitFor({ state: 'visible', timeout: 10_000 });
        await page.waitForTimeout(300);
        actionOutcome = 'dialog opened';
      } catch {
        actionOutcome = 'no dialog opened';
      }
    }
  }
  const session = await context.newCDPSession(page);
  const { nodes } = await session.send('Accessibility.getFullAXTree');
  await session.detach();
  const report = {
    generatedAt: new Date().toISOString(),
    role,
    route,
    actionName,
    actionOutcome,
    url: page.url(),
    controls: nodes
      .filter((node) =>
        ['button', 'textbox', 'searchbox', 'link', 'checkbox', 'combobox', 'tab'].includes(
          node.role?.value,
        ),
      )
      .map((node) => ({
        role: node.role?.value ?? '',
        name: node.name?.value ?? '',
        value: node.value?.value ?? '',
        disabled:
          node.properties?.find((property) => property.name === 'disabled')?.value?.value ??
          false,
      })),
    visibleText: nodes
      .filter((node) => node.role?.value === 'StaticText')
      .map((node) => node.name?.value ?? '')
      .filter(Boolean),
    apiResponses: apiResponses.slice(responseStart).map((entry) => ({
      ...entry,
      url: redactUrl(entry.url),
    })),
    failedRequests,
    consoleErrors,
  };
  const slug = [role, route, actionName]
    .filter(Boolean)
    .join('-')
    .replace(/^\//, '')
    .replace(/[^a-z0-9]+/gi, '-');
  await writeFile(
    new URL(`detail-${slug}.json`, artifactDir),
    `${JSON.stringify(report, null, 2)}\n`,
  );
  console.log(JSON.stringify(report, null, 2));
} finally {
  await context.close();
  await browser.close();
}

function roleHome(value) {
  return {
    patient: '/patient',
    doctor: '/doctor',
    hospitalAdmin: '/hospital-admin',
    superAdmin: '/super-admin',
  }[value];
}

function redactUrl(value) {
  const url = new URL(value);
  for (const key of [...url.searchParams.keys()]) {
    if (/token|key|password|email/i.test(key)) url.searchParams.set(key, '<redacted>');
  }
  return url.toString();
}
