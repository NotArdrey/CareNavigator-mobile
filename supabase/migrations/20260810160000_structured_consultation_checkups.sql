-- Extend the existing consultation and medical-record sources of truth with
-- optional structured checkup data. Identity fields remain in public.users.
alter table public.consultations
  add column if not exists height_cm numeric(5, 2),
  add column if not exists weight_kg numeric(6, 2),
  add column if not exists bmi numeric(5, 2),
  add column if not exists blood_pressure_systolic smallint,
  add column if not exists blood_pressure_diastolic smallint,
  add column if not exists body_temperature_c numeric(4, 1),
  add column if not exists heart_rate_bpm smallint,
  add column if not exists respiratory_rate_bpm smallint,
  add column if not exists oxygen_saturation_percent numeric(5, 2),
  add column if not exists vitals_recorded_at timestamptz,
  add column if not exists current_symptoms text,
  add column if not exists known_medical_conditions text[] not null default '{}'::text[],
  add column if not exists allergies text[] not null default '{}'::text[],
  add column if not exists current_medications text[] not null default '{}'::text[],
  add column if not exists relevant_medical_history text,
  add column if not exists previous_surgeries text,
  add column if not exists smoking_status text,
  add column if not exists alcohol_use text,
  add column if not exists pregnancy_status text;

alter table public.medical_records
  add column if not exists reason_for_visit text,
  add column if not exists height_cm numeric(5, 2),
  add column if not exists weight_kg numeric(6, 2),
  add column if not exists bmi numeric(5, 2),
  add column if not exists blood_pressure_systolic smallint,
  add column if not exists blood_pressure_diastolic smallint,
  add column if not exists body_temperature_c numeric(4, 1),
  add column if not exists heart_rate_bpm smallint,
  add column if not exists respiratory_rate_bpm smallint,
  add column if not exists oxygen_saturation_percent numeric(5, 2),
  add column if not exists vitals_recorded_at timestamptz,
  add column if not exists current_symptoms text,
  add column if not exists known_medical_conditions text[] not null default '{}'::text[],
  add column if not exists allergies text[] not null default '{}'::text[],
  add column if not exists current_medications text[] not null default '{}'::text[],
  add column if not exists relevant_medical_history text,
  add column if not exists previous_surgeries text,
  add column if not exists smoking_status text,
  add column if not exists alcohol_use text,
  add column if not exists pregnancy_status text,
  add column if not exists doctor_notes text;

do $$
begin
  if not exists (
    select 1 from pg_constraint
    where conname = 'consultations_checkup_vitals_range'
  ) then
    alter table public.consultations
      add constraint consultations_checkup_vitals_range check (
        (height_cm is null or height_cm between 30 and 250)
        and (weight_kg is null or weight_kg between 1 and 500)
        and (bmi is null or bmi > 0)
        and (blood_pressure_systolic is null or blood_pressure_systolic between 50 and 300)
        and (blood_pressure_diastolic is null or blood_pressure_diastolic between 30 and 200)
        and (
          blood_pressure_systolic is null
          or blood_pressure_diastolic is null
          or blood_pressure_systolic > blood_pressure_diastolic
        )
        and (body_temperature_c is null or body_temperature_c between 25 and 45)
        and (heart_rate_bpm is null or heart_rate_bpm between 20 and 250)
        and (respiratory_rate_bpm is null or respiratory_rate_bpm between 5 and 80)
        and (oxygen_saturation_percent is null or oxygen_saturation_percent between 50 and 100)
      );
  end if;
  if not exists (
    select 1 from pg_constraint
    where conname = 'medical_records_checkup_vitals_range'
  ) then
    alter table public.medical_records
      add constraint medical_records_checkup_vitals_range check (
        (height_cm is null or height_cm between 30 and 250)
        and (weight_kg is null or weight_kg between 1 and 500)
        and (bmi is null or bmi > 0)
        and (blood_pressure_systolic is null or blood_pressure_systolic between 50 and 300)
        and (blood_pressure_diastolic is null or blood_pressure_diastolic between 30 and 200)
        and (
          blood_pressure_systolic is null
          or blood_pressure_diastolic is null
          or blood_pressure_systolic > blood_pressure_diastolic
        )
        and (body_temperature_c is null or body_temperature_c between 25 and 45)
        and (heart_rate_bpm is null or heart_rate_bpm between 20 and 250)
        and (respiratory_rate_bpm is null or respiratory_rate_bpm between 5 and 80)
        and (oxygen_saturation_percent is null or oxygen_saturation_percent between 50 and 100)
      );
  end if;
