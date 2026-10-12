import {defineConfig} from '@playwright/test';
import {fileURLToPath} from 'node:url';
const artifacts=fileURLToPath(new URL('../.codex-runtime/repair-browser/',import.meta.url));
export default defineConfig({testDir:'browser',testMatch:'*.spec.mjs',workers:1,
  timeout:120000,reporter:[['list'],['json',{outputFile:artifacts+'playwright-results.json'}]],
  outputDir:artifacts+'test-results',use:{timezoneId:'Asia/Manila'}});
