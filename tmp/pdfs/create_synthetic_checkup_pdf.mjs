import { mkdir } from 'node:fs/promises';
import { chromium } from '../../.codex-runtime/playwright/node_modules/playwright/index.mjs';

const outputDirectory = new URL('../../output/pdf/', import.meta.url);
const previewDirectory = new URL('./', import.meta.url);
await mkdir(outputDirectory, { recursive: true });
await mkdir(previewDirectory, { recursive: true });

const outputPath = new URL(
  'synthetic_follow_up_checkup_test.pdf',
  outputDirectory,
);
const previewPath = new URL('synthetic_follow_up_checkup_preview.png', previewDirectory);

const html = `<!doctype html>
<html lang="en">
<head>
  <meta charset="utf-8">
  <style>
    @page { size: A4; margin: 0; }
    * { box-sizing: border-box; }
    html, body { margin: 0; padding: 0; background: #eef3f5; color: #102a3a; }
    body { font-family: Arial, Helvetica, sans-serif; }
    .page {
      position: relative;
      width: 210mm;
      min-height: 297mm;
      margin: 0 auto;
      padding: 15mm 16mm 13mm;
      background: #ffffff;
      overflow: hidden;
    }
    .watermark {
      position: absolute;
      top: 127mm;
      left: 21mm;
      transform: rotate(-31deg);
      color: rgba(7, 91, 104, 0.055);
      font-size: 42pt;
      font-weight: 800;
      letter-spacing: 4px;
      white-space: nowrap;
      pointer-events: none;
    }
    .topbar {
      height: 4mm;
      margin: -15mm -16mm 9mm;
      background: #087f82;
    }
    .header { display: flex; justify-content: space-between; gap: 12mm; align-items: flex-start; }
    .brand { display: flex; gap: 4mm; align-items: center; }
    .mark { position: relative; width: 12mm; height: 12mm; }
    .mark::before, .mark::after {
      content: "";
      position: absolute;
      background: #0aa39e;
      border-radius: 2.5mm;
    }
    .mark::before { width: 12mm; height: 4.2mm; left: 0; top: 3.9mm; }
    .mark::after { width: 4.2mm; height: 12mm; left: 3.9mm; top: 0; }
    .brand-name { font-size: 16pt; font-weight: 800; line-height: 1; }
    .brand-sub { margin-top: 1.5mm; color: #5f7481; font-size: 8.3pt; letter-spacing: .5px; }
    .test-badge {
      padding: 2.3mm 3mm;
      border: 1px solid #d5a126;
      border-radius: 2mm;
      background: #fff8df;
      color: #7a5300;
      font-size: 8.5pt;
      font-weight: 800;
      text-align: center;
      line-height: 1.35;
    }
    h1 { margin: 8mm 0 1.5mm; font-size: 22pt; line-height: 1.12; }
    .subtitle { margin: 0 0 6mm; color: #5f7481; font-size: 9.5pt; }
    .identity {
      display: grid;
      grid-template-columns: 1.35fr 1fr 1fr;
      gap: 3.2mm 6mm;
      padding: 4.5mm 5mm;
      border: 1px solid #d9e2e8;
      border-radius: 3mm;
      background: #f5f8f9;
    }
    .field .label { color: #6a7e89; font-size: 7.6pt; text-transform: uppercase; letter-spacing: .55px; }
    .field .value { margin-top: 1mm; font-size: 10pt; font-weight: 700; }
    .section { margin-top: 5.5mm; break-inside: avoid; }
    .section-title {
      display: flex;
      align-items: center;
      gap: 2.5mm;
      margin-bottom: 2.5mm;
      color: #075b68;
      font-size: 11pt;
      font-weight: 800;
    }
    .section-title::before { content: ""; width: 1.4mm; height: 5mm; border-radius: 1mm; background: #0aa39e; }
    .reason {
      padding: 3.2mm 4mm;
      border-left: 1.4mm solid #087f82;
      background: #edf8f7;
      font-size: 9.5pt;
      line-height: 1.45;
    }
    .vitals {
      display: grid;
      grid-template-columns: repeat(4, 1fr);
      border: 1px solid #d9e2e8;
      border-radius: 2.5mm;
      overflow: hidden;
    }
    .vital { padding: 3mm; min-height: 15mm; border-right: 1px solid #e4eaee; border-bottom: 1px solid #e4eaee; }
    .vital:nth-child(4n) { border-right: 0; }
    .vital:nth-child(n+5) { border-bottom: 0; }
    .vital-label { color: #667b87; font-size: 7.7pt; line-height: 1.25; }
    .vital-value { margin-top: 1.4mm; color: #075b68; font-size: 12pt; font-weight: 800; }
    .detail-grid { display: grid; grid-template-columns: 1fr 1fr; gap: 2.5mm 5mm; }
    .detail {
      padding-bottom: 2.3mm;
      border-bottom: 1px solid #e8edf1;
      font-size: 8.8pt;
      line-height: 1.4;
    }
    .detail strong { display: block; margin-bottom: .6mm; color: #516a77; font-size: 7.8pt; text-transform: uppercase; letter-spacing: .35px; }
    .notes {
      display: grid;
      grid-template-columns: 1fr 1fr;
      gap: 4mm;
    }
    .note-card { padding: 3.5mm 4mm; border: 1px solid #cfe2e3; border-radius: 2.5mm; background: #f6fbfb; }
    .note-card strong { display: block; margin-bottom: 1.5mm; color: #075b68; font-size: 9pt; }
    .note-card p { margin: 0; font-size: 8.6pt; line-height: 1.45; }
    .footer {
      position: absolute;
      left: 16mm;
      right: 16mm;
      bottom: 8mm;
      display: flex;
      justify-content: space-between;
      padding-top: 2.5mm;
      border-top: 1px solid #d9e2e8;
      color: #6e818b;
      font-size: 7.5pt;
    }
  </style>
</head>
<body>
  <main class="page">
    <div class="watermark">SYNTHETIC TEST DATA</div>
    <div class="topbar"></div>
    <header class="header">
      <div class="brand">
        <div class="mark"></div>
        <div>
          <div class="brand-name">CareNavigator PH</div>
          <div class="brand-sub">CLINICAL DOCUMENT TEST FIXTURE</div>
        </div>
      </div>
      <div class="test-badge">SYNTHETIC RECORD<br>NOT A REAL PATIENT</div>
    </header>

    <h1>Follow-up Checkup Summary</h1>
    <p class="subtitle">Prepared solely for attachment and document-processing tests.</p>

    <section class="identity">
      <div class="field"><div class="label">Patient name</div><div class="value">Juan Test Reyes</div></div>
      <div class="field"><div class="label">Patient ID</div><div class="value">CNPH-TEST-0001</div></div>
      <div class="field"><div class="label">Visit date</div><div class="value">Aug 23, 2026 - 3:30 PM</div></div>
      <div class="field"><div class="label">Date of birth</div><div class="value">Apr 18, 1992</div></div>
      <div class="field"><div class="label">Sex</div><div class="value">Male</div></div>
      <div class="field"><div class="label">Visit type</div><div class="value">Follow-up checkup</div></div>
    </section>

    <section class="section">
      <div class="section-title">Reason for visit</div>
      <div class="reason">Follow-up for blood pressure monitoring and intermittent mild headache.</div>
    </section>

    <section class="section">
      <div class="section-title">Basic measurements and vital signs</div>
      <div class="vitals">
        <div class="vital"><div class="vital-label">Height</div><div class="vital-value">170 cm</div></div>
        <div class="vital"><div class="vital-label">Weight</div><div class="vital-value">72 kg</div></div>
        <div class="vital"><div class="vital-label">BMI</div><div class="vital-value">24.91</div></div>
        <div class="vital"><div class="vital-label">Blood pressure</div><div class="vital-value">138/88 mmHg</div></div>
        <div class="vital"><div class="vital-label">Temperature</div><div class="vital-value">36.8 C</div></div>
        <div class="vital"><div class="vital-label">Heart rate</div><div class="vital-value">78 bpm</div></div>
        <div class="vital"><div class="vital-label">Respiratory rate</div><div class="vital-value">16 /min</div></div>
        <div class="vital"><div class="vital-label">Oxygen saturation</div><div class="vital-value">98%</div></div>
      </div>
    </section>

    <section class="section">
      <div class="section-title">Medical information</div>
      <div class="detail-grid">
        <div class="detail"><strong>Current symptoms</strong>Intermittent mild headache for 3 days. No chest pain or shortness of breath reported.</div>
        <div class="detail"><strong>Known condition</strong>Hypertension.</div>
        <div class="detail"><strong>Allergy</strong>Penicillin - rash.</div>
        <div class="detail"><strong>Current medication</strong>Amlodipine 5 mg once daily.</div>
        <div class="detail"><strong>Relevant history</strong>Family history of hypertension in father.</div>
        <div class="detail"><strong>Previous surgery</strong>Appendectomy in 2012.</div>
        <div class="detail"><strong>Smoking status</strong>Former smoker.</div>
        <div class="detail"><strong>Alcohol use</strong>Occasional.</div>
      </div>
    </section>

    <section class="section">
      <div class="section-title">Notes and observations</div>
      <div class="notes">
        <div class="note-card">
          <strong>Notes</strong>
          <p>Patient reports taking the prescribed medication consistently. Continue home blood pressure log and bring readings to the next visit.</p>
        </div>
        <div class="note-card">
          <strong>Observations</strong>
          <p>Patient was alert and able to speak comfortably. Blood pressure recorded at 138/88 mmHg. No acute distress documented.</p>
        </div>
      </div>
    </section>

    <footer class="footer">
      <span>CareNavigator PH test fixture - no clinical use</span>
      <span>Page 1 of 1</span>
    </footer>
  </main>
</body>
</html>`;

const browser = await chromium.launch({
  executablePath: 'C:\\Program Files (x86)\\Microsoft\\Edge\\Application\\msedge.exe',
  headless: true,
});

try {
  const page = await browser.newPage({ viewport: { width: 794, height: 1123 } });
  await page.setContent(html, { waitUntil: 'load' });
  await page.emulateMedia({ media: 'print' });
  await page.pdf({
    path: outputPath.pathname.replace(/^\/(.:)/, '$1'),
    format: 'A4',
    printBackground: true,
    preferCSSPageSize: true,
  });
  await page.emulateMedia({ media: 'screen' });
  await page.screenshot({
    path: previewPath.pathname.replace(/^\/(.:)/, '$1'),
    fullPage: true,
  });
} finally {
  await browser.close();
}

console.log(outputPath.pathname.replace(/^\/(.:)/, '$1'));
