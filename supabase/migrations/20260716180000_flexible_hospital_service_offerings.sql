begin;

create table public.healthcare_service_categories (
  id uuid primary key default gen_random_uuid(),
  category_name text not null unique,
  description text not null default '',
  icon_name text,
  display_order integer not null default 0,
  is_active boolean not null default true,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  check (length(btrim(category_name)) between 2 and 120),
  check (display_order >= 0)
);

create unique index healthcare_service_categories_name_ci_key
  on public.healthcare_service_categories (lower(category_name));
create index healthcare_service_categories_directory_idx
  on public.healthcare_service_categories (is_active, display_order, category_name);

insert into public.healthcare_service_categories
  (category_name, description, icon_name, display_order)
values
  ('Emergency & Critical Care', 'Emergency, trauma, and intensive care services', 'emergency', 10),
  ('Medical Consultation', 'General and specialist clinical consultations', 'stethoscope', 20),
  ('Diagnostics & Imaging', 'Laboratory, imaging, and diagnostic procedures', 'diagnostics', 30),
  ('Surgical Services', 'Inpatient and outpatient surgical care', 'surgery', 40),
  ('Maternal & Child Care', 'Obstetric, neonatal, pediatric, and family services', 'child_care', 50),
  ('Rehabilitation & Therapy', 'Physical, occupational, speech, and related therapy', 'rehabilitation', 60),
  ('Pharmacy & Support', 'Pharmacy and supporting clinical services', 'pharmacy', 70),
  ('Preventive & Wellness', 'Screening, vaccination, and preventive care', 'wellness', 80)
on conflict (category_name) do nothing;

alter table public.hospital_services
  add column category_id uuid references public.healthcare_service_categories(id) on delete set null,
  add column service_code text,
  add column delivery_modes text[] not null default array['in_person']::text[],
  add column appointment_required boolean not null default false,
  add column accepts_walk_ins boolean not null default true,
  add column fee_min numeric(10, 2),
  add column fee_max numeric(10, 2),
  add column fee_notes text,
  add column contact_number text,
  add column booking_url text,
  add column preparation_instructions text,
  add column tags text[] not null default '{}'::text[],
  add column last_updated timestamptz not null default now();

