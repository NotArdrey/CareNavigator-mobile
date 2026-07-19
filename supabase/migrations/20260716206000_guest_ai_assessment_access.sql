begin;

-- Anonymous Auth identities are transport identities for the guest AI flow,
-- not application accounts. Avoid creating active guest rows that could make
-- unrelated active-account RLS predicates true.
create or replace function public.handle_new_auth_user()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  guest_role_id smallint;
begin
  if coalesce(new.is_anonymous,false) then
    return new;
  end if;

  select id into guest_role_id
  from public.roles
  where role_name='guest';

  insert into public.users(
    id,auth_user_id,role_id,first_name,last_name,email,mobile_number,
    account_status
  ) values(
    new.id,new.id,guest_role_id,
    coalesce(new.raw_user_meta_data->>'first_name',''),
    coalesce(new.raw_user_meta_data->>'last_name',''),
    new.email,new.phone,'active'
  ) on conflict(auth_user_id) do nothing;
  return new;
end;
$$;

revoke all on function public.handle_new_auth_user()
from public,anon,authenticated;

-- Anonymous Supabase users may submit only their own standalone symptom
-- navigation assessment. They cannot link it to a patient, consultation, or
-- any other clinical context, and every other private RLS policy continues to
-- require an active CareNavigator application account.
drop policy if exists ai_assessments_owner_read on public.ai_assessments;
create policy ai_assessments_owner_read on public.ai_assessments
for select to authenticated using (
  (
    private.current_user_id() is not null
    and coalesce((select auth.jwt())->>'is_anonymous','false')<>'true'
    and (
      user_id=(select auth.uid())
      or (patient_id is not null and private.can_access_patient(patient_id))
      or (
        guest_request_id is not null
        and private.can_access_guest_request(guest_request_id)
      )
    )
  )
  or (
    user_id=(select auth.uid())
    and patient_id is null
    and guest_request_id is null
    and (select auth.jwt())->>'is_anonymous'='true'
    and (select auth.jwt())->'user_metadata'->>'access_purpose'=
      'guest_symptom_assessment'
  )
);

drop policy if exists ai_assessments_owner_insert on public.ai_assessments;
create policy ai_assessments_owner_insert on public.ai_assessments
for insert to authenticated with check (
  user_id=(select auth.uid())
  and (
    (
      private.current_user_id() is not null
      and coalesce((select auth.jwt())->>'is_anonymous','false')<>'true'
    )
    or (
      patient_id is null
      and guest_request_id is null
      and (select auth.jwt())->>'is_anonymous'='true'
      and (select auth.jwt())->'user_metadata'->>'access_purpose'=
        'guest_symptom_assessment'
    )
  )
);

commit;
