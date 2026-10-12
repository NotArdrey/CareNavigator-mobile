-- Make emergency capacity a derived, attributable, freshness-aware operational
-- record. Public clients continue to read the published row, while only an
-- authorized administrator for the hospital can submit a manual census.

alter table public.emergency_room_status
  add column if not exists occupied_beds integer,
  add column if not exists closed_or_unstaffed_beds integer not null default 0,
  add column if not exists reserved_beds integer not null default 0,
  add column if not exists status_override public.emergency_room_state,
  add column if not exists override_reason text,
  add column if not exists capacity_source text not null default 'manual',
  add column if not exists updated_by uuid references public.users(id) on delete set null;

-- Preserve every currently published available-bed count. The old model did
-- not publish occupied beds, so this is the only lossless backfill.
update public.emergency_room_status
set occupied_beds = greatest(
  0,
  maximum_capacity - least(available_beds, maximum_capacity)
)
where occupied_beds is null;

alter table public.emergency_room_status
  alter column occupied_beds set default 0,
  alter column occupied_beds set not null;

-- Patient count includes waiting and boarding patients, so it is deliberately
-- not constrained to staffed bed capacity.
alter table public.emergency_room_status
  drop constraint if exists emergency_room_status_check,
  drop constraint if exists emergency_capacity_components_check,
  drop constraint if exists emergency_capacity_available_check,
  drop constraint if exists emergency_capacity_override_check,
  drop constraint if exists emergency_capacity_override_reason_check,
  drop constraint if exists emergency_capacity_source_check;

alter table public.emergency_room_status
  add constraint emergency_capacity_components_check check (
    occupied_beds >= 0
    and closed_or_unstaffed_beds >= 0
    and reserved_beds >= 0
    and occupied_beds + closed_or_unstaffed_beds + reserved_beds
      <= maximum_capacity
  ),
  add constraint emergency_capacity_available_check check (
    available_beds = maximum_capacity
      - occupied_beds
      - closed_or_unstaffed_beds
      - reserved_beds
  ),
  add constraint emergency_capacity_override_check check (
    status_override is null
    or status_override in ('limited', 'full', 'temporarily_closed')
  ),
  add constraint emergency_capacity_override_reason_check check (
    status_override is null
    or length(btrim(coalesce(override_reason, ''))) between 3 and 500
  ),
  add constraint emergency_capacity_source_check check (
    capacity_source in ('manual', 'integration')
  );

comment on column public.emergency_room_status.maximum_capacity is
  'Physical ER treatment spaces configured for this census.';
comment on column public.emergency_room_status.closed_or_unstaffed_beds is
  'Physical ER spaces unavailable because of staffing, maintenance, cleaning, or infection-control restrictions.';
comment on column public.emergency_room_status.occupied_beds is
  'Staffed ER beds currently occupied by a patient.';
comment on column public.emergency_room_status.reserved_beds is
  'Usable ER beds held for an arriving or clinically reserved patient.';
comment on column public.emergency_room_status.available_beds is
  'Server-derived maximum capacity minus occupied, closed or unstaffed, and reserved beds.';
comment on column public.emergency_room_status.current_patient_count is
  'All patients currently managed by the ER, including waiting or boarding patients who may not occupy an ER bed.';
comment on column public.emergency_room_status.status_override is
  'Optional operational override for crowding, full capacity, or temporary closure.';
comment on column public.emergency_room_status.last_updated is
  'Server timestamp of the latest capacity confirmation or operational override.';

create or replace function private.derive_emergency_capacity()
returns trigger
language plpgsql
security definer
set search_path to ''
as $function$
declare
  staffed_capacity integer;
  is_meaningful_update boolean := true;
