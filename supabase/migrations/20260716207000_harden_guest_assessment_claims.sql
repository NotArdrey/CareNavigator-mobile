begin;

-- `user_metadata` is editable by end users and must not participate in an RLS
-- authorization decision. The signed `is_anonymous` JWT claim, absence of an
-- application account, strict ownership, and null clinical links form the
-- complete guest boundary.
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
    and private.current_user_id() is null
    and (select auth.jwt())->>'is_anonymous'='true'
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
      and private.current_user_id() is null
      and (select auth.jwt())->>'is_anonymous'='true'
    )
  )
);

commit;
