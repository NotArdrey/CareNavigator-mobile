import { randomBytes } from 'node:crypto';
import { mkdir, readFile, writeFile } from 'node:fs/promises';

const projectRoot = new URL('../', import.meta.url);
const envText = await readFile(new URL('env', projectRoot), 'utf8');
const config = Object.fromEntries(
  envText
    .split(/\r?\n/)
    .map((line) => line.match(/^\s*([^#=][^=]*)=(.*)$/))
    .filter(Boolean)
    .map((match) => [match[1].trim(), match[2].trim()]),
);

const projectId = process.env.SUPABASE_PROJECT_ID ?? config.SUPABASE_PROJECT_ID;
const accessToken = process.env.SUPABASE_ACCESS_TOKEN ?? config.SUPABASE_ACCESS_TOKEN;
const supabaseUrl = process.env.NEXT_PUBLIC_SUPABASE_URL ?? config.NEXT_PUBLIC_SUPABASE_URL;
if (!projectId || !accessToken || !supabaseUrl) {
  throw new Error('SUPABASE_PROJECT_ID, SUPABASE_ACCESS_TOKEN, and NEXT_PUBLIC_SUPABASE_URL are required in env.');
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

const password = `CareNav-${randomBytes(14).toString('base64url')}aA1!`;
const roles = await rest('roles?select=id,role_name');
const roleIds = Object.fromEntries(roles.map((role) => [role.role_name, role.id]));
for (const role of ['doctor', 'hospital_admin', 'patient']) {
  if (!roleIds[role]) throw new Error(`The ${role} role is not configured.`);
}

const hospitals = await rest(
  'hospitals?select=id,hospital_name,city,province&verification_status=eq.verified&operating_status=eq.open&order=hospital_name.asc',
);
const hospitalById = Object.fromEntries(hospitals.map((hospital) => [hospital.id, hospital]));
const definitions = [
  {
    slug: 'aurora', hospitalId: '20000000-0000-4000-8000-000000000007',
    doctor: ['Liza Mae', 'Villanueva', 'female', '1984-04-18', '09175501001', 'Family Medicine', 650, 'Baler, Aurora'],
    admin: ['Ramon', 'Castillo', 'male', '1987-08-09', '09175502001', 'Baler, Aurora'],
    patient: ['Angela', 'Domingo', 'female', '1998-02-23', '09175503001', 'Baler, Aurora', 'A+', ['Shellfish'], ['Asthma']],
  },
  {
    slug: 'bulacan', hospitalId: '20000000-0000-4000-8000-000000000003',
    doctor: ['Carlo', 'Mendoza', 'male', '1981-12-05', '09175501002', 'Neurology', 900, 'Malolos City, Bulacan'],
    admin: ['Patricia', 'Soriano', 'female', '1990-06-14', '09175502002', 'Malolos City, Bulacan'],
    patient: ['Paolo', 'Mercado', 'male', '1992-10-11', '09175503002', 'Malolos City, Bulacan', 'O+', [], ['Migraine']],
  },
  {
    slug: 'cabanatuan', hospitalId: '20000000-0000-4000-8000-000000000004',
    doctor: ['Andrea', 'Bautista', 'female', '1983-09-27', '09175501003', 'Cardiology', 1000, 'Cabanatuan City, Nueva Ecija'],
    admin: ['Joel', 'Pascual', 'male', '1986-03-30', '09175502003', 'Cabanatuan City, Nueva Ecija'],
    patient: ['Marites', 'Santiago', 'female', '1976-07-19', '09175503003', 'Cabanatuan City, Nueva Ecija', 'B+', ['Ibuprofen'], ['Hypertension']],
  },
  {
    slug: 'zambales', hospitalId: '20000000-0000-4000-8000-000000000006',
    doctor: ['Miguel', 'Ramos', 'male', '1988-01-16', '09175501004', 'Family Medicine', 700, 'Iba, Zambales'],
    admin: ['Grace', 'Manalo', 'female', '1989-11-08', '09175502004', 'Iba, Zambales'],
    patient: ['Renato', 'De Guzman', 'male', '1968-05-07', '09175503004', 'Iba, Zambales', 'AB+', [], ['Type 2 diabetes']],
  },
  {
    slug: 'tarlac', hospitalId: '20000000-0000-4000-8000-000000000005',
    doctor: ['Nina', 'Aquino', 'female', '1985-07-22', '09175501005', 'Nephrology', 950, 'Tarlac City, Tarlac'],
    admin: ['Dennis', 'Lacson', 'male', '1984-10-12', '09175502005', 'Tarlac City, Tarlac'],
    patient: ['Jasmine', 'Navarro', 'female', '2000-01-29', '09175503005', 'Tarlac City, Tarlac', 'O-', ['Penicillin'], []],
  },
];

for (const definition of definitions) {
  if (!hospitalById[definition.hospitalId]) {
    throw new Error(`Verified hospital ${definition.hospitalId} is unavailable.`);
  }
}

const existingAuthUsers = await listAllAuthUsers();
const authByEmail = new Map(existingAuthUsers.map((user) => [user.email?.toLowerCase(), user]));
const createdAuthIds = [];
const accounts = [];

try {
  for (const [index, definition] of definitions.entries()) {
    const hospital = hospitalById[definition.hospitalId];
    const [doctorFirst, doctorLast, doctorSex, doctorBirth, doctorMobile, specialization, fee, doctorAddress] = definition.doctor;
    const [adminFirst, adminLast, adminSex, adminBirth, adminMobile, adminAddress] = definition.admin;
    const [patientFirst, patientLast, patientSex, patientBirth, patientMobile, patientAddress, bloodType, allergies, conditions] = definition.patient;

    const doctorEmail = `doctor.${definition.slug}@demo.test`;
    const doctorAuth = await ensureAuthUser(doctorEmail, {
      first_name: doctorFirst, last_name: doctorLast, mobile_number: doctorMobile,
      birth_date: doctorBirth, sex: doctorSex, address: doctorAddress,
    });
    await patchUser(doctorAuth.id, {
      role_id: roleIds.doctor, first_name: doctorFirst, last_name: doctorLast,
      email: doctorEmail, mobile_number: doctorMobile, birth_date: doctorBirth,
      sex: doctorSex, address: doctorAddress, hospital_id: definition.hospitalId,
      account_status: 'active',
    });
    const departments = await rest(
      `hospital_departments?select=id,department_name&hospital_id=eq.${definition.hospitalId}&department_name=eq.${encodeURIComponent(specialization)}&limit=1`,
    );
    if (!departments[0]) throw new Error(`${specialization} is not configured for ${hospital.hospital_name}.`);
    const doctorRows = await rest('doctors?on_conflict=user_id&select=id', {
      method: 'POST',
      prefer: 'resolution=merge-duplicates,return=representation',
      body: {
        user_id: doctorAuth.id, hospital_id: definition.hospitalId,
        department_id: departments[0].id, display_name: `Dr. ${doctorFirst} ${doctorLast}`,
        specialization, license_number: `DEMO-PRC-${String(index + 1003).padStart(4, '0')}`,
        availability_status: 'available', consultation_fee: fee,
        biography: `${specialization} physician serving patients in ${hospital.city ?? hospital.province}. This is a synthetic demo profile.`,
      },
    });
    await replaceSchedules(doctorRows[0].id, index);
    accounts.push({ role: 'doctor', email: doctorEmail, name: `Dr. ${doctorFirst} ${doctorLast}`, hospital: hospital.hospital_name });

    const adminEmail = `admin.${definition.slug}@demo.test`;
    const adminAuth = await ensureAuthUser(adminEmail, {
      first_name: adminFirst, last_name: adminLast, mobile_number: adminMobile,
      birth_date: adminBirth, sex: adminSex, address: adminAddress,
    });
    await patchUser(adminAuth.id, {
      role_id: roleIds.hospital_admin, first_name: adminFirst, last_name: adminLast,
      email: adminEmail, mobile_number: adminMobile, birth_date: adminBirth,
      sex: adminSex, address: adminAddress, hospital_id: definition.hospitalId,
      account_status: 'active',
    });
    accounts.push({ role: 'hospital_admin', email: adminEmail, name: `${adminFirst} ${adminLast}`, hospital: hospital.hospital_name });

    const patientEmail = `patient.${definition.slug}@demo.test`;
    const patientAuth = await ensureAuthUser(patientEmail, {
      first_name: patientFirst, last_name: patientLast, mobile_number: patientMobile,
      birth_date: patientBirth, sex: patientSex, address: patientAddress,
      registration_source: 'patient_self_service',
    });
    await patchUser(patientAuth.id, {
      role_id: roleIds.patient, first_name: patientFirst, last_name: patientLast,
      email: patientEmail, mobile_number: patientMobile, birth_date: patientBirth,
      sex: patientSex, address: patientAddress, hospital_id: null,
      account_status: 'active',
    });
    await rest('patients?on_conflict=user_id', {
      method: 'POST',
      prefer: 'resolution=merge-duplicates,return=minimal',
      body: {
        user_id: patientAuth.id, patient_number: `CNPH-DEMO-${String(index + 1).padStart(3, '0')}`,
        primary_hospital_id: definition.hospitalId, blood_type: bloodType,
        emergency_contact: {
          name: `${patientLast} Family Contact`, relationship: 'Family',
          phone: `09175504${String(index + 1).padStart(3, '0')}`,
        },
        allergies, existing_conditions: conditions,
        identity_verification_status: 'verified', account_activation_status: 'active',
        profile_status: 'official', activated_at: new Date().toISOString(),
      },
    });
    accounts.push({ role: 'patient', email: patientEmail, name: `${patientFirst} ${patientLast}`, hospital: hospital.hospital_name });
  }

  await repairSyntheticAuditProfiles();
  await mkdir(new URL('.codex-runtime/', projectRoot), { recursive: true });
  const credentialsPath = new URL('.codex-runtime/demo-account-credentials.json', projectRoot);
  await writeFile(credentialsPath, `${JSON.stringify({
    createdAt: new Date().toISOString(),
    note: 'Synthetic demo accounts only. Do not use in production.',
    password,
    accounts,
  }, null, 2)}\n`, { mode: 0o600 });
  console.log(JSON.stringify({ createdOrUpdated: accounts.length, credentialsPath: credentialsPath.pathname, accounts }, null, 2));
} catch (error) {
  for (const id of createdAuthIds.reverse()) {
    await authAdmin('DELETE', `/users/${id}`).catch(() => {});
  }
  throw error;
}

async function ensureAuthUser(email, metadata) {
  const verifiedMetadata = { ...metadata, email_verified: true };
  const existing = authByEmail.get(email.toLowerCase());
  if (existing) {
    return authAdmin('PUT', `/users/${existing.id}`, {
      password, email_confirm: true, user_metadata: verifiedMetadata,
    });
  }
  const created = await authAdmin('POST', '/users', {
    email, password, email_confirm: true, user_metadata: verifiedMetadata,
  });
  createdAuthIds.push(created.id);
  authByEmail.set(email.toLowerCase(), created);
  return created;
}

async function patchUser(id, body) {
  await rest(`users?id=eq.${id}`, { method: 'PATCH', body });
}

async function replaceSchedules(doctorId, index) {
  await rest(`doctor_schedules?doctor_id=eq.${doctorId}`, { method: 'DELETE' });
  const firstDay = 1 + (index % 2);
  await rest('doctor_schedules', {
    method: 'POST',
    body: [firstDay, firstDay + 2, firstDay + 4].map((day) => ({
      doctor_id: doctorId, day_of_week: day, starts_at: '09:00:00', ends_at: '16:00:00',
      consultation_type: day === firstDay + 2 ? 'online' : 'face_to_face', slot_minutes: 30, is_active: true,
    })),
  });
}

async function repairSyntheticAuditProfiles() {
  const rows = await rest('users?select=id,email,role_id,first_name,last_name,mobile_number,birth_date,sex,address&email=like.ui.audit.*@demo.test');
  let suffix = 0;
  for (const row of rows) {
    const missing = !row.mobile_number || !row.birth_date || !row.sex || !row.address;
    if (missing) {
      suffix += 1;
      await patchUser(row.id, {
        first_name: row.first_name || 'UI Audit', last_name: row.last_name || 'Account',
        mobile_number: `09175509${String(suffix).padStart(3, '0')}`,
        birth_date: '1990-01-15', sex: 'female', address: 'City of San Fernando, Pampanga',
        account_status: 'active',
      });
    }

    if (row.role_id === roleIds.doctor) {
      const doctorRows = await rest(`doctors?select=id,hospital_id,department_id,consultation_fee,biography&user_id=eq.${row.id}&limit=1`);
      const doctor = doctorRows[0];
      if (doctor && (!doctor.department_id || !doctor.consultation_fee || !doctor.biography)) {
        const departments = await rest(
          `hospital_departments?select=id&hospital_id=eq.${doctor.hospital_id}&department_name=eq.Internal%20Medicine&limit=1`,
        );
        await rest(`doctors?id=eq.${doctor.id}`, {
          method: 'PATCH',
          body: {
            department_id: doctor.department_id ?? departments[0]?.id ?? null,
            consultation_fee: doctor.consultation_fee ?? 500,
            biography: doctor.biography ?? 'Synthetic clinician profile used for CareNavigator interface verification.',
          },
        });
      }
    }

    if (row.role_id === roleIds.patient) {
      const patientRows = await rest(`patients?select=id,patient_number,primary_hospital_id,blood_type,emergency_contact&user_id=eq.${row.id}&limit=1`);
      const patient = patientRows[0];
      if (patient && (!patient.patient_number || !patient.primary_hospital_id || !patient.blood_type || Object.keys(patient.emergency_contact ?? {}).length === 0)) {
        await rest(`patients?id=eq.${patient.id}`, {
          method: 'PATCH',
          body: {
            patient_number: patient.patient_number ?? `UI-AUDIT-${row.id.slice(0, 8).toUpperCase()}`,
            primary_hospital_id: patient.primary_hospital_id ?? hospitals[0].id,
            blood_type: patient.blood_type ?? 'O+',
            emergency_contact: Object.keys(patient.emergency_contact ?? {}).length > 0
              ? patient.emergency_contact
              : { name: 'UI Audit Contact', relationship: 'Family', phone: '09175509999' },
            identity_verification_status: 'verified', account_activation_status: 'active', profile_status: 'official',
          },
        });
      }
    }
  }
}

async function listAllAuthUsers() {
  const users = [];
  for (let page = 1; ; page += 1) {
    const response = await authAdmin('GET', `/users?page=${page}&per_page=100`);
    const batch = response.users ?? [];
    users.push(...batch);
    if (batch.length < 100) return users;
  }
}

async function rest(path, options = {}) {
  const response = await fetch(`${supabaseUrl}/rest/v1/${path}`, {
    method: options.method ?? 'GET',
    headers: {
      apikey: serviceKey, Authorization: `Bearer ${serviceKey}`,
      'Content-Type': 'application/json', Prefer: options.prefer ?? 'return=minimal',
    },
    body: options.body === undefined ? undefined : JSON.stringify(options.body),
  });
  if (response.status === 204) return [];
  return readJson(response, `${options.method ?? 'GET'} ${path}`);
}

async function authAdmin(method, path, body) {
  const response = await fetch(`${supabaseUrl}/auth/v1/admin${path}`, {
    method,
    headers: {
      apikey: serviceKey, Authorization: `Bearer ${serviceKey}`,
      'Content-Type': 'application/json',
    },
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  if (response.status === 204) return {};
  return readJson(response, `${method} auth admin ${path}`);
}

async function readJson(response, operation) {
  const text = await response.text();
  const parsed = text ? JSON.parse(text) : {};
  if (!response.ok) throw new Error(`${operation} failed (${response.status}): ${text}`);
  return parsed;
}
