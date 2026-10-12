-- Patient rows are readable by their owner, but deliberately have no broad
-- UPDATE policy. Expose only the health-profile fields supported by the
-- self-service form and derive ownership from auth.uid().

create or replace function public.update_own_patient_profile(
  patient_profile_update jsonb
)
returns void
language plpgsql
security definer
set search_path to ''
as $function$
declare
  updated_patient_id uuid;
  normalized_blood_type text := nullif(
    pg_catalog.btrim(
      coalesce(patient_profile_update->>'blood_type', '')
    ),
    ''
  );
begin
  if (select auth.uid()) is null then
    raise exception 'An authenticated account is required';
  end if;

  if patient_profile_update is null
    or jsonb_typeof(patient_profile_update) <> 'object' then
    raise exception 'A valid patient profile update is required';
  end if;

  if normalized_blood_type is not null
    and normalized_blood_type not in (
      'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
    ) then
    raise exception 'The selected blood type is not valid';
  end if;

  update public.patients as patient
  set blood_type = normalized_blood_type,
      emergency_contact = coalesce(
        patient_profile_update->'emergency_contact',
        '{}'::jsonb
      ),
      allergies = array(
        select jsonb_array_elements_text(
          coalesce(
            patient_profile_update->'allergies',
            '[]'::jsonb
          )
        )
      ),
      existing_conditions = array(
        select jsonb_array_elements_text(
          coalesce(
            patient_profile_update->'existing_conditions',
            '[]'::jsonb
          )
        )
      ),
      updated_at = now()
  from public.users as app_user
  where app_user.id = patient.user_id
    and app_user.auth_user_id = (select auth.uid())
  returning patient.id into updated_patient_id;

  if updated_patient_id is null then
    raise exception 'Patient profile not found';
  end if;
end;
$function$;

revoke all on function public.update_own_patient_profile(jsonb)
  from public, anon;
grant execute on function public.update_own_patient_profile(jsonb)
  to authenticated, service_role;

comment on function public.update_own_patient_profile(jsonb) is
  'Updates only health-profile fields for the authenticated patient account.';
