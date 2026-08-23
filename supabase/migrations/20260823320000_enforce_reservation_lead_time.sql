-- Reservations and schedule changes require at least 24 hours of notice.
-- The legacy booking RPC names remain available for deployed clients, while
-- this database rule is authoritative for every reservation path.

create or replace function private.meets_reservation_lead_time(
  target_start timestamptz
)
returns boolean
language sql
stable
set search_path to ''
as $function$
  select target_start is not null
    and target_start >= now() + interval '24 hours'
$function$;

create or replace function private.is_doctor_slot_available(
  target_doctor_id uuid,
  target_hospital_id uuid,
  target_type public.consultation_type,
  target_start timestamptz,
  excluded_consultation_id uuid default null
)
returns boolean
language sql
stable
security definer
set search_path to ''
as $function$
  select coalesce(
    private.meets_reservation_lead_time(target_start)
    and exists (
      select 1
      from public.doctors doctor
      join public.hospitals hospital on hospital.id = doctor.hospital_id
      where doctor.id = target_doctor_id
        and doctor.hospital_id = target_hospital_id
        and doctor.availability_status <> 'unavailable'
        and hospital.verification_status = 'verified'
        and hospital.operating_status in ('open', 'limited')
    )
    and exists (
      select 1
      from public.doctor_schedules schedule
      where schedule.doctor_id = target_doctor_id
        and schedule.is_active
        and (
          schedule.consultation_type = target_type
          or (
            target_type = 'guest_online'
            and schedule.consultation_type = 'online'
          )
        )
        and schedule.day_of_week = extract(
          dow from target_start at time zone 'Asia/Manila'
        )::integer
        and (target_start at time zone 'Asia/Manila')::time >= schedule.starts_at
        and (target_start at time zone 'Asia/Manila')::time
          + make_interval(mins => schedule.slot_minutes) <= schedule.ends_at
        and not exists (
          select 1
          from public.consultations consultation
          where consultation.doctor_id = target_doctor_id
            and consultation.id is distinct from excluded_consultation_id
            and consultation.status not in ('rejected', 'cancelled')
            and consultation.appointment_date
              < target_start + make_interval(mins => schedule.slot_minutes)
            and consultation.appointment_date
              > target_start - make_interval(mins => schedule.slot_minutes)
        )
    ),
    false
  )
$function$;

create or replace function private.enforce_reservation_lead_time()
returns trigger
language plpgsql
set search_path to ''
as $function$
declare
  scheduled_at timestamptz;
begin
  if tg_op = 'UPDATE' then
    if tg_table_name = 'consultations'
      and new.appointment_date is not distinct from old.appointment_date then
      return new;
    elsif tg_table_name in (
      'guest_consultation_requests', 'online_consultation_requests'
    ) and new.preferred_schedule is not distinct from old.preferred_schedule then
      return new;
    end if;
  end if;

  if tg_table_name = 'consultations' then
    if new.consultation_type::text = 'emergency' then
      return new;
    end if;
    scheduled_at := new.appointment_date;
  else
    scheduled_at := new.preferred_schedule;
  end if;

  if not private.meets_reservation_lead_time(scheduled_at) then
    raise exception 'Reservations must be made at least 24 hours in advance';
  end if;
  return new;
end
$function$;

drop trigger if exists enforce_reservation_lead_time on public.consultations;
create trigger enforce_reservation_lead_time
before insert or update of appointment_date on public.consultations
for each row execute function private.enforce_reservation_lead_time();

drop trigger if exists enforce_reservation_lead_time
  on public.guest_consultation_requests;
create trigger enforce_reservation_lead_time
before insert or update of preferred_schedule
on public.guest_consultation_requests
for each row execute function private.enforce_reservation_lead_time();

drop trigger if exists enforce_reservation_lead_time
  on public.online_consultation_requests;
create trigger enforce_reservation_lead_time
before insert or update of preferred_schedule
on public.online_consultation_requests
for each row execute function private.enforce_reservation_lead_time();

revoke all on function private.meets_reservation_lead_time(timestamptz)
  from public, anon, authenticated;
revoke all on function private.enforce_reservation_lead_time()
  from public, anon, authenticated;

comment on function private.meets_reservation_lead_time(timestamptz) is
  'Requires consultation reservations and schedule changes to be at least 24 hours in the future.';

update public.hospital_services
set description = replace(description, 'available for booking', 'available for reservation')
where description like '%available for booking%';
