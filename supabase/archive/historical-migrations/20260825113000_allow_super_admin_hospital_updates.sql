-- Super administrators can already create, review, and delete hospital
-- records. Keep hospital administrators scoped to their assigned hospital
-- while allowing platform administrators to correct directory information.

drop policy if exists hospitals_admin_update on public.hospitals;

create policy hospitals_admin_update
on public.hospitals
for update
to authenticated
using (
  private.is_super_admin()
  or private.is_hospital_admin_for(id)
)
with check (
  private.is_super_admin()
  or private.is_hospital_admin_for(id)
);
