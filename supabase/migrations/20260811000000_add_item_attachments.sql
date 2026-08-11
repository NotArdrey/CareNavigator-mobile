-- Add reference fields to medical_documents table to associate files with specific actions
ALTER TABLE public.medical_documents 
  ADD COLUMN IF NOT EXISTS reference_id UUID,
  ADD COLUMN IF NOT EXISTS reference_type TEXT;

-- We also want to ensure these are indexed for faster lookups when loading a specific item
CREATE INDEX IF NOT EXISTS medical_documents_reference_idx 
  ON public.medical_documents(reference_id, reference_type);

-- If the existing policies on medical_documents use patient_id, they will still work.
-- A user authorized to see the patient will be able to see the files associated with the patient's actions.
