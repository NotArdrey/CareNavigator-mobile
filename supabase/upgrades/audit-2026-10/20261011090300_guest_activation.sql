alter table public.guest_consultation_requests add column submission_key text;
create unique index guest_submission_idempotency on public.guest_consultation_requests(submitted_by,submission_key)
where submission_key is not null;

create or replace function public.submit_guest_consultation_request(request_payload jsonb, idempotency_key text)
returns uuid language plpgsql security definer set search_path = '' as $$
declare account auth.users; request_id uuid;
begin
  select * into account from auth.users where id=auth.uid();
  if not found or account.email_confirmed_at is null or coalesce(account.is_anonymous,false)
    or lower(account.email) is distinct from lower(btrim(request_payload->>'email'))
    or private.current_user_id() is null then raise exception 'Verify this request email before submitting'; end if;
  if length(coalesce(idempotency_key,''))<16 or length(idempotency_key)>160 then raise exception 'A submission idempotency key is required'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(account.id::text||':'||idempotency_key,0));
  select id into request_id from public.guest_consultation_requests where submitted_by=account.id and submission_key=idempotency_key;
  if found then return request_id; end if;
  if length(btrim(coalesce(request_payload->>'symptoms','')))<10
    or nullif(btrim(request_payload->>'symptom_duration'),'') is null then raise exception 'Complete the care concern and symptom duration'; end if;
  if request_payload->>'preferred_consultation_type' not in ('face_to_face','guest_online') then raise exception 'Invalid guest care mode'; end if;
  if not exists (select 1 from public.hospital_departments d join public.hospitals h on h.id=d.hospital_id
    where d.id=(request_payload->>'preferred_department_id')::uuid
      and h.id=(request_payload->>'preferred_hospital_id')::uuid and h.verification_status='verified'
      and h.operating_status in ('open','limited') and d.availability_status<>'unavailable'
      and (request_payload->>'preferred_consultation_type'<>'guest_online' or private.has_online_reviewer(h.id))) then
    raise exception 'Choose an eligible hospital and department'; end if;
  insert into public.guest_consultation_requests(submitted_by,submission_key,first_name,last_name,full_name,
    birth_date,sex,mobile_number,email,address,symptoms,symptom_duration,consultation_reason,
    preferred_hospital_id,preferred_department_id,preferred_consultation_type,preferred_schedule,otp_verified_at,consent_at)
  values(account.id,idempotency_key,btrim(request_payload->>'first_name'),btrim(request_payload->>'last_name'),
    btrim(concat_ws(' ',request_payload->>'first_name',request_payload->>'last_name')),
    (request_payload->>'birth_date')::date,(request_payload->>'sex')::public.sex_type,
    btrim(request_payload->>'mobile_number'),lower(account.email),btrim(request_payload->>'address'),
    btrim(request_payload->>'symptoms'),btrim(request_payload->>'symptom_duration'),btrim(request_payload->>'symptoms'),
    (request_payload->>'preferred_hospital_id')::uuid,(request_payload->>'preferred_department_id')::uuid,
    (request_payload->>'preferred_consultation_type')::public.consultation_type,(request_payload->>'preferred_schedule')::timestamptz,now(),now())
  returning id into request_id;
  return request_id;
end $$;
revoke all on function public.submit_guest_consultation_request(jsonb,text) from public,anon;
grant execute on function public.submit_guest_consultation_request(jsonb,text) to authenticated;

create or replace function public.activate_approved_guest(target_request_id uuid)
returns jsonb language plpgsql security definer set search_path = '' as $$
declare r public.guest_consultation_requests; p public.patients; u public.users; a auth.users; existing_id uuid;
begin
  select * into a from auth.users where id=auth.uid();
  select * into r from public.guest_consultation_requests where id=target_request_id for update;
  if r.id is null or a.id is null or a.email_confirmed_at is null or coalesce(a.is_anonymous,false)
    or r.submitted_by is distinct from a.id or lower(r.email) is distinct from lower(a.email) then
    raise exception 'Use the verified account that submitted this request'; end if;
  if r.request_status not in ('approved','temporary_patient_created','account_activation_pending','consultation_scheduled','consultation_completed') then
    raise exception 'Hospital approval is required before activation'; end if;
  select * into u from public.users where auth_user_id=a.id for update;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('guest-activation:'||a.id::text,0));
  if u.id is null or (select role_name from public.roles where id=u.role_id) not in ('guest','patient') or u.account_status<>'active' then
    return jsonb_build_object('status','identity_conflict','resolution_action','Sign in with the verified patient account or contact the hospital to resolve the identity. Your consultation tracking remains available.'); end if;
  select patient.* into p from public.patients patient join public.consultations c on c.patient_id=patient.id
    where c.guest_request_id=r.id order by c.created_at desc limit 1 for update of patient;
  if p.id is null then select * into p from public.patients where guest_request_id=r.id for update; end if;
  if p.id is null then raise exception 'The approved temporary patient has not been prepared'; end if;
  select id into existing_id from public.patients where user_id=u.id and id<>p.id;
  if existing_id is not null or (p.user_id is not null and p.user_id<>u.id) then
    return jsonb_build_object('status','identity_conflict','resolution_action','Ask the hospital to reconcile the existing patient profiles. Your consultation tracking remains available.'); end if;
  update public.patients set user_id=u.id,profile_status='official',account_activation_status='active',
    activated_at=coalesce(activated_at,now()),converted_from_guest=true,converted_at=coalesce(converted_at,now()) where id=p.id;
  update public.users set role_id=(select id from public.roles where role_name='patient') where id=u.id;
  return jsonb_build_object('status','active','patient_id',p.id,'password_action','patient_controlled');
end $$;
revoke all on function public.activate_approved_guest(uuid) from public,anon;
grant execute on function public.activate_approved_guest(uuid) to authenticated;

CREATE OR REPLACE FUNCTION public.protect_user_privileges()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor_role text := private.current_role();
begin
  if (select auth.uid()) is null or actor_role = 'super_admin' then
    return new;
  end if;

  if actor_role = 'hospital_admin' and old.hospital_id = private.current_hospital_id() then
    if new.auth_user_id is distinct from old.auth_user_id
       or new.role_id is distinct from old.role_id
       or new.hospital_id is distinct from old.hospital_id then
      raise exception 'Hospital administrators cannot change identity, role, or hospital assignment directly';
    end if;
    return new;
  end if;

  if old.auth_user_id = (select auth.uid()) then
    if actor_role='guest' and new.role_id=(select id from public.roles where role_name='patient')
      and new.account_status=old.account_status and new.hospital_id is not distinct from old.hospital_id
      and new.auth_user_id=old.auth_user_id
      and exists (select 1 from public.patients p join public.consultations c on c.patient_id=p.id
        join public.guest_consultation_requests g on g.id=c.guest_request_id
        join auth.users a on a.id=g.submitted_by
        where p.user_id=old.id and p.profile_status='official' and p.account_activation_status='active'
          and g.submitted_by=auth.uid() and a.email_confirmed_at is not null
          and lower(a.email)=lower(g.email) and g.request_status in ('consultation_scheduled','consultation_completed')) then
      return new;
    end if;
    if new.auth_user_id is distinct from old.auth_user_id
       or new.role_id is distinct from old.role_id
       or new.hospital_id is distinct from old.hospital_id
       or new.account_status is distinct from old.account_status then
      raise exception 'Role, hospital, identity, and account status are protected';
    end if;
    return new;
  end if;

  raise exception 'Not authorized to update this user';
end;
$function$
;
