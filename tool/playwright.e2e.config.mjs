import {defineConfig} from '@playwright/test';
import {fileURLToPath} from 'node:url';
const artifacts=fileURLToPath(new URL('../.codex-runtime/e2e/',import.meta.url));
export default defineConfig({testDir:'e2e_browser',testMatch:'*.spec.mjs',workers:1,
  timeout:120000,expect:{timeout:15000},
  reporter:[['list'],['json',{outputFile:artifacts+'playwright-results.json'}]],
  outputDir:'../.codex-runtime/e2e/test-results',use:{timezoneId:'Asia/Manila',actionTimeout:15000}});