end;
$$;

create unique index if not exists medical_records_consultation_checkup_unique
  on public.medical_records (consultation_id)
  where consultation_id is not null and record_type = 'consultation_checkup';

create or replace function public.transition_consultation(
  target_consultation_id uuid,
  target_status public.consultation_status,
  transition_notes text default null,
  scheduled_for timestamptz default null,
  clinical_payload jsonb default '{}'::jsonb
)
returns jsonb
language plpgsql
set search_path to ''
as $function$
declare
  result_row public.consultations;
  next_height numeric;
  next_weight numeric;
begin
  if not (
    private.has_permission('consultations.read_own')
    or private.has_permission('hospital.manage')
  ) then
    raise exception 'Consultation workflow permission is required';
  end if;

  select * into result_row
  from public.consultations
  where id = target_consultation_id
  for update;
  if not found or not private.is_consultation_participant(target_consultation_id) then
    raise exception 'Consultation was not found or is not accessible';
  end if;

  if scheduled_for is not null and scheduled_for is distinct from result_row.appointment_date then
    if target_status not in ('approved', 'scheduled') then
      raise exception 'Only an approved or scheduled consultation may be rescheduled';
    end if;
    perform pg_catalog.pg_advisory_xact_lock(
      pg_catalog.hashtextextended(result_row.doctor_id::text || ':' || scheduled_for::date::text, 0)
    );
    if not private.is_doctor_slot_available(
      result_row.doctor_id,
      result_row.hospital_id,
      result_row.consultation_type,
      scheduled_for,
      result_row.id
    ) then
      raise exception 'The selected appointment slot is unavailable';
    end if;
  end if;

  next_height := result_row.height_cm;
  next_weight := result_row.weight_kg;
  if private.current_doctor_id() = result_row.doctor_id then
    if clinical_payload ? 'height_cm' then
      next_height := nullif(btrim(clinical_payload->>'height_cm'), '')::numeric;
    end if;
    if clinical_payload ? 'weight_kg' then
      next_weight := nullif(btrim(clinical_payload->>'weight_kg'), '')::numeric;
    end if;
  end if;

  update public.consultations
  set
    status = target_status,
    appointment_date = coalesce(scheduled_for, appointment_date),
    rejection_reason = case
      when target_status = 'rejected' then nullif(btrim(transition_notes), '')
      else rejection_reason
    end,
    doctor_notes = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'doctor_notes'
        then nullif(btrim(clinical_payload->>'doctor_notes'), '')
      else doctor_notes
    end,
    confirmed_diagnosis = case
      when private.current_doctor_id() = doctor_id
        then coalesce(clinical_payload->>'confirmed_diagnosis', confirmed_diagnosis)
      else confirmed_diagnosis
    end,
    treatment_plan = case
      when private.current_doctor_id() = doctor_id
        then coalesce(clinical_payload->>'treatment_plan', treatment_plan)
      else treatment_plan
    end,
    consultation_summary = case
      when private.current_doctor_id() = doctor_id
        then coalesce(clinical_payload->>'consultation_summary', consultation_summary)
      else consultation_summary
    end,
    height_cm = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'height_cm'
        then next_height
      else height_cm
    end,
    weight_kg = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'weight_kg'
        then next_weight
      else weight_kg
    end,
    bmi = case
      when private.current_doctor_id() = doctor_id
        and (clinical_payload ? 'height_cm' or clinical_payload ? 'weight_kg')
        and next_height is not null
        and next_weight is not null
        then round(next_weight / power(next_height / 100, 2), 2)
      when private.current_doctor_id() = doctor_id
        and (clinical_payload ? 'height_cm' or clinical_payload ? 'weight_kg')
        then null
      else bmi
    end,
    blood_pressure_systolic = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'blood_pressure_systolic'
        then nullif(btrim(clinical_payload->>'blood_pressure_systolic'), '')::smallint
      else blood_pressure_systolic
    end,
    blood_pressure_diastolic = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'blood_pressure_diastolic'
        then nullif(btrim(clinical_payload->>'blood_pressure_diastolic'), '')::smallint
      else blood_pressure_diastolic
    end,
    body_temperature_c = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'body_temperature_c'
        then nullif(btrim(clinical_payload->>'body_temperature_c'), '')::numeric
      else body_temperature_c
    end,
    heart_rate_bpm = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'heart_rate_bpm'
        then nullif(btrim(clinical_payload->>'heart_rate_bpm'), '')::smallint
      else heart_rate_bpm
    end,
    respiratory_rate_bpm = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'respiratory_rate_bpm'
        then nullif(btrim(clinical_payload->>'respiratory_rate_bpm'), '')::smallint
      else respiratory_rate_bpm
    end,
    oxygen_saturation_percent = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'oxygen_saturation_percent'
        then nullif(btrim(clinical_payload->>'oxygen_saturation_percent'), '')::numeric
      else oxygen_saturation_percent
    end,
    vitals_recorded_at = case
      when private.current_doctor_id() = doctor_id
        and (
          nullif(btrim(clinical_payload->>'height_cm'), '') is not null
          or nullif(btrim(clinical_payload->>'weight_kg'), '') is not null
          or nullif(btrim(clinical_payload->>'blood_pressure_systolic'), '') is not null
          or nullif(btrim(clinical_payload->>'blood_pressure_diastolic'), '') is not null
          or nullif(btrim(clinical_payload->>'body_temperature_c'), '') is not null
          or nullif(btrim(clinical_payload->>'heart_rate_bpm'), '') is not null
          or nullif(btrim(clinical_payload->>'respiratory_rate_bpm'), '') is not null
          or nullif(btrim(clinical_payload->>'oxygen_saturation_percent'), '') is not null
        ) then coalesce(vitals_recorded_at, now())
      when private.current_doctor_id() = doctor_id
        and (
          clinical_payload ? 'height_cm'
          or clinical_payload ? 'weight_kg'
          or clinical_payload ? 'blood_pressure_systolic'
          or clinical_payload ? 'blood_pressure_diastolic'
          or clinical_payload ? 'body_temperature_c'
          or clinical_payload ? 'heart_rate_bpm'
          or clinical_payload ? 'respiratory_rate_bpm'
          or clinical_payload ? 'oxygen_saturation_percent'
        ) then null
      else vitals_recorded_at
    end,
    current_symptoms = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'current_symptoms'
        then nullif(btrim(clinical_payload->>'current_symptoms'), '')
      else current_symptoms
    end,
    known_medical_conditions = case
      when private.current_doctor_id() = doctor_id
        and jsonb_typeof(clinical_payload->'known_medical_conditions') = 'array'
        then array(select jsonb_array_elements_text(clinical_payload->'known_medical_conditions'))
      else known_medical_conditions
    end,
    allergies = case
      when private.current_doctor_id() = doctor_id
        and jsonb_typeof(clinical_payload->'allergies') = 'array'
        then array(select jsonb_array_elements_text(clinical_payload->'allergies'))
      else allergies
    end,
    current_medications = case
      when private.current_doctor_id() = doctor_id
        and jsonb_typeof(clinical_payload->'current_medications') = 'array'
        then array(select jsonb_array_elements_text(clinical_payload->'current_medications'))
      else current_medications
    end,
    relevant_medical_history = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'relevant_medical_history'
        then nullif(btrim(clinical_payload->>'relevant_medical_history'), '')
      else relevant_medical_history
    end,
    previous_surgeries = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'previous_surgeries'
        then nullif(btrim(clinical_payload->>'previous_surgeries'), '')
      else previous_surgeries
    end,
    smoking_status = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'smoking_status'
        then nullif(btrim(clinical_payload->>'smoking_status'), '')
      else smoking_status
    end,
    alcohol_use = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'alcohol_use'
        then nullif(btrim(clinical_payload->>'alcohol_use'), '')
      else alcohol_use
    end,
    pregnancy_status = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'pregnancy_status'
        then nullif(btrim(clinical_payload->>'pregnancy_status'), '')
      else pregnancy_status
    end,
    approved_by = case
      when target_status in ('approved', 'scheduled') then private.current_user_id()
      else approved_by
    end,
    approved_at = case
      when target_status in ('approved', 'scheduled') then coalesce(approved_at, now())
      else approved_at
    end,
    rejected_at = case
      when target_status = 'rejected' then now()
      else rejected_at
    end
  where id = target_consultation_id
  returning * into result_row;

  if result_row.guest_request_id is not null then
    update public.guest_consultation_requests
    set request_status = case target_status
      when 'completed' then 'consultation_completed'::public.guest_request_status
      when 'cancelled' then 'cancelled'::public.guest_request_status
      else request_status
    end
    where id = result_row.guest_request_id;
  end if;

  return jsonb_build_object(
    'id', result_row.id,
    'status', result_row.status,
    'appointment_date', result_row.appointment_date,
    'completed_at', result_row.completed_at
  );
