-- Platform administrators must be able to read every hospital record so
-- newly-created and pending records remain visible in governance workflows.

drop policy if exists hospitals_authenticated_read on public.hospitals;

create policy hospitals_authenticated_read
on public.hospitals
for select
to authenticated
using (
  private.is_super_admin()
  or (
    verification_status = 'verified'
    and operating_status in ('open', 'limited')
  )
  or private.is_hospital_admin_for(id)
);
