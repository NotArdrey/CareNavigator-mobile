-- The function intentionally uses SECURITY DEFINER so occupied consultations
-- can be filtered without exposing any appointment or patient record. Only a
-- signed-in account may request the resulting anonymous time list.
revoke all on function public.list_available_consultation_slots(
  uuid,
  public.consultation_type,
  integer
) from public;
revoke all on function public.list_available_consultation_slots(
  uuid,
  public.consultation_type,
  integer
) from anon;
grant execute on function public.list_available_consultation_slots(
  uuid,
  public.consultation_type,
  integer
) to authenticated;
