-- Storage update/delete policies call this security-definer ownership helper.
-- Authenticated users need EXECUTE permission for PostgreSQL to evaluate the
-- policy; the function itself still restricts access to the original uploader.

grant execute on function private.is_storage_upload_owner(text)
  to authenticated, service_role;
