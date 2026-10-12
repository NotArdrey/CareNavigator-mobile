create schema auth;create schema storage;create schema extensions;create extension pgcrypto with schema extensions;create type storage.buckettype as enum('STANDARD','ANALYTICS','VECTOR');
create table auth.users ("instance_id" uuid,"id" uuid primary key,"aud" character varying(255),"role" character varying(255),"email" character varying(255),"encrypted_password" character varying(255),"email_confirmed_at" timestamp with time zone,"invited_at" timestamp with time zone,"confirmation_token" character varying(255),"confirmation_sent_at" timestamp with time zone,"recovery_token" character varying(255),"recovery_sent_at" timestamp with time zone,"email_change_token_new" character varying(255),"email_change" character varying(255),"email_change_sent_at" timestamp with time zone,"last_sign_in_at" timestamp with time zone,"raw_app_meta_data" jsonb,"raw_user_meta_data" jsonb,"is_super_admin" boolean,"created_at" timestamp with time zone,"updated_at" timestamp with time zone,"phone" text,"phone_confirmed_at" timestamp with time zone,"phone_change" text,"phone_change_token" character varying(255),"phone_change_sent_at" timestamp with time zone,"confirmed_at" timestamp with time zone,"email_change_token_current" character varying(255),"email_change_confirm_status" smallint,"banned_until" timestamp with time zone,"reauthentication_token" character varying(255),"reauthentication_sent_at" timestamp with time zone,"is_sso_user" boolean,"deleted_at" timestamp with time zone,"is_anonymous" boolean);
create table storage.buckets ("id" text primary key,"name" text,"owner" uuid,"created_at" timestamp with time zone,"updated_at" timestamp with time zone,"public" boolean,"avif_autodetection" boolean,"file_size_limit" bigint,"allowed_mime_types" text[],"owner_id" text,"type" storage.buckettype,"versioning_status" text,"lifecycle_configuration" jsonb,"lifecycle_configuration_generation" uuid);
create table storage.objects ("id" uuid primary key,"bucket_id" text,"name" text,"owner" uuid,"created_at" timestamp with time zone,"updated_at" timestamp with time zone,"last_accessed_at" timestamp with time zone,"metadata" jsonb,"path_tokens" text[],"version" text,"owner_id" text,"user_metadata" jsonb,"archived_at" timestamp with time zone,"is_delete_marker" boolean,"is_versioned" boolean);
CREATE OR REPLACE FUNCTION auth.uid()
 RETURNS uuid
 LANGUAGE sql
 STABLE
AS $function$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.sub', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'sub')
  )::uuid
$function$
;
CREATE OR REPLACE FUNCTION auth.role()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.role', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'role')
  )::text
$function$
;
CREATE OR REPLACE FUNCTION auth.email()
 RETURNS text
 LANGUAGE sql
 STABLE
AS $function$
  select 
  coalesce(
    nullif(current_setting('request.jwt.claim.email', true), ''),
    (nullif(current_setting('request.jwt.claims', true), '')::jsonb ->> 'email')
  )::text
$function$
;
CREATE OR REPLACE FUNCTION auth.jwt()
 RETURNS jsonb
 LANGUAGE sql
 STABLE
AS $function$
  select 
    coalesce(
        nullif(current_setting('request.jwt.claim', true), ''),
        nullif(current_setting('request.jwt.claims', true), '')
    )::jsonb
$function$
;
CREATE OR REPLACE FUNCTION storage.filename(name text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    _parts text[];
BEGIN
    SELECT string_to_array(name, '/') INTO _parts;
    RETURN _parts[array_length(_parts, 1)];
END
$function$
;
CREATE OR REPLACE FUNCTION storage.extension(name text)
 RETURNS text
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    _parts text[];
    _filename text;
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Get the last path segment (the actual filename)
    SELECT _parts[array_length(_parts, 1)] INTO _filename;
    -- Extract extension: reverse, split on '.', then reverse again
    RETURN reverse(split_part(reverse(_filename), '.', 1));
END
$function$
;
CREATE OR REPLACE FUNCTION storage.foldername(name text)
 RETURNS text[]
 LANGUAGE plpgsql
 IMMUTABLE
AS $function$
DECLARE
    _parts text[];
BEGIN
    -- Split on "/" to get path segments
    SELECT string_to_array(name, '/') INTO _parts;
    -- Return everything except the last segment
    RETURN _parts[1 : array_length(_parts,1) - 1];
END
$function$
;