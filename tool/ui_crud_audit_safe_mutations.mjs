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
const roles = ['patient', 'doctor', 'hospitalAdmin', 'superAdmin'];
const report = { generatedAt: new Date().toISOString(), notifications: {} };

await mkdir(artifactDir, { recursive: true });
const browser = await chromium.launch({
  executablePath: bravePath,
  headless: false,
  args: ['--disable-features=Translate', '--no-default-browser-check'],
});

try {
  for (const role of roles) {
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
    const page = await context.newPage();
    const apiResponses = [];
    const failedRequests = [];
    const consoleErrors = [];
    page.on('response', (response) => {
      if (response.url().includes('.supabase.co/')) {
        apiResponses.push({
          method: response.request().method(),
          status: response.status(),
          url: response.url(),
        });
      }
    });
    page.on('requestfailed', (request) => {
      failedRequests.push({ url: request.url(), error: request.failure()?.errorText });
    });
    page.on('console', (message) => {
      if (message.type() === 'error') consoleErrors.push(message.text());
    });

    await page.goto(`${baseUrl}/#/sign-in`, { waitUntil: 'domcontentloaded' });
    await page.locator('flutter-view').waitFor({ state: 'attached', timeout: 30_000 });
    await enableAccessibility(page);
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
    await page.goto(`${baseUrl}/#${roleHome(role)}/notifications`, {
      waitUntil: 'domcontentloaded',
    });
    await page.waitForTimeout(1_200);

    const before = await notificationRows(page);
    const markRead = page.getByRole('button', { name: 'Mark read', exact: true }).first();
    const responseStart = apiResponses.length;
    if (await markRead.count()) {
      await markRead.click();
      await page.waitForTimeout(1_000);
    }
    const afterMutation = await notificationRows(page);
    await page.reload({ waitUntil: 'domcontentloaded' });
    await page.waitForTimeout(1_200);
    const afterReload = await notificationRows(page);
    const mutationResponses = apiResponses
      .slice(responseStart)
      .filter((entry) => entry.method !== 'GET')
      .map((entry) => ({ ...entry, url: redactUrl(entry.url) }));

    report.notifications[role] = {
      userId: state.accounts[role].userId,
      before,
      mutationResponses,
      afterMutation,
      afterReload,
      failedRequests,
      consoleErrors,
      result:
        mutationResponses.some((entry) => entry.status >= 200 && entry.status < 300) &&
        afterReload.markReadCount < before.markReadCount
          ? 'PASS'
          : before.markReadCount === 0
            ? 'N/A - no unread notification was available'
            : 'FAIL',
    };
    await context.close();
  }
} finally {
  await browser.close();
}

await writeFile(
  new URL('safe-mutations.json', artifactDir),
  `${JSON.stringify(report, null, 2)}\n`,
);
console.log(JSON.stringify(report, null, 2));

async function notificationRows(page) {
  const rows = await page.getByRole('button', { name: /Current records/ }).allTextContents();
  return {
    markReadCount: await page.getByRole('button', { name: 'Mark read', exact: true }).count(),
    rows,
  };
}

async function enableAccessibility(page) {
  const placeholder = page.locator('flt-semantics-placeholder');
  if (await placeholder.count()) {
    await placeholder.evaluate((element) => element.click());
    await page.waitForTimeout(500);
  }
}

function roleHome(role) {
  return {
    patient: '/patient',
    doctor: '/doctor',
    hospitalAdmin: '/hospital-admin',
    superAdmin: '/super-admin',
  }[role];
}

function redactUrl(value) {
  const url = new URL(value);
  for (const key of [...url.searchParams.keys()]) {
    if (/token|key|password|email/i.test(key)) url.searchParams.set(key, '<redacted>');
  }
  return url.toString();
}