end;
$function$;

create or replace function public.sync_completed_consultation_clinical_records()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
begin
  if new.status <> 'completed' or new.patient_id is null then return new; end if;

  if nullif(btrim(new.confirmed_diagnosis), '') is not null then
    insert into public.diagnoses (
      patient_id, consultation_id, doctor_id, hospital_id, diagnosis, is_primary, confirmed_at, source
    ) values (
      new.patient_id, new.id, new.doctor_id, new.hospital_id, btrim(new.confirmed_diagnosis), true,
      coalesce(new.completed_at, now()), 'consultation_completion'
    )
    on conflict (consultation_id) where is_primary do update
    set diagnosis = excluded.diagnosis,
        doctor_id = excluded.doctor_id,
        hospital_id = excluded.hospital_id,
        confirmed_at = excluded.confirmed_at,
        updated_at = now();
  end if;

  if nullif(btrim(new.treatment_plan), '') is not null then
    insert into public.treatment_plans (
      patient_id, consultation_id, doctor_id, hospital_id, plan, status, source
    ) values (
      new.patient_id, new.id, new.doctor_id, new.hospital_id, btrim(new.treatment_plan), 'active', 'consultation_completion'
    )
    on conflict (consultation_id) where source = 'consultation_completion' do update
    set plan = excluded.plan,
        doctor_id = excluded.doctor_id,
        hospital_id = excluded.hospital_id,
        updated_at = now();
  end if;

  insert into public.medical_records (
    patient_id,
    doctor_id,
    hospital_id,
    consultation_id,
    record_type,
    title,
    description,
    confirmed_diagnosis,
    treatment_plan,
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
  ) values (
    new.patient_id,
    new.doctor_id,
    new.hospital_id,
    new.id,
    'consultation_checkup',
    coalesce(nullif(btrim(new.chief_complaint), ''), 'Consultation checkup'),
    nullif(btrim(new.consultation_summary), ''),
    nullif(btrim(new.confirmed_diagnosis), ''),
    nullif(btrim(new.treatment_plan), ''),
    coalesce(new.completed_at, now())::date,
    nullif(btrim(new.chief_complaint), ''),
    new.height_cm,
    new.weight_kg,
    case
      when new.height_cm is not null and new.weight_kg is not null
        then round(new.weight_kg / power(new.height_cm / 100, 2), 2)
      else null
    end,
    new.blood_pressure_systolic,
    new.blood_pressure_diastolic,
    new.body_temperature_c,
    new.heart_rate_bpm,
    new.respiratory_rate_bpm,
    new.oxygen_saturation_percent,
    new.vitals_recorded_at,
    new.current_symptoms,
    coalesce(new.known_medical_conditions, '{}'::text[]),
    coalesce(new.allergies, '{}'::text[]),
    coalesce(new.current_medications, '{}'::text[]),
    new.relevant_medical_history,
    new.previous_surgeries,
    new.smoking_status,
    new.alcohol_use,
    new.pregnancy_status,
    new.doctor_notes
  )
  on conflict (consultation_id) where record_type = 'consultation_checkup' do update
  set title = excluded.title,
      description = excluded.description,
      confirmed_diagnosis = excluded.confirmed_diagnosis,
      treatment_plan = excluded.treatment_plan,
      record_date = excluded.record_date,
      reason_for_visit = excluded.reason_for_visit,
      height_cm = excluded.height_cm,
      weight_kg = excluded.weight_kg,
      bmi = excluded.bmi,
      blood_pressure_systolic = excluded.blood_pressure_systolic,
      blood_pressure_diastolic = excluded.blood_pressure_diastolic,
      body_temperature_c = excluded.body_temperature_c,
      heart_rate_bpm = excluded.heart_rate_bpm,
      respiratory_rate_bpm = excluded.respiratory_rate_bpm,
      oxygen_saturation_percent = excluded.oxygen_saturation_percent,
      vitals_recorded_at = excluded.vitals_recorded_at,
      current_symptoms = excluded.current_symptoms,
      known_medical_conditions = excluded.known_medical_conditions,
      allergies = excluded.allergies,
      current_medications = excluded.current_medications,
      relevant_medical_history = excluded.relevant_medical_history,
      previous_surgeries = excluded.previous_surgeries,
      smoking_status = excluded.smoking_status,
      alcohol_use = excluded.alcohol_use,
      pregnancy_status = excluded.pregnancy_status,
      doctor_notes = excluded.doctor_notes,
      updated_at = now();

  return new;
