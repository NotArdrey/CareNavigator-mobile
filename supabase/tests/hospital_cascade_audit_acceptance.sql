-- No fixture or audit change survives this suite.
BEGIN;
DO $test$
DECLARE
  target_hospital_id uuid := gen_random_uuid();
  bed_id uuid := gen_random_uuid();
BEGIN
  INSERT INTO public.hospitals(id,hospital_name,address,city,province,operating_status,verification_status)
    VALUES(target_hospital_id,'SYNTHETIC transactional cascade test '||target_hospital_id,
      'Synthetic test address','Test City','Test Province','closed','pending');
  INSERT INTO public.hospital_beds(id,hospital_id,bed_type,total_beds,available_beds,occupied_beds)
    VALUES(bed_id,target_hospital_id,'SYNTHETIC cascade bed',2,2,0);
  DELETE FROM public.hospitals WHERE id=target_hospital_id;
  IF EXISTS(SELECT 1 FROM public.hospital_beds WHERE id=bed_id) THEN
    RAISE EXCEPTION 'Hospital deletion did not cascade to its synthetic bed';
  END IF;
  IF NOT EXISTS(SELECT 1 FROM public.audit_logs WHERE record_id=bed_id AND action='delete'
    AND hospital_id IS NULL AND metadata->>'source_hospital_id'=target_hospital_id::text) THEN
    RAISE EXCEPTION 'Cascade deletion did not preserve the bed audit provenance';
  END IF;
END;
$test$;
ROLLBACK;
