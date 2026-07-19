begin;

-- Cover every remaining foreign key reported by the production database linter.
-- These indexes keep deletes/updates on parent records predictable as data grows.
create index if not exists ai_assessment_recommendations_hospital_idx on public.ai_assessment_recommendations (hospital_id);
create index if not exists ai_configurations_updated_by_idx on public.ai_configurations (updated_by);
create index if not exists chat_message_attachments_uploaded_by_idx on public.chat_message_attachments (uploaded_by);
create index if not exists consultation_attachments_guest_request_idx on public.consultation_attachments (guest_request_id);
create index if not exists consultation_attachments_patient_idx on public.consultation_attachments (patient_id);
create index if not exists consultation_attachments_uploaded_by_idx on public.consultation_attachments (uploaded_by);
create index if not exists consultation_status_history_changed_by_idx on public.consultation_status_history (changed_by);
create index if not exists consultations_approved_by_idx on public.consultations (approved_by);
create index if not exists consultations_department_idx on public.consultations (department_id);
create index if not exists consultations_follow_up_of_idx on public.consultations (follow_up_of);
create index if not exists diagnoses_doctor_idx on public.diagnoses (doctor_id);
create index if not exists diagnoses_hospital_idx on public.diagnoses (hospital_id);
create index if not exists document_jobs_laboratory_result_idx on public.document_processing_jobs (laboratory_result_id);
create index if not exists document_jobs_medical_document_idx on public.document_processing_jobs (medical_document_id);
create index if not exists document_jobs_requested_by_idx on public.document_processing_jobs (requested_by);
create index if not exists guest_requests_reviewed_by_idx on public.guest_consultation_requests (reviewed_by);
create index if not exists guest_request_history_changed_by_idx on public.guest_request_status_history (changed_by);
create index if not exists hospital_service_doctors_doctor_hospital_idx on public.hospital_service_doctors (doctor_id, hospital_id);
create index if not exists hospital_service_doctors_service_hospital_idx on public.hospital_service_doctors (service_id, hospital_id);
create index if not exists laboratory_requests_consultation_idx on public.laboratory_requests (consultation_id);
create index if not exists laboratory_requests_hospital_idx on public.laboratory_requests (hospital_id);
create index if not exists laboratory_results_confirmed_by_idx on public.laboratory_results (confirmed_by);
create index if not exists laboratory_results_reviewed_by_idx on public.laboratory_results (reviewed_by);
create index if not exists laboratory_results_source_document_idx on public.laboratory_results (source_document_id);
create index if not exists maintenance_windows_created_by_idx on public.maintenance_windows (created_by);
create index if not exists medical_documents_consultation_idx on public.medical_documents (consultation_id);
create index if not exists medical_documents_hospital_idx on public.medical_documents (hospital_id);
create index if not exists medical_documents_uploaded_by_idx on public.medical_documents (uploaded_by);
create index if not exists medical_records_confirmed_by_idx on public.medical_records (confirmed_by);
create index if not exists medical_records_source_result_idx on public.medical_records (source_laboratory_result_id);
create index if not exists notification_outbox_user_idx on public.notification_outbox (user_id);
create index if not exists patient_consents_captured_by_idx on public.patient_consents (captured_by);
create index if not exists prescriptions_hospital_idx on public.prescriptions (hospital_id);
create index if not exists security_logs_actor_idx on public.security_logs (actor_auth_user_id);
create index if not exists system_settings_updated_by_idx on public.system_settings (updated_by);
create index if not exists treatment_plans_consultation_idx on public.treatment_plans (consultation_id);
create index if not exists treatment_plans_doctor_idx on public.treatment_plans (doctor_id);
create index if not exists treatment_plans_hospital_idx on public.treatment_plans (hospital_id);
create index if not exists video_sessions_created_by_idx on public.video_sessions (created_by);

-- Merge mutually exclusive insert paths so PostgreSQL evaluates one policy.
drop policy if exists consultations_guest_reviewer_insert on public.consultations;
drop policy if exists consultations_patient_insert on public.consultations;
create policy consultations_authorized_insert on public.consultations
for insert to authenticated with check (
  (
    patient_id=private.current_patient_id()
    and guest_request_id is null
    and status='pending'
    and exists (
      select 1 from public.doctors d
      where d.id=doctor_id and d.hospital_id=consultations.hospital_id
    )
    and doctor_notes is null
    and confirmed_diagnosis is null
    and treatment_plan is null
    and meeting_link is null
    and approved_by is null
    and completed_at is null
    and appointment_date > now()
    and (
      follow_up_of is null
      or exists (
        select 1 from public.consultations previous
        where previous.id=consultations.follow_up_of
          and previous.patient_id=private.current_patient_id()
          and previous.status='completed'
      )
    )
  )
  or (
    guest_request_id is not null
    and patient_id is null
    and status in ('approved','scheduled')
    and exists (
      select 1 from public.guest_consultation_requests g
      where g.id=guest_request_id
        and g.preferred_hospital_id=consultations.hospital_id
        and g.assigned_doctor_id=doctor_id
        and (
          g.assigned_doctor_id=private.current_doctor_id()
          or private.is_hospital_admin_for(g.preferred_hospital_id)
        )
    )
  )
);

