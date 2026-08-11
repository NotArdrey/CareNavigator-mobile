alter table public.hospitals
  add column if not exists image_attribution text,
  add column if not exists image_source_url text;

alter table public.doctors
  add column if not exists profile_image_url text;

-- Use verified real-hospital photography when an appropriate reusable source
-- is available. These URLs remain database content rather than UI defaults.
update public.hospitals
set
  image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/e/e6/Lingadjf2.JPG/1280px-Lingadjf2.JPG',
  image_attribution = 'Ramon FVelasquez · CC BY-SA 3.0',
  image_source_url = 'https://commons.wikimedia.org/wiki/File:Lingadjf2.JPG'
where hospital_name ilike '%Jose B.%Lingad%';

update public.hospitals
set
  image_url = 'https://upload.wikimedia.org/wikipedia/commons/thumb/0/06/2025-09-02_%E2%80%93_PBBM_visits_Bataan_General_Hospital_to_check_on_zero_balance_billing_program_%2802%29.jpg/1280px-2025-09-02_%E2%80%93_PBBM_visits_Bataan_General_Hospital_to_check_on_zero_balance_billing_program_%2802%29.jpg',
  image_attribution = 'Presidential Communications Office · Public domain',
  image_source_url = 'https://commons.wikimedia.org/wiki/File:2025-09-02_%E2%80%93_PBBM_visits_Bataan_General_Hospital_to_check_on_zero_balance_billing_program_%2802%29.jpg'
where hospital_name ilike '%Bataan General Hospital%';

-- Every remaining hospital receives a database-backed dummy photo. Admins can
-- replace it with a verified facility photo without an application release.
update public.hospitals
set
  image_url = 'https://placehold.co/1280x800/0f766e/ffffff/png?text=Hospital',
  image_attribution = 'Hospital placeholder',
  image_source_url = 'https://placehold.co/'
where nullif(btrim(image_url), '') is null;

-- Doctor portraits use the existing user profile image column. Demo and
-- missing profiles get deterministic database values until a photo is added.
update public.users
set profile_image_url = case lower(email)
  when 'doctor@demo.test'
    then 'https://api.dicebear.com/9.x/personas/png?seed=Maria%20Santos&backgroundColor=d1fae5'
  when 'history.doctor@demo.test'
    then 'https://api.dicebear.com/9.x/personas/png?seed=Elena%20Reyes&backgroundColor=dbeafe'
  else 'https://api.dicebear.com/9.x/personas/png?seed=' || id::text
end
where id in (select user_id from public.doctors)
  and nullif(btrim(profile_image_url), '') is null;

update public.doctors as doctor
set profile_image_url = app_user.profile_image_url
from public.users as app_user
where app_user.id = doctor.user_id
  and nullif(btrim(app_user.profile_image_url), '') is not null;

create or replace function public.sync_doctor_profile_image()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
begin
  update public.doctors
  set profile_image_url = new.profile_image_url
  where user_id = new.id;
  return new;
end;
$$;

drop trigger if exists sync_doctor_profile_image on public.users;
create trigger sync_doctor_profile_image
after update of profile_image_url on public.users
for each row execute function public.sync_doctor_profile_image();
