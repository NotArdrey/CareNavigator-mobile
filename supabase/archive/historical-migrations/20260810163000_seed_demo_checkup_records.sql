-- Give the built-in John Reyes patient account realistic structured clinical
-- history without changing the standardized identity profile.
update public.medical_records as record
set
  height_cm = 174.0,
  weight_kg = 73.0,
  bmi = round(73.0 / power(174.0 / 100, 2), 2),
  blood_pressure_systolic = 128,
  blood_pressure_diastolic = 82,
  body_temperature_c = 37.0,
  heart_rate_bpm = 78,
  respiratory_rate_bpm = 16,
  oxygen_saturation_percent = 98,
  vitals_recorded_at = '2025-12-19 09:20:00+00'::timestamptz,
  current_symptoms = 'Persistent cough and occasional wheezing.',
  known_medical_conditions = array['Mild persistent asthma', 'Hypertension']::text[],
  allergies = array['Penicillin']::text[],
  current_medications = array['Salbutamol inhaler as needed']::text[],
  relevant_medical_history = 'Asthma diagnosed in childhood; hypertension monitored since 2024.',
  previous_surgeries = 'Appendectomy (2018).',
  smoking_status = 'never',
  alcohol_use = 'occasional',
  pregnancy_status = 'not_applicable',
  doctor_notes = 'Alert and oriented; no acute distress. Continue inhaler plan and reassess respiratory symptoms.'
from public.patients as patient
join public.users as app_user on app_user.id = patient.user_id
where record.patient_id = patient.id
  and lower(app_user.email) = 'patient@demo.test'
  and record.record_type = 'consultation_summary'
  and record.title = 'Respiratory consultation';

update public.medical_records as record
set
  height_cm = 174.0,
  weight_kg = 75.2,
  bmi = round(75.2 / power(174.0 / 100, 2), 2),
  blood_pressure_systolic = 138,
  blood_pressure_diastolic = 86,
  body_temperature_c = 36.8,
  heart_rate_bpm = 82,
  respiratory_rate_bpm = 16,
  oxygen_saturation_percent = 97,
  vitals_recorded_at = '2025-05-19 14:20:00+00'::timestamptz,
  current_symptoms = 'Occasional morning headache; no chest pain or shortness of breath.',
  known_medical_conditions = array['Hypertension']::text[],
  allergies = array['Penicillin']::text[],
  current_medications = array['Amlodipine 5 mg daily']::text[],
  relevant_medical_history = 'Family history of hypertension.',
  previous_surgeries = '{}'::text,
  smoking_status = 'never',
  alcohol_use = 'occasional',
  pregnancy_status = 'not_applicable',
  doctor_notes = 'Blood pressure remains above target; continue home BP log and low-sodium diet.'
from public.patients as patient
join public.users as app_user on app_user.id = patient.user_id
where record.patient_id = patient.id
  and lower(app_user.email) = 'patient@demo.test'
  and record.record_type = 'consultation_summary'
  and record.title = 'Hypertension follow-up';

with demo_context as (
  select
    patient.id as patient_id,
    doctor.id as doctor_id,
    doctor.hospital_id
  from public.patients as patient
  join public.users as patient_user on patient_user.id = patient.user_id
  cross join public.doctors as doctor
  join public.users as doctor_user on doctor_user.id = doctor.user_id
  where lower(patient_user.email) = 'patient@demo.test'
    and lower(doctor_user.email) = 'doctor@demo.test'
)
insert into public.medical_records(
  patient_id,
  doctor_id,
  hospital_id,
  record_type,
  title,
  description,
  record_date,
  reason_for_visit,
  height_cm,
  weight_kg,
  bmi,
  blood_pressure_systolic,
  blood_pressure_diastolic,
  body_temperature_c,
  heart_rate_bpm,
  respiratory_rate_bpm,
  oxygen_saturation_percent,
  vitals_recorded_at,
  current_symptoms,
  known_medical_conditions,
  allergies,
  current_medications,
  relevant_medical_history,
  previous_surgeries,
  smoking_status,
  alcohol_use,
  pregnancy_status,
  doctor_notes
)
select
  demo.patient_id,
  demo.doctor_id,
  demo.hospital_id,
  'checkup',
  'Routine follow-up checkup',
  'Routine monitoring visit with stable examination findings.',
  '2026-08-08'::date,
  'Routine blood pressure and respiratory follow-up',
  174.0,
  72.5,
  round(72.5 / power(174.0 / 100, 2), 2),
  126,
  80,
  36.8,
  76,
  16,
  98,
  '2026-08-08 09:15:00+08'::timestamptz,
  'No acute symptoms; occasional morning wheeze reported.',
  array['Mild persistent asthma', 'Hypertension']::text[],
  array['Penicillin']::text[],
  array['Amlodipine 5 mg daily', 'Salbutamol inhaler as needed']::text[],
  'Asthma diagnosed in childhood; hypertension monitored since 2024.',
  'Appendectomy (2018).',
  'never',
  'occasional',
  'not_applicable',
  'Alert and oriented; lungs clear at rest. Continue current medicines and home BP monitoring.'
from demo_context as demo
where not exists (
  select 1
  from public.medical_records as existing
  where existing.patient_id = demo.patient_id
    and existing.record_type = 'checkup'
    and existing.title = 'Routine follow-up checkup'
    and existing.record_date = '2026-08-08'::date
);
