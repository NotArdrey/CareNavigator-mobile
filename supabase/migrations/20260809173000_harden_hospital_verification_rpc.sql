-- Supabase may retain an explicit anon EXECUTE grant even after PUBLIC is
-- revoked. This privileged wrapper is a signed-in governance action only.
revoke execute on function public.review_hospital_application(
  uuid,
  public.verification_status,
  text
) from anon;

grant execute on function public.review_hospital_application(
  uuid,
  public.verification_status,
  text
) to authenticated;
