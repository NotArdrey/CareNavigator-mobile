insert into storage.buckets (
  id,
  name,
  public,
  file_size_limit,
  allowed_mime_types
)
values (
  'hospital-images',
  'hospital-images',
  true,
  10485760,
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do update set
  public = true,
  file_size_limit = excluded.file_size_limit,
  allowed_mime_types = excluded.allowed_mime_types;

drop policy if exists "Hospital directory images are publicly readable"
  on storage.objects;
create policy "Hospital directory images are publicly readable"
on storage.objects for select
using (bucket_id = 'hospital-images');

update public.hospitals
set
  image_url = 'https://crhsbpkuteyqbxjpozrp.supabase.co/storage/v1/object/public/hospital-images/directory/aurora-memorial-hospital.jpg',
  image_attribution = 'Photo source: CCT Constructors Corporation',
  image_source_url = 'https://cctconst.com/portfolio-view/aurora-memorial-hospital/'
where hospital_name = 'Aurora Memorial Hospital';

update public.hospitals
set
  image_url = 'https://crhsbpkuteyqbxjpozrp.supabase.co/storage/v1/object/public/hospital-images/directory/bataan-general-hospital.jpg',
  image_attribution = 'Presidential Communications Office - Public domain',
  image_source_url = 'https://commons.wikimedia.org/wiki/File:2025-09-02_%E2%80%93_PBBM_visits_Bataan_General_Hospital_to_check_on_zero_balance_billing_program_%2802%29.jpg'
where hospital_name = 'Bataan General Hospital and Medical Center';

update public.hospitals
set
  image_url = 'https://crhsbpkuteyqbxjpozrp.supabase.co/storage/v1/object/public/hospital-images/directory/bulacan-medical-center.jpg',
  image_attribution = 'Photo source: Manila Bulletin',
  image_source_url = 'https://mb.com.ph/2023/5/25/bmc-s-luntiang-silong-cited-for-excellent-hiv-treatment-initiation'
where hospital_name = 'Bulacan Medical Center';

update public.hospitals
set
  image_url = 'https://crhsbpkuteyqbxjpozrp.supabase.co/storage/v1/object/public/hospital-images/directory/paulino-garcia-medical-center.jpg',
  image_attribution = 'Jarel Zoldyck - CC BY 4.0',
  image_source_url = 'https://commons.wikimedia.org/wiki/File:Dr._Paulino_J._Garcia_Memorial_Research_and_Medical_Center_(PJG),_Cabanatuan_City.jpg'
where hospital_name = 'Dr. Paulino J. Garcia Memorial Research and Medical Center';

update public.hospitals
set
  image_url = 'https://crhsbpkuteyqbxjpozrp.supabase.co/storage/v1/object/public/hospital-images/directory/jose-lingad-memorial-general-hospital.jpg',
  image_attribution = 'Ramon FVelasquez - CC BY-SA 3.0',
  image_source_url = 'https://commons.wikimedia.org/wiki/File:Lingadjf2.JPG'
where hospital_name = 'Jose B. Lingad Memorial General Hospital';

update public.hospitals
set
  image_url = 'https://crhsbpkuteyqbxjpozrp.supabase.co/storage/v1/object/public/hospital-images/directory/president-ramon-magsaysay-memorial-hospital.jpg',
  image_attribution = 'Photo source: RH-Care',
  image_source_url = 'https://rh-care.info/clinic/president-ramon-magsaysay-memorial-hospital-balin-kalinga/'
where hospital_name = 'President Ramon Magsaysay Memorial Hospital';

update public.hospitals
set
  image_url = 'https://crhsbpkuteyqbxjpozrp.supabase.co/storage/v1/object/public/hospital-images/directory/tarlac-provincial-hospital.jpg',
  image_attribution = 'Photo source: RH-Care',
  image_source_url = 'https://rh-care.info/clinic/tarlac-provincial-hospital-tph-cares/'
where hospital_name = 'Tarlac Provincial Hospital';

