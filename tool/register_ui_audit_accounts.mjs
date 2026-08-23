import { randomBytes } from 'node:crypto';
import { mkdir, writeFile } from 'node:fs/promises';
import { chromium } from '../.codex-runtime/playwright/node_modules/playwright/index.mjs';

const baseUrl = process.env.CNPH_AUDIT_URL ?? 'http://127.0.0.1:7357';
const bravePath = 'C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe';
const artifactDir = 'E:\\Codes\\CareNavigatorPh\\.codex-runtime\\ui-audit';
const statePath = 'E:\\Codes\\CareNavigatorPh\\.codex-runtime\\ui-audit-state.json';
const suffix = Date.now().toString(36);
const password = `UiAudit-${randomBytes(12).toString('base64url')}aA1!`;
const definitions = [
  { key: 'patient', firstName: 'UI Audit', lastName: 'Patient' },
  { key: 'doctor', firstName: 'UI Audit', lastName: 'Doctor' },
  { key: 'hospitalAdmin', firstName: 'UI Audit', lastName: 'Hospital Admin' },
  { key: 'superAdmin', firstName: 'UI Audit', lastName: 'Super Admin' },
];

await mkdir(artifactDir, { recursive: true });
const accounts = {};
for (const definition of definitions) {
  const email = `ui.audit.${definition.key}.${suffix}@demo.test`.toLowerCase();
  const browser = await chromium.launch({
    executablePath: bravePath,
    headless: false,
    args: ['--disable-features=Translate', '--no-default-browser-check'],
  });
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await context.newPage();
  const consoleErrors = [];
  const failedRequests = [];
  page.on('console', (message) => {
    if (message.type() === 'error') consoleErrors.push(message.text());
  });
  page.on('requestfailed', (request) => {
    failedRequests.push({ url: request.url(), error: request.failure()?.errorText ?? 'unknown' });
  });

  try {
    await page.goto(`${baseUrl}/#/register`, { waitUntil: 'domcontentloaded' });
    await page.locator('flutter-view').waitFor({ state: 'attached' });
    await page.waitForTimeout(1_000);
    const placeholder = page.locator('flt-semantics-placeholder');
    if (await placeholder.count()) await placeholder.evaluate((element) => element.click());
    await page.waitForTimeout(500);

    await page.getByRole('textbox', { name: 'First name', exact: true }).fill(definition.firstName);
    await page.getByRole('textbox', { name: 'Last name', exact: true }).fill(definition.lastName);
    await page.getByRole('button', { name: 'Select date of birth', exact: true }).click();
    await page.getByRole('button', { name: 'OK', exact: true }).click();
    await page.getByRole('button', { name: /Sex Select your sex/ }).click();
    await page.getByRole('menuitem', { name: 'Female', exact: true }).click();
    await page.getByRole('textbox', { name: 'Mobile number', exact: true }).fill('09171234567');
    await page.getByRole('textbox', { name: 'Home address', exact: true }).fill('Manila City, Metro Manila');
    await page.getByRole('textbox', { name: 'Email address', exact: true }).fill(email);
    await page.getByRole('textbox', { name: 'Password', exact: true }).fill(password);
    const confirmationField = page.getByRole('textbox', { name: 'Confirm password', exact: true });
    await confirmationField.click();
    await page.keyboard.insertText(password);
    const createButton = page.getByRole('button', { name: 'Create account', exact: true });
    await page.locator('flt-semantics[role="checkbox"]:not([aria-label])').click();
    await page.waitForTimeout(300);
    await page.screenshot({ path: `${artifactDir}\\registration-${definition.key}-ready.png`, fullPage: true });
    if ((await createButton.count()) !== 1 || !(await createButton.isEnabled())) {
      await page.screenshot({ path: `${artifactDir}\\registration-${definition.key}-disabled.png`, fullPage: true });
      throw new Error(`Registration submit remained disabled or missing for ${email} at ${page.url()}.`);
    }

    const signupResponsePromise = page.waitForResponse(
      (response) => response.url().includes('/auth/v1/signup'),
      { timeout: 30_000 },
    );
    await createButton.click();
    const signupResponse = await signupResponsePromise;
    const responseBody = await signupResponse.json().catch(() => ({}));
    await page.waitForTimeout(1_000);
    await page.screenshot({ path: `${artifactDir}\\registration-${definition.key}.png`, fullPage: true });

    if (!signupResponse.ok()) {
      throw new Error(`Registration for ${email} failed (${signupResponse.status()}): ${JSON.stringify(responseBody)}`);
    }
    accounts[definition.key] = {
      email,
      requestedRole: definition.key,
      authUserId: responseBody.user?.id ?? responseBody.id ?? null,
      signupStatus: signupResponse.status(),
      currentUrl: page.url(),
      consoleErrors,
      failedRequests,
    };
  } finally {
    await browser.close();
  }
}

await writeFile(
  statePath,
  `${JSON.stringify({ createdAt: new Date().toISOString(), password, accounts }, null, 2)}\n`,
  { mode: 0o600 },
);
console.log(JSON.stringify({
  created: Object.fromEntries(
    Object.entries(accounts).map(([key, account]) => [key, {
      email: account.email,
      authUserId: account.authUserId,
      signupStatus: account.signupStatus,
      currentUrl: account.currentUrl,
      consoleErrorCount: account.consoleErrors.length,
      failedRequestCount: account.failedRequests.length,
    }]),
  ),
}, null, 2));
