-- Explicitly share a patient-supplied document within existing consent scope.
create or replace function public.share_patient_document_for_review(target_document_id uuid,target_relationship_id uuid)
returns jsonb language plpgsql security definer set search_path='' as $$
declare d public.medical_documents; relationship public.patient_care_relationships; shared_count int;
begin
  if not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null and not coalesce(is_anonymous,false)) then
    raise exception 'A verified patient identity is required'; end if;
  select * into d from public.medical_documents where id=target_document_id for update;
  if d.id is null or d.patient_id is distinct from private.current_patient_id()
    or d.uploaded_by is distinct from private.current_user_id() or d.origin_type<>'patient_supplied' then
    raise exception 'Share only your own supporting document'; end if;
  select * into relationship from public.patient_care_relationships where id=target_relationship_id for update;
  if relationship.id is null or relationship.patient_id is distinct from d.patient_id or relationship.status<>'active' then
    raise exception 'Choose an active care relationship belonging to you'; end if;
  perform 1 from public.patient_access_grants g where g.care_relationship_id=relationship.id for update;
  insert into public.patient_access_record_selections(grant_id,record_category,source_table,record_id)
  select g.id,'medical_documents','medical_documents',d.id from public.patient_access_grants g
  where g.care_relationship_id=relationship.id and g.patient_id=d.patient_id and g.status='active'
    and g.revoked_at is null and g.expires_at>now() and g.receiving_doctor_id is not null
    and exists(select 1 from public.doctor_hospital_employments e join public.doctors doctor on doctor.id=e.doctor_id
      join public.users u on u.id=doctor.user_id where e.doctor_id=g.receiving_doctor_id and e.hospital_id=g.receiving_hospital_id
      and e.employment_status='active' and e.is_verified and e.starts_at<=now() and (e.ends_at is null or e.ends_at>now())
      and u.account_status='active')
    and exists(select 1 from public.patient_access_scopes s where s.grant_id=g.id and s.record_category='medical_documents')
  on conflict(grant_id,source_table,record_id) do nothing;
  select count(*) into shared_count from public.patient_access_record_selections s join public.patient_access_grants g on g.id=s.grant_id
  where g.care_relationship_id=relationship.id and g.status='active' and g.expires_at>now()
    and s.source_table='medical_documents' and s.record_id=d.id;
  if shared_count=0 then raise exception 'This relationship does not include supporting-document sharing. Request care with document sharing enabled.'; end if;
  perform private.enqueue_notification(u.auth_user_id,'Supporting document ready for review','The patient shared a supporting document for your review.',
    'medical_result',d.id,jsonb_build_object('document_id',d.id,'care_relationship_id',relationship.id,'event_key','document-review-share:'||d.id::text||':'||relationship.id::text))
  from public.doctors doctor join public.users u on u.id=doctor.user_id
  where doctor.id in (select g.receiving_doctor_id from public.patient_access_grants g where g.care_relationship_id=relationship.id and g.status='active');
  return jsonb_build_object('document_id',d.id,'care_relationship_id',relationship.id,'shared_grants',shared_count);
end $$;
revoke all on function public.share_patient_document_for_review(uuid,uuid) from public,anon;
grant execute on function public.share_patient_document_for_review(uuid,uuid) to authenticated;
