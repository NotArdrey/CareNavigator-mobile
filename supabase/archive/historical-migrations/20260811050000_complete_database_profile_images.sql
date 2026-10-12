-- Keep profile imagery database-backed for every existing account. The
-- deterministic placeholder is replaced automatically when a user uploads a
-- real profile photo.
update public.users
set profile_image_url = 'https://api.dicebear.com/9.x/personas/png?seed=' || id::text
where nullif(btrim(profile_image_url), '') is null;

