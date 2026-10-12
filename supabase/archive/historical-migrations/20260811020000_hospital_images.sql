alter table public.hospitals
  add column if not exists image_url text;

comment on column public.hospitals.image_url is
  'Publicly accessible hospital exterior image used in patient-facing facility cards.';
