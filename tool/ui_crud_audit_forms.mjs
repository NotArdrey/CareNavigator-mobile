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
const report = { generatedAt: new Date().toISOString(), roles: {}, public: {} };

await mkdir(artifactDir, { recursive: true });
const browser = await chromium.launch({
  executablePath: bravePath,
  headless: false,
  args: ['--disable-features=Translate', '--no-default-browser-check'],
});

try {
  await inspectPublicGuestForm();
  await inspectRole('patient', async (page, roleReport) => {
    await capturePage(page, roleReport, '/patient/appointments', 'Appointments');
    await openDialog(page, roleReport, 'Book consultation', 'Book consultation');
    await capturePage(page, roleReport, '/patient/messages', 'Messages');
    await openDialog(page, roleReport, 'Start a conversation', 'Start conversation');
    await capturePage(page, roleReport, '/patient/profile', 'Profile');
    roleReport.forms.Profile = await controls(page);
    await capturePage(page, roleReport, '/hospitals', 'Find care');
    roleReport.forms['Hospital filters'] = await controls(page);
  });

  await inspectRole('doctor', async (page, roleReport) => {
    await capturePage(page, roleReport, '/doctor/scheduling', 'Scheduling');
    await openDialog(page, roleReport, 'Add slot', 'Publish schedule slot');

    await capturePage(page, roleReport, '/doctor/patients', 'Patients');
    await openDialog(page, roleReport, 'Register patient', 'Register patient');
    await openDialog(page, roleReport, 'Follow-up checkup', 'Follow-up patient checkup');
    const patientRow = page.getByRole('button', { name: /UI Audit · Patient/ }).first();
    if (await patientRow.count()) {
      await patientRow.click();
      await page.waitForTimeout(500);
      roleReport.pages['Patient detail'] = await controls(page);
      for (const [button, label] of [
        ['Message Patient', 'Message patient'],
        ['Add Record', 'Follow-up patient checkup'],
        ['Issue Prescription', 'Issue prescription'],
        ['Upload diagnostic result', 'Upload diagnostic result'],
      ]) {
        await openDialog(page, roleReport, button, label);
      }
    }

    await capturePage(page, roleReport, '/doctor/laboratory', 'Laboratory');
    await openDialog(page, roleReport, 'Request test', 'Request laboratory test');
    await clickTabAndCapture(page, roleReport, 'Results Review');
    await capturePage(page, roleReport, '/doctor/messages', 'Messages');
    await openDialog(page, roleReport, 'Start a conversation', 'Start conversation');
    await capturePage(page, roleReport, '/doctor/profile', 'Profile');
    roleReport.forms.Profile = await controls(page);
  });

  await inspectRole('hospitalAdmin', async (page, roleReport) => {
    await capturePage(page, roleReport, '/hospital-admin/facility', 'Facility');
    await clickTabAndCapture(page, roleReport, 'Rooms');
    await capturePage(
      page,
      roleReport,
      '/hospital-admin/services-departments',
      'Services & departments',
    );
    await openDialog(page, roleReport, 'Add service', 'Add service');
    await clickTabAndCapture(page, roleReport, 'Departments');
    await openDialog(page, roleReport, 'Add department', 'Add department');

    await capturePage(page, roleReport, '/hospital-admin/staff', 'Staff');
    await openDialog(page, roleReport, 'Add doctor', 'Create doctor account');
    await capturePage(page, roleReport, '/hospital-admin/profile', 'Profile');
    roleReport.forms.Profile = await controls(page);
  });

  await inspectRole('superAdmin', async (page, roleReport) => {
    await capturePage(page, roleReport, '/super-admin/system', 'System');
    await clickTabAndCapture(page, roleReport, 'Settings');
    const edit = page.getByRole('button', { name: 'Edit', exact: true }).first();
    if (await edit.count()) {
      await edit.click();
      await page.waitForTimeout(300);
      roleReport.forms['Edit system setting'] = await controls(page);
      await cancelDialog(page);
    }
    await clickTabAndCapture(page, roleReport, 'Security');
    await clickTabAndCapture(page, roleReport, 'Maintenance');
    await openDialog(page, roleReport, 'Schedule maintenance', 'Schedule maintenance');
    await clickTabAndCapture(page, roleReport, 'Audit');
    await capturePage(page, roleReport, '/super-admin/accounts', 'Accounts');
    await capturePage(page, roleReport, '/super-admin/approvals', 'Approvals');
    await capturePage(page, roleReport, '/super-admin/profile', 'Profile');
    roleReport.forms.Profile = await controls(page);
  });
} finally {
  await browser.close();
}

