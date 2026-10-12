-- Preserve the complete clinical and dispensing directions shown to the
-- prescriber at confirmation time. Existing legacy rows remain readable.

alter table public.prescriptions
  add column if not exists diagnosis_reason text,
  add column if not exists medication_form_strength text,
  add column if not exists route text,
  add column if not exists exact_dose text,
  add column if not exists quantity_to_dispense text,
  add column if not exists refills integer,
  add column if not exists start_date date,
  add column if not exists end_date date,
  add column if not exists is_prn boolean not null default false,
  add column if not exists prn_reason text,
  add column if not exists maximum_daily_dose text,
  add column if not exists prescriber_name text,
  add column if not exists prescriber_license_number text,
  add column if not exists prescriber_specialization text,
  add column if not exists electronically_signed_at timestamptz,
  add column if not exists electronically_signed_by uuid references public.users(id),
  add column if not exists signature_method text;

alter table public.prescriptions
  drop constraint if exists prescriptions_refills_range,
  add constraint prescriptions_refills_range
    check (refills is null or refills between 0 and 99),
  drop constraint if exists prescriptions_date_order,
  add constraint prescriptions_date_order
    check (end_date is null or start_date is null or end_date >= start_date),
  drop constraint if exists prescriptions_prn_details,
  add constraint prescriptions_prn_details
    check (
      not is_prn or (
        nullif(btrim(prn_reason), '') is not null and
        nullif(btrim(maximum_daily_dose), '') is not null
      )
    ),
  drop constraint if exists prescriptions_signature_method,
  add constraint prescriptions_signature_method
    check (
      signature_method is null or
      signature_method = 'authenticated_account_attestation'
    );

comment on column public.prescriptions.electronically_signed_by is
  'Authenticated application user who attested to and issued the prescription.';
comment on column public.prescriptions.electronically_signed_at is
  'Server-submission timestamp recorded when the authenticated prescriber confirmed issuance.';

create or replace function private.apply_authenticated_prescription_signature()
returns trigger
language plpgsql
security definer
set search_path = public, private, pg_temp
as $$
declare
  signer_user_id uuid;
  signer_name text;
  signer_license text;
  signer_specialization text;
begin
  select app_user.id, doctor.display_name, doctor.license_number,
         doctor.specialization
    into signer_user_id, signer_name, signer_license, signer_specialization
  from public.users app_user
  join public.doctors doctor on doctor.user_id = app_user.id
  where app_user.auth_user_id = auth.uid()
    and doctor.id = new.doctor_id
  limit 1;

  if signer_user_id is null then
    raise exception 'Only the authenticated prescriber may sign this prescription';
  end if;
  if nullif(btrim(signer_name), '') is null or
     nullif(btrim(signer_license), '') is null then
    raise exception 'Complete the prescriber name and license number before issuing';
  end if;
  if nullif(btrim(new.diagnosis_reason), '') is null or
     nullif(btrim(new.medication_form_strength), '') is null or
     nullif(btrim(new.route), '') is null or
     nullif(btrim(new.exact_dose), '') is null or
     nullif(btrim(new.quantity_to_dispense), '') is null or
     new.refills is null or new.start_date is null then
    raise exception 'The structured prescription fields are required';
  end if;

  new.prescriber_name := signer_name;
  new.prescriber_license_number := signer_license;
  new.prescriber_specialization := nullif(btrim(signer_specialization), '');
  new.electronically_signed_by := signer_user_id;
  new.electronically_signed_at := clock_timestamp();
  new.signature_method := 'authenticated_account_attestation';
  return new;
end;
$$;

revoke all on function private.apply_authenticated_prescription_signature()
from public;

drop trigger if exists prescriptions_authenticated_signature
on public.prescriptions;
create trigger prescriptions_authenticated_signature
before insert on public.prescriptions
for each row execute function private.apply_authenticated_prescription_signature();