begin
  new.maximum_capacity := coalesce(new.maximum_capacity, 0);
  new.occupied_beds := coalesce(new.occupied_beds, 0);
  new.closed_or_unstaffed_beds := coalesce(new.closed_or_unstaffed_beds, 0);
  new.reserved_beds := coalesce(new.reserved_beds, 0);
  new.current_patient_count := coalesce(new.current_patient_count, 0);
  new.capacity_source := coalesce(nullif(new.capacity_source, ''), 'manual');

  -- Translate writes from clients deployed before status_override existed.
  if tg_op = 'UPDATE'
    and new.status is distinct from old.status
    and new.status_override is not distinct from old.status_override then
    if new.status = 'available' then
      new.status_override := null;
      new.override_reason := null;
    else
      new.status_override := new.status;
      new.override_reason := coalesce(
        nullif(btrim(new.override_reason), ''),
        'Manual operational status override'
      );
    end if;
  end if;

  if new.maximum_capacity < 0
    or new.occupied_beds < 0
    or new.closed_or_unstaffed_beds < 0
    or new.reserved_beds < 0
    or new.current_patient_count < 0 then
    raise exception 'Emergency capacity values cannot be negative';
  end if;

  if new.occupied_beds
      + new.closed_or_unstaffed_beds
      + new.reserved_beds > new.maximum_capacity then
    raise exception 'Occupied, unavailable, and reserved beds cannot exceed total ER capacity';
  end if;

  if new.status_override is not null
    and length(btrim(coalesce(new.override_reason, ''))) not between 3 and 500 then
    raise exception 'An operational override reason between 3 and 500 characters is required';
  end if;

  if new.status_override is null then
    new.override_reason := null;
  end if;

  staffed_capacity := new.maximum_capacity - new.closed_or_unstaffed_beds;
  new.available_beds := staffed_capacity - new.occupied_beds - new.reserved_beds;

  if new.status_override is not null then
    new.status := new.status_override;
  elsif new.available_beds = 0 then
    new.status := 'full';
  elsif new.available_beds * 5 <= staffed_capacity then
    new.status := 'limited';
  else
    new.status := 'available';
  end if;

  if tg_op = 'UPDATE' then
    is_meaningful_update :=
      new.maximum_capacity is distinct from old.maximum_capacity
      or new.occupied_beds is distinct from old.occupied_beds
      or new.closed_or_unstaffed_beds is distinct from old.closed_or_unstaffed_beds
      or new.reserved_beds is distinct from old.reserved_beds
      or new.current_patient_count is distinct from old.current_patient_count
      or new.status_override is distinct from old.status_override
      or new.override_reason is distinct from old.override_reason
      or new.capacity_source is distinct from old.capacity_source;
  end if;

  if tg_op = 'INSERT' or is_meaningful_update then
    new.last_updated := now();
    new.updated_by := coalesce(private.current_user_id(), new.updated_by);
  end if;

  return new;
end
$function$;

drop trigger if exists derive_emergency_capacity_before_write
  on public.emergency_room_status;
create trigger derive_emergency_capacity_before_write
before insert or update on public.emergency_room_status
for each row execute function private.derive_emergency_capacity();

create or replace function public.update_emergency_capacity(
  target_record_id uuid,
  total_capacity integer,
  occupied_capacity integer,
  closed_unstaffed_capacity integer,
  reserved_capacity integer,
  reported_patient_count integer,
  manual_status_override text default null,
  manual_override_reason text default null
)
returns public.emergency_room_status
language plpgsql
security definer
set search_path to ''
as $function$
declare
  target_row public.emergency_room_status;
  normalized_override text := nullif(btrim(coalesce(manual_status_override, '')), '');
begin
  if (select auth.uid()) is null
    or private.current_user_id() is null
    or not private.has_permission('hospital.manage') then
    raise exception 'An authorized hospital operations account is required';
  end if;

  select * into target_row
  from public.emergency_room_status status_row
  where status_row.id = target_record_id
  for update;

  if not found then
    raise exception 'Emergency capacity record was not found';
  end if;

  if not private.is_hospital_admin_for(target_row.hospital_id) then
    raise exception 'You cannot update emergency capacity for this hospital';
  end if;

  if total_capacity is null
    or occupied_capacity is null
    or closed_unstaffed_capacity is null
    or reserved_capacity is null
    or reported_patient_count is null
    or total_capacity < 0
    or occupied_capacity < 0
    or closed_unstaffed_capacity < 0
    or reserved_capacity < 0
    or reported_patient_count < 0 then
    raise exception 'Emergency capacity requires non-negative whole numbers';
  end if;

  if occupied_capacity + closed_unstaffed_capacity + reserved_capacity
      > total_capacity then
    raise exception 'Occupied, unavailable, and reserved beds cannot exceed total ER capacity';
  end if;

  if normalized_override is not null
    and normalized_override not in ('limited', 'full', 'temporarily_closed') then
    raise exception 'Unsupported emergency status override';
  end if;

  if normalized_override is not null
    and length(btrim(coalesce(manual_override_reason, ''))) not between 3 and 500 then
    raise exception 'Explain why the automatic status is being overridden';
  end if;

  update public.emergency_room_status status_row
  set
    maximum_capacity = total_capacity,
    occupied_beds = occupied_capacity,
    closed_or_unstaffed_beds = closed_unstaffed_capacity,
    reserved_beds = reserved_capacity,
    current_patient_count = reported_patient_count,
    status_override = normalized_override::public.emergency_room_state,
    override_reason = case
      when normalized_override is null then null
      else btrim(manual_override_reason)
    end,
    capacity_source = 'manual'
  where status_row.id = target_record_id
  returning * into target_row;

  return target_row;
end
$function$;

revoke all on function public.update_emergency_capacity(
  uuid, integer, integer, integer, integer, integer, text, text
) from public, anon;
grant execute on function public.update_emergency_capacity(
  uuid, integer, integer, integer, integer, integer, text, text
) to authenticated, service_role;
