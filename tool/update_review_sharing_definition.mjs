import {readFile} from 'node:fs/promises';
import {sql} from './repair_backend.mjs';
await sql(await readFile('supabase/migrations/20261011172038_patient_document_review_sharing.sql','utf8'));
console.log('Installed verified-recipient employment check for patient document sharing.');
