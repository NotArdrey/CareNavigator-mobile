import { randomBytes } from 'node:crypto';
import { readFile, writeFile } from 'node:fs/promises';

const projectRoot = new URL('../', import.meta.url);
const envText = await readFile(new URL('env', projectRoot), 'utf8');
const config = Object.fromEntries(
  envText
    .split(/\r?\n/)
    .map((line) => line.match(/^\s*([^#=][^=]*)=(.*)$/))
    .filter(Boolean)
    .map((match) => [match[1].trim(), match[2].trim()]),
);

const projectId = config.SUPABASE_PROJECT_ID;
const accessToken = config.SUPABASE_ACCESS_TOKEN;
const supabaseUrl = config.NEXT_PUBLIC_SUPABASE_URL;
if (!projectId || !accessToken || !supabaseUrl) {
  throw new Error('The project ID, access token, and Supabase URL are required.');
}

const managementResponse = await fetch(
  `https://api.supabase.com/v1/projects/${projectId}/api-keys`,
  { headers: { Authorization: `Bearer ${accessToken}` } },
);
const managementKeys = await readJson(managementResponse, 'load project API keys');
const serviceKeyRecord = managementKeys.find(
  (record) => record.name === 'service_role' && record.disabled !== true,
);
const serviceKey = serviceKeyRecord?.api_key ?? serviceKeyRecord?.apiKey;
if (!serviceKey) throw new Error('An active service-role key was not returned.');

const password = `UiAudit-${randomBytes(12).toString('base64url')}aA1!`;
const suffix = Date.now().toString(36);
const roles = await rest('roles?select=id,role_name');
const roleIds = Object.fromEntries(roles.map((role) => [role.role_name, role.id]));
const hospitals = await rest(
  'hospitals?select=id,hospital_name&verification_status=eq.verified&order=created_at.asc&limit=1',
);
const hospital = hospitals[0];
if (!hospital) throw new Error('A verified hospital is required for role fixtures.');

const definitions = [
  { key: 'patient', role: 'patient', firstName: 'UI Audit', lastName: 'Patient' },
  { key: 'doctor', role: 'doctor', firstName: 'UI Audit', lastName: 'Doctor' },
  { key: 'hospitalAdmin', role: 'hospital_admin', firstName: 'UI Audit', lastName: 'Hospital Admin' },
  { key: 'superAdmin', role: 'super_admin', firstName: 'UI Audit', lastName: 'Super Admin' },
];

const accounts = {};
try {
  for (const definition of definitions) {
    const email = `ui.audit.${definition.key}.${suffix}@demo.test`.toLowerCase();
    const authUser = await authAdmin('POST', '/users', {
      email,
      password,
      email_confirm: true,
      user_metadata: {
        first_name: definition.firstName,
        last_name: definition.lastName,
        mobile_number: '09171234567',
        birth_date: '1990-01-15',
        sex: 'female',
        address: 'Manila City, Metro Manila',
      },
    });
    const userId = authUser.id;
    await rest(`users?id=eq.${userId}`, {
      method: 'PATCH',
      body: {
        role_id: roleIds[definition.role],
        first_name: definition.firstName,
        last_name: definition.lastName,
        hospital_id: ['doctor', 'hospital_admin'].includes(definition.role)
          ? hospital.id
          : null,
        account_status: 'active',
      },
    });
    accounts[definition.key] = { email, userId, role: definition.role };
  }

  const patientRows = await rest('patients?select=id', {
    method: 'POST',
    body: {
      user_id: accounts.patient.userId,
      patient_number: `UI-${suffix.toUpperCase()}`,
      primary_hospital_id: hospital.id,
      identity_verification_status: 'verified',
      account_activation_status: 'active',
      profile_status: 'official',
      activated_at: new Date().toISOString(),
    },
    prefer: 'return=representation',
  });
  accounts.patient.patientId = patientRows[0].id;

  const doctorRows = await rest('doctors?select=id', {
    method: 'POST',
    body: {
      user_id: accounts.doctor.userId,
      hospital_id: hospital.id,
      display_name: 'Dr. UI Audit Doctor',
      specialization: 'Internal Medicine',
      license_number: `UI-AUDIT-${suffix.toUpperCase()}`,
      availability_status: 'available',
      consultation_fee: 500,
      biography: 'Disposable clinician identity for UI CRUD verification.',
    },
    prefer: 'return=representation',
  });
  accounts.doctor.doctorId = doctorRows[0].id;

  const assignments = await rest('doctor_patient_assignments?select=id', {
    method: 'POST',
    body: {
      doctor_id: accounts.doctor.doctorId,
      patient_id: accounts.patient.patientId,
      notes: 'UI CRUD audit fixture relationship',
    },
    prefer: 'return=representation',
  });

  const state = {
    createdAt: new Date().toISOString(),
    password,
    hospital,
    accounts,
    assignmentId: assignments[0].id,
  };
  await writeFile(
    new URL('.codex-runtime/ui-audit-state.json', projectRoot),
    `${JSON.stringify(state, null, 2)}\n`,
    { mode: 0o600 },
  );
  console.log(JSON.stringify({
    created: Object.fromEntries(
      Object.entries(accounts).map(([key, account]) => [key, {
        email: account.email,
        userId: account.userId,
      }]),
    ),
    hospital,
    assignmentId: state.assignmentId,
  }, null, 2));
} catch (error) {
  for (const account of Object.values(accounts).reverse()) {
    await authAdmin('DELETE', `/users/${account.userId}`).catch(() => {});
  }
  throw error;
}

async function rest(path, options = {}) {
  const headers = {
    apikey: serviceKey,
    Authorization: `Bearer ${serviceKey}`,
    'Content-Type': 'application/json',
    Prefer: options.prefer ?? 'return=minimal',
  };
  const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
    method: options.method ?? 'GET',
    headers,
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  if (response.status === 204) return [];
  return readJson(response, `${options.method ?? 'GET'} ${path}`);
}

async function authAdmin(method, path, body) {
  const response = await fetch(`${supabaseUrl}/auth/v1/admin${path}`, {
    method,
    headers: {
      apikey: serviceKey,
      Authorization: `Bearer ${serviceKey}`,
      'Content-Type': 'application/json',
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (response.status === 204) return {};
  return readJson(response, `${method} auth admin ${path}`);
}

async function readJson(response, operation) {
  const text = await response.text();
  let data;
  try {
    data = text ? JSON.parse(text) : {};
  } catch {
    data = { message: text };
  }
  if (!response.ok) {
    throw new Error(`${operation} failed (${response.status}): ${JSON.stringify(data)}`);
  }
  return data;
}
