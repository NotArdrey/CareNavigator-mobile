import { readFile, writeFile, mkdir } from 'node:fs/promises';
import path from 'node:path';
import { createCanvas } from '../pdfs/runtime/node_modules/@napi-rs/canvas/index.js';
import * as pdfjs from '../pdfs/runtime/node_modules/pdfjs-dist/legacy/build/pdf.mjs';

const [inputPath, outputDir] = process.argv.slice(2);
if (!inputPath || !outputDir) throw new Error('Usage: node render_pdf_pages.mjs input.pdf output-dir');
await mkdir(outputDir, { recursive: true });
const data = new Uint8Array(await readFile(inputPath));
const pdf = await pdfjs.getDocument({ data, disableWorker: true }).promise;
for (let pageNumber = 1; pageNumber <= pdf.numPages; pageNumber += 1) {
  const page = await pdf.getPage(pageNumber);
  const viewport = page.getViewport({ scale: 1.5 });
  const canvas = createCanvas(Math.ceil(viewport.width), Math.ceil(viewport.height));
  const context = canvas.getContext('2d');
  context.fillStyle = '#ffffff';
  context.fillRect(0, 0, canvas.width, canvas.height);
  await page.render({ canvasContext: context, viewport }).promise;
  const filename = `page-${String(pageNumber).padStart(2, '0')}.png`;
  await writeFile(path.join(outputDir, filename), canvas.toBuffer('image/png'));
}
console.log(JSON.stringify({ pages: pdf.numPages, outputDir }));
