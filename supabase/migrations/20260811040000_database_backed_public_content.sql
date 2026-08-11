-- Public operational content belongs in the database so every client receives
-- the same reviewed values without compiling regional facts into the app.
insert into public.system_settings(key, value, description, is_public)
values
  (
    'emergency_number',
    to_jsonb('911'::text),
    'Emergency services number displayed by public and authenticated clients',
    true
  ),
  (
    'emergency_region',
    to_jsonb('the Philippines'::text),
    'Region associated with the published emergency services number',
    true
  )
on conflict (key) do update set
  value = excluded.value,
  description = excluded.description,
  is_public = excluded.is_public,
  updated_at = now();

alter table public.hospitals
  add column if not exists directory_source_url text,
  add column if not exists directory_verified_at timestamptz;

comment on column public.hospitals.directory_source_url is
  'Authoritative source used to verify patient-facing directory contact data.';
comment on column public.hospitals.directory_verified_at is
  'Most recent date that patient-facing directory contact data was checked.';

-- Contact details below come from the latest available DOH or PhilHealth
-- facility directories. Emergency-specific numbers remain null unless an
-- authoritative source explicitly identifies one.
update public.hospitals
set
  contact_number = '0920 622 4641 / 0917 180 1120',
  email = 'auroramemhos@gmail.com',
  directory_source_url = 'https://www.philhealth.gov.ph/partners/providers/facilities/accredited/HOSP_022825.pdf',
  directory_verified_at = now(),
  updated_at = now()
where hospital_name = 'Aurora Memorial Hospital';

update public.hospitals
set
  contact_number = '(047) 237-9772 local 1118 / 6706',
  email = 'bataanghmc2020@gmail.com',
  directory_source_url = 'https://www.philhealth.gov.ph/partners/providers/facilities/contracted/ZBENEFITS_CONTRACTED_01312026.pdf',
  directory_verified_at = now(),
  updated_at = now()
where hospital_name = 'Bataan General Hospital and Medical Center';

update public.hospitals
set
  contact_number = '(044) 791-0630 local 164 / 485-4207',
  email = 'pho_bulacan@yahoo.com',
  directory_source_url = 'https://www.philhealth.gov.ph/partners/providers/facilities/accredited/HOSP_123125.pdf',
  directory_verified_at = now(),
  updated_at = now()
where hospital_name = 'Bulacan Medical Center';

update public.hospitals
set
  contact_number = '(044) 463-8286',
  email = 'dr.pjgmrmc85cabanatuan@gmail.com',
  directory_source_url = 'https://www.philhealth.gov.ph/partners/providers/facilities/contracted/ZBENEFITS_CONTRACTED_01312026.pdf',
  directory_verified_at = now(),
  updated_at = now()
where hospital_name =
  'Dr. Paulino J. Garcia Memorial Research and Medical Center';

update public.hospitals
set
  contact_number = '(045) 409-6688 / 961-3544',
  email = 'mcc@jblmgh.com.ph',
  directory_source_url = 'https://www.philhealth.gov.ph/partners/providers/facilities/accredited/HOSP_022825.pdf',
  directory_verified_at = now(),
  updated_at = now()
where hospital_name = 'Jose B. Lingad Memorial General Hospital';

update public.hospitals
set
  contact_number = '0985 607 8663',
  email = 'pho.prmmh@gmail.com',
  directory_source_url = 'https://www.philhealth.gov.ph/partners/providers/facilities/accredited/HOSP_093025_v2.pdf',
  directory_verified_at = now(),
  updated_at = now()
where hospital_name = 'President Ramon Magsaysay Memorial Hospital';

update public.hospitals
set
  contact_number = '(045) 982-1306',
  email = 'tarlacprovincialhospital@yahoo.com',
  directory_source_url = 'https://www.philhealth.gov.ph/partners/providers/facilities/accredited/HOSP_123125.pdf',
  directory_verified_at = now(),
  updated_at = now()
where hospital_name = 'Tarlac Provincial Hospital';

-- The old synthetic map-coverage row must not pass the verified public
-- directory query. Keep it closed for auditability instead of deleting it.
update public.hospitals
set
  operating_status = 'closed',
  verification_status = 'rejected',
  verification_notes =
    'Synthetic development fixture excluded from the production directory.',
  verification_decided_at = now(),
  updated_at = now()
where hospital_name = 'CareNavigator Primary Hospital (Demo)';
