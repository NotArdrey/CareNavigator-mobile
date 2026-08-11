alter table public.users
  add column if not exists address_geocode_hash text,
  add column if not exists address_latitude double precision,
  add column if not exists address_longitude double precision;

alter table public.users
  drop constraint if exists users_address_latitude_check;

alter table public.users
  add constraint users_address_latitude_check
  check (address_latitude is null or address_latitude between -90 and 90);

alter table public.users
  drop constraint if exists users_address_longitude_check;

alter table public.users
  add constraint users_address_longitude_check
  check (address_longitude is null or address_longitude between -180 and 180);

comment on column public.users.address_geocode_hash is
  'Hash of the address used for the cached location coordinates.';
comment on column public.users.address_latitude is
  'Cached latitude resolved from the user address for distance-aware facility suggestions.';
comment on column public.users.address_longitude is
  'Cached longitude resolved from the user address for distance-aware facility suggestions.';