drop policy if exists patients_doctor_insert on public.patients;
drop policy if exists patients_hospital_admin_temporary_insert on public.patients;
create policy patients_care_team_insert on public.patients
for insert to authenticated with check (
  created_by_doctor=private.current_doctor_id()
  or (
    profile_status='temporary'
    and user_id is null
    and private.is_hospital_admin_for(primary_hospital_id)
  )
);

-- FOR ALL policies overlap their dedicated read policies. Split only the
-- mutating operations while preserving the original checks verbatim.
drop policy if exists document_jobs_doctor_manage on public.document_processing_jobs;
drop policy if exists document_jobs_care_team_read on public.document_processing_jobs;
create policy document_jobs_care_team_read on public.document_processing_jobs
for select to authenticated using (
  requested_by=private.current_doctor_id()
  or exists (
    select 1 from public.laboratory_results r
    where r.id=laboratory_result_id and private.can_access_patient(r.patient_id)
  )
  or exists (
    select 1 from public.medical_documents d
    where d.id=medical_document_id and private.can_access_patient(d.patient_id)
  )
);
create policy document_jobs_doctor_insert on public.document_processing_jobs
for insert to authenticated with check (requested_by=private.current_doctor_id());
create policy document_jobs_doctor_update on public.document_processing_jobs
for update to authenticated using (requested_by=private.current_doctor_id())
with check (requested_by=private.current_doctor_id());
create policy document_jobs_doctor_delete on public.document_processing_jobs
for delete to authenticated using (requested_by=private.current_doctor_id());

drop policy if exists laboratory_requests_doctor_manage on public.laboratory_requests;
create policy laboratory_requests_doctor_insert on public.laboratory_requests
for insert to authenticated with check (
  doctor_id=private.current_doctor_id() and private.can_access_patient(patient_id)
);
create policy laboratory_requests_doctor_update on public.laboratory_requests
for update to authenticated using (doctor_id=private.current_doctor_id())
with check (doctor_id=private.current_doctor_id() and private.can_access_patient(patient_id));
create policy laboratory_requests_doctor_delete on public.laboratory_requests
for delete to authenticated using (doctor_id=private.current_doctor_id());

drop policy if exists treatment_plans_doctor_manage on public.treatment_plans;
create policy treatment_plans_doctor_insert on public.treatment_plans
for insert to authenticated with check (
  doctor_id=private.current_doctor_id() and private.can_access_patient(patient_id)
);
create policy treatment_plans_doctor_update on public.treatment_plans
for update to authenticated using (doctor_id=private.current_doctor_id())
with check (doctor_id=private.current_doctor_id() and private.can_access_patient(patient_id));
create policy treatment_plans_doctor_delete on public.treatment_plans
for delete to authenticated using (doctor_id=private.current_doctor_id());

drop policy if exists patient_consents_patient_manage on public.patient_consents;
create policy patient_consents_patient_insert on public.patient_consents
for insert to authenticated with check (
  patient_id=private.current_patient_id() and captured_by=(select auth.uid())
);
create policy patient_consents_patient_update on public.patient_consents
for update to authenticated using (patient_id=private.current_patient_id())
with check (patient_id=private.current_patient_id() and captured_by=(select auth.uid()));
create policy patient_consents_patient_delete on public.patient_consents
for delete to authenticated using (patient_id=private.current_patient_id());

drop policy if exists maintenance_windows_super_manage on public.maintenance_windows;
create policy maintenance_windows_super_insert on public.maintenance_windows
for insert to authenticated with check (private.is_super_admin());
create policy maintenance_windows_super_update on public.maintenance_windows
for update to authenticated using (private.is_super_admin()) with check (private.is_super_admin());
create policy maintenance_windows_super_delete on public.maintenance_windows
for delete to authenticated using (private.is_super_admin());

drop policy if exists role_permissions_super_manage on public.role_permissions;
create policy role_permissions_super_insert on public.role_permissions
for insert to authenticated with check (private.is_super_admin());
create policy role_permissions_super_update on public.role_permissions
for update to authenticated using (private.is_super_admin()) with check (private.is_super_admin());
create policy role_permissions_super_delete on public.role_permissions
for delete to authenticated using (private.is_super_admin());

drop policy if exists system_settings_super_manage on public.system_settings;
create policy system_settings_super_insert on public.system_settings
for insert to authenticated with check (private.is_super_admin());
create policy system_settings_super_update on public.system_settings
for update to authenticated using (private.is_super_admin()) with check (private.is_super_admin());
create policy system_settings_super_delete on public.system_settings
for delete to authenticated using (private.is_super_admin());

insert into supabase_migrations.schema_migrations (version, statements, name)
values ('20260716203000', array[]::text[], 'final_performance_hardening')
on conflict (version) do nothing;

commit;
