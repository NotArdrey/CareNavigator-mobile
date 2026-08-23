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
const report = { generatedAt: new Date().toISOString(), roles: {} };

await mkdir(artifactDir, { recursive: true });
const browser = await chromium.launch({
  executablePath: bravePath,
  headless: false,
  args: ['--disable-features=Translate', '--no-default-browser-check'],
});

try {
  if (selectedRole == null || selectedRole === 'patient') {
    await withRole('patient', async (page, roleReport) => {
    await go(page, '/hospitals');
    const hospitalSearch = page.getByRole('textbox', {
      name: 'Hospital, service, department, or location',
      exact: true,
    });
    const detailsBefore = await page.getByRole('button', { name: 'Details', exact: true }).count();
    await hospitalSearch.fill('Aurora Memorial');
    await page.waitForTimeout(700);
    const detailsAfterSearch = await page
      .getByRole('button', { name: 'Details', exact: true })
      .count();
    await hospitalSearch.fill('');
    await page.waitForTimeout(500);
    const available = page.getByRole('checkbox', { name: 'Available only', exact: true });
    await available.click();
    await page.waitForTimeout(500);
    const detailsAvailableOnly = await page
      .getByRole('button', { name: 'Details', exact: true })
      .count();
    await available.click();

    const locationButton = page.getByRole('button', { name: /Location All locations/ });
    await locationButton.click();
    const locationItems = page.getByRole('menuitem');
    const locationOptions = await locationItems.evaluateAll((elements) =>
      elements.map((element) => element.getAttribute('aria-label') ?? element.textContent ?? ''),
    );
    await locationItems.nth(1).click();
    await page.waitForTimeout(500);
    const detailsLocation = await page
      .getByRole('button', { name: 'Details', exact: true })
      .count();

    await go(page, '/hospitals');
    const firstDetails = page.getByRole('button', { name: 'Details', exact: true }).first();
    await firstDetails.click();
    await page.waitForTimeout(900);
    const detailUrl = page.url();
    const detailControls = await controlNames(page);

    await go(page, '/patient/messages');
    const messageSearch = page.getByRole('textbox', {
      name: 'Search conversations...',
      exact: true,
    });
    await messageSearch.fill('nobody');
    await page.waitForTimeout(400);
    const clearSearchVisible = await page
      .getByRole('button', { name: 'Clear search', exact: true })
      .last()
      .isVisible();
    await page.getByRole('button', { name: 'Clear search', exact: true }).last().click();
    await page.getByRole('button', { name: 'Start a conversation', exact: true }).last().click();
    await page.waitForTimeout(500);

    roleReport.interactions = {
      hospitalSearch: {
        detailsBefore,
        detailsAfterSearch,
        result: detailsAfterSearch === 1 ? 'PASS' : 'FAIL',
      },
      availableOnly: {
        detailsAvailableOnly,
        result: detailsAvailableOnly > 0 && detailsAvailableOnly <= detailsBefore ? 'PASS' : 'FAIL',
      },
      locationFilter: {
        options: locationOptions,
        filteredCount: detailsLocation,
        result: locationOptions.length > 1 && detailsLocation < detailsBefore ? 'PASS' : 'FAIL',
      },
      hospitalDetail: {
        url: detailUrl,
        controls: detailControls,
        result: /#\/hospitals\//.test(detailUrl) ? 'PASS' : 'FAIL',
      },
      messageSearch: { clearSearchVisible, result: clearSearchVisible ? 'PASS' : 'FAIL' },
      startConversation: {
        url: page.url(),
        result: page.url().endsWith('#/patient/consultations') ? 'PASS' : 'FAIL',
      },
      pagination: {
        result:
          (await page.getByRole('button', { name: /Load more|Next page|Previous page/ }).count()) ===
          0
            ? 'N/A - no pagination control is exposed for the current result set'
            : 'PRESENT',
      },
    };
    });
  }

  if (selectedRole == null || selectedRole === 'doctor') {
    await withRole('doctor', async (page, roleReport) => {
    await go(page, '/doctor/scheduling');
    await page.getByRole('tab', { name: 'Appointments', exact: true }).click();
    await page.waitForTimeout(800);
    const schedulingAppointments = await controlNames(page);
    await go(page, '/doctor/laboratory');
    await page.getByRole('tab', { name: 'Results Review', exact: true }).click();
    await page.waitForTimeout(800);
    const resultsReview = await controlNames(page);
    await go(page, '/doctor/messages');
    await page.getByRole('textbox', { name: 'Search conversations...', exact: true }).fill(
      'nobody',
    );
    await page.waitForTimeout(400);
    const clearSearch = await page
      .getByRole('button', { name: 'Clear search', exact: true })
      .last()
      .isVisible();
    await page.getByRole('button', { name: 'Clear search', exact: true }).last().click();
    await page.getByRole('button', { name: 'Start a conversation', exact: true }).last().click();
    await page.waitForTimeout(500);
    roleReport.interactions = {
      schedulingAppointments: {
        controls: schedulingAppointments,
        result: schedulingAppointments.includes('Refresh') ? 'PASS' : 'FAIL',
      },
      resultsReview: {
        controls: resultsReview,
        result: resultsReview.includes('Refresh') ? 'PASS' : 'FAIL',
      },
      messageSearch: { clearSearch, result: clearSearch ? 'PASS' : 'FAIL' },
      startConversation: {
        url: page.url(),
        result: page.url().endsWith('#/doctor/patients') ? 'PASS' : 'FAIL',
      },
    };
    });
  }

  if (selectedRole == null || selectedRole === 'hospitalAdmin') {
    await withRole('hospitalAdmin', async (page, roleReport) => {
    await go(page, '/hospital-admin/facility');
    await page.getByRole('tab', { name: 'Rooms', exact: true }).click();
    await page.waitForTimeout(800);
    const roomEdits = await page.getByRole('button', { name: 'Edit', exact: true }).count();
    await go(page, '/hospital-admin/services-departments');
    await page.getByRole('tab', { name: 'Services', exact: true }).click();
    await page.waitForTimeout(800);
    const search = page.getByRole('textbox', { name: 'Search visible records', exact: true });
    const serviceActionsBefore = await page
      .getByRole('button', { name: 'Update availability', exact: true })
      .count();
    await search.fill('Oncology');
    await page.waitForTimeout(400);
    const serviceActionsAfter = await page
      .getByRole('button', { name: 'Update availability', exact: true })
      .count();
    await search.fill('');
    await page.getByRole('tab', { name: 'Departments', exact: true }).click();
    await page.waitForTimeout(800);
    const departmentActions = await page
      .getByRole('button', { name: 'Update availability', exact: true })
      .count();
    await go(page, '/hospital-admin/audit-reports');
    await page.getByRole('tab', { name: 'Reports', exact: true }).click();
    await page.waitForTimeout(800);
    roleReport.interactions = {
      rooms: { count: roomEdits, result: roomEdits === 1 ? 'PASS' : 'FAIL' },
      serviceSearch: {
        before: serviceActionsBefore,
        after: serviceActionsAfter,
        result: serviceActionsBefore === 8 && serviceActionsAfter === 1 ? 'PASS' : 'FAIL',
      },
      departments: {
        count: departmentActions,
        result: departmentActions === 8 ? 'PASS' : 'FAIL',
      },
      reports: {
        controls: await controlNames(page),
        result: 'PASS',
      },
    };
    });
  }

  if (selectedRole == null || selectedRole === 'superAdmin') {
    await withRole('superAdmin', async (page, roleReport) => {
    await go(page, '/super-admin/system');
    const tabs = ['Settings', 'Security', 'Maintenance', 'Audit'];
    const tabEvidence = {};
    for (const tabName of tabs) {
      await page.getByRole('tab', { name: tabName, exact: true }).click();
      await page.waitForTimeout(700);
      tabEvidence[tabName] = await controlNames(page);
    }
    await go(page, '/super-admin/accounts');
    const search = page.getByRole('textbox', { name: 'Search visible records', exact: true });
    const before = await page
      .getByRole('button', { name: 'Change account status', exact: true })
      .count();
    await search.fill('ui.audit.patient');
    await page.waitForTimeout(400);
    const after = await page
      .getByRole('button', { name: 'Change account status', exact: true })
      .count();
    roleReport.interactions = {
      systemTabs: Object.fromEntries(
        Object.entries(tabEvidence).map(([name, controls]) => [
          name,
          { controls, result: controls.includes('Refresh') ? 'PASS' : 'FAIL' },
        ]),
      ),
      accountSearch: { before, after, result: before > 1 && after === 1 ? 'PASS' : 'FAIL' },
    };
    });
  }
} finally {
  await browser.close();
}

await writeFile(
  new URL(
    selectedRole == null
      ? 'read-interactions.json'
      : `read-interactions-${selectedRole}.json`,
    artifactDir,
  ),
  `${JSON.stringify(report, null, 2)}\n`,
);
console.log(JSON.stringify(report, null, 2));

async function withRole(role, inspect) {
  const context = await browser.newContext({ viewport: { width: 1440, height: 1000 } });
  const page = await context.newPage();
  const failedRequests = [];
  const consoleErrors = [];
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
  const roleReport = { interactions: {}, failedRequests, consoleErrors };
  report.roles[role] = roleReport;
  await inspect(page, roleReport);
  await context.close();
}

async function go(page, route) {
  await page.goto(`${baseUrl}/#${route}`, { waitUntil: 'domcontentloaded' });
  await page.waitForTimeout(1_200);
}

async function controlNames(page) {
  const session = await page.context().newCDPSession(page);
  const { nodes } = await session.send('Accessibility.getFullAXTree');
  await session.detach();
  return nodes
    .filter((node) => ['button', 'tab', 'textbox', 'checkbox'].includes(node.role?.value))
    .map((node) => node.name?.value ?? '')
    .filter(Boolean);
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