alter table public.hospital_services
  add constraint hospital_services_name_not_blank
    check (length(btrim(service_name)) between 2 and 180),
  add constraint hospital_services_code_format
    check (service_code is null or service_code ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$'),
  add constraint hospital_services_delivery_modes_valid
    check (
      cardinality(delivery_modes) > 0
      and delivery_modes <@ array['in_person', 'online', 'home_service', 'emergency']::text[]
    ),
  add constraint hospital_services_fee_min_valid
    check (fee_min is null or fee_min >= 0),
  add constraint hospital_services_fee_max_valid
    check (fee_max is null or fee_max >= 0),
  add constraint hospital_services_fee_range_valid
    check (fee_min is null or fee_max is null or fee_max >= fee_min),
  add constraint hospital_services_operating_hours_object
    check (jsonb_typeof(operating_hours) = 'object'),
  add constraint hospital_services_tags_limit
    check (cardinality(tags) <= 20);

create unique index hospital_services_name_ci_key
  on public.hospital_services (hospital_id, lower(service_name));
create unique index hospital_services_code_key
  on public.hospital_services (hospital_id, lower(service_code))
  where service_code is not null;
create index hospital_services_category_idx
  on public.hospital_services (category_id, availability_status)
  where category_id is not null;
create index hospital_services_tags_gin_idx
  on public.hospital_services using gin (tags);

alter table public.hospital_services
  add constraint hospital_services_id_hospital_key unique (id, hospital_id);
alter table public.doctors
  add constraint doctors_id_hospital_key unique (id, hospital_id);

create table public.hospital_service_doctors (
  id uuid primary key default gen_random_uuid(),
  hospital_id uuid not null references public.hospitals(id) on delete cascade,
  service_id uuid not null,
  doctor_id uuid not null,
  is_primary boolean not null default false,
  notes text,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  foreign key (service_id, hospital_id)
    references public.hospital_services(id, hospital_id) on delete cascade,
  foreign key (doctor_id, hospital_id)
    references public.doctors(id, hospital_id) on delete cascade,
  unique (service_id, doctor_id)
);

create index hospital_service_doctors_hospital_idx
  on public.hospital_service_doctors (hospital_id, service_id);
create index hospital_service_doctors_doctor_idx
  on public.hospital_service_doctors (doctor_id, service_id);

create trigger set_service_categories_updated_at
  before update on public.healthcare_service_categories
  for each row execute function public.set_updated_at();
create trigger set_service_doctors_updated_at
  before update on public.hospital_service_doctors
  for each row execute function public.set_updated_at();

create trigger audit_service_categories
  after insert or update or delete on public.healthcare_service_categories
  for each row execute function public.log_audit_event();
create trigger audit_service_doctors
  after insert or update or delete on public.hospital_service_doctors
  for each row execute function public.log_audit_event();

alter table public.healthcare_service_categories enable row level security;
alter table public.hospital_service_doctors enable row level security;

create policy service_categories_anon_read
  on public.healthcare_service_categories for select to anon
  using (is_active);
create policy service_categories_authenticated_read
  on public.healthcare_service_categories for select to authenticated
  using (is_active or private.is_super_admin());
create policy service_categories_super_admin_insert
  on public.healthcare_service_categories for insert to authenticated
  with check (private.is_super_admin());
create policy service_categories_super_admin_update
  on public.healthcare_service_categories for update to authenticated
  using (private.is_super_admin()) with check (private.is_super_admin());
create policy service_categories_super_admin_delete
  on public.healthcare_service_categories for delete to authenticated
  using (private.is_super_admin());

create policy service_doctors_anon_directory_read
  on public.hospital_service_doctors for select to anon
  using (
    exists (
      select 1
      from public.hospital_services service
      join public.hospitals hospital on hospital.id = service.hospital_id
      join public.doctors doctor on doctor.id = hospital_service_doctors.doctor_id
      where service.id = hospital_service_doctors.service_id
        and service.availability_status <> 'unavailable'
        and doctor.availability_status <> 'unavailable'
        and hospital.verification_status = 'verified'
        and hospital.operating_status in ('open', 'limited')
    )
  );
create policy service_doctors_authenticated_read
  on public.hospital_service_doctors for select to authenticated
  using (
    private.is_hospital_admin_for(hospital_id)
    or exists (
      select 1
      from public.hospital_services service
      join public.hospitals hospital on hospital.id = service.hospital_id
      join public.doctors doctor on doctor.id = hospital_service_doctors.doctor_id
      where service.id = hospital_service_doctors.service_id
        and service.availability_status <> 'unavailable'
        and doctor.availability_status <> 'unavailable'
        and hospital.verification_status = 'verified'
        and hospital.operating_status in ('open', 'limited')
    )
  );
create policy service_doctors_admin_insert
  on public.hospital_service_doctors for insert to authenticated
  with check (private.is_hospital_admin_for(hospital_id));
create policy service_doctors_admin_update
  on public.hospital_service_doctors for update to authenticated
  using (private.is_hospital_admin_for(hospital_id))
  with check (private.is_hospital_admin_for(hospital_id));
create policy service_doctors_admin_delete
  on public.hospital_service_doctors for delete to authenticated
  using (private.is_hospital_admin_for(hospital_id));

grant select on public.healthcare_service_categories, public.hospital_service_doctors
  to anon, authenticated;
grant insert, update, delete on public.healthcare_service_categories,
  public.hospital_service_doctors to authenticated;

do $$
begin
  if not exists (
    select 1 from pg_publication_tables
    where pubname = 'supabase_realtime'
      and schemaname = 'public'
      and tablename = 'hospital_services'
  ) then
    alter publication supabase_realtime add table public.hospital_services;
  end if;
end;
$$;

insert into supabase_migrations.schema_migrations (version, statements, name)
values (
  '20260716180000',
  array[]::text[],
  'flexible_hospital_service_offerings'
)
on conflict (version) do nothing;

commit;
