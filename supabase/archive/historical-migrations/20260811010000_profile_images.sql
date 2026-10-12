alter table public.users
  add column if not exists profile_image_url text;

insert into storage.buckets (id, name, public)
values ('profile-images', 'profile-images', true)
on conflict (id) do update set public = true;

create policy "Profile images are publicly readable"
on storage.objects for select
using (bucket_id = 'profile-images');

create policy "Authenticated users can upload profile images"
on storage.objects for insert to authenticated
with check (bucket_id = 'profile-images');

create policy "Authenticated users can update profile images"
on storage.objects for update to authenticated
using (bucket_id = 'profile-images')
with check (bucket_id = 'profile-images');
