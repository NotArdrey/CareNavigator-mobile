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
set search_path = ''
as $$
  select coalesce(
    target_start > now()
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
$$;

comment on function private.is_doctor_slot_available(
  uuid,
  uuid,
  public.consultation_type,
  timestamptz,
  uuid
) is 'Checks recurring Philippines-local schedule hours against an absolute appointment timestamp.';
