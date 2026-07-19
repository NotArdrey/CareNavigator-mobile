begin;

drop policy if exists cnph_hospital_images_public_read on storage.objects;

revoke execute on function public.current_user_id() from public, anon;
revoke execute on function public.current_role() from public, anon;
revoke execute on function public.current_hospital_id() from public, anon;
revoke execute on function public.current_doctor_id() from public, anon;
revoke execute on function public.current_patient_id() from public, anon;
revoke execute on function public.is_super_admin() from public, anon;
revoke execute on function public.is_hospital_admin_for(uuid) from public, anon;
revoke execute on function public.can_access_patient(uuid) from public, anon;
revoke execute on function public.can_access_guest_request(uuid) from public, anon;
revoke execute on function public.can_access_conversation(uuid) from public, anon;
revoke execute on function public.can_view_user(uuid) from public, anon;
revoke execute on function public.storage_path_owner(text) from public, anon;
revoke execute on function public.can_access_patient_storage(text) from public, anon;

grant execute on function public.current_user_id(), public.current_role(), public.current_hospital_id(),
  public.current_doctor_id(), public.current_patient_id(), public.is_super_admin(),
  public.is_hospital_admin_for(uuid), public.can_access_patient(uuid),
  public.can_access_guest_request(uuid), public.can_access_conversation(uuid),
  public.can_view_user(uuid), public.storage_path_owner(text),
  public.can_access_patient_storage(text) to authenticated;

drop policy if exists guest_requests_owner_insert on public.guest_consultation_requests;
create policy guest_requests_owner_insert on public.guest_consultation_requests
  for insert to authenticated
  with check (
    submitted_by = (select auth.uid())
    and nullif((select auth.jwt() ->> 'phone'), '') is not null
  );

drop policy if exists hospitals_public_read on public.hospitals;
create policy hospitals_anon_directory_read on public.hospitals
  for select to anon
  using (verification_status = 'verified' and operating_status in ('open', 'limited'));
create policy hospitals_authenticated_read on public.hospitals
  for select to authenticated
  using (
    (verification_status = 'verified' and operating_status in ('open', 'limited'))
    or public.is_hospital_admin_for(id)
  );

drop policy if exists departments_public_read on public.hospital_departments;
create policy departments_anon_directory_read on public.hospital_departments
  for select to anon
  using (
    availability_status <> 'unavailable'
    and exists (
      select 1 from public.hospitals h
      where h.id = hospital_id
        and h.verification_status = 'verified'
        and h.operating_status in ('open', 'limited')
    )
  );
create policy departments_authenticated_read on public.hospital_departments
  for select to authenticated
  using (
    (
      availability_status <> 'unavailable'
      and exists (
        select 1 from public.hospitals h
        where h.id = hospital_id
          and h.verification_status = 'verified'
          and h.operating_status in ('open', 'limited')
      )
    )
    or public.is_hospital_admin_for(hospital_id)
  );

drop policy if exists services_public_read on public.hospital_services;
create policy services_anon_directory_read on public.hospital_services
  for select to anon
  using (
    availability_status <> 'unavailable'
    and exists (
      select 1 from public.hospitals h
      where h.id = hospital_id
        and h.verification_status = 'verified'
        and h.operating_status in ('open', 'limited')
    )
  );
create policy services_authenticated_read on public.hospital_services
  for select to authenticated
  using (
    (
      availability_status <> 'unavailable'
      and exists (
        select 1 from public.hospitals h
        where h.id = hospital_id
          and h.verification_status = 'verified'
          and h.operating_status in ('open', 'limited')
      )
    )
    or public.is_hospital_admin_for(hospital_id)
  );

drop policy if exists rooms_public_read on public.hospital_rooms;
create policy rooms_anon_directory_read on public.hospital_rooms
  for select to anon
  using (exists (select 1 from public.hospitals h where h.id = hospital_id and h.verification_status = 'verified'));
create policy rooms_authenticated_read on public.hospital_rooms
  for select to authenticated
  using (
    exists (select 1 from public.hospitals h where h.id = hospital_id and h.verification_status = 'verified')
    or public.is_hospital_admin_for(hospital_id)
  );

