begin;

insert into auth.users(
  id,aud,role,is_anonymous,raw_app_meta_data,raw_user_meta_data
) values
(
  '12000000-0000-4000-8000-000000000001','authenticated','authenticated',true,
  '{"provider":"anonymous","providers":["anonymous"]}',
  '{"access_purpose":"guest_symptom_assessment"}'
),
(
  '12000000-0000-4000-8000-000000000002','authenticated','authenticated',true,
  '{"provider":"anonymous","providers":["anonymous"]}',
  '{"access_purpose":"guest_symptom_assessment"}'
);

do $$
begin
  if exists(
    select 1 from public.users
    where auth_user_id in(
      '12000000-0000-4000-8000-000000000001',
      '12000000-0000-4000-8000-000000000002'
    )
  ) then
    raise exception 'Anonymous transport identities became application accounts';
  end if;
end
$$;

set local role authenticated;
select set_config(
  'request.jwt.claim.sub','12000000-0000-4000-8000-000000000001',true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"12000000-0000-4000-8000-000000000001","role":"authenticated","is_anonymous":true,"user_metadata":{"access_purpose":"guest_symptom_assessment"}}',
  true
);

insert into public.ai_assessments(
  id,user_id,symptoms,urgency_level,recommended_action,disclaimer
) values(
  '22000000-0000-4000-8000-000000000001',
  '12000000-0000-4000-8000-000000000001',
  'Rollback-only guest assessment','routine','Seek appropriate care',
  'Test guidance is not a diagnosis.'
);

do $$
begin
  if not exists(
    select 1 from public.ai_assessments
    where id='22000000-0000-4000-8000-000000000001'
  ) then
    raise exception 'Guest could not read its own standalone assessment';
  end if;
end
$$;

select set_config(
  'request.jwt.claim.sub','12000000-0000-4000-8000-000000000002',true
);
select set_config(
  'request.jwt.claims',
  '{"sub":"12000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":true,"user_metadata":{"access_purpose":"guest_symptom_assessment"}}',
  true
);

do $$
declare
  visible_count integer;
  spoof_rejected boolean := false;
begin
  select count(*) into visible_count
  from public.ai_assessments
  where id='22000000-0000-4000-8000-000000000001';
  if visible_count <> 0 then
    raise exception 'Guest could read another guest assessment';
  end if;

  begin
    insert into public.ai_assessments(
      user_id,symptoms,urgency_level,recommended_action,disclaimer
    ) values(
      '12000000-0000-4000-8000-000000000001',
      'Spoof attempt','routine','No action','Test only'
    );
  exception when insufficient_privilege then
    spoof_rejected := true;
  end;
  if not spoof_rejected then
    raise exception 'Guest could spoof another assessment owner';
  end if;
end
$$;

select set_config(
  'request.jwt.claims',
  '{"sub":"12000000-0000-4000-8000-000000000002","role":"authenticated","is_anonymous":false}',
  true
);

do $$
declare
  non_anonymous_rejected boolean := false;
begin
  begin
    insert into public.ai_assessments(
      user_id,symptoms,urgency_level,recommended_action,disclaimer
    ) values(
      '12000000-0000-4000-8000-000000000002',
      'Non-anonymous accountless attempt','routine','No action','Test only'
    );
  exception when insufficient_privilege then
    non_anonymous_rejected := true;
  end;
  if not non_anonymous_rejected then
    raise exception 'An accountless non-anonymous session could create an assessment';
  end if;
end
$$;

reset role;
rollback;
