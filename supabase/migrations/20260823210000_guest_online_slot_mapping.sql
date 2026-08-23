-- Guest online requests use published online schedules. The availability
-- predicate already supported this mapping; expose the same slots in the list
-- RPC so intake and hospital review use one consistent contract.

create or replace function public.list_available_consultation_slots(
  target_doctor_id uuid,
  target_type public.consultation_type,
  horizon_days integer default 30
)
returns table(starts_at timestamptz, ends_at timestamptz)
language sql
stable
security definer
set search_path to ''
as $function$
  with requested_window as (
    select
      (now() at time zone 'Asia/Manila')::date as first_date,
      least(greatest(coalesce(horizon_days, 30), 1), 60) as day_count
  ),
  calendar_dates as (
    select generated_date.value::date as local_date
    from requested_window bounds,
    lateral generate_series(
      bounds.first_date::timestamp,
      (bounds.first_date + bounds.day_count - 1)::timestamp,
      interval '1 day'
    ) as generated_date(value)
  ),
  published_slots as (
    select
      generated_local_start.value at time zone 'Asia/Manila' as slot_start,
      schedule.slot_minutes
    from public.doctor_schedules schedule
    join calendar_dates calendar
      on schedule.day_of_week = extract(dow from calendar.local_date)::integer,
    lateral generate_series(
      calendar.local_date + schedule.starts_at,
      calendar.local_date + schedule.ends_at
        - make_interval(mins => schedule.slot_minutes),
      make_interval(mins => schedule.slot_minutes)
    ) as generated_local_start(value)
    where schedule.doctor_id = target_doctor_id
      and schedule.is_active
      and (
        schedule.consultation_type = target_type
        or (
          target_type = 'guest_online'::public.consultation_type
          and schedule.consultation_type = 'online'::public.consultation_type
        )
      )
  )
  select
    slot.slot_start as starts_at,
    slot.slot_start + make_interval(mins => slot.slot_minutes) as ends_at
  from published_slots slot
  join public.doctors doctor on doctor.id = target_doctor_id
  where private.is_doctor_slot_available(
    target_doctor_id, doctor.hospital_id,
    target_type, slot.slot_start, null
  )
  order by slot.slot_start
  limit 240
$function$;

revoke all on function public.list_available_consultation_slots(
  uuid, public.consultation_type, integer
) from public;
grant execute on function public.list_available_consultation_slots(
  uuid, public.consultation_type, integer
) to anon, authenticated, service_role;