drop policy if exists beds_public_read on public.hospital_beds;
create policy beds_anon_directory_read on public.hospital_beds
  for select to anon
  using (exists (select 1 from public.hospitals h where h.id = hospital_id and h.verification_status = 'verified'));
create policy beds_authenticated_read on public.hospital_beds
  for select to authenticated
  using (
    exists (select 1 from public.hospitals h where h.id = hospital_id and h.verification_status = 'verified')
    or public.is_hospital_admin_for(hospital_id)
  );

drop policy if exists emergency_status_public_read on public.emergency_room_status;
create policy emergency_status_anon_directory_read on public.emergency_room_status
  for select to anon
  using (exists (select 1 from public.hospitals h where h.id = hospital_id and h.verification_status = 'verified'));
create policy emergency_status_authenticated_read on public.emergency_room_status
  for select to authenticated
  using (
    exists (select 1 from public.hospitals h where h.id = hospital_id and h.verification_status = 'verified')
    or public.is_hospital_admin_for(hospital_id)
  );

drop policy if exists facility_status_public_read on public.hospital_facility_status;
create policy facility_status_anon_directory_read on public.hospital_facility_status
  for select to anon
  using (exists (select 1 from public.hospitals h where h.id = hospital_id and h.verification_status = 'verified'));
create policy facility_status_authenticated_read on public.hospital_facility_status
  for select to authenticated
  using (
    exists (select 1 from public.hospitals h where h.id = hospital_id and h.verification_status = 'verified')
    or public.is_hospital_admin_for(hospital_id)
  );

drop policy if exists doctors_public_read on public.doctors;
create policy doctors_anon_directory_read on public.doctors
  for select to anon
  using (
    availability_status <> 'unavailable'
    and exists (select 1 from public.hospitals h where h.id = hospital_id and h.verification_status = 'verified')
  );
create policy doctors_authenticated_read on public.doctors
  for select to authenticated
  using (
    (
      availability_status <> 'unavailable'
      and exists (select 1 from public.hospitals h where h.id = hospital_id and h.verification_status = 'verified')
    )
    or user_id = public.current_user_id()
    or public.is_hospital_admin_for(hospital_id)
  );

drop policy if exists doctor_schedules_public_read on public.doctor_schedules;
create policy doctor_schedules_anon_directory_read on public.doctor_schedules
  for select to anon using (is_active);
create policy doctor_schedules_authenticated_read on public.doctor_schedules
  for select to authenticated using (is_active or doctor_id = public.current_doctor_id());

drop policy if exists roles_super_admin_manage on public.roles;
create policy roles_super_admin_insert on public.roles for insert to authenticated with check (public.is_super_admin());
create policy roles_super_admin_update on public.roles for update to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
create policy roles_super_admin_delete on public.roles for delete to authenticated using (public.is_super_admin());

drop policy if exists classifications_super_admin_manage on public.hospital_classifications;
create policy classifications_super_admin_insert on public.hospital_classifications for insert to authenticated with check (public.is_super_admin());
create policy classifications_super_admin_update on public.hospital_classifications for update to authenticated using (public.is_super_admin()) with check (public.is_super_admin());
create policy classifications_super_admin_delete on public.hospital_classifications for delete to authenticated using (public.is_super_admin());

drop policy if exists departments_admin_manage on public.hospital_departments;
create policy departments_admin_insert on public.hospital_departments for insert to authenticated with check (public.is_hospital_admin_for(hospital_id));
create policy departments_admin_update on public.hospital_departments for update to authenticated using (public.is_hospital_admin_for(hospital_id)) with check (public.is_hospital_admin_for(hospital_id));
create policy departments_admin_delete on public.hospital_departments for delete to authenticated using (public.is_hospital_admin_for(hospital_id));

drop policy if exists services_admin_manage on public.hospital_services;
create policy services_admin_insert on public.hospital_services for insert to authenticated with check (public.is_hospital_admin_for(hospital_id));
create policy services_admin_update on public.hospital_services for update to authenticated using (public.is_hospital_admin_for(hospital_id)) with check (public.is_hospital_admin_for(hospital_id));
create policy services_admin_delete on public.hospital_services for delete to authenticated using (public.is_hospital_admin_for(hospital_id));