end;
$function$;

create or replace function public.record_patient_checkup(
  target_patient_id uuid,
  checkup_payload jsonb,
  recorded_at timestamptz default now()
)
returns public.medical_records
language plpgsql
security definer
set search_path to ''
as $function$
declare
  doctor_row public.doctors;
  result_row public.medical_records;
  height_value numeric;
  weight_value numeric;
  systolic_value smallint;
  diastolic_value smallint;
  temperature_value numeric;
  heart_rate_value smallint;
  respiratory_rate_value smallint;
  oxygen_value numeric;
begin
  if not private.has_permission('records.write') then
    raise exception 'Medical record write permission is required';
  end if;
  if checkup_payload is null or jsonb_typeof(checkup_payload) <> 'object' then
    raise exception 'Checkup data must be a JSON object';
  end if;

  select * into doctor_row
  from public.doctors
  where id = private.current_doctor_id();
  if not found or not private.can_access_patient(target_patient_id) then
    raise exception 'Patient record access is not authorized';
  end if;

  height_value := nullif(btrim(checkup_payload->>'height_cm'), '')::numeric;
  weight_value := nullif(btrim(checkup_payload->>'weight_kg'), '')::numeric;
  systolic_value := nullif(btrim(checkup_payload->>'blood_pressure_systolic'), '')::smallint;
  diastolic_value := nullif(btrim(checkup_payload->>'blood_pressure_diastolic'), '')::smallint;
  temperature_value := nullif(btrim(checkup_payload->>'body_temperature_c'), '')::numeric;
  heart_rate_value := nullif(btrim(checkup_payload->>'heart_rate_bpm'), '')::smallint;
  respiratory_rate_value := nullif(btrim(checkup_payload->>'respiratory_rate_bpm'), '')::smallint;
  oxygen_value := nullif(btrim(checkup_payload->>'oxygen_saturation_percent'), '')::numeric;

  if height_value is not null and (height_value < 30 or height_value > 250) then
    raise exception 'Height must be between 30 and 250 cm';
  end if;
  if weight_value is not null and (weight_value < 1 or weight_value > 500) then
    raise exception 'Weight must be between 1 and 500 kg';
  end if;
  if systolic_value is not null and (systolic_value < 50 or systolic_value > 300) then
    raise exception 'Systolic blood pressure must be between 50 and 300 mmHg';
  end if;
  if diastolic_value is not null and (diastolic_value < 30 or diastolic_value > 200) then
    raise exception 'Diastolic blood pressure must be between 30 and 200 mmHg';
  end if;
  if systolic_value is not null and diastolic_value is not null and systolic_value <= diastolic_value then
    raise exception 'Systolic blood pressure must be higher than diastolic pressure';
  end if;
  if temperature_value is not null and (temperature_value < 25 or temperature_value > 45) then
    raise exception 'Temperature must be between 25 and 45 °C';
  end if;
  if heart_rate_value is not null and (heart_rate_value < 20 or heart_rate_value > 250) then
    raise exception 'Heart rate must be between 20 and 250 bpm';
  end if;
  if respiratory_rate_value is not null and (respiratory_rate_value < 5 or respiratory_rate_value > 80) then
    raise exception 'Respiratory rate must be between 5 and 80 breaths/min';
  end if;
  if oxygen_value is not null and (oxygen_value < 50 or oxygen_value > 100) then
    raise exception 'Oxygen saturation must be between 50 and 100 percent';
  end if;
  if not (
    nullif(btrim(checkup_payload->>'reason_for_visit'), '') is not null
    or height_value is not null
    or weight_value is not null
    or systolic_value is not null
    or diastolic_value is not null
    or temperature_value is not null
    or heart_rate_value is not null
    or respiratory_rate_value is not null
    or oxygen_value is not null
    or nullif(btrim(checkup_payload->>'current_symptoms'), '') is not null
    or nullif(btrim(checkup_payload->>'relevant_medical_history'), '') is not null
    or nullif(btrim(checkup_payload->>'previous_surgeries'), '') is not null
    or nullif(btrim(checkup_payload->>'smoking_status'), '') is not null
    or nullif(btrim(checkup_payload->>'alcohol_use'), '') is not null
    or nullif(btrim(checkup_payload->>'pregnancy_status'), '') is not null
    or nullif(btrim(checkup_payload->>'doctor_notes'), '') is not null
    or (
      jsonb_typeof(checkup_payload->'known_medical_conditions') = 'array'
      and jsonb_array_length(checkup_payload->'known_medical_conditions') > 0
    )
    or (
      jsonb_typeof(checkup_payload->'allergies') = 'array'
      and jsonb_array_length(checkup_payload->'allergies') > 0
    )
    or (
      jsonb_typeof(checkup_payload->'current_medications') = 'array'
      and jsonb_array_length(checkup_payload->'current_medications') > 0
    )
  ) then
    raise exception 'Add at least one checkup detail before saving';
  end if;

  insert into public.medical_records (
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
  ) values (
    target_patient_id,
    doctor_row.id,
    doctor_row.hospital_id,
    'checkup',
    coalesce(nullif(btrim(checkup_payload->>'reason_for_visit'), ''), 'Patient checkup'),
    nullif(btrim(checkup_payload->>'doctor_notes'), ''),
    coalesce(recorded_at, now())::date,
    nullif(btrim(checkup_payload->>'reason_for_visit'), ''),
    height_value,
    weight_value,
    case
      when height_value is not null and weight_value is not null
        then round(weight_value / power(height_value / 100, 2), 2)
      else null
    end,
    systolic_value,
    diastolic_value,
    temperature_value,
    heart_rate_value,
    respiratory_rate_value,
    oxygen_value,
    case
      when height_value is not null
        or weight_value is not null
        or systolic_value is not null
        or diastolic_value is not null
        or temperature_value is not null
        or heart_rate_value is not null
        or respiratory_rate_value is not null
        or oxygen_value is not null
        then coalesce(recorded_at, now())
      else null
    end,
    nullif(btrim(checkup_payload->>'current_symptoms'), ''),
    case when jsonb_typeof(checkup_payload->'known_medical_conditions') = 'array'
      then array(select jsonb_array_elements_text(checkup_payload->'known_medical_conditions'))
      else '{}'::text[] end,
    case when jsonb_typeof(checkup_payload->'allergies') = 'array'
      then array(select jsonb_array_elements_text(checkup_payload->'allergies'))
      else '{}'::text[] end,
    case when jsonb_typeof(checkup_payload->'current_medications') = 'array'
      then array(select jsonb_array_elements_text(checkup_payload->'current_medications'))
      else '{}'::text[] end,
    nullif(btrim(checkup_payload->>'relevant_medical_history'), ''),
    nullif(btrim(checkup_payload->>'previous_surgeries'), ''),
    nullif(btrim(checkup_payload->>'smoking_status'), ''),
    nullif(btrim(checkup_payload->>'alcohol_use'), ''),
    nullif(btrim(checkup_payload->>'pregnancy_status'), ''),
    nullif(btrim(checkup_payload->>'doctor_notes'), '')
  )
  returning * into result_row;

  return result_row;
end;
$function$;

grant execute on function public.record_patient_checkup(uuid, jsonb, timestamptz)
  to authenticated, service_role;
