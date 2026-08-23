-- Repeatable post-migration comparison report. This query is read-only.

select 'patient_hospital_identifiers' as metric,
       count(*)::bigint as value
from public.patient_hospital_identifiers
union all
select 'verified_active_doctor_employments', count(*)::bigint
from public.doctor_hospital_employments
where employment_status = 'active'
  and is_verified
  and starts_at <= now()
  and (ends_at is null or ends_at > now())
union all
select 'care_relationships', count(*)::bigint
from public.patient_care_relationships
union all
select 'active_access_grants', count(*)::bigint
from public.patient_access_grants
where status = 'active' and revoked_at is null and expires_at > now()
union all
select 'unresolved_quarantine', count(*)::bigint
from public.clinical_record_quarantine
where resolved_at is null
union all
select 'consultations_missing_hospital', count(*)::bigint
from public.consultations
where hospital_id is null
union all
select 'prescriptions_missing_hospital', count(*)::bigint
from public.prescriptions
where hospital_id is null
union all
select 'documents_missing_hospital', count(*)::bigint
from public.medical_documents
where hospital_id is null
union all
select 'active_assignments_missing_provenance', count(*)::bigint
from public.doctor_patient_assignments assignment
left join public.patient_care_relationships relationship
  on relationship.id = assignment.care_relationship_id
where assignment.ended_at is null
  and assignment.assignment_status = 'active'
  and (
    assignment.hospital_id is null
    or assignment.care_relationship_id is null
    or (
      relationship.relationship_type = 'consultation'
      and assignment.consultation_id is null
    )
  )
order by metric;
