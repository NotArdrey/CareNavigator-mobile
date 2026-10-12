update storage.buckets
set allowed_mime_types = array[
  'image/jpeg',
  'image/png',
  'application/pdf',
  'application/msword',
  'application/vnd.openxmlformats-officedocument.wordprocessingml.document'
]::text[]
where id = 'medical-documents';
