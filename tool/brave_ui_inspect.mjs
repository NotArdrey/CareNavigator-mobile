import { chromium } from '../.codex-runtime/playwright/node_modules/playwright/index.mjs';

const baseUrl = process.env.CNPH_AUDIT_URL ?? 'http://127.0.0.1:7357';
const route = process.argv[2] ?? '/';
const clickName = process.argv[3];
const bravePath = 'C:\\Program Files\\BraveSoftware\\Brave-Browser\\Application\\brave.exe';
const profilePath = 'E:\\Codes\\CareNavigatorPh\\.codex-runtime\\brave-ui-audit';

const failures = [];
const consoleErrors = [];
const context = await chromium.launchPersistentContext(profilePath, {
  executablePath: bravePath,
  headless: false,
  viewport: { width: 1440, height: 1000 },
  args: ['--disable-features=Translate', '--no-default-browser-check'],
});

try {
  const page = context.pages()[0] ?? await context.newPage();
  page.on('console', (message) => {
    if (message.type() === 'error') consoleErrors.push(message.text());
  });
  page.on('requestfailed', (request) => {
    failures.push({ url: request.url(), error: request.failure()?.errorText ?? 'unknown' });
  });

  await page.goto(new URL(route, baseUrl).href, {
    waitUntil: 'domcontentloaded',
    timeout: 30_000,
  });
  await page.locator('flutter-view').waitFor({ state: 'attached', timeout: 30_000 });
  await page.waitForTimeout(1_500);
  const semanticsPlaceholder = page.locator('flt-semantics-placeholder');
  if (await semanticsPlaceholder.count()) {
    await semanticsPlaceholder.evaluate((element) => element.click());
    await page.waitForTimeout(800);
  }
  if (clickName) {
    await page.getByRole('button', { name: clickName, exact: true }).click();
    await page.waitForTimeout(500);
  }

  const session = await context.newCDPSession(page);
  const { nodes } = await session.send('Accessibility.getFullAXTree');
  const controls = nodes
    .map((node) => ({
      role: node.role?.value ?? '',
      name: node.name?.value ?? '',
      description: node.description?.value ?? '',
      value: node.value?.value ?? '',
      disabled: node.properties?.find((property) => property.name === 'disabled')?.value?.value ?? false,
    }))
    .filter((node) => node.name || ['button', 'textbox', 'link', 'checkbox', 'combobox'].includes(node.role));

  console.log(JSON.stringify({
    url: page.url(),
    title: await page.title(),
    domControls: await page.locator('flt-semantics[role="checkbox"], flt-semantics[role="button"][aria-label="Create account"]').evaluateAll(
      (elements) => elements.map((element) => ({
        tag: element.tagName,
        role: element.getAttribute('role'),
        label: element.getAttribute('aria-label'),
        disabled: element.getAttribute('aria-disabled'),
        checked: element.getAttribute('aria-checked'),
        rect: element.getBoundingClientRect().toJSON(),
      })),
    ),
    controls,
    failures,
    consoleErrors,
  }, null, 2));
  await page.screenshot({
    path: 'E:\\Codes\\CareNavigatorPh\\.codex-runtime\\brave-ui-inspect.png',
    fullPage: true,
  });
} finally {
  await context.close();
}