await writeFile(
  new URL('forms.json', artifactDir),
  `${JSON.stringify(report, null, 2)}\n`,
);

console.log(JSON.stringify(report, null, 2));

async function inspectPublicGuestForm() {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await context.newPage();
  await page.goto(`${baseUrl}/consultation/request`, {
    waitUntil: 'domcontentloaded',
  });
  await page.locator('flutter-view').waitFor({ state: 'attached', timeout: 30_000 });
  await enableAccessibility(page);
  await page.waitForTimeout(800);
  report.public['Guest consultation request'] = await controls(page);
  await context.close();
}

async function inspectRole(role, inspect) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await context.newPage();
  await page.goto(`${baseUrl}/sign-in`, { waitUntil: 'domcontentloaded' });
  await page.locator('flutter-view').waitFor({ state: 'attached', timeout: 30_000 });
  await enableAccessibility(page);
  await page.getByRole('textbox', { name: 'Email address', exact: true }).fill(
    state.accounts[role].email,
  );
  await page.getByRole('textbox', { name: 'Password', exact: true }).fill(
    state.password,
  );
  await page.getByRole('button', { name: 'Sign in', exact: true }).click();
  await page.waitForURL(new RegExp(`/${roleHome(role).replace(/^\//, '')}$`), {
    timeout: 30_000,
  });
  await page.waitForTimeout(1_500);
  const roleReport = { pages: {}, forms: {} };
  report.roles[role] = roleReport;
  await inspect(page, roleReport);
  await context.close();
}

async function capturePage(page, roleReport, route, label) {
  await page.goto(`${baseUrl}${route}`, { waitUntil: 'domcontentloaded' });
  await page.locator('flutter-view').waitFor({ state: 'attached', timeout: 30_000 });
  await enableAccessibility(page);
  await page.waitForTimeout(1_500);
  roleReport.pages[label] = await controls(page);
}

async function clickTabAndCapture(page, roleReport, tabName) {
  const tab = page.getByRole('tab', { name: tabName, exact: true });
  try {
    await tab.waitFor({ state: 'visible', timeout: 10_000 });
  } catch {
    roleReport.pages[tabName] = {
      unavailable: true,
      reason: 'Tab did not become visible',
    };
    return;
  }
  await tab.click();
  await page.waitForTimeout(1_200);
  roleReport.pages[tabName] = await controls(page);
}

async function openDialog(page, roleReport, buttonName, label) {
  const button = page.getByRole('button', { name: buttonName, exact: true }).first();
  if (!(await button.count()) || !(await button.isEnabled())) {
    roleReport.forms[label] = { unavailable: true, reason: 'Control absent or disabled' };
    return;
  }
  await button.click();
  const cancel = page.getByRole('button', { name: 'Cancel', exact: true }).last();
  try {
    await cancel.waitFor({ state: 'visible', timeout: 15_000 });
  } catch {
    roleReport.forms[label] = {
      unavailable: true,
      reason: 'Dialog did not become visible after the UI action',
      controls: await controls(page),
    };
    return;
  }
  await page.waitForTimeout(250);
  roleReport.forms[label] = await controls(page);
  await cancelDialog(page);
}

async function cancelDialog(page) {
  const cancel = page.getByRole('button', { name: 'Cancel', exact: true }).last();
  if (await cancel.count()) {
    await cancel.click();
    await page.waitForTimeout(250);
  }
}

async function controls(page) {
  const session = await page.context().newCDPSession(page);
  const { nodes } = await session.send('Accessibility.getFullAXTree');
  await session.detach();
  return nodes
    .map((node) => ({
      role: node.role?.value ?? '',
      name: node.name?.value ?? '',
      value: node.value?.value ?? '',
      disabled:
        node.properties?.find((property) => property.name === 'disabled')?.value
          ?.value ?? false,
    }))
    .filter((node) =>
      ['button', 'textbox', 'searchbox', 'link', 'checkbox', 'combobox', 'tab']
        .includes(node.role),
    );
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