drop policy if exists rooms_admin_manage on public.hospital_rooms;
create policy rooms_admin_insert on public.hospital_rooms for insert to authenticated with check (public.is_hospital_admin_for(hospital_id));
create policy rooms_admin_update on public.hospital_rooms for update to authenticated using (public.is_hospital_admin_for(hospital_id)) with check (public.is_hospital_admin_for(hospital_id));
create policy rooms_admin_delete on public.hospital_rooms for delete to authenticated using (public.is_hospital_admin_for(hospital_id));

drop policy if exists beds_admin_manage on public.hospital_beds;
create policy beds_admin_insert on public.hospital_beds for insert to authenticated with check (public.is_hospital_admin_for(hospital_id));
create policy beds_admin_update on public.hospital_beds for update to authenticated using (public.is_hospital_admin_for(hospital_id)) with check (public.is_hospital_admin_for(hospital_id));
create policy beds_admin_delete on public.hospital_beds for delete to authenticated using (public.is_hospital_admin_for(hospital_id));

drop policy if exists emergency_status_admin_manage on public.emergency_room_status;
create policy emergency_status_admin_insert on public.emergency_room_status for insert to authenticated with check (public.is_hospital_admin_for(hospital_id));
create policy emergency_status_admin_update on public.emergency_room_status for update to authenticated using (public.is_hospital_admin_for(hospital_id)) with check (public.is_hospital_admin_for(hospital_id));
create policy emergency_status_admin_delete on public.emergency_room_status for delete to authenticated using (public.is_hospital_admin_for(hospital_id));

drop policy if exists facility_status_admin_manage on public.hospital_facility_status;
create policy facility_status_admin_insert on public.hospital_facility_status for insert to authenticated with check (public.is_hospital_admin_for(hospital_id));
create policy facility_status_admin_update on public.hospital_facility_status for update to authenticated using (public.is_hospital_admin_for(hospital_id)) with check (public.is_hospital_admin_for(hospital_id));
create policy facility_status_admin_delete on public.hospital_facility_status for delete to authenticated using (public.is_hospital_admin_for(hospital_id));

drop policy if exists doctors_admin_manage on public.doctors;
create policy doctors_admin_insert on public.doctors for insert to authenticated with check (public.is_hospital_admin_for(hospital_id));
create policy doctors_admin_update on public.doctors for update to authenticated using (public.is_hospital_admin_for(hospital_id)) with check (public.is_hospital_admin_for(hospital_id));
create policy doctors_admin_delete on public.doctors for delete to authenticated using (public.is_hospital_admin_for(hospital_id));

drop policy if exists doctor_schedules_manage on public.doctor_schedules;
create policy doctor_schedules_insert on public.doctor_schedules for insert to authenticated
  with check (
    doctor_id = public.current_doctor_id()
    or exists (select 1 from public.doctors d where d.id = doctor_id and public.is_hospital_admin_for(d.hospital_id))
  );
create policy doctor_schedules_update on public.doctor_schedules for update to authenticated
  using (
    doctor_id = public.current_doctor_id()
    or exists (select 1 from public.doctors d where d.id = doctor_id and public.is_hospital_admin_for(d.hospital_id))
  )
  with check (
    doctor_id = public.current_doctor_id()
    or exists (select 1 from public.doctors d where d.id = doctor_id and public.is_hospital_admin_for(d.hospital_id))
  );
create policy doctor_schedules_delete on public.doctor_schedules for delete to authenticated
  using (
    doctor_id = public.current_doctor_id()
    or exists (select 1 from public.doctors d where d.id = doctor_id and public.is_hospital_admin_for(d.hospital_id))
  );

drop policy if exists assignments_doctor_manage on public.doctor_patient_assignments;
create policy assignments_doctor_insert on public.doctor_patient_assignments for insert to authenticated
  with check (
    doctor_id = public.current_doctor_id()
    or exists (select 1 from public.doctors d where d.id = doctor_id and public.is_hospital_admin_for(d.hospital_id))
  );
