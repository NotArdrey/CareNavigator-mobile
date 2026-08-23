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
const selectedRole = process.argv[2];

const pagesByRole = {
  patient: [
    '/patient',
    '/hospitals',
    '/doctors',
    '/patient/appointments',
    '/patient/consultations',
    '/patient/medical-records',
    '/patient/labs',
    '/patient/prescriptions',
    '/patient/messages',
    '/patient/notifications',
    '/patient/profile',
  ],
  doctor: [
    '/doctor',
    '/doctor/scheduling',
    '/doctor/patients',
    '/doctor/consultations',
    '/doctor/laboratory',
    '/doctor/messages',
    '/doctor/notifications',
    '/doctor/profile',
  ],
  hospitalAdmin: [
    '/hospital-admin',
    '/hospital-admin/appointments',
    '/hospital-admin/facility',
    '/hospital-admin/emergency-room',
    '/hospital-admin/services-departments',
    '/hospital-admin/staff',
    '/hospital-admin/audit-reports',
    '/hospital-admin/notifications',
    '/hospital-admin/profile',
  ],
  superAdmin: [
    '/super-admin',
    '/super-admin/approvals',
    '/super-admin/accounts',
    '/super-admin/system',
    '/super-admin/analytics',
    '/super-admin/notifications',
    '/super-admin/profile',
  ],
};

await mkdir(artifactDir, { recursive: true });
const browser = await chromium.launch({
  executablePath: bravePath,
  headless: false,
  args: ['--disable-features=Translate', '--no-default-browser-check'],
});
const report = { generatedAt: new Date().toISOString(), roles: {} };

try {
  const roleEntries = Object.entries(pagesByRole).filter(
    ([role]) => selectedRole == null || role === selectedRole,
  );
  if (selectedRole != null && roleEntries.length === 0) {
    throw new Error(`Unknown role: ${selectedRole}`);
  }
  for (const [role, routes] of roleEntries) {
    const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
    const page = await context.newPage();
    const consoleErrors = [];
    const failedRequests = [];
    const responses = [];
    page.on('console', (message) => {
      if (message.type() === 'error') consoleErrors.push(message.text());
    });
    page.on('requestfailed', (request) => {
      failedRequests.push({
        method: request.method(),
        url: request.url(),
        error: request.failure()?.errorText ?? 'unknown',
      });
    });
    page.on('response', (response) => {
      const url = response.url();
      if (url.includes('.supabase.co/')) {
        responses.push({
          method: response.request().method(),
          status: response.status(),
          url: redactUrl(url),
        });
      }
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

    const roleReport = { email: maskEmail(state.accounts[role].email), pages: {} };
    for (const route of routes) {
      const responseStart = responses.length;
      const failureStart = failedRequests.length;
      const consoleStart = consoleErrors.length;
      await page.goto(`${baseUrl}/#${route}`, { waitUntil: 'domcontentloaded' });
      await page.waitForTimeout(1_200);
      const session = await context.newCDPSession(page);
      const { nodes } = await session.send('Accessibility.getFullAXTree');
      await session.detach();
      roleReport.pages[route] = {
        url: page.url(),
        visibleText: nodes
          .filter((node) => node.role?.value === 'StaticText')
          .map((node) => node.name?.value ?? '')
          .filter(Boolean),
        controls: nodes
          .map((node) => ({
            role: node.role?.value ?? '',
            name: node.name?.value ?? '',
            value: node.value?.value ?? '',
            disabled:
              node.properties?.find((property) => property.name === 'disabled')
                ?.value?.value ?? false,
          }))
          .filter((node) =>
            ['button', 'textbox', 'searchbox', 'link', 'checkbox', 'combobox', 'tab']
              .includes(node.role),
          ),
        apiResponses: responses.slice(responseStart),
        failedRequests: failedRequests.slice(failureStart),
        consoleErrors: consoleErrors.slice(consoleStart),
      };
    }
    report.roles[role] = roleReport;
    await context.close();
  }
} finally {
  await browser.close();
}

await writeFile(
  new URL(selectedRole == null ? 'discovery.json' : `discovery-${selectedRole}.json`, artifactDir),
  `${JSON.stringify(report, null, 2)}\n`,
);

for (const [role, roleReport] of Object.entries(report.roles)) {
  console.log(`\n${role}`);
  for (const [route, page] of Object.entries(roleReport.pages)) {
    const controls = page.controls.map((control) => `${control.role}:${control.name}`);
    console.log(`${route}\n  ${controls.join(' | ')}`);
    if (page.failedRequests.length || page.consoleErrors.length) {
      console.log(
        `  failures=${page.failedRequests.length} consoleErrors=${page.consoleErrors.length}`,
      );
    }
  }
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

function maskEmail(email) {
  const [local, domain] = email.split('@');
  return `${local.slice(0, 8)}…@${domain}`;
}

function redactUrl(value) {
  const url = new URL(value);
  for (const key of [...url.searchParams.keys()]) {
    if (/token|key|password|email/i.test(key)) url.searchParams.set(key, '<redacted>');
  }
  return url.toString();
}
