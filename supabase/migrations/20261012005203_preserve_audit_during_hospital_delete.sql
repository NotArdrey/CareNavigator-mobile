-- Preserve delete audit records even when their hospital has already been
-- removed by the parent DELETE. The original ID remains in audit metadata.
CREATE OR REPLACE FUNCTION public.log_audit_event()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  row_data jsonb := CASE WHEN tg_op = 'DELETE' THEN to_jsonb(old) ELSE to_jsonb(new) END;
  original_hospital_id uuid;
  target_hospital_id uuid;
BEGIN
  original_hospital_id := coalesce(
    nullif(row_data ->> 'hospital_id', '')::uuid,
    nullif(row_data ->> 'preferred_hospital_id', '')::uuid,
    nullif(row_data ->> 'primary_hospital_id', '')::uuid
  );
  SELECT h.id INTO target_hospital_id FROM public.hospitals h
    WHERE h.id = original_hospital_id FOR KEY SHARE;
  INSERT INTO public.audit_logs(user_id,hospital_id,action,module,record_id,metadata)
  VALUES(private.current_user_id(),target_hospital_id,lower(tg_op),tg_table_name,
    nullif(row_data ->> 'id','')::uuid,
    jsonb_build_object('source_hospital_id',original_hospital_id));
  IF tg_op = 'DELETE' THEN RETURN old; END IF;
  RETURN new;
END;
$function$;

CREATE OR REPLACE FUNCTION private.audit_multi_hospital_change()
RETURNS trigger LANGUAGE plpgsql SECURITY DEFINER SET search_path TO ''
AS $function$
DECLARE
  payload jsonb := CASE WHEN tg_op = 'DELETE' THEN to_jsonb(old) ELSE to_jsonb(new) END;
  original_hospital_id uuid := nullif(payload->>'hospital_id','')::uuid;
  actor_hospital uuid;
  target_id uuid := nullif(payload->>'id','')::uuid;
BEGIN
  SELECT h.id INTO actor_hospital FROM public.hospitals h
    WHERE h.id = original_hospital_id FOR KEY SHARE;
  INSERT INTO public.audit_logs(user_id,hospital_id,action,module,record_id,metadata)
  VALUES(private.current_user_id(),actor_hospital,lower(tg_op),tg_table_name,target_id,
    jsonb_build_object('table',tg_table_schema||'.'||tg_table_name,
      'source_hospital_id',original_hospital_id,'patient_id',payload->>'patient_id',
      'care_relationship_id',payload->>'care_relationship_id','request_id',payload->>'request_id'));
  IF tg_op = 'DELETE' THEN RETURN old; END IF;
  RETURN new;
END;
$function$;
