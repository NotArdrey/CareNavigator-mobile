import {readFile} from 'node:fs/promises';
import {sql} from './repair_backend.mjs';
const d=JSON.parse(await readFile('.codex-runtime/repair-upload-fixture.json','utf8'));
console.log(await sql(`select g.status,g.receiving_doctor_id is null as no_doctor,g.receiving_hospital_id is null as no_receiving_hospital,
private.has_active_doctor_employment(g.receiving_doctor_id,g.receiving_hospital_id) as active_employment,
exists(select 1 from public.patient_access_scopes s where s.grant_id=g.id and s.record_category='medical_documents') as document_scope,
g.revoked_at is null as not_revoked,g.expires_at>now() as not_expired
from public.patient_access_grants g where g.patient_id='${d.patient_id}' and g.status='active'`));
