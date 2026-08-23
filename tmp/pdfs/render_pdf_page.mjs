import { readFile, writeFile } from 'node:fs/promises';
import { createCanvas } from './runtime/node_modules/@napi-rs/canvas/index.js';
import * as pdfjs from './runtime/node_modules/pdfjs-dist/legacy/build/pdf.mjs';

const inputPath = new URL(
  '../../output/pdf/synthetic_follow_up_checkup_test.pdf',
  import.meta.url,
);
const outputPath = new URL('synthetic_follow_up_checkup_page_1.png', import.meta.url);
const data = new Uint8Array(await readFile(inputPath));
const document = await pdfjs.getDocument({ data, disableWorker: true }).promise;
if (document.numPages !== 1) {
  throw new Error(`Expected one page, found ${document.numPages}.`);
}

const page = await document.getPage(1);
const textContent = await page.getTextContent();
const extractedText = textContent.items.map((item) => item.str ?? '').join(' ');
for (const expected of [
  'Follow-up Checkup Summary',
  '138/88 mmHg',
  'Amlodipine 5 mg once daily',
  'Notes and observations',
  'SYNTHETIC RECORD',
]) {
  if (!extractedText.includes(expected)) {
    throw new Error(`Expected PDF text was missing: ${expected}`);
  }
}
const viewport = page.getViewport({ scale: 2 });
const canvas = createCanvas(Math.ceil(viewport.width), Math.ceil(viewport.height));
const context = canvas.getContext('2d');
context.fillStyle = '#ffffff';
context.fillRect(0, 0, canvas.width, canvas.height);
await page.render({ canvasContext: context, viewport }).promise;
await writeFile(outputPath, canvas.toBuffer('image/png'));
console.log(`Verified ${document.numPages} page with ${extractedText.length} extracted characters.`);
console.log(outputPath.pathname.replace(/^\/(.:)/, '$1'));