create policy assignments_doctor_update on public.doctor_patient_assignments for update to authenticated
  using (
    doctor_id = public.current_doctor_id()
    or exists (select 1 from public.doctors d where d.id = doctor_id and public.is_hospital_admin_for(d.hospital_id))
  )
  with check (
    doctor_id = public.current_doctor_id()
    or exists (select 1 from public.doctors d where d.id = doctor_id and public.is_hospital_admin_for(d.hospital_id))
  );
create policy assignments_doctor_delete on public.doctor_patient_assignments for delete to authenticated
  using (
    doctor_id = public.current_doctor_id()
    or exists (select 1 from public.doctors d where d.id = doctor_id and public.is_hospital_admin_for(d.hospital_id))
  );

drop policy if exists conversations_doctor_manage on public.chat_conversations;
create policy conversations_doctor_insert on public.chat_conversations for insert to authenticated with check (doctor_id = public.current_doctor_id());
create policy conversations_doctor_update on public.chat_conversations for update to authenticated using (doctor_id = public.current_doctor_id()) with check (doctor_id = public.current_doctor_id());
create policy conversations_doctor_delete on public.chat_conversations for delete to authenticated using (doctor_id = public.current_doctor_id());

drop policy if exists announcements_admin_manage on public.hospital_announcements;
create policy announcements_admin_insert on public.hospital_announcements for insert to authenticated
  with check ((is_global and public.is_super_admin()) or (hospital_id is not null and public.is_hospital_admin_for(hospital_id)));
create policy announcements_admin_update on public.hospital_announcements for update to authenticated
  using ((is_global and public.is_super_admin()) or (hospital_id is not null and public.is_hospital_admin_for(hospital_id)))
  with check ((is_global and public.is_super_admin()) or (hospital_id is not null and public.is_hospital_admin_for(hospital_id)));
create policy announcements_admin_delete on public.hospital_announcements for delete to authenticated
  using ((is_global and public.is_super_admin()) or (hospital_id is not null and public.is_hospital_admin_for(hospital_id)));

create or replace function public.log_audit_event()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  row_data jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  target_hospital_id uuid;
begin
  target_hospital_id := coalesce(
    nullif(row_data ->> 'hospital_id', '')::uuid,
    nullif(row_data ->> 'preferred_hospital_id', '')::uuid,
    nullif(row_data ->> 'primary_hospital_id', '')::uuid
  );

  insert into public.audit_logs (user_id, hospital_id, action, module, record_id)
  values (
    public.current_user_id(),
    target_hospital_id,
    lower(tg_op),
    tg_table_name,
    nullif(row_data ->> 'id', '')::uuid
  );
  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$$;

revoke all on function public.log_audit_event() from public, anon, authenticated;

create trigger audit_hospitals after insert or update or delete on public.hospitals for each row execute function public.log_audit_event();
create trigger audit_departments after insert or update or delete on public.hospital_departments for each row execute function public.log_audit_event();
create trigger audit_services after insert or update or delete on public.hospital_services for each row execute function public.log_audit_event();
create trigger audit_rooms after insert or update or delete on public.hospital_rooms for each row execute function public.log_audit_event();
create trigger audit_beds after insert or update or delete on public.hospital_beds for each row execute function public.log_audit_event();
create trigger audit_emergency_status after insert or update or delete on public.emergency_room_status for each row execute function public.log_audit_event();
create trigger audit_doctors after insert or update or delete on public.doctors for each row execute function public.log_audit_event();
create trigger audit_guest_requests after insert or update or delete on public.guest_consultation_requests for each row execute function public.log_audit_event();
create trigger audit_consultations after insert or update or delete on public.consultations for each row execute function public.log_audit_event();
create trigger audit_medical_records after insert or update or delete on public.medical_records for each row execute function public.log_audit_event();
create trigger audit_laboratory_results after insert or update or delete on public.laboratory_results for each row execute function public.log_audit_event();
create trigger audit_prescriptions after insert or update or delete on public.prescriptions for each row execute function public.log_audit_event();

commit;
