-- Sanitized CareNavigator application baseline, 2026-10-11.

-- Apply only to an empty Supabase application schema; platform auth/storage exist first.

create schema if not exists private;

set check_function_bodies = off;

create type "public"."account_status" as enum ('pending','active','inactive','suspended');

create type "public"."availability_status" as enum ('available','limited','unavailable');

create type "public"."consultation_status" as enum ('pending','approved','rejected','scheduled','in_progress','completed','cancelled');

create type "public"."consultation_type" as enum ('face_to_face','online','emergency','guest_online');

create type "public"."conversation_status" as enum ('pending','active','closed','archived');

create type "public"."emergency_room_state" as enum ('available','limited','full','temporarily_closed');

create type "public"."guest_request_status" as enum ('pending_verification','otp_verified','pending_doctor_review','approved','rejected','temporary_patient_created','account_activation_pending','consultation_scheduled','consultation_completed','cancelled');

create type "public"."hospital_operating_status" as enum ('open','limited','temporarily_closed','closed');

create type "public"."medical_result_status" as enum ('uploaded','ocr_processing','ai_analysis_pending','pending_doctor_review','doctor_confirmed','doctor_modified','rejected','saved_to_patient_record');

create type "public"."sex_type" as enum ('female','male','intersex','prefer_not_to_say');

create type "public"."urgency_level" as enum ('self_care','routine','urgent','emergency');

create type "public"."verification_status" as enum ('pending','verified','rejected');

create sequence "public"."guest_consultation_reference_seq" as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;

create sequence "public"."online_consultation_reference_seq" as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;

create sequence "public"."patient_number_seq" as bigint increment 1 minvalue 1 maxvalue 9223372036854775807 start 1 cache 1;

create table "public"."ai_assessment_recommendations" (
  "id" uuid default gen_random_uuid() not null,
  "assessment_id" uuid not null,
  "hospital_id" uuid not null,
  "rank" integer not null,
  "score" numeric(8,3) not null,
  "reasons" text[] default '{}'::text[] not null,
  "distance_km" numeric(10,3),
  "created_at" timestamp with time zone default now() not null
);

create table "public"."ai_assessments" (
  "id" uuid default gen_random_uuid() not null,
  "user_id" uuid,
  "patient_id" uuid,
  "guest_request_id" uuid,
  "symptoms" text not null,
  "symptom_duration" text,
  "possible_conditions" jsonb default '[]'::jsonb not null,
  "urgency_level" urgency_level not null,
  "warning_signs" jsonb default '[]'::jsonb not null,
  "recommended_action" text not null,
  "recommended_department" text,
  "recommended_hospital_id" uuid,
  "groq_response" jsonb default '{}'::jsonb not null,
  "disclaimer" text default 'This preliminary guidance is not a diagnosis. Consult a licensed healthcare professional.'::text not null,
  "model_name" text,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."ai_configurations" (
  "id" uuid default gen_random_uuid() not null,
  "configuration_key" text not null,
  "purpose" text not null,
  "provider" text default 'groq'::text not null,
  "model_name" text not null,
  "prompt_template" text,
  "configuration" jsonb default '{}'::jsonb not null,
  "is_active" boolean default true not null,
  "updated_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."appointment_reminder_jobs" (
  "consultation_id" uuid not null,
  "appointment_date" timestamp with time zone not null,
  "processed_at" timestamp with time zone default now() not null
);

create table "public"."audit_logs" (
  "id" bigint generated always as identity not null,
  "user_id" uuid,
  "hospital_id" uuid,
  "action" text not null,
  "module" text not null,
  "record_id" uuid,
  "metadata" jsonb default '{}'::jsonb not null,
  "ip_address" inet,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."care_assistant_conversations" (
  "id" text not null,
  "user_id" uuid not null,
  "title" text not null,
  "is_pinned" boolean default false not null,
  "is_title_edited" boolean default false not null,
  "payload" jsonb default '{}'::jsonb not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."chat_conversations" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid,
  "guest_request_id" uuid,
  "doctor_id" uuid not null,
  "consultation_id" uuid,
  "status" conversation_status default 'pending'::conversation_status not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."chat_message_attachments" (
  "id" uuid default gen_random_uuid() not null,
  "message_id" uuid not null,
  "uploaded_by" uuid not null,
  "storage_path" text not null,
  "file_name" text not null,
  "mime_type" text,
  "size_bytes" bigint,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."chat_messages" (
  "id" uuid default gen_random_uuid() not null,
  "conversation_id" uuid not null,
  "sender_id" uuid not null,
  "message" text,
  "attachment_path" text,
  "sent_at" timestamp with time zone default now() not null,
  "delivered_at" timestamp with time zone,
  "read_at" timestamp with time zone,
  "message_type" text default 'text'::text not null,
  "edited_at" timestamp with time zone,
  "deleted_at" timestamp with time zone
);

create table "public"."clinical_record_addenda" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "record_category" text not null,
  "source_table" text not null,
  "record_id" uuid not null,
  "originating_hospital_id" uuid not null,
  "author_doctor_id" uuid,
  "author_user_id" uuid not null,
  "addendum_text" text not null,
  "correction_reason" text not null,
  "supersedes_addendum_id" uuid,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."clinical_record_quarantine" (
  "id" uuid default gen_random_uuid() not null,
  "source_table" text not null,
  "record_id" uuid not null,
  "patient_id" uuid,
  "quarantine_reason" text not null,
  "snapshot" jsonb not null,
  "quarantined_at" timestamp with time zone default now() not null,
  "resolved_at" timestamp with time zone,
  "resolved_by" uuid,
  "resolution_notes" text
);

create table "public"."consultation_attachments" (
  "id" uuid default gen_random_uuid() not null,
  "consultation_id" uuid not null,
  "patient_id" uuid,
  "guest_request_id" uuid,
  "uploaded_by" uuid not null,
  "storage_path" text not null,
  "file_name" text not null,
  "mime_type" text,
  "size_bytes" bigint,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."consultation_status_history" (
  "id" bigint generated always as identity not null,
  "consultation_id" uuid not null,
  "old_status" consultation_status,
  "new_status" consultation_status not null,
  "changed_by" uuid,
  "reason" text,
  "metadata" jsonb default '{}'::jsonb not null,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."consultations" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid,
  "guest_request_id" uuid,
  "doctor_id" uuid not null,
  "hospital_id" uuid not null,
  "consultation_type" consultation_type not null,
  "appointment_date" timestamp with time zone not null,
  "status" consultation_status default 'pending'::consultation_status not null,
  "chief_complaint" text not null,
  "doctor_notes" text,
  "confirmed_diagnosis" text,
  "treatment_plan" text,
  "meeting_link" text,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "department_id" uuid,
  "approved_by" uuid,
  "approved_at" timestamp with time zone,
  "rejected_at" timestamp with time zone,
  "rejection_reason" text,
  "started_at" timestamp with time zone,
  "follow_up_of" uuid,
  "consultation_summary" text,
  "height_cm" numeric(5,2),
  "weight_kg" numeric(6,2),
  "bmi" numeric(5,2),
  "blood_pressure_systolic" smallint,
  "blood_pressure_diastolic" smallint,
  "body_temperature_c" numeric(4,1),
  "heart_rate_bpm" smallint,
  "respiratory_rate_bpm" smallint,
  "oxygen_saturation_percent" numeric(5,2),
  "vitals_recorded_at" timestamp with time zone,
  "current_symptoms" text,
  "known_medical_conditions" text[] default '{}'::text[] not null,
  "allergies" text[] default '{}'::text[] not null,
  "current_medications" text[] default '{}'::text[] not null,
  "relevant_medical_history" text,
  "previous_surgeries" text,
  "smoking_status" text,
  "alcohol_use" text,
  "pregnancy_status" text,
  "outcome_reason" text
);

create table "public"."diagnoses" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "consultation_id" uuid not null,
  "doctor_id" uuid not null,
  "hospital_id" uuid not null,
  "diagnosis" text not null,
  "diagnosis_code" text,
  "is_primary" boolean default false not null,
  "confirmed_at" timestamp with time zone default now() not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "source" text default 'manual'::text not null
);

create table "public"."doctor_hospital_employments" (
  "id" uuid default gen_random_uuid() not null,
  "doctor_id" uuid not null,
  "hospital_id" uuid not null,
  "employment_status" text default 'pending'::text not null,
  "is_verified" boolean default false not null,
  "verified_by" uuid,
  "verified_at" timestamp with time zone,
  "starts_at" timestamp with time zone default now() not null,
  "ends_at" timestamp with time zone,
  "termination_reason" text,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."doctor_patient_assignments" (
  "id" uuid default gen_random_uuid() not null,
  "doctor_id" uuid not null,
  "patient_id" uuid not null,
  "assigned_at" timestamp with time zone default now() not null,
  "ended_at" timestamp with time zone,
  "notes" text,
  "hospital_id" uuid,
  "care_relationship_id" uuid,
  "consultation_id" uuid,
  "assignment_status" text default 'active'::text not null,
  "ended_reason" text
);

create table "public"."doctor_schedules" (
  "id" uuid default gen_random_uuid() not null,
  "doctor_id" uuid not null,
  "day_of_week" smallint not null,
  "starts_at" time without time zone not null,
  "ends_at" time without time zone not null,
  "consultation_type" consultation_type default 'online'::consultation_type not null,
  "slot_minutes" integer default 30 not null,
  "is_active" boolean default true not null,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."doctors" (
  "id" uuid default gen_random_uuid() not null,
  "user_id" uuid not null,
  "hospital_id" uuid not null,
  "department_id" uuid,
  "display_name" text not null,
  "specialization" text not null,
  "license_number" text not null,
  "availability_status" availability_status default 'available'::availability_status not null,
  "consultation_fee" numeric(10,2),
  "biography" text,
  "created_by_admin" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "profile_image_url" text
);

create table "public"."document_processing_jobs" (
  "id" uuid default gen_random_uuid() not null,
  "medical_document_id" uuid,
  "laboratory_result_id" uuid,
  "requested_by" uuid not null,
  "status" text default 'queued'::text not null,
  "ocr_provider" text,
  "ai_provider" text default 'groq'::text not null,
  "model_name" text,
  "attempt_count" integer default 0 not null,
  "last_error" text,
  "started_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."emergency_access_events" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "hospital_id" uuid not null,
  "doctor_id" uuid not null,
  "reason" text not null,
  "categories" text[] not null,
  "status" text default 'active'::text not null,
  "started_at" timestamp with time zone default now() not null,
  "expires_at" timestamp with time zone not null,
  "ended_at" timestamp with time zone,
  "patient_notified_at" timestamp with time zone,
  "reviewed_by" uuid,
  "reviewed_at" timestamp with time zone,
  "review_notes" text,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."emergency_room_status" (
  "id" uuid default gen_random_uuid() not null,
  "hospital_id" uuid not null,
  "status" emergency_room_state default 'available'::emergency_room_state not null,
  "available_beds" integer default 0 not null,
  "current_patient_count" integer default 0 not null,
  "maximum_capacity" integer default 0 not null,
  "last_updated" timestamp with time zone default now() not null,
  "occupied_beds" integer default 0 not null,
  "closed_or_unstaffed_beds" integer default 0 not null,
  "reserved_beds" integer default 0 not null,
  "status_override" emergency_room_state,
  "override_reason" text,
  "capacity_source" text default 'manual'::text not null,
  "updated_by" uuid
);

create table "public"."guest_consultation_requests" (
  "id" uuid default gen_random_uuid() not null,
  "submitted_by" uuid,
  "reference_number" text not null,
  "full_name" text not null,
  "birth_date" date not null,
  "sex" sex_type not null,
  "mobile_number" text not null,
  "email" text,
  "address" text not null,
  "latitude" numeric(9,6),
  "longitude" numeric(9,6),
  "symptoms" text not null,
  "symptom_duration" text not null,
  "consultation_reason" text not null,
  "existing_conditions" text[] default '{}'::text[] not null,
  "allergies" text[] default '{}'::text[] not null,
  "current_medications" text[] default '{}'::text[] not null,
  "urgency_level" urgency_level,
  "preferred_hospital_id" uuid,
  "preferred_department_id" uuid,
  "assigned_doctor_id" uuid,
  "preferred_schedule" timestamp with time zone,
  "identification_file_path" text,
  "otp_verification_status" verification_status default 'verified'::verification_status not null,
  "request_status" guest_request_status default 'otp_verified'::guest_request_status not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "otp_verified_at" timestamp with time zone,
  "reviewed_by" uuid,
  "reviewed_at" timestamp with time zone,
  "rejection_reason" text,
  "identity_review_status" verification_status default 'pending'::verification_status not null,
  "identity_review_notes" text,
  "additional_documents_requested" text,
  "consent_at" timestamp with time zone,
  "first_name" text not null,
  "last_name" text not null,
  "preferred_consultation_type" consultation_type default 'guest_online'::consultation_type not null,
  "submission_key" text
);

create table "public"."guest_request_status_history" (
  "id" bigint generated always as identity not null,
  "request_id" uuid not null,
  "old_status" guest_request_status,
  "new_status" guest_request_status not null,
  "changed_by" uuid,
  "reason" text,
  "metadata" jsonb default '{}'::jsonb not null,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."healthcare_service_categories" (
  "id" uuid default gen_random_uuid() not null,
  "category_name" text not null,
  "description" text default ''::text not null,
  "icon_name" text,
  "display_order" integer default 0 not null,
  "is_active" boolean default true not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."hospital_announcements" (
  "id" uuid default gen_random_uuid() not null,
  "hospital_id" uuid,
  "title" text not null,
  "message" text not null,
  "is_global" boolean default false not null,
  "published_at" timestamp with time zone default now() not null,
  "expires_at" timestamp with time zone,
  "created_by" uuid,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."hospital_beds" (
  "id" uuid default gen_random_uuid() not null,
  "hospital_id" uuid not null,
  "department_id" uuid,
  "bed_type" text default 'regular'::text not null,
  "total_beds" integer default 0 not null,
  "available_beds" integer default 0 not null,
  "occupied_beds" integer default 0 not null,
  "last_updated" timestamp with time zone default now() not null
);

create table "public"."hospital_classifications" (
  "id" uuid default gen_random_uuid() not null,
  "classification_name" text not null,
  "description" text default ''::text not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."hospital_departments" (
  "id" uuid default gen_random_uuid() not null,
  "hospital_id" uuid not null,
  "department_name" text not null,
  "description" text default ''::text not null,
  "availability_status" availability_status default 'available'::availability_status not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."hospital_facility_status" (
  "id" uuid default gen_random_uuid() not null,
  "hospital_id" uuid not null,
  "facility_type" text not null,
  "status" availability_status default 'available'::availability_status not null,
  "available_units" integer,
  "notes" text,
  "last_updated" timestamp with time zone default now() not null
);

create table "public"."hospital_rooms" (
  "id" uuid default gen_random_uuid() not null,
  "hospital_id" uuid not null,
  "room_type" text not null,
  "total_rooms" integer default 0 not null,
  "available_rooms" integer default 0 not null,
  "occupied_rooms" integer default 0 not null,
  "status" availability_status default 'available'::availability_status not null,
  "last_updated" timestamp with time zone default now() not null
);

create table "public"."hospital_service_doctors" (
  "id" uuid default gen_random_uuid() not null,
  "hospital_id" uuid not null,
  "service_id" uuid not null,
  "doctor_id" uuid not null,
  "is_primary" boolean default false not null,
  "notes" text,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."hospital_services" (
  "id" uuid default gen_random_uuid() not null,
  "hospital_id" uuid not null,
  "department_id" uuid,
  "service_name" text not null,
  "description" text default ''::text not null,
  "availability_status" availability_status default 'available'::availability_status not null,
  "operating_hours" jsonb default '{}'::jsonb not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "category_id" uuid,
  "service_code" text,
  "delivery_modes" text[] default ARRAY['in_person'::text] not null,
  "appointment_required" boolean default false not null,
  "accepts_walk_ins" boolean default true not null,
  "fee_min" numeric(10,2),
  "fee_max" numeric(10,2),
  "fee_notes" text,
  "contact_number" text,
  "booking_url" text,
  "preparation_instructions" text,
  "tags" text[] default '{}'::text[] not null,
  "last_updated" timestamp with time zone default now() not null
);

create table "public"."hospitals" (
  "id" uuid default gen_random_uuid() not null,
  "hospital_name" text not null,
  "classification_id" uuid,
  "address" text not null,
  "city" text,
  "province" text,
  "latitude" numeric(9,6),
  "longitude" numeric(9,6),
  "contact_number" text,
  "emergency_contact_number" text,
  "email" text,
  "description" text default ''::text not null,
  "operating_hours" jsonb default '{}'::jsonb not null,
  "operating_status" hospital_operating_status default 'open'::hospital_operating_status not null,
  "verification_status" verification_status default 'pending'::verification_status not null,
  "image_url" text,
  "created_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "verification_notes" text,
  "verification_decided_at" timestamp with time zone,
  "verification_decided_by" uuid,
  "image_attribution" text,
  "image_source_url" text,
  "directory_source_url" text,
  "directory_verified_at" timestamp with time zone,
  "online_request_workflow_enabled" boolean default false not null
);

create table "public"."laboratory_requests" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "consultation_id" uuid,
  "doctor_id" uuid not null,
  "hospital_id" uuid not null,
  "test_name" text not null,
  "instructions" text,
  "priority" text default 'routine'::text not null,
  "status" text default 'requested'::text not null,
  "requested_at" timestamp with time zone default now() not null,
  "due_at" timestamp with time zone,
  "completed_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."laboratory_results" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "doctor_id" uuid not null,
  "hospital_id" uuid not null,
  "consultation_id" uuid,
  "test_name" text not null,
  "extracted_text" text,
  "ai_summary" text,
  "ai_possible_findings" jsonb,
  "doctor_confirmed_findings" text,
  "professional_interpretation" text,
  "file_path" text not null,
  "verification_status" medical_result_status default 'uploaded'::medical_result_status not null,
  "confirmed_at" timestamp with time zone,
  "uploaded_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "ocr_provider" text,
  "ocr_confidence" numeric(5,4),
  "ocr_completed_at" timestamp with time zone,
  "ai_analyzed_at" timestamp with time zone,
  "reviewed_by" uuid,
  "reviewed_at" timestamp with time zone,
  "rejection_reason" text,
  "source_document_id" uuid,
  "confirmed_by" uuid
);

create table "public"."maintenance_windows" (
  "id" uuid default gen_random_uuid() not null,
  "title" text not null,
  "message" text not null,
  "starts_at" timestamp with time zone not null,
  "ends_at" timestamp with time zone not null,
  "is_active" boolean default true not null,
  "created_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."medical_documents" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "consultation_id" uuid,
  "uploaded_by" uuid not null,
  "hospital_id" uuid,
  "document_type" text not null,
  "title" text not null,
  "storage_bucket" text not null,
  "storage_path" text not null,
  "mime_type" text,
  "size_bytes" bigint,
  "created_at" timestamp with time zone default now() not null,
  "reference_id" uuid,
  "reference_type" text,
  "author_doctor_id" uuid,
  "origin_type" text default 'hospital_generated'::text not null,
  "record_status" text default 'final'::text not null,
  "ai_summary" text,
  "ai_extracted_data" jsonb,
  "ai_analysis_status" text default 'not_requested'::text not null,
  "ai_analysis_error" text,
  "ai_analyzed_at" timestamp with time zone,
  "result_category" text,
  "test_procedure_name" text,
  "performed_or_collected_date" date,
  "result_date" date,
  "facility" text,
  "requesting_doctor" text,
  "findings_impression" text,
  "notes" text,
  "test_procedure_name_ai_generated" boolean default false not null,
  "performed_or_collected_date_text" text,
  "result_date_text" text,
  "patient_name_on_report" text,
  "procedure_details" text,
  "result_details" text,
  "official_findings_impression" text,
  "report_recommendations" text,
  "technical_summary" text,
  "patient_friendly_summary" text,
  "verification_notes" text,
  "review_state" text default 'unreviewed'::text not null,
  "reviewed_by" uuid,
  "reviewed_at" timestamp with time zone,
  "review_rejection_reason" text
);

create table "public"."medical_record_access_logs" (
  "id" bigint generated always as identity not null,
  "patient_id" uuid not null,
  "actor_user_id" uuid,
  "actor_role" text,
  "resource_type" text not null,
  "resource_id" uuid,
  "access_type" text not null,
  "reason" text,
  "ip_address" inet,
  "metadata" jsonb default '{}'::jsonb not null,
  "created_at" timestamp with time zone default now() not null,
  "grant_id" uuid,
  "care_relationship_id" uuid,
  "source_hospital_id" uuid,
  "receiving_hospital_id" uuid,
  "success" boolean default true not null,
  "failure_reason" text
);

create table "public"."medical_records" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "doctor_id" uuid not null,
  "hospital_id" uuid not null,
  "consultation_id" uuid,
  "record_type" text not null,
  "title" text not null,
  "description" text,
  "confirmed_diagnosis" text,
  "treatment_plan" text,
  "record_date" date default CURRENT_DATE not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "source_laboratory_result_id" uuid,
  "confirmed_by" uuid,
  "is_ai_assisted" boolean default false not null,
  "reason_for_visit" text,
  "height_cm" numeric(5,2),
  "weight_kg" numeric(6,2),
  "bmi" numeric(5,2),
  "blood_pressure_systolic" smallint,
  "blood_pressure_diastolic" smallint,
  "body_temperature_c" numeric(4,1),
  "heart_rate_bpm" smallint,
  "respiratory_rate_bpm" smallint,
  "oxygen_saturation_percent" numeric(5,2),
  "vitals_recorded_at" timestamp with time zone,
  "current_symptoms" text,
  "known_medical_conditions" text[] default '{}'::text[] not null,
  "allergies" text[] default '{}'::text[] not null,
  "current_medications" text[] default '{}'::text[] not null,
  "relevant_medical_history" text,
  "previous_surgeries" text,
  "smoking_status" text,
  "alcohol_use" text,
  "pregnancy_status" text,
  "doctor_notes" text,
  "source_document_id" uuid
);

create table "public"."medication_summary_days" (
  "patient_id" uuid not null,
  "local_date" date not null,
  "notification_id" uuid,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."notification_outbox" (
  "id" bigint generated always as identity not null,
  "notification_id" uuid not null,
  "user_id" uuid not null,
  "channel" text not null,
  "status" text default 'pending'::text not null,
  "attempt_count" integer default 0 not null,
  "next_attempt_at" timestamp with time zone default now() not null,
  "provider_message_id" text,
  "last_error" text,
  "delivered_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."notification_preferences" (
  "user_id" uuid not null,
  "consultation_updates" boolean default true not null,
  "appointment_reminders" boolean default true not null,
  "medical_results" boolean default true not null,
  "prescriptions" boolean default true not null,
  "messages" boolean default true not null,
  "hospital_alerts" boolean default true not null,
  "email_enabled" boolean default false not null,
  "quiet_hours_start" time without time zone,
  "quiet_hours_end" time without time zone,
  "updated_at" timestamp with time zone default now() not null,
  "in_app_enabled" boolean default true not null,
  "medication_reminders" boolean default true not null
);

create table "public"."notifications" (
  "id" uuid default gen_random_uuid() not null,
  "user_id" uuid,
  "guest_request_id" uuid,
  "title" text not null,
  "message" text not null,
  "notification_type" text not null,
  "reference_id" uuid,
  "is_read" boolean default false not null,
  "created_at" timestamp with time zone default now() not null,
  "data" jsonb default '{}'::jsonb not null,
  "action_url" text,
  "read_at" timestamp with time zone,
  "action_path" text,
  "dedupe_key" text,
  "email_delivery_status" text default 'disabled'::text not null
);

create table "public"."online_consultation_request_status_history" (
  "id" bigint generated by default as identity not null,
  "request_id" uuid not null,
  "from_status" text,
  "to_status" text not null,
  "changed_by" uuid,
  "notes" text,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."online_consultation_requests" (
  "id" uuid default gen_random_uuid() not null,
  "reference_number" text not null,
  "patient_id" uuid not null,
  "submitted_by" uuid not null,
  "profile_first_name" text not null,
  "profile_last_name" text not null,
  "profile_email" text,
  "phone_number_snapshot" text not null,
  "birth_date_snapshot" date,
  "address_snapshot" text,
  "hospital_id" uuid not null,
  "requested_department_id" uuid not null,
  "requested_doctor_id" uuid,
  "assigned_doctor_id" uuid,
  "medical_concern" text not null,
  "symptom_duration" text not null,
  "preferred_schedule" timestamp with time zone not null,
  "proposed_schedule" timestamp with time zone,
  "confirmed_schedule" timestamp with time zone,
  "supporting_document_ids" uuid[] default '{}'::uuid[] not null,
  "shared_categories" text[] default '{}'::text[] not null,
  "selected_records" jsonb default '[]'::jsonb not null,
  "consent_id" uuid not null,
  "care_relationship_id" uuid not null,
  "consultation_channel" text,
  "request_status" text default 'submitted'::text not null,
  "official_consultation_id" uuid,
  "additional_information_request" text,
  "contact_attempt_status" text,
  "contact_attempted_at" timestamp with time zone,
  "reviewed_by" uuid,
  "reviewed_at" timestamp with time zone,
  "rejection_reason" text,
  "cancellation_reason" text,
  "hospital_feature_key" text default 'reviewed_online_consultation'::text not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "patient_response" text,
  "contact_attempt_notes" text,
  "outcome_notes" text
);

create table "public"."patient_access_grants" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "care_relationship_id" uuid not null,
  "consent_id" uuid not null,
  "source_hospital_id" uuid not null,
  "receiving_hospital_id" uuid not null,
  "receiving_doctor_id" uuid not null,
  "consultation_id" uuid,
  "purpose" text not null,
  "status" text default 'requested'::text not null,
  "selection_mode" text default 'categories'::text not null,
  "permitted_actions" text[] default '{view}'::text[] not null,
  "external_read_only" boolean default true not null,
  "activated_at" timestamp with time zone,
  "expires_at" timestamp with time zone not null,
  "revoked_at" timestamp with time zone,
  "revoked_by" uuid,
  "revocation_reason" text,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."patient_access_record_selections" (
  "id" uuid default gen_random_uuid() not null,
  "grant_id" uuid not null,
  "record_category" text not null,
  "source_table" text not null,
  "record_id" uuid not null,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."patient_access_scopes" (
  "id" uuid default gen_random_uuid() not null,
  "grant_id" uuid not null,
  "record_category" text not null,
  "can_view" boolean default true not null,
  "can_download" boolean default false not null,
  "can_create" boolean default false not null,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."patient_care_relationships" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "hospital_id" uuid not null,
  "doctor_id" uuid,
  "consultation_id" uuid,
  "online_request_id" uuid,
  "referral_reference" text,
  "relationship_type" text not null,
  "purpose" text not null,
  "status" text default 'requested'::text not null,
  "requested_at" timestamp with time zone default now() not null,
  "approved_at" timestamp with time zone,
  "starts_at" timestamp with time zone,
  "expires_at" timestamp with time zone,
  "ended_at" timestamp with time zone,
  "termination_reason" text,
  "created_by" uuid,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."patient_connection_requests" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "hospital_id" uuid not null,
  "doctor_id" uuid not null,
  "requested_by" uuid not null,
  "purpose" text default 'clinician_patient_connection'::text not null,
  "status" text default 'requested'::text not null,
  "requested_at" timestamp with time zone default now() not null,
  "decided_at" timestamp with time zone,
  "expires_at" timestamp with time zone default (now() + '7 days'::interval) not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."patient_consents" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "consent_type" text not null,
  "consent_version" text default '1'::text not null,
  "is_granted" boolean not null,
  "granted_at" timestamp with time zone,
  "revoked_at" timestamp with time zone,
  "captured_by" uuid not null,
  "metadata" jsonb default '{}'::jsonb not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "care_relationship_id" uuid,
  "source_hospital_id" uuid,
  "receiving_hospital_id" uuid,
  "purpose" text,
  "categories" text[] default '{}'::text[] not null,
  "permitted_actions" text[] default '{view}'::text[] not null,
  "record_selection_mode" text default 'categories'::text not null,
  "expires_at" timestamp with time zone,
  "granted_by" uuid,
  "revocation_reason" text,
  "replaces_consent_id" uuid,
  "version_sequence" integer default 1 not null
);

create table "public"."patient_hospital_identifiers" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "hospital_id" uuid not null,
  "local_mrn" text not null,
  "status" text default 'active'::text not null,
  "verified_at" timestamp with time zone,
  "retired_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."patient_representatives" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "representative_user_id" uuid not null,
  "authority_type" text not null,
  "authority_scope" text[] default '{consent,view}'::text[] not null,
  "verification_status" text default 'pending'::text not null,
  "evidence_document_id" uuid,
  "starts_at" timestamp with time zone default now() not null,
  "expires_at" timestamp with time zone,
  "revoked_at" timestamp with time zone,
  "verified_by" uuid,
  "verified_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."patients" (
  "id" uuid default gen_random_uuid() not null,
  "user_id" uuid,
  "patient_number" text,
  "created_by_doctor" uuid,
  "guest_request_id" uuid,
  "primary_hospital_id" uuid,
  "blood_type" text,
  "emergency_contact" jsonb default '{}'::jsonb not null,
  "allergies" text[] default '{}'::text[] not null,
  "existing_conditions" text[] default '{}'::text[] not null,
  "identity_verification_status" verification_status default 'pending'::verification_status not null,
  "account_activation_status" account_status default 'pending'::account_status not null,
  "converted_from_guest" boolean default false not null,
  "converted_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "profile_status" text default 'official'::text not null,
  "activation_sent_at" timestamp with time zone,
  "activated_at" timestamp with time zone
);

create table "public"."prescription_orders" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "doctor_id" uuid not null,
  "hospital_id" uuid not null,
  "consultation_id" uuid,
  "assignment_id" uuid,
  "issued_by" uuid,
  "issued_at" timestamp with time zone default now() not null,
  "diagnosis_reason" text,
  "idempotency_key" text,
  "payload_fingerprint" text,
  "status" text default 'issued'::text not null,
  "legacy_import" boolean default false not null
);

create table "public"."prescriptions" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "doctor_id" uuid not null,
  "consultation_id" uuid,
  "medication_name" text not null,
  "dosage" text not null,
  "frequency" text not null,
  "duration" text not null,
  "instructions" text,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "hospital_id" uuid not null,
  "diagnosis_reason" text,
  "medication_form_strength" text,
  "route" text,
  "exact_dose" text,
  "quantity_to_dispense" text,
  "refills" integer,
  "start_date" date,
  "end_date" date,
  "is_prn" boolean default false not null,
  "prn_reason" text,
  "maximum_daily_dose" text,
  "prescriber_name" text,
  "prescriber_license_number" text,
  "prescriber_specialization" text,
  "electronically_signed_at" timestamp with time zone,
  "electronically_signed_by" uuid,
  "signature_method" text,
  "assignment_id" uuid,
  "order_id" uuid
);

create table "public"."role_permissions" (
  "id" uuid default gen_random_uuid() not null,
  "role_id" smallint not null,
  "permission" text not null,
  "is_allowed" boolean default true not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."roles" (
  "id" smallint generated by default as identity not null,
  "role_name" text not null,
  "description" text not null,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."security_logs" (
  "id" bigint generated always as identity not null,
  "actor_auth_user_id" uuid,
  "event_type" text not null,
  "severity" text default 'info'::text not null,
  "success" boolean default true not null,
  "ip_address" inet,
  "user_agent" text,
  "metadata" jsonb default '{}'::jsonb not null,
  "created_at" timestamp with time zone default now() not null
);

create table "public"."system_settings" (
  "key" text not null,
  "value" jsonb not null,
  "description" text,
  "is_public" boolean default false not null,
  "updated_by" uuid,
  "updated_at" timestamp with time zone default now() not null
);

create table "public"."treatment_plans" (
  "id" uuid default gen_random_uuid() not null,
  "patient_id" uuid not null,
  "consultation_id" uuid not null,
  "doctor_id" uuid not null,
  "hospital_id" uuid not null,
  "plan" text not null,
  "starts_on" date,
  "ends_on" date,
  "status" text default 'active'::text not null,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "source" text default 'manual'::text not null
);

create table "public"."users" (
  "id" uuid default gen_random_uuid() not null,
  "auth_user_id" uuid not null,
  "role_id" smallint not null,
  "first_name" text default ''::text not null,
  "middle_name" text,
  "last_name" text default ''::text not null,
  "email" text,
  "mobile_number" text,
  "birth_date" date,
  "sex" sex_type,
  "address" text,
  "hospital_id" uuid,
  "account_status" account_status default 'pending'::account_status not null,
  "avatar_url" text,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null,
  "address_geocode_hash" text,
  "address_latitude" double precision,
  "address_longitude" double precision,
  "profile_image_url" text
);

create table "public"."video_sessions" (
  "id" uuid default gen_random_uuid() not null,
  "consultation_id" uuid not null,
  "provider" text not null,
  "room_name" text not null,
  "join_url" text not null,
  "status" text default 'pending'::text not null,
  "provider_metadata" jsonb default '{}'::jsonb not null,
  "created_by" uuid not null,
  "starts_at" timestamp with time zone,
  "started_at" timestamp with time zone,
  "ended_at" timestamp with time zone,
  "expires_at" timestamp with time zone,
  "created_at" timestamp with time zone default now() not null,
  "updated_at" timestamp with time zone default now() not null
);

CREATE OR REPLACE FUNCTION public.activate_approved_guest(target_request_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.guest_consultation_requests; p public.patients; u public.users; a auth.users; existing_id uuid;
begin
  select * into a from auth.users where id=auth.uid();
  select * into r from public.guest_consultation_requests where id=target_request_id for update;
  if r.id is null or a.id is null or a.email_confirmed_at is null or coalesce(a.is_anonymous,false)
    or r.submitted_by is distinct from a.id or lower(r.email) is distinct from lower(a.email) then
    raise exception 'Use the verified account that submitted this request'; end if;
  if r.request_status not in ('approved','temporary_patient_created','account_activation_pending','consultation_scheduled','consultation_completed') then
    raise exception 'Hospital approval is required before activation'; end if;
  select * into u from public.users where auth_user_id=a.id for update;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('guest-activation:'||a.id::text,0));
  if u.id is null or (select role_name from public.roles where id=u.role_id) not in ('guest','patient') or u.account_status<>'active' then
    return jsonb_build_object('status','identity_conflict','resolution_action','Sign in with the verified patient account or contact the hospital to resolve the identity. Your consultation tracking remains available.'); end if;
  select patient.* into p from public.patients patient join public.consultations c on c.patient_id=patient.id
    where c.guest_request_id=r.id order by c.created_at desc limit 1 for update of patient;
  if p.id is null then select * into p from public.patients where guest_request_id=r.id for update; end if;
  if p.id is null then raise exception 'The approved temporary patient has not been prepared'; end if;
  select id into existing_id from public.patients where user_id=u.id and id<>p.id;
  if existing_id is not null or (p.user_id is not null and p.user_id<>u.id) then
    return jsonb_build_object('status','identity_conflict','resolution_action','Ask the hospital to reconcile the existing patient profiles. Your consultation tracking remains available.'); end if;
  update public.patients set user_id=u.id,profile_status='official',account_activation_status='active',
    activated_at=coalesce(activated_at,now()),converted_from_guest=true,converted_at=coalesce(converted_at,now()) where id=p.id;
  update public.users set role_id=(select id from public.roles where role_name='patient') where id=u.id;
  return jsonb_build_object('status','active','patient_id',p.id,'password_action','patient_controlled');
end $function$;

CREATE OR REPLACE FUNCTION private.activate_relationship_access(target_relationship_id uuid, target_consent_id uuid, target_doctor_id uuid, target_consultation_id uuid, target_selected_records jsonb DEFAULT '[]'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  relationship_row public.patient_care_relationships;
  consent_row public.patient_consents;
  local_grant_id uuid;
  external_grant_id uuid;
  grant_expiry timestamptz;
  category text;
  local_categories text[];
  selected_record jsonb;
  ext_hospital_id uuid;
begin
  select * into relationship_row
  from public.patient_care_relationships
  where id = target_relationship_id
  for update;

  select * into consent_row
  from public.patient_consents
  where id = target_consent_id
  for update;

  if not found
    or relationship_row.id is null
    or consent_row.patient_id is distinct from relationship_row.patient_id
    or consent_row.care_relationship_id is distinct from relationship_row.id
    or not consent_row.is_granted
    or consent_row.granted_at is null
    or consent_row.revoked_at is not null
    or (consent_row.expires_at is not null and consent_row.expires_at <= now()) then
    raise exception 'An active patient consent for this care relationship is required';
  end if;
  if target_doctor_id is null
    or not exists (
      select 1 from public.doctors doctor
      where doctor.id = target_doctor_id
        and doctor.hospital_id = relationship_row.hospital_id
    )
    or not exists (
      select 1
      from public.doctor_hospital_employments employment
      where employment.doctor_id = target_doctor_id
        and employment.hospital_id = relationship_row.hospital_id
        and employment.employment_status = 'active'
        and employment.is_verified
        and employment.starts_at <= now()
        and (employment.ends_at is null or employment.ends_at > now())
    ) then
    raise exception 'A verified doctor with active hospital employment is required';
  end if;

  grant_expiry := least(
    coalesce(consent_row.expires_at, now() + interval '30 days'),
    coalesce(relationship_row.expires_at, now() + interval '30 days')
  );
  if grant_expiry <= now() then
    raise exception 'The consent or care relationship has expired';
  end if;

  update public.doctor_patient_assignments
  set assignment_status = 'ended',
      ended_at = coalesce(ended_at, now()),
      ended_reason = coalesce(ended_reason, 'Consultation reassigned')
  where care_relationship_id = relationship_row.id
    and doctor_id <> target_doctor_id
    and ended_at is null;

  update public.patient_access_grants
  set status = 'revoked',
      revoked_at = coalesce(revoked_at, now()),
      revoked_by = private.current_user_id(),
      revocation_reason = coalesce(revocation_reason, 'Consultation reassigned'),
      updated_at = now()
  where care_relationship_id = relationship_row.id
    and receiving_doctor_id <> target_doctor_id
    and status in ('requested', 'active')
    and revoked_at is null;

  insert into public.doctor_patient_assignments(
    doctor_id, patient_id, hospital_id, care_relationship_id,
    consultation_id, assigned_at, assignment_status, notes
  )
  select target_doctor_id, relationship_row.patient_id,
         relationship_row.hospital_id, relationship_row.id,
         target_consultation_id, now(), 'active',
         'Activated from verified care relationship'
  where not exists (
    select 1 from public.doctor_patient_assignments assignment
    where assignment.care_relationship_id = relationship_row.id
      and assignment.doctor_id = target_doctor_id
      and assignment.assignment_status = 'active'
      and assignment.ended_at is null
  );

  update public.patient_care_relationships
  set doctor_id = target_doctor_id,
      consultation_id = coalesce(target_consultation_id, consultation_id),
      status = 'active',
      approved_at = coalesce(approved_at, now()),
      starts_at = coalesce(starts_at, now()),
      expires_at = grant_expiry,
      ended_at = null,
      termination_reason = null,
      updated_at = now()
  where id = relationship_row.id
  returning * into relationship_row;

  select id into local_grant_id
  from public.patient_access_grants
  where care_relationship_id = relationship_row.id
    and source_hospital_id = relationship_row.hospital_id
    and receiving_hospital_id = relationship_row.hospital_id
    and receiving_doctor_id = target_doctor_id
    and status in ('requested', 'active')
    and revoked_at is null
  for update;

  if local_grant_id is null then
    insert into public.patient_access_grants(
      patient_id, care_relationship_id, consent_id, source_hospital_id,
      receiving_hospital_id, receiving_doctor_id, consultation_id,
      purpose, status, selection_mode, permitted_actions,
      external_read_only, activated_at, expires_at
    ) values (
      relationship_row.patient_id, relationship_row.id, consent_row.id,
      relationship_row.hospital_id, relationship_row.hospital_id,
      target_doctor_id, target_consultation_id, relationship_row.purpose,
      'active', 'categories', array['view', 'download', 'create']::text[],
      false, now(), grant_expiry
    ) returning id into local_grant_id;
  else
    update public.patient_access_grants
    set consent_id = consent_row.id,
        consultation_id = coalesce(target_consultation_id, consultation_id),
        status = 'active',
        selection_mode = 'categories',
        permitted_actions = array['view', 'download', 'create']::text[],
        external_read_only = false,
        activated_at = coalesce(activated_at, now()),
        expires_at = grant_expiry,
        updated_at = now()
    where id = local_grant_id;
  end if;

  local_categories := case
    when cardinality(consent_row.categories) > 0 then consent_row.categories
    else array['consultations']::text[]
  end;
  foreach category in array local_categories loop
    if not private.valid_record_category(category) then
      raise exception 'Unsupported record category: %', category;
    end if;
    insert into public.patient_access_scopes(
      grant_id, record_category, can_view, can_download, can_create
    ) values (
      local_grant_id, category, true,
      category in ('prescriptions', 'laboratory_results', 'medical_documents'),
      true
    )
    on conflict (grant_id, record_category) do update
    set can_view = excluded.can_view,
        can_download = excluded.can_download,
        can_create = excluded.can_create;
  end loop;

  -- External source hospitals
  if cardinality(consent_row.categories) > 0 then
    for ext_hospital_id in
      select distinct src_hosp.id
      from (
        select hospital_id as id from public.medical_records where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select hospital_id as id from public.prescriptions where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select hospital_id as id from public.laboratory_results where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select hospital_id as id from public.laboratory_requests where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select hospital_id as id from public.medical_documents where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select hospital_id as id from public.diagnoses where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select hospital_id as id from public.treatment_plans where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select hospital_id as id from public.consultations where patient_id = relationship_row.patient_id and hospital_id is not null
        union
        select consent_row.source_hospital_id as id where consent_row.source_hospital_id is not null
        union
        select id from public.hospitals where verification_status = 'verified'
      ) src_hosp
      where src_hosp.id <> relationship_row.hospital_id
    loop
      select id into external_grant_id
      from public.patient_access_grants
      where care_relationship_id = relationship_row.id
        and source_hospital_id = ext_hospital_id
        and receiving_hospital_id = relationship_row.hospital_id
        and receiving_doctor_id = target_doctor_id
        and status in ('requested', 'active')
        and revoked_at is null
      for update;

      if external_grant_id is null then
        insert into public.patient_access_grants(
          patient_id, care_relationship_id, consent_id, source_hospital_id,
          receiving_hospital_id, receiving_doctor_id, consultation_id,
          purpose, status, selection_mode, permitted_actions,
          external_read_only, activated_at, expires_at
        ) values (
          relationship_row.patient_id, relationship_row.id, consent_row.id,
          ext_hospital_id, relationship_row.hospital_id,
          target_doctor_id, target_consultation_id, relationship_row.purpose,
          'active', consent_row.record_selection_mode,
          array['view', 'download']::text[], true, now(), grant_expiry
        ) returning id into external_grant_id;
      else
        update public.patient_access_grants
        set consent_id = consent_row.id,
            consultation_id = coalesce(target_consultation_id, consultation_id),
            status = 'active',
            selection_mode = consent_row.record_selection_mode,
            permitted_actions = array['view', 'download']::text[],
            external_read_only = true,
            activated_at = coalesce(activated_at, now()),
            expires_at = grant_expiry,
            updated_at = now()
        where id = external_grant_id;
      end if;

      foreach category in array consent_row.categories loop
        if not private.valid_record_category(category) then
          raise exception 'Unsupported record category: %', category;
        end if;
        insert into public.patient_access_scopes(
          grant_id, record_category, can_view, can_download, can_create
        ) values (
          external_grant_id, category, true,
          category in ('prescriptions', 'laboratory_results', 'medical_documents'),
          false
        )
        on conflict (grant_id, record_category) do update
        set can_view = excluded.can_view,
            can_download = excluded.can_download,
            can_create = false;
      end loop;
    end loop;
  end if;

  perform private.validate_record_selections(relationship_row.patient_id,consent_row.categories,target_selected_records);
  insert into public.patient_access_record_selections(grant_id,record_category,source_table,record_id)
  select g.id,item->>'category',item->>'source_table',(item->>'record_id')::uuid
  from public.patient_access_grants g cross join jsonb_array_elements(target_selected_records) item
  where g.care_relationship_id=relationship_row.id and g.status='active' and g.revoked_at is null
  on conflict (grant_id,source_table,record_id) do nothing;
  return local_grant_id;
end;
$function$;

CREATE OR REPLACE FUNCTION private.actor_has_category_access(target_patient_id uuid, target_category text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    target_patient_id = private.current_patient_id()
    or exists (
      select 1
      from public.patient_access_grants grant_row
      join public.patient_access_scopes scope on scope.grant_id = grant_row.id
      where grant_row.patient_id = target_patient_id
        and grant_row.receiving_doctor_id = private.current_doctor_id()
        and grant_row.status = 'active'
        and grant_row.expires_at > now()
        and grant_row.revoked_at is null
        and scope.record_category = target_category
        and scope.can_view
        and private.has_active_doctor_employment(
          grant_row.receiving_doctor_id, grant_row.receiving_hospital_id
        )
        and private.is_active_care_relationship(
          grant_row.care_relationship_id, grant_row.patient_id,
          grant_row.receiving_hospital_id, grant_row.receiving_doctor_id
        )
    ), false
  )
$function$;

CREATE OR REPLACE FUNCTION public.add_clinical_record_addendum(target_resource_type text, target_record_id uuid, addendum_text text, correction_reason text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  patient_id uuid;
  hospital_id uuid;
  category text;
  source_table text;
  addendum_id uuid;
begin
  case target_resource_type
    when 'medical_record' then
      select record.patient_id, record.hospital_id, 'medical_records', 'medical_records'
      into patient_id, hospital_id, category, source_table
      from public.medical_records record where record.id = target_record_id;
    when 'diagnosis' then
      select record.patient_id, record.hospital_id, 'diagnoses', 'diagnoses'
      into patient_id, hospital_id, category, source_table
      from public.diagnoses record where record.id = target_record_id;
    when 'prescription' then
      select record.patient_id, record.hospital_id, 'prescriptions', 'prescriptions'
      into patient_id, hospital_id, category, source_table
      from public.prescriptions record where record.id = target_record_id;
    when 'laboratory_result' then
      select record.patient_id, record.hospital_id, 'laboratory_results', 'laboratory_results'
      into patient_id, hospital_id, category, source_table
      from public.laboratory_results record where record.id = target_record_id;
    when 'treatment_plan' then
      select record.patient_id, record.hospital_id, 'treatment_plans', 'treatment_plans'
      into patient_id, hospital_id, category, source_table
      from public.treatment_plans record where record.id = target_record_id;
    else raise exception 'Unsupported addendum resource type';
  end case;
  if patient_id is null or hospital_id is null
    or not private.can_access_clinical_record(
      patient_id, hospital_id, category, target_record_id, 'create'
    ) then
    raise exception 'Only the originating authorized care team may add an addendum';
  end if;
  if nullif(btrim(addendum_text), '') is null
    or nullif(btrim(correction_reason), '') is null then
    raise exception 'Addendum text and a correction reason are required';
  end if;

  insert into public.clinical_record_addenda(
    patient_id, record_category, source_table, record_id,
    originating_hospital_id, author_doctor_id, author_user_id,
    addendum_text, correction_reason
  ) values (
    patient_id, category, source_table, target_record_id,
    hospital_id, private.current_doctor_id(), private.current_user_id(),
    btrim(addendum_text), btrim(correction_reason)
  ) returning id into addendum_id;
  return addendum_id;
end
$function$;

CREATE OR REPLACE FUNCTION private.apply_authenticated_prescription_signature()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'private', 'pg_temp'
AS $function$
declare
  signer_user_id uuid;
  signer_name text;
  signer_license text;
  signer_specialization text;
begin
  select app_user.id, doctor.display_name, doctor.license_number,
         doctor.specialization
    into signer_user_id, signer_name, signer_license, signer_specialization
  from public.users app_user
  join public.doctors doctor on doctor.user_id = app_user.id
  where app_user.auth_user_id = auth.uid()
    and doctor.id = new.doctor_id
  limit 1;

  if signer_user_id is null then
    raise exception 'Only the authenticated prescriber may sign this prescription';
  end if;
  if nullif(btrim(signer_name), '') is null or
     nullif(btrim(signer_license), '') is null then
    raise exception 'Complete the prescriber name and license number before issuing';
  end if;
  if nullif(btrim(new.diagnosis_reason), '') is null or
     nullif(btrim(new.medication_form_strength), '') is null or
     nullif(btrim(new.route), '') is null or
     nullif(btrim(new.exact_dose), '') is null or
     nullif(btrim(new.quantity_to_dispense), '') is null or
     new.refills is null or new.start_date is null then
    raise exception 'The structured prescription fields are required';
  end if;

  new.prescriber_name := signer_name;
  new.prescriber_license_number := signer_license;
  new.prescriber_specialization := nullif(btrim(signer_specialization), '');
  new.electronically_signed_by := signer_user_id;
  new.electronically_signed_at := clock_timestamp();
  new.signature_method := 'authenticated_account_attestation';
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.approve_patient_care_relationship(target_relationship_id uuid, assigned_doctor_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  relationship_row public.patient_care_relationships;
  consent_row public.patient_consents;
begin
  select * into relationship_row
  from public.patient_care_relationships
  where id = target_relationship_id
  for update;
  if not found or relationship_row.status <> 'requested'
    or not private.is_hospital_admin_for(relationship_row.hospital_id) then
    raise exception 'A pending relationship for this hospital is required';
  end if;
  if relationship_row.relationship_type not in (
    'second_opinion', 'ongoing_outpatient_care', 'transfer'
  ) then
    raise exception 'This relationship uses a different approval workflow';
  end if;
  select * into consent_row
  from public.patient_consents
  where care_relationship_id = relationship_row.id
    and is_granted and revoked_at is null
    and (expires_at is null or expires_at > now())
  order by version_sequence desc, created_at desc limit 1;
  if consent_row.id is null then
    raise exception 'Active patient consent is required';
  end if;

  perform private.activate_relationship_access(
    relationship_row.id, consent_row.id, assigned_doctor_id, null, '[]'::jsonb
  );

  if relationship_row.relationship_type = 'transfer' then
    update public.patients
    set primary_hospital_id = relationship_row.hospital_id, updated_at = now()
    where id = relationship_row.patient_id;
    insert into public.patient_hospital_identifiers(
      patient_id, hospital_id, local_mrn, status, verified_at
    ) values (
      relationship_row.patient_id, relationship_row.hospital_id,
      'TRANSFER-' || upper(substr(replace(relationship_row.patient_id::text, '-', ''), 1, 10)),
      'active', now()
    ) on conflict (patient_id, hospital_id) do update
      set status = 'active', verified_at = coalesce(
        public.patient_hospital_identifiers.verified_at, excluded.verified_at
      ), updated_at = now();
  end if;
end
$function$;

CREATE OR REPLACE FUNCTION public.assign_doctor_department(target_user_id uuid, target_department_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  admin_hospital_id uuid;
  updated_doctor_id uuid;
begin
  select hospital_id into admin_hospital_id
  from public.users
  where auth_user_id = auth.uid();

  if admin_hospital_id is null
    or not private.is_hospital_admin_for(admin_hospital_id) then
    raise exception 'Hospital administrator access is required';
  end if;

  if not exists (
    select 1
    from public.hospital_departments
    where id = target_department_id
      and hospital_id = admin_hospital_id
  ) then
    raise exception 'The selected department does not belong to your hospital';
  end if;

  update public.doctors
  set department_id = target_department_id,
      updated_at = now()
  where user_id = target_user_id
    and hospital_id = admin_hospital_id
  returning id into updated_doctor_id;

  if updated_doctor_id is null then
    raise exception 'Doctor not found in your hospital';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION private.audit_multi_hospital_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  payload jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  actor_hospital uuid := nullif(payload->>'hospital_id', '')::uuid;
  target_id uuid := nullif(payload->>'id', '')::uuid;
begin
  insert into public.audit_logs(user_id, hospital_id, action, module, record_id, metadata)
  values (
    private.current_user_id(),
    actor_hospital,
    lower(tg_op),
    tg_table_name,
    target_id,
    jsonb_build_object(
      'table', tg_table_schema || '.' || tg_table_name,
      'patient_id', payload->>'patient_id',
      'care_relationship_id', payload->>'care_relationship_id',
      'request_id', payload->>'request_id'
    )
  );
  if tg_op = 'DELETE' then return old; end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.available_doctor_slots(target_doctor_id uuid, target_date date, target_type consultation_type DEFAULT 'online'::consultation_type)
 RETURNS TABLE(slot_start timestamp with time zone, slot_end timestamp with time zone)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select generated.slot_start::timestamptz,
    (generated.slot_start+make_interval(mins=>schedule.slot_minutes))::timestamptz
  from public.doctor_schedules schedule
  cross join lateral generate_series(
    target_date+schedule.starts_at,
    target_date+schedule.ends_at-make_interval(mins=>schedule.slot_minutes),
    make_interval(mins=>schedule.slot_minutes)
  ) generated(slot_start)
  join public.doctors doctor on doctor.id=schedule.doctor_id
  join public.hospitals hospital on hospital.id=doctor.hospital_id
  where schedule.doctor_id=target_doctor_id and schedule.day_of_week=extract(dow from target_date)::integer
    and schedule.consultation_type=target_type and schedule.is_active and doctor.availability_status<>'unavailable'
    and hospital.verification_status='verified' and hospital.operating_status in ('open','limited')
    and generated.slot_start>now()
    and not exists(select 1 from public.consultations consultation where consultation.doctor_id=target_doctor_id
      and consultation.appointment_date=generated.slot_start::timestamptz and consultation.status not in ('rejected','cancelled'))
  order by generated.slot_start
$function$;

CREATE OR REPLACE FUNCTION public.begin_emergency_patient_access(target_patient_id uuid, target_hospital_id uuid, emergency_reason text, target_categories text[], duration_minutes integer DEFAULT 60)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  event_id uuid;
  category text;
begin
  if private.current_doctor_id() is null
    or not private.has_active_doctor_employment(
      private.current_doctor_id(), target_hospital_id
    ) then
    raise exception 'A verified active doctor at this hospital is required';
  end if;
  if nullif(btrim(emergency_reason), '') is null or length(btrim(emergency_reason)) < 10 then
    raise exception 'A specific emergency reason is required';
  end if;
  if duration_minutes < 5 or duration_minutes > 240 then
    raise exception 'Emergency access must last 5 to 240 minutes';
  end if;
  if cardinality(target_categories) = 0 then
    raise exception 'Choose at least one emergency record category';
  end if;
  foreach category in array target_categories loop
    if not private.valid_record_category(category) then
      raise exception 'Unsupported emergency category: %', category;
    end if;
  end loop;

  insert into public.emergency_access_events(
    patient_id, hospital_id, doctor_id, reason, categories,
    status, started_at, expires_at
  ) values (
    target_patient_id, target_hospital_id, private.current_doctor_id(),
    btrim(emergency_reason), target_categories, 'active', now(),
    now() + make_interval(mins => duration_minutes)
  ) returning id into event_id;

  insert into public.notifications(
    user_id, title, message, notification_type, reference_id, data
  )
  select app_user.auth_user_id,
         'Emergency record access activated',
         'A verified clinician activated short-lived emergency access to selected records.',
         'security_alert', event_id,
         jsonb_build_object(
           'emergency_access_event_id', event_id,
           'hospital_id', target_hospital_id,
           'expires_at', now() + make_interval(mins => duration_minutes)
         )
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where patient.id = target_patient_id;

  update public.emergency_access_events
  set patient_notified_at = case
    when exists (
      select 1 from public.patients patient
      where patient.id = target_patient_id and patient.user_id is not null
    ) then now() else null end
  where id = event_id;
  return event_id;
end
$function$;

CREATE OR REPLACE FUNCTION public.book_consultation_v2(booking_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  target_patient uuid := private.current_patient_id();
  target_user uuid := private.current_user_id();
  target_doctor uuid := nullif(booking_payload->>'doctor_id', '')::uuid;
  target_hospital uuid := nullif(booking_payload->>'hospital_id', '')::uuid;
  target_type public.consultation_type := coalesce(
    nullif(booking_payload->>'consultation_type', ''), 'face_to_face'
  )::public.consultation_type;
  target_date timestamptz := nullif(booking_payload->>'appointment_date', '')::timestamptz;
  target_complaint text := btrim(coalesce(booking_payload->>'chief_complaint', ''));
  categories text[] := array(
    select distinct value
    from jsonb_array_elements_text(coalesce(booking_payload->'shared_categories', '[]'::jsonb)) value
  );
  selected_records jsonb := coalesce(booking_payload->'selected_records', '[]'::jsonb);
  target_department uuid;
  source_hospital uuid;
  reviewed_enabled boolean;
  booked_id uuid;
  relationship_id uuid;
  consent_id uuid;
  online_result jsonb;
  patient_auth_id uuid;
begin
  perform private.lock_doctor_schedule(target_doctor);
  if (select auth.uid()) is null or target_patient is null or target_user is null then
    raise exception 'An active patient profile is required';
  end if;
  if target_doctor is null or target_hospital is null then
    raise exception 'A published clinician and hospital are required';
  end if;
  if target_date is null or target_date <= now() then
    raise exception 'Choose a future appointment time';
  end if;
  if length(target_complaint) < 5 or length(target_complaint) > 2000 then
    raise exception 'Describe the care concern in 5 to 2000 characters';
  end if;
  if target_type not in ('face_to_face', 'online') then
    raise exception 'Patients may book face-to-face care or request online care';
  end if;

  select doctor.department_id,
         hospital.online_request_workflow_enabled
  into target_department, reviewed_enabled
  from public.doctors doctor
  join public.hospitals hospital on hospital.id = doctor.hospital_id
  join public.doctor_hospital_employments employment
    on employment.doctor_id = doctor.id and employment.hospital_id = hospital.id
  where doctor.id = target_doctor
    and doctor.hospital_id = target_hospital
    and doctor.availability_status <> 'unavailable'
    and hospital.verification_status = 'verified'
    and hospital.operating_status in ('open', 'limited')
    and employment.employment_status = 'active'
    and employment.is_verified
    and employment.starts_at <= now()
    and (employment.ends_at is null or employment.ends_at > now());

  if not found or target_department is null then
    raise exception 'Doctor is not available at the selected hospital and department';
  end if;

  if target_type = 'online' then
    online_result := public.submit_online_consultation_request(
      jsonb_build_object(
        'hospital_id', target_hospital,
        'department_id', target_department,
        'requested_doctor_id', target_doctor,
        'preferred_schedule', target_date,
        'medical_concern', target_complaint,
        'symptom_duration', coalesce(
          nullif(btrim(booking_payload->>'symptom_duration'), ''),
          'Not specified'
        ),
        'shared_categories', coalesce(
          booking_payload->'shared_categories',
          '["consultations","medical_records","diagnoses","prescriptions","laboratory_requests","laboratory_results","medical_documents","clinical_notes","allergies_medications","treatment_plans"]'::jsonb
        ),
        'selected_records', selected_records,
        'supporting_document_ids', coalesce(
          booking_payload->'supporting_document_ids', '[]'::jsonb
        )
      )
    );
    return online_result || jsonb_build_object('consultation_id',null,'slot_reserved',false);
  end if;

  perform private.lock_doctor_schedule(target_doctor);
  if not private.is_doctor_slot_available(
    target_doctor, target_hospital, target_type, target_date, null
  ) then
    raise exception 'The selected appointment slot is no longer available';
  end if;

  insert into public.consultations(
    patient_id, doctor_id, hospital_id, department_id,
    consultation_type, appointment_date, status, chief_complaint,
    follow_up_of
  ) values (
    target_patient, target_doctor, target_hospital, target_department,
    target_type, target_date, 'pending', target_complaint,
    nullif(booking_payload->>'follow_up_of', '')::uuid
  ) returning id into booked_id;

  insert into public.patient_care_relationships(
    patient_id, hospital_id, doctor_id, consultation_id,
    relationship_type, purpose, status, requested_at, expires_at, created_by
  ) values (
    target_patient, target_hospital, target_doctor, booked_id,
    'consultation', case when target_type = 'face_to_face'
      then 'face_to_face_consultation' else 'legacy_online_consultation' end,
    'requested', now(), target_date + interval '7 days', target_user
  ) returning id into relationship_id;

  if cardinality(categories) = 0 then
    categories := array[
      'consultations', 'medical_records', 'diagnoses', 'prescriptions',
      'laboratory_requests', 'laboratory_results', 'medical_documents',
      'clinical_notes', 'allergies_medications', 'treatment_plans'
    ]::text[];
  end if;
  select app_user.auth_user_id into patient_auth_id
  from public.users app_user where app_user.id = target_user;
  select coalesce(patient.primary_hospital_id, target_hospital) into source_hospital
  from public.patients patient where patient.id = target_patient;

  insert into public.patient_consents(
    patient_id, consent_type, consent_version, is_granted, granted_at,
    captured_by, metadata, care_relationship_id, source_hospital_id,
    receiving_hospital_id, purpose, categories, permitted_actions,
    record_selection_mode, expires_at, granted_by, version_sequence
  ) values (
    target_patient, 'consultation_access', relationship_id::text, true, now(),
    patient_auth_id,
    jsonb_build_object(
      'booking_type', target_type,
      'selected_records', selected_records
    ),
    relationship_id, source_hospital, target_hospital,
    case when target_type = 'face_to_face'
      then 'face_to_face_consultation' else 'legacy_online_consultation' end,
    categories, array['view', 'download', 'create']::text[],
    case when jsonb_array_length(selected_records) > 0
      then 'selected_records' else 'categories' end,
    target_date + interval '7 days', target_user, 1
  ) returning id into consent_id;

  return jsonb_build_object('request_id',null,'consultation_id',booked_id,'status','pending','slot_reserved',true);
end
$function$;

CREATE OR REPLACE FUNCTION public.book_consultation(booking_payload jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare result jsonb;
begin
 result:=public.book_consultation_v2(booking_payload);
 return coalesce(result->>'request_id',result->>'consultation_id')::uuid;
end $function$;

CREATE OR REPLACE FUNCTION public.book_doctor_consultation(target_patient_id uuid, target_appointment_date timestamp with time zone, target_type consultation_type, target_chief_complaint text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  doctor_row public.doctors;
  booked_id uuid;
begin
  if (select auth.uid()) is null
    or private.current_doctor_id() is null
    or not private.has_permission('consultations.read_own') then
    raise exception 'An authorized doctor session is required';
  end if;

  if target_patient_id is null
    or target_appointment_date is null
    or target_appointment_date <= now()
    or nullif(btrim(target_chief_complaint), '') is null
    or length(btrim(target_chief_complaint)) < 5 then
    raise exception 'A patient, future appointment time, and care concern are required';
  end if;

  if target_type not in ('online', 'face_to_face') then
    raise exception 'Doctors may book online or in-person consultations';
  end if;

  select * into doctor_row
  from public.doctors
  where id = private.current_doctor_id();

  if not found or not private.can_access_patient(target_patient_id) then
    raise exception 'The patient is not assigned to this doctor';
  end if;

  perform pg_catalog.pg_advisory_xact_lock(
    pg_catalog.hashtextextended(
      doctor_row.id::text || ':' || target_appointment_date::date::text,
      0
    )
  );

  if not private.is_doctor_slot_available(
    doctor_row.id,
    doctor_row.hospital_id,
    target_type,
    target_appointment_date,
    null
  ) then
    raise exception 'The selected appointment slot is unavailable';
  end if;

  insert into public.consultations(
    patient_id,
    doctor_id,
    hospital_id,
    department_id,
    consultation_type,
    appointment_date,
    status,
    chief_complaint,
    approved_by,
    approved_at
  ) values (
    target_patient_id,
    doctor_row.id,
    doctor_row.hospital_id,
    doctor_row.department_id,
    target_type,
    target_appointment_date,
    'scheduled',
    btrim(target_chief_complaint),
    private.current_user_id(),
    now()
  )
  returning id into booked_id;

  return booked_id;
end;
$function$;

CREATE OR REPLACE FUNCTION private.can_access_clinical_record(target_patient_id uuid, target_source_hospital_id uuid, target_category text, target_record_id uuid, target_action text DEFAULT 'view'::text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    target_patient_id = private.current_patient_id()
    or (
      private.valid_record_category(target_category)
      and target_action in ('view', 'download', 'create')
      and exists (
        select 1
        from public.patient_access_grants grant_row
        join public.patient_consents consent on consent.id = grant_row.consent_id
        join public.patient_access_scopes scope on scope.grant_id = grant_row.id
        where grant_row.patient_id = target_patient_id
          and grant_row.receiving_doctor_id = private.current_doctor_id()
          and (
            grant_row.source_hospital_id = target_source_hospital_id
            or (
              target_source_hospital_id is null
              and target_category = 'medical_documents'
              and target_record_id is not null
              and exists (
                select 1
                from public.patient_access_record_selections patient_selection
                where patient_selection.grant_id = grant_row.id
                  and patient_selection.record_category = target_category
                  and patient_selection.record_id = target_record_id
              )
            )
          )
          and grant_row.status = 'active'
          and grant_row.activated_at is not null
          and grant_row.activated_at <= now()
          and grant_row.expires_at > now()
          and grant_row.revoked_at is null
          and consent.patient_id = grant_row.patient_id
          and consent.care_relationship_id = grant_row.care_relationship_id
          and consent.is_granted
          and consent.granted_at is not null
          and consent.revoked_at is null
          and (consent.expires_at is null or consent.expires_at > now())
          and target_category = any(consent.categories)
          and target_action = any(consent.permitted_actions)
          and scope.record_category = target_category
          and case target_action
            when 'view' then scope.can_view
            when 'download' then scope.can_download
            when 'create' then scope.can_create
            else false
          end
          and private.has_active_doctor_employment(
            grant_row.receiving_doctor_id,
            grant_row.receiving_hospital_id
          )
          and private.is_active_care_relationship(
            grant_row.care_relationship_id,
            grant_row.patient_id,
            grant_row.receiving_hospital_id,
            grant_row.receiving_doctor_id
          )
          and (
            target_action <> 'create'
            or (
              grant_row.source_hospital_id = grant_row.receiving_hospital_id
              and not grant_row.external_read_only
            )
          )
          and (
            grant_row.selection_mode = 'categories'
            or target_record_id is null
            or exists (
              select 1
              from public.patient_access_record_selections selection
              where selection.grant_id = grant_row.id
                and selection.record_category = target_category
                and selection.record_id = target_record_id
            )
          )
      )
    )
    or (
      target_action = 'view'
      and exists (
        select 1
        from public.emergency_access_events emergency
        where emergency.patient_id = target_patient_id
          and emergency.doctor_id = private.current_doctor_id()
          and emergency.status = 'active'
          and emergency.started_at <= now()
          and emergency.expires_at > now()
          and target_category = any(emergency.categories)
          and private.has_active_doctor_employment(
            emergency.doctor_id,
            emergency.hospital_id
          )
      )
    ),
    false
  )
$function$;

CREATE OR REPLACE FUNCTION private.can_access_consultation_storage(object_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare folder text := (storage.foldername(object_name))[1];
begin
  if folder is null or folder !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then return false; end if;
  return private.is_consultation_participant(folder::uuid);
end;
$function$;

CREATE OR REPLACE FUNCTION private.can_access_conversation(target_conversation_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(exists (
    select 1
    from public.chat_conversations c
    where c.id = target_conversation_id
      and (
        c.doctor_id = private.current_doctor_id()
        or (c.patient_id is not null and c.patient_id = private.current_patient_id())
        or (c.guest_request_id is not null and private.can_access_guest_request(c.guest_request_id))
      )
  ), false)
$function$;

CREATE OR REPLACE FUNCTION private.can_access_direct_chat_storage(object_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  folders text[] := storage.foldername(object_name);
  conversation_id uuid;
begin
  if coalesce(folders[1], '') <> 'direct' then
    return false;
  end if;
  begin
    conversation_id := folders[3]::uuid;
  exception when invalid_text_representation then
    return false;
  end;
  return private.can_participate_conversation(conversation_id);
end
$function$;

CREATE OR REPLACE FUNCTION private.can_access_guest_request(target_request_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    exists (
      select 1 from public.guest_consultation_requests guest_request
      where guest_request.id=target_request_id
        and guest_request.submitted_by=(select auth.uid())
        and private.current_user_id() is not null
    )
    or exists (
      select 1 from public.guest_consultation_requests guest_request
      where guest_request.id=target_request_id
        and guest_request.assigned_doctor_id=private.current_doctor_id()
    )
    or exists (
      select 1 from public.guest_consultation_requests guest_request
      where guest_request.id=target_request_id
        and private.is_hospital_admin_for(guest_request.preferred_hospital_id)
    ),false
  )
$function$;

CREATE OR REPLACE FUNCTION private.can_access_guest_storage(object_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(private.storage_path_owner(object_name) or exists(
    select 1 from public.guest_consultation_requests g
    where (g.identification_file_path=object_name or object_name like g.id::text||'/%') and private.can_access_guest_request(g.id)
  ),false)
$function$;

CREATE OR REPLACE FUNCTION private.can_access_online_request(target_request_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(exists (
    select 1
    from public.online_consultation_requests request
    where request.id = target_request_id
      and (
        request.patient_id = private.current_patient_id()
        or request.submitted_by = private.current_user_id()
        or request.assigned_doctor_id = private.current_doctor_id()
        or (
          request.requested_doctor_id = private.current_doctor_id()
          and request.request_status in ('submitted', 'under_review', 'schedule_proposed')
        )
        or private.is_hospital_admin_for(request.hospital_id)
      )
  ), false)
$function$;

CREATE OR REPLACE FUNCTION private.can_access_patient_storage(object_name text, object_bucket text, target_action text DEFAULT 'view'::text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  folder text := (storage.foldername(object_name))[1];
  folder_uuid uuid;
begin
  if folder is not null
    and folder ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    folder_uuid := folder::uuid;
    if folder_uuid = private.current_patient_id() then
      return true;
    end if;
  end if;

  if exists (
    select 1
    from public.medical_documents document
    where document.storage_bucket = object_bucket
      and document.storage_path = object_name
      and private.can_access_clinical_record(
        document.patient_id, document.hospital_id,
        'medical_documents', document.id, target_action
      )
  ) then return true; end if;

  if exists (
    select 1
    from public.laboratory_results result
    where result.file_path = object_name
      and private.can_access_clinical_record(
        result.patient_id, result.hospital_id,
        'laboratory_results', result.id, target_action
      )
  ) then return true; end if;

  if exists (
    select 1
    from public.consultation_attachments attachment
    join public.consultations consultation on consultation.id = attachment.consultation_id
    where attachment.storage_path = object_name
      and private.can_access_clinical_record(
        coalesce(attachment.patient_id, consultation.patient_id),
        consultation.hospital_id, 'consultations', consultation.id, target_action
      )
  ) then return true; end if;

  return false;
end
$function$;

CREATE OR REPLACE FUNCTION private.can_access_patient_storage(object_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  folder text := (storage.foldername(object_name))[1];
begin
  if folder is null or folder !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return false;
  end if;
  return private.can_access_patient(folder::uuid);
end;
$function$;

CREATE OR REPLACE FUNCTION private.can_access_patient(target_patient_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    target_patient_id = private.current_patient_id()
    or exists (
      select 1
      from public.patient_access_grants grant_row
      join public.patient_access_scopes scope on scope.grant_id = grant_row.id
      where grant_row.patient_id = target_patient_id
        and grant_row.receiving_doctor_id = private.current_doctor_id()
        and grant_row.status = 'active'
        and grant_row.activated_at <= now()
        and grant_row.expires_at > now()
        and grant_row.revoked_at is null
        and scope.can_view
        and private.has_active_doctor_employment(
          grant_row.receiving_doctor_id,
          grant_row.receiving_hospital_id
        )
        and private.is_active_care_relationship(
          grant_row.care_relationship_id,
          grant_row.patient_id,
          grant_row.receiving_hospital_id,
          grant_row.receiving_doctor_id
        )
    )
    or exists (
      select 1
      from public.emergency_access_events emergency
      where emergency.patient_id = target_patient_id
        and emergency.doctor_id = private.current_doctor_id()
        and emergency.status = 'active'
        and emergency.expires_at > now()
    ),
    false
  )
$function$;

CREATE OR REPLACE FUNCTION private.can_create_assigned_patient_document(target_patient_id uuid, target_hospital_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(exists (
    select 1
    from public.doctor_patient_assignments assignment
    where assignment.patient_id = target_patient_id
      and assignment.doctor_id = private.current_doctor_id()
      and assignment.hospital_id = target_hospital_id
      and assignment.assignment_status = 'active'
      and assignment.ended_at is null
      and private.has_active_doctor_employment(
        assignment.doctor_id,
        assignment.hospital_id
      )
  ), false)
$function$;

CREATE OR REPLACE FUNCTION private.can_manage_hospital_storage(object_name text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare folder text := (storage.foldername(object_name))[1];
begin
  if private.is_super_admin() then return true; end if;
  if folder is null or folder !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then return false; end if;
  return private.is_hospital_admin_for(folder::uuid);
end;
$function$;

CREATE OR REPLACE FUNCTION private.can_participate_conversation(target_conversation_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(exists (
    select 1
    from public.chat_conversations conversation
    left join public.consultations consultation
      on consultation.id = conversation.consultation_id
    left join public.guest_consultation_requests guest_request
      on guest_request.id = conversation.guest_request_id
    where conversation.id = target_conversation_id
      and conversation.status in ('pending', 'active', 'closed')
      and (
        conversation.patient_id = private.current_patient_id()
        or (
          conversation.doctor_id = private.current_doctor_id()
          and (
            consultation.status in (
              'approved', 'scheduled', 'in_progress', 'completed'
            )
            or exists (
              select 1
              from public.doctor_patient_assignments assignment
              where assignment.doctor_id = conversation.doctor_id
                and assignment.patient_id = conversation.patient_id
                and assignment.assignment_status = 'active'
                and assignment.ended_at is null
            )
          )
        )
        or (
          conversation.guest_request_id is not null
          and guest_request.submitted_by = (select auth.uid())
          and private.current_user_id() is not null
          and guest_request.request_status in (
            'approved', 'temporary_patient_created',
            'account_activation_pending', 'consultation_scheduled',
            'consultation_completed'
          )
        )
      )
  ), false)
$function$;

CREATE OR REPLACE FUNCTION private.can_send_to_conversation(target_conversation_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    private.can_participate_conversation(target_conversation_id)
    and exists (
      select 1
      from public.chat_conversations conversation
      left join public.consultations consultation
        on consultation.id = conversation.consultation_id
      where conversation.id = target_conversation_id
        and conversation.status = 'active'
        and (
          consultation.status in ('approved', 'scheduled', 'in_progress')
          or exists (
            select 1
            from public.doctor_patient_assignments assignment
            where assignment.doctor_id = conversation.doctor_id
              and assignment.patient_id = conversation.patient_id
              and assignment.assignment_status = 'active'
              and assignment.ended_at is null
          )
        )
    ),
    false
  )
$function$;

CREATE OR REPLACE FUNCTION private.can_upload_patient_storage(object_name text, object_bucket text)
 RETURNS boolean
 LANGUAGE plpgsql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  folder text := (storage.foldername(object_name))[1];
  target_patient_id uuid;
  doctor_row public.doctors;
  category text;
begin
  if folder is null
    or folder !~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' then
    return false;
  end if;
  target_patient_id := folder::uuid;
  if target_patient_id = private.current_patient_id() then return true; end if;

  select * into doctor_row
  from public.doctors doctor
  where doctor.id = private.current_doctor_id();
  if doctor_row.id is null then return false; end if;

  category := case
    when object_bucket in ('laboratory-results', 'scanned-medical-results') then 'laboratory_results'
    when object_bucket = 'prescriptions' then 'prescriptions'
    else 'medical_documents'
  end;

  if category = 'medical_documents'
    and private.can_create_assigned_patient_document(
      target_patient_id, doctor_row.hospital_id
    ) then
    return true;
  end if;

  return private.can_access_clinical_record(
    target_patient_id, doctor_row.hospital_id, category, null, 'create'
  );
end
$function$;

CREATE OR REPLACE FUNCTION private.can_view_user(target_user_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    target_user_id = private.current_user_id()
    or private.is_super_admin()
    or exists (
      select 1 from public.users target
      where target.id = target_user_id
        and private.current_role() = 'hospital_admin'
        and target.hospital_id = private.current_hospital_id()
    )
    or exists (
      select 1 from public.patients p
      where p.user_id = target_user_id and private.can_access_patient(p.id)
    ),
    false
  )
$function$;

CREATE OR REPLACE FUNCTION public.cancel_consultation(target_consultation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  consultation_row public.consultations;
begin
  if (select auth.uid()) is null then
    raise exception 'A signed-in patient is required';
  end if;

  select * into consultation_row
  from public.consultations
  where id = target_consultation_id
  for update;

  if not found
    or private.current_patient_id() is null
    or consultation_row.patient_id is distinct from private.current_patient_id() then
    raise exception 'The consultation is not accessible to this patient';
  end if;
  if consultation_row.status not in ('pending','approved','scheduled') then
    raise exception 'This consultation can no longer be cancelled by the patient';
  end if;

  update public.consultations
  set status = 'cancelled'
  where id = target_consultation_id
  returning * into consultation_row;

  return jsonb_build_object('id', consultation_row.id, 'status', consultation_row.status);
end;
$function$;

CREATE OR REPLACE FUNCTION public.cancel_online_consultation_request(target_request_id uuid, cancellation_reason text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  request_row public.online_consultation_requests;
  normalized_reason text := nullif(btrim($2), '');
begin
  select * into request_row
  from public.online_consultation_requests
  where id = target_request_id
  for update;

  if not found
    or request_row.patient_id is distinct from private.current_patient_id()
    or request_row.submitted_by is distinct from private.current_user_id() then
    raise exception 'The online request was not found for the current patient';
  end if;
  if request_row.request_status in (
    'completed', 'rejected', 'cancelled', 'no_show', 'in_progress'
  ) then
    raise exception 'This online request can no longer be cancelled';
  end if;
  if normalized_reason is null then
    raise exception 'A cancellation reason is required';
  end if;

  update public.online_consultation_requests request
  set request_status = 'cancelled',
      cancellation_reason = normalized_reason,
      updated_at = now()
  where request.id = request_row.id;

  if request_row.official_consultation_id is not null then
    update public.consultations consultation
    set status = 'cancelled', updated_at = now()
    where consultation.id = request_row.official_consultation_id
      and consultation.status in ('pending', 'approved', 'scheduled');
  end if;

  perform private.revoke_relationship_access(
    request_row.care_relationship_id, 'cancelled', normalized_reason
  );

  return jsonb_build_object(
    'request_id', request_row.id,
    'reference_number', request_row.reference_number,
    'status', 'cancelled'
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.claim_notification_outbox(batch_size integer DEFAULT 50)
 RETURNS SETOF notification_outbox
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  return query
  update public.notification_outbox outbox set status='processing',attempt_count=attempt_count+1,updated_at=now()
  where outbox.id in (
    select queued.id from public.notification_outbox queued
    where queued.status in ('pending','failed') and queued.next_attempt_at<=now()
    order by queued.created_at for update skip locked limit least(greatest(batch_size,1),500)
  ) returning outbox.*;
end;
$function$;

CREATE OR REPLACE FUNCTION public.complete_notification_delivery(target_outbox_id bigint, delivered boolean, provider_id text DEFAULT NULL::text, error_message text DEFAULT NULL::text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.notification_outbox
  set status=case
        when delivered then 'delivered'
        when attempt_count>=5 then 'cancelled'
        else 'failed'
      end,
      provider_message_id=provider_id,
      last_error=case when delivered then null else left(coalesce(error_message,'Delivery failed'),1000) end,
      delivered_at=case when delivered then now() else null end,
      next_attempt_at=case
        when delivered or attempt_count>=5 then next_attempt_at
        else now()+make_interval(mins=>least(60,power(2,least(attempt_count,5))::integer))
      end,
      updated_at=now()
  where id=target_outbox_id and status='processing';
  if not found then raise exception 'Processing outbox delivery was not found'; end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.confirm_medical_result(target_result_id uuid, confirmed_findings text, interpretation text DEFAULT NULL::text, create_record boolean DEFAULT true)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare result_row public.laboratory_results; record_id uuid; final_status public.medical_result_status;
begin
  select * into result_row from public.laboratory_results where id=target_result_id for update;
  if not found or result_row.doctor_id <> private.current_doctor_id() or not private.can_access_patient(result_row.patient_id) then
    raise exception 'Only the responsible doctor may confirm this result';
  end if;
  if result_row.verification_status not in ('pending_doctor_review','doctor_modified') then raise exception 'Result is not awaiting doctor confirmation'; end if;
  update public.laboratory_results set doctor_confirmed_findings=btrim(confirmed_findings), professional_interpretation=nullif(btrim(interpretation),''),
    verification_status=case when interpretation is null then 'doctor_confirmed'::public.medical_result_status else 'doctor_modified'::public.medical_result_status end,
    confirmed_by=private.current_doctor_id(),reviewed_by=private.current_doctor_id(),reviewed_at=now(),confirmed_at=now()
  where id=target_result_id;
  final_status := case when interpretation is null then 'doctor_confirmed'::public.medical_result_status else 'doctor_modified'::public.medical_result_status end;
  if create_record then
    insert into public.medical_records (patient_id,doctor_id,hospital_id,consultation_id,record_type,title,description,record_date,
      source_laboratory_result_id,confirmed_by,is_ai_assisted)
    values (result_row.patient_id,result_row.doctor_id,result_row.hospital_id,result_row.consultation_id,'laboratory_result',result_row.test_name,
      coalesce(interpretation,confirmed_findings),current_date,target_result_id,result_row.doctor_id,true)
    returning id into record_id;
    update public.laboratory_results set verification_status='saved_to_patient_record' where id=target_result_id;
    final_status := 'saved_to_patient_record';
  end if;
  return jsonb_build_object('laboratory_result_id',target_result_id,'medical_record_id',record_id,'status',final_status);
end;
$function$;

CREATE OR REPLACE FUNCTION private.current_doctor_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select d.id from public.doctors d where d.user_id = private.current_user_id() limit 1
$function$;

CREATE OR REPLACE FUNCTION private.current_hospital_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select app_user.hospital_id
  from public.users app_user
  where app_user.auth_user_id = (select auth.uid())
    and app_user.account_status = 'active'
  limit 1
$function$;

CREATE OR REPLACE FUNCTION private.current_patient_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select p.id from public.patients p where p.user_id = private.current_user_id() limit 1
$function$;

CREATE OR REPLACE FUNCTION public.current_permissions()
 RETURNS text[]
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select coalesce(array_agg(permission.permission order by permission.permission),'{}'::text[])
  from public.users app_user
  join public.role_permissions permission on permission.role_id=app_user.role_id
  where app_user.auth_user_id=(select auth.uid())
    and app_user.account_status='active'
    and permission.is_allowed
$function$;

CREATE OR REPLACE FUNCTION private."current_role"()
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select role.role_name
  from public.users app_user
  join public.roles role on role.id = app_user.role_id
  where app_user.auth_user_id = (select auth.uid())
    and app_user.account_status = 'active'
  limit 1
$function$;

CREATE OR REPLACE FUNCTION private.current_user_id()
 RETURNS uuid
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select app_user.id
  from public.users app_user
  where app_user.auth_user_id = (select auth.uid())
    and app_user.account_status = 'active'
  limit 1
$function$;

CREATE OR REPLACE FUNCTION public.decide_patient_connection_request(target_request_id uuid, approve_request boolean)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  request_row public.patient_connection_requests;
  patient_row public.patients;
  relationship_id uuid;
  consent_id uuid;
  access_expires_at timestamptz := now() + interval '90 days';
  patient_auth_id uuid := (select auth.uid());
  doctor_auth_id uuid;
  decision_status text;
  all_categories text[] := array[
    'consultations', 'medical_records', 'diagnoses', 'prescriptions',
    'laboratory_requests', 'laboratory_results', 'medical_documents',
    'clinical_notes', 'allergies_medications', 'treatment_plans'
  ]::text[];
begin
  if patient_auth_id is null
    or private.current_user_id() is null
    or private.current_patient_id() is null then
    raise exception 'An authenticated patient account is required';
  end if;

  select * into request_row
  from public.patient_connection_requests request
  where request.id = target_request_id
    and request.patient_id = private.current_patient_id()
  for update;

  if not found then
    raise exception 'This connection request was not found';
  end if;
  if request_row.status <> 'requested' then
    raise exception 'This connection request has already been decided';
  end if;
  if request_row.expires_at <= now() then
    raise exception 'This connection request has expired';
  end if;

  select * into patient_row
  from public.patients patient
  where patient.id = request_row.patient_id;

  if approve_request then
    if not exists (
      select 1
      from public.doctor_hospital_employments employment
      where employment.doctor_id = request_row.doctor_id
        and employment.hospital_id = request_row.hospital_id
        and employment.employment_status = 'active'
        and employment.is_verified
        and employment.starts_at <= now()
        and (employment.ends_at is null or employment.ends_at > now())
    ) then
      raise exception 'This clinician is no longer verified at the facility';
    end if;

    insert into public.patient_care_relationships(
      patient_id, hospital_id, doctor_id, relationship_type, purpose,
      status, requested_at, expires_at, created_by
    ) values (
      request_row.patient_id,
      request_row.hospital_id,
      request_row.doctor_id,
      'ongoing_outpatient_care',
      'clinician_patient_connection',
      'requested',
      request_row.requested_at,
      access_expires_at,
      request_row.requested_by
    ) returning id into relationship_id;

    insert into public.patient_consents(
      patient_id, consent_type, consent_version, is_granted, granted_at,
      captured_by, metadata, care_relationship_id, source_hospital_id,
      receiving_hospital_id, purpose, categories, permitted_actions,
      record_selection_mode, expires_at, granted_by, version_sequence
    ) values (
      request_row.patient_id,
      'clinician_connection_access',
      relationship_id::text,
      true,
      now(),
      patient_auth_id,
      pg_catalog.jsonb_build_object(
        'connection_request_id', request_row.id,
        'patient_decision', 'approved',
        'access_duration_days', 90
      ),
      relationship_id,
      coalesce(patient_row.primary_hospital_id, request_row.hospital_id),
      request_row.hospital_id,
      'clinician_patient_connection',
      all_categories,
      array['view', 'download', 'create']::text[],
      'categories',
      access_expires_at,
      private.current_user_id(),
      1
    ) returning id into consent_id;

    perform private.activate_relationship_access(
      relationship_id,
      consent_id,
      request_row.doctor_id,
      null,
      '[]'::jsonb
    );
    decision_status := 'approved';
  else
    decision_status := 'rejected';
  end if;

  update public.patient_connection_requests request
  set status = decision_status,
      decided_at = now(),
      updated_at = now()
  where request.id = request_row.id;

  update public.notifications notification
  set is_read = true,
      data = coalesce(notification.data, '{}'::jsonb)
        || pg_catalog.jsonb_build_object(
          'status', decision_status,
          'access_expires_at', case
            when approve_request then access_expires_at
            else null
          end
        )
  where notification.notification_type = 'access_request'
    and notification.reference_id = request_row.id
    and notification.user_id = patient_auth_id;

  select app_user.auth_user_id into doctor_auth_id
  from public.users app_user
  where app_user.id = request_row.requested_by;

  if doctor_auth_id is not null then
    insert into public.notifications(
      user_id, title, message, notification_type, reference_id, data
    ) values (
      doctor_auth_id,
      case when approve_request
        then 'Patient connection accepted'
        else 'Patient connection declined'
      end,
      case when approve_request
        then 'The patient accepted your connection request. You can now access their authorized care workspace.'
        else 'The patient declined your connection request. No account access was granted.'
      end,
      'access_request_decision',
      request_row.id,
      pg_catalog.jsonb_build_object(
        'connection_request_id', request_row.id,
        'status', decision_status
      )
    );
  end if;

  return pg_catalog.jsonb_build_object(
    'request_id', request_row.id,
    'status', decision_status,
    'access_expires_at', case when approve_request then access_expires_at else null end
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.delete_own_medical_document(target_document_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  deleted_document public.medical_documents;
begin
  if private.current_role() <> 'patient' or target_document_id is null then
    raise exception 'An authenticated patient file is required';
  end if;

  delete from public.medical_documents
  where id = target_document_id
    and uploaded_by = private.current_user_id()
    and patient_id = private.current_patient_id()
    and document_type in ('lab_result', 'prescription')
  returning * into deleted_document;

  if not found then
    raise exception 'Patients may delete only lab or prescription files they uploaded themselves';
  end if;

  return jsonb_build_object(
    'storage_bucket', deleted_document.storage_bucket,
    'storage_path', deleted_document.storage_path
  );
end;
$function$;

CREATE OR REPLACE FUNCTION private.derive_emergency_capacity()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  staffed_capacity integer;
  is_meaningful_update boolean := true;
begin
  new.maximum_capacity := coalesce(new.maximum_capacity, 0);
  new.occupied_beds := coalesce(new.occupied_beds, 0);
  new.closed_or_unstaffed_beds := coalesce(new.closed_or_unstaffed_beds, 0);
  new.reserved_beds := coalesce(new.reserved_beds, 0);
  new.current_patient_count := coalesce(new.current_patient_count, 0);
  new.capacity_source := coalesce(nullif(new.capacity_source, ''), 'manual');

  -- Translate writes from clients deployed before status_override existed.
  if tg_op = 'UPDATE'
    and new.status is distinct from old.status
    and new.status_override is not distinct from old.status_override then
    if new.status = 'available' then
      new.status_override := null;
      new.override_reason := null;
    else
      new.status_override := new.status;
      new.override_reason := coalesce(
        nullif(btrim(new.override_reason), ''),
        'Manual operational status override'
      );
    end if;
  end if;

  if new.maximum_capacity < 0
    or new.occupied_beds < 0
    or new.closed_or_unstaffed_beds < 0
    or new.reserved_beds < 0
    or new.current_patient_count < 0 then
    raise exception 'Emergency capacity values cannot be negative';
  end if;

  if new.occupied_beds
      + new.closed_or_unstaffed_beds
      + new.reserved_beds > new.maximum_capacity then
    raise exception 'Occupied, unavailable, and reserved beds cannot exceed total ER capacity';
  end if;

  if new.status_override is not null
    and length(btrim(coalesce(new.override_reason, ''))) not between 3 and 500 then
    raise exception 'An operational override reason between 3 and 500 characters is required';
  end if;

  if new.status_override is null then
    new.override_reason := null;
  end if;

  staffed_capacity := new.maximum_capacity - new.closed_or_unstaffed_beds;
  new.available_beds := staffed_capacity - new.occupied_beds - new.reserved_beds;

  if new.status_override is not null then
    new.status := new.status_override;
  elsif new.available_beds = 0 then
    new.status := 'full';
  elsif new.available_beds * 5 <= staffed_capacity then
    new.status := 'limited';
  else
    new.status := 'available';
  end if;

  if tg_op = 'UPDATE' then
    is_meaningful_update :=
      new.maximum_capacity is distinct from old.maximum_capacity
      or new.occupied_beds is distinct from old.occupied_beds
      or new.closed_or_unstaffed_beds is distinct from old.closed_or_unstaffed_beds
      or new.reserved_beds is distinct from old.reserved_beds
      or new.current_patient_count is distinct from old.current_patient_count
      or new.status_override is distinct from old.status_override
      or new.override_reason is distinct from old.override_reason
      or new.capacity_source is distinct from old.capacity_source;
  end if;

  if tg_op = 'INSERT' or is_meaningful_update then
    new.last_updated := now();
    new.updated_by := coalesce(private.current_user_id(), new.updated_by);
  end if;

  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.end_emergency_patient_access(target_event_id uuid, review_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  event_row public.emergency_access_events;
begin
  select * into event_row
  from public.emergency_access_events
  where id = target_event_id
  for update;
  if not found or (
    event_row.doctor_id <> private.current_doctor_id()
    and not private.is_hospital_admin_for(event_row.hospital_id)
  ) then
    raise exception 'This emergency access event is not available for review';
  end if;
  update public.emergency_access_events
  set status = 'ended', ended_at = coalesce(ended_at, now()),
      reviewed_by = private.current_user_id(), reviewed_at = now(),
      review_notes = nullif(btrim(review_note), '')
  where id = target_event_id;
end
$function$;

CREATE OR REPLACE FUNCTION private.end_replaced_doctor_patient_assignment()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.assignment_status = 'active' and new.ended_at is null then
    update public.doctor_patient_assignments assignment
    set assignment_status = 'ended',
        ended_at = now(),
        ended_reason = 'Replaced by a newly approved care relationship'
    where assignment.doctor_id = new.doctor_id
      and assignment.patient_id = new.patient_id
      and assignment.ended_at is null
      and assignment.assignment_status = 'active'
      and assignment.id is distinct from new.id
      and assignment.care_relationship_id is distinct from new.care_relationship_id;
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION private.enforce_clinical_provenance()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  old_row jsonb := to_jsonb(old);
  new_row jsonb := to_jsonb(new);
  protected_column text;
begin
  foreach protected_column in array array[
    'patient_id', 'hospital_id', 'doctor_id', 'author_doctor_id',
    'consultation_id', 'created_at', 'record_date', 'requested_at', 'uploaded_at'
  ] loop
    if old_row ? protected_column
      and new_row ? protected_column
      and old_row->protected_column is distinct from new_row->protected_column then
      raise exception 'Clinical provenance column % is immutable; add an addendum instead', protected_column;
    end if;
  end loop;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION private.enforce_consultation_assignment_provenance()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.patient_id is distinct from old.patient_id
    or new.hospital_id is distinct from old.hospital_id then
    raise exception 'Consultation patient and hospital provenance are immutable';
  end if;
  if new.doctor_id is distinct from old.doctor_id
    and coalesce(current_setting('app.authorized_reassignment', true), 'off') <> 'on' then
    raise exception 'Use the protected reassignment workflow to change the assigned doctor';
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.enforce_consultation_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor_role text := private.current_role();
  patient_cancel boolean := false;
  patient_reschedule boolean := false;
begin
  if tg_op = 'UPDATE' then
    if new.patient_id is distinct from old.patient_id
      or new.guest_request_id is distinct from old.guest_request_id
      or new.doctor_id is distinct from old.doctor_id
      or new.hospital_id is distinct from old.hospital_id
      or new.consultation_type is distinct from old.consultation_type
      or new.created_at is distinct from old.created_at then
      raise exception 'Consultation ownership fields are immutable';
    end if;

    if new.status is distinct from old.status and not (
      (old.status = 'pending' and new.status in ('approved','rejected','scheduled','cancelled'))
      or (old.status = 'approved' and new.status in ('scheduled','in_progress','cancelled'))
      or (old.status = 'scheduled' and new.status in ('in_progress','cancelled'))
      or (old.status = 'in_progress' and new.status in ('completed','cancelled'))
    ) then
      raise exception 'Invalid consultation status transition from % to %', old.status, new.status;
    end if;

    if actor_role = 'patient' then
      patient_cancel :=
        old.status in ('pending','approved','scheduled')
        and new.status = 'cancelled'
        and (to_jsonb(new) - array['status','updated_at'])
          is not distinct from (to_jsonb(old) - array['status','updated_at']);

      patient_reschedule :=
        old.status in ('approved','scheduled')
        and new.status = old.status
        and new.appointment_date is distinct from old.appointment_date
        and (to_jsonb(new) - array['appointment_date','updated_at'])
          is not distinct from (to_jsonb(old) - array['appointment_date','updated_at']);

      if not patient_cancel and not patient_reschedule then
        raise exception 'Patients may only cancel or reschedule their own eligible consultation';
      end if;
    elsif actor_role = 'hospital_admin' and (
      new.doctor_notes is distinct from old.doctor_notes
      or new.confirmed_diagnosis is distinct from old.confirmed_diagnosis
      or new.treatment_plan is distinct from old.treatment_plan
      or new.consultation_summary is distinct from old.consultation_summary
    ) then
      raise exception 'Hospital administrators cannot modify clinical content';
    end if;

    if new.status = 'completed' and new.completed_at is null then
      new.completed_at := now();
    end if;
    if new.status = 'in_progress' and new.started_at is null then
      new.started_at := now();
    end if;
    if new.status = 'approved' and new.approved_at is null then
      new.approved_at := now();
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.enforce_guest_request_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor_role text := private.current_role();
begin
  if new.submitted_by is distinct from old.submitted_by or new.reference_number is distinct from old.reference_number
    or new.created_at is distinct from old.created_at then raise exception 'Guest request ownership fields are immutable'; end if;
  if new.request_status is distinct from old.request_status and not (
    (old.request_status='pending_verification' and new.request_status in ('otp_verified','cancelled'))
    or (old.request_status='otp_verified' and new.request_status in ('pending_doctor_review','approved','rejected','cancelled'))
    or (old.request_status='pending_doctor_review' and new.request_status in ('approved','rejected','cancelled'))
    or (old.request_status='approved' and new.request_status in ('temporary_patient_created','consultation_scheduled','cancelled'))
    or (old.request_status='temporary_patient_created' and new.request_status in ('account_activation_pending','consultation_scheduled','cancelled'))
    or (old.request_status='account_activation_pending' and new.request_status in ('consultation_scheduled','cancelled'))
    or (old.request_status='consultation_scheduled' and new.request_status in ('consultation_completed','cancelled'))
  ) then raise exception 'Invalid guest request status transition from % to %',old.request_status,new.request_status; end if;
  if actor_role='guest' and not (new.request_status='cancelled' and old.submitted_by=(select auth.uid())) then
    raise exception 'Guests may only cancel their own request';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.enforce_reservation_lead_time()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare scheduled_at timestamptz;
begin
  if tg_table_name='consultations' then
    if tg_op='UPDATE' then
      if new.appointment_date is not distinct from old.appointment_date then return new; end if;
    end if;
    if new.consultation_type::text='emergency' then return new; end if;
    scheduled_at := new.appointment_date;
  elsif tg_table_name='guest_consultation_requests' then
    if tg_op='UPDATE' then
      if new.preferred_schedule is not distinct from old.preferred_schedule then return new; end if;
    end if;
    scheduled_at := new.preferred_schedule;
  elsif tg_table_name='online_consultation_requests' then
    if tg_op='UPDATE' then
      if new.preferred_schedule is not distinct from old.preferred_schedule then return new; end if;
    end if;
    scheduled_at := new.preferred_schedule;
  else raise exception 'Unsupported reservation table';
  end if;
  if not private.meets_reservation_lead_time(scheduled_at) then
    raise exception 'Reservations must be made at least 24 hours in advance';
  end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.enqueue_due_appointment_reminders(batch_size integer DEFAULT 100, reminder_window interval DEFAULT '24:00:00'::interval)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  consultation_row record;
  patient_recipient uuid;
  doctor_recipient uuid;
  processed integer := 0;
  safe_data jsonb;
begin
  if reminder_window <= interval '0 seconds' or reminder_window > interval '14 days' then
    raise exception 'Reminder window must be between zero and fourteen days';
  end if;

  for consultation_row in
    select consultation.id,consultation.patient_id,consultation.guest_request_id,
      consultation.doctor_id,consultation.hospital_id,consultation.appointment_date
    from public.consultations consultation
    where consultation.status in ('approved','scheduled')
      and consultation.appointment_date > now()
      and consultation.appointment_date <= now() + reminder_window
      and not exists (
        select 1 from public.appointment_reminder_jobs reminder_job
        where reminder_job.consultation_id=consultation.id
          and reminder_job.appointment_date=consultation.appointment_date
      )
    order by consultation.appointment_date,consultation.id
    for update skip locked
    limit least(greatest(batch_size,1),500)
  loop
    insert into public.appointment_reminder_jobs(consultation_id,appointment_date)
    values(consultation_row.id,consultation_row.appointment_date)
    on conflict do nothing;
    if not found then continue; end if;

    patient_recipient := null;
    doctor_recipient := null;
    if consultation_row.patient_id is not null then
      select app_user.auth_user_id into patient_recipient
      from public.patients patient
      join public.users app_user on app_user.id = patient.user_id
      where patient.id = consultation_row.patient_id;
    elsif consultation_row.guest_request_id is not null then
      select submitted_by into patient_recipient
      from public.guest_consultation_requests
      where id = consultation_row.guest_request_id;
    end if;
    select app_user.auth_user_id into doctor_recipient
    from public.doctors doctor
    join public.users app_user on app_user.id = doctor.user_id
    where doctor.id = consultation_row.doctor_id;

    safe_data := jsonb_build_object(
      'appointment_date',consultation_row.appointment_date,
      'hospital_id',consultation_row.hospital_id,
      'event_key','appointment:' || consultation_row.appointment_date::text,
      'dedupe_key','appointment_reminder:' || consultation_row.id::text || ':' || consultation_row.appointment_date::text
    );
    perform private.enqueue_notification(
      patient_recipient,'Upcoming consultation',
      'You have an upcoming CareNavigator consultation.',
      'appointment_reminder',consultation_row.id,safe_data
    );
    perform private.enqueue_notification(
      doctor_recipient,'Upcoming assigned consultation',
      'An assigned CareNavigator consultation is approaching.',
      'appointment_reminder',consultation_row.id,
      safe_data || jsonb_build_object(
        'dedupe_key','doctor_appointment_reminder:' || consultation_row.id::text || ':' || consultation_row.appointment_date::text
      )
    );
    processed := processed + 1;
  end loop;
  return processed;
end;
$function$;

CREATE OR REPLACE FUNCTION public.enqueue_due_medication_summaries(batch_size integer DEFAULT 100)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare p record; today date:=(now() at time zone 'Asia/Manila')::date; content text; notification_id uuid; processed integer:=0;
begin
 if (now() at time zone 'Asia/Manila')::time<time '08:00' then return 0; end if;
 for p in select patient.id,u.auth_user_id from public.patients patient join public.users u on u.id=patient.user_id
   join auth.users a on a.id=u.auth_user_id join public.notification_preferences pref on pref.user_id=u.auth_user_id
   where u.account_status='active' and a.email_confirmed_at is not null and pref.medication_reminders and pref.email_enabled
     and not exists(select 1 from public.medication_summary_days d where d.patient_id=patient.id and d.local_date=today)
   order by patient.id limit least(greatest(batch_size,1),500)
 loop
  content:=private.medication_summary(p.id,today);
  if content is null then continue; end if;
  insert into public.medication_summary_days(patient_id,local_date) values(p.id,today) on conflict do nothing;
  if not found then continue; end if;
  notification_id:=private.enqueue_notification(p.auth_user_id,'Daily medication summary',content,'medication_reminder',p.id,
    jsonb_build_object('summary_date',today,'dedupe_key','daily-medications:'||p.id::text||':'||today::text));
  update public.medication_summary_days set notification_id=enqueue_due_medication_summaries.notification_id where patient_id=p.id and local_date=today;
  processed:=processed+1;
 end loop;
 return processed;
end $function$;

CREATE OR REPLACE FUNCTION private.enqueue_hospital_audience(target_hospital_id uuid, target_title text, target_message text, target_type text, target_reference_id uuid, target_data jsonb DEFAULT '{}'::jsonb)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  recipient record;
  enqueued integer := 0;
begin
  for recipient in
    select distinct audience.auth_user_id
    from (
      select app_user.auth_user_id
      from public.users app_user
      where app_user.account_status = 'active'
        and (target_hospital_id is null or app_user.hospital_id = target_hospital_id)
      union
      select app_user.auth_user_id
      from public.patients patient
      join public.users app_user on app_user.id = patient.user_id
      where app_user.account_status = 'active'
        and (target_hospital_id is null or patient.primary_hospital_id = target_hospital_id)
    ) audience
    where audience.auth_user_id is not null
  loop
    perform private.enqueue_notification(
      recipient.auth_user_id,target_title,target_message,target_type,
      target_reference_id,target_data
    );
    enqueued := enqueued + 1;
  end loop;
  return enqueued;
end;
$function$;

CREATE OR REPLACE FUNCTION private.enqueue_notification(target_user_id uuid, target_title text, target_message text, target_type text, target_reference_id uuid DEFAULT NULL::uuid, target_data jsonb DEFAULT '{}'::jsonb)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  notification_id uuid;
  generated_dedupe_key text;
begin
  if target_user_id is null then return null; end if;

  generated_dedupe_key := nullif(target_data->>'dedupe_key','');
  if generated_dedupe_key is null and target_reference_id is not null then
    generated_dedupe_key := concat_ws(
      ':',
      target_type,
      target_reference_id::text,
      coalesce(nullif(target_data->>'event_key',''), nullif(target_data->>'status',''), 'event')
    );
  end if;

  insert into public.notifications (
    user_id,title,message,notification_type,reference_id,data,action_path,dedupe_key
  ) values (
    target_user_id,
    target_title,
    target_message,
    target_type,
    target_reference_id,
    coalesce(target_data,'{}'::jsonb) - 'dedupe_key',
    private.notification_action_path(target_type,coalesce(target_data,'{}'::jsonb)),
    generated_dedupe_key
  )
  on conflict (user_id,dedupe_key) where dedupe_key is not null do nothing
  returning id into notification_id;

  if notification_id is null and generated_dedupe_key is not null then
    select id into notification_id
    from public.notifications
    where user_id=target_user_id and dedupe_key=generated_dedupe_key;
  end if;
  return notification_id;
end;
$function$;

CREATE OR REPLACE FUNCTION private.enrich_connection_request_notification()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  clinician_name text;
  facility_name text;
  request_status text;
  request_expires_at timestamptz;
begin
  if new.notification_type <> 'access_request' or new.reference_id is null then
    return new;
  end if;

  select
    nullif(pg_catalog.btrim(pg_catalog.concat_ws(
      ' ', app_user.first_name, app_user.last_name
    )), ''),
    hospital.hospital_name,
    request.status,
    request.expires_at
  into clinician_name, facility_name, request_status, request_expires_at
  from public.patient_connection_requests request
  join public.doctors doctor on doctor.id = request.doctor_id
  join public.users app_user on app_user.id = doctor.user_id
  join public.hospitals hospital on hospital.id = request.hospital_id
  where request.id = new.reference_id;

  new.data := coalesce(new.data, '{}'::jsonb) || pg_catalog.jsonb_build_object(
    'connection_request_id', new.reference_id,
    'doctor_display_name', coalesce(clinician_name, 'Verified clinician'),
    'hospital_name', coalesce(facility_name, 'Verified healthcare facility'),
    'status', request_status,
    'expires_at', request_expires_at
  );
  new.title := 'Care connection request';
  new.message := pg_catalog.format(
    '%s from %s would like to connect with your care account. Review the request before sharing access.',
    coalesce(clinician_name, 'A verified clinician'),
    coalesce(facility_name, 'a verified healthcare facility')
  );
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.ensure_consultation_conversation(target_consultation_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare consultation_row public.consultations; conversation_id uuid;
begin
  select * into consultation_row from public.consultations where id=target_consultation_id for update;
  if not found or consultation_row.status not in ('approved','scheduled','in_progress') then raise exception 'An approved consultation is required'; end if;
  if consultation_row.doctor_id<>private.current_doctor_id() then raise exception 'Only the assigned doctor may open this conversation'; end if;
  select id into conversation_id from public.chat_conversations where consultation_id=target_consultation_id;
  if conversation_id is not null then
    update public.chat_conversations set status=case when status='pending' then 'active' else status end where id=conversation_id;
    return conversation_id;
  end if;
  conversation_id := gen_random_uuid();
  insert into public.chat_conversations (id,patient_id,guest_request_id,doctor_id,consultation_id,status)
  values (conversation_id,consultation_row.patient_id,consultation_row.guest_request_id,consultation_row.doctor_id,consultation_row.id,'active');
  return conversation_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.ensure_patient_conversation(target_patient_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor_doctor_id uuid := private.current_doctor_id();
  conversation_id uuid;
begin
  if actor_doctor_id is null then
    raise exception 'An authenticated doctor is required';
  end if;

  if not exists (
    select 1
    from public.doctor_patient_assignments assignment
    where assignment.doctor_id = actor_doctor_id
      and assignment.patient_id = target_patient_id
      and assignment.assignment_status = 'active'
      and assignment.ended_at is null
  ) then
    raise exception 'An active doctor-patient assignment is required';
  end if;

  select conversation.id
  into conversation_id
  from public.chat_conversations conversation
  where conversation.doctor_id = actor_doctor_id
    and conversation.patient_id = target_patient_id
  order by
    (conversation.consultation_id is null) desc,
    conversation.updated_at desc
  limit 1;

  if conversation_id is not null then
    update public.chat_conversations
    set status = 'active', updated_at = now()
    where id = conversation_id;
    return conversation_id;
  end if;

  begin
    insert into public.chat_conversations(
      doctor_id,
      patient_id,
      consultation_id,
      status
    ) values (
      actor_doctor_id,
      target_patient_id,
      null,
      'active'
    )
    returning id into conversation_id;
  exception
    when unique_violation then
      select conversation.id
      into conversation_id
      from public.chat_conversations conversation
      where conversation.doctor_id = actor_doctor_id
        and conversation.patient_id = target_patient_id
        and conversation.consultation_id is null
      limit 1;
  end;

  return conversation_id;
end
$function$;

CREATE OR REPLACE FUNCTION public.ensure_video_session(target_consultation_id uuid, target_provider text DEFAULT 'jitsi'::text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  consultation_row public.consultations;
  session_row public.video_sessions;
  request_row public.online_consultation_requests;
  generated_room text;
  generated_url text;
begin
  if (select auth.uid()) is null or lower(target_provider) <> 'jitsi' then
    raise exception 'A signed-in doctor and the supported video provider are required';
  end if;

  select * into consultation_row
  from public.consultations
  where id = target_consultation_id
  for update;

  if not found
    or private.current_doctor_id() is null
    or consultation_row.patient_id is null
    or consultation_row.doctor_id is distinct from private.current_doctor_id()
    or consultation_row.consultation_type not in ('online', 'guest_online')
    or consultation_row.status not in ('approved', 'scheduled', 'in_progress')
    or not private.has_active_doctor_employment(
      consultation_row.doctor_id, consultation_row.hospital_id
    )
    or not private.actor_has_category_access(
      consultation_row.patient_id, 'consultations'
    ) then
    raise exception 'An active authorized online consultation assigned to this doctor is required';
  end if;

  select * into request_row
  from public.online_consultation_requests request
  where request.official_consultation_id = consultation_row.id;
  if request_row.id is not null
    and (
      request_row.consultation_channel <> 'video'
      or request_row.request_status not in (
        'confirmed', 'awaiting_contact', 'video_ready', 'in_progress'
      )
    ) then
    raise exception 'Video is not the confirmed channel for this request';
  end if;

  if now() < consultation_row.appointment_date - interval '15 minutes'
    or now() >= consultation_row.appointment_date + interval '4 hours' then
    raise exception 'The video room opens 15 minutes before the scheduled consultation';
  end if;

  select * into session_row
  from public.video_sessions
  where consultation_id = target_consultation_id
  for update;

  if found
    and session_row.provider = 'jitsi'
    and session_row.status in ('ready', 'active')
    and session_row.starts_at = consultation_row.appointment_date
    and session_row.expires_at > now() then
    return session_row.id;
  end if;

  generated_room := 'cnph-' || replace(gen_random_uuid()::text, '-', '');
  generated_url := 'https://meet.jit.si/' || generated_room;

  if session_row.id is null then
    insert into public.video_sessions(
      consultation_id, provider, room_name, join_url, status, created_by,
      starts_at, expires_at
    ) values (
      target_consultation_id, 'jitsi', generated_room, generated_url, 'ready',
      (select auth.uid()), consultation_row.appointment_date,
      consultation_row.appointment_date + interval '4 hours'
    ) returning * into session_row;
  else
    update public.video_sessions
    set provider = 'jitsi',
        room_name = generated_room,
        join_url = generated_url,
        status = 'ready',
        provider_metadata = '{}'::jsonb,
        created_by = (select auth.uid()),
        starts_at = consultation_row.appointment_date,
        started_at = null,
        ended_at = null,
        expires_at = consultation_row.appointment_date + interval '4 hours'
    where id = session_row.id
    returning * into session_row;
  end if;

  return session_row.id;
end
$function$;

CREATE OR REPLACE FUNCTION private.finalize_online_outcome()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.request_status is not distinct from old.request_status then return new; end if;
  if new.request_status in ('rejected','cancelled','patient_unreachable','no_show','face_to_face_recommended') then
    if new.official_consultation_id is not null then
      update public.consultations set status='cancelled'
      where id=new.official_consultation_id and status not in ('cancelled','rejected','completed');
      if private.current_role() in ('doctor','hospital_admin','super_admin') then
        update public.consultations set outcome_reason=new.request_status where id=new.official_consultation_id;
      end if;
    end if;
    perform private.revoke_relationship_access(new.care_relationship_id,new.request_status,
      coalesce(new.outcome_notes,new.cancellation_reason,new.rejection_reason,new.request_status));
  end if;
  perform private.enqueue_notification(
    (select u.auth_user_id from public.patients p join public.users u on u.id=p.user_id where p.id=new.patient_id),
    'Online consultation update',
    case new.request_status
      when 'more_information_required' then 'The hospital needs more information: '||coalesce(new.additional_information_request,'')
      when 'schedule_proposed' then 'The hospital proposed a schedule. Accept or decline it in your appointments.'
      when 'face_to_face_recommended' then 'The care team recommends a face-to-face visit. Make a new booking when ready.'
      else 'Request status: '||replace(new.request_status,'_',' ') end,
    'consultation_update',new.id,jsonb_build_object('status',new.request_status,'event_key',new.request_status||':'||new.updated_at::text)
  );
  return new;
end $function$;

CREATE OR REPLACE FUNCTION public.get_approved_video_room(target_consultation_id uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  consultation_row public.consultations;
  session_row public.video_sessions;
  online_request public.online_consultation_requests;
  is_authorized_participant boolean := false;
begin
  if (select auth.uid()) is null then
    raise exception 'A signed-in consultation participant is required';
  end if;
  select * into consultation_row
  from public.consultations where id = target_consultation_id;
  if not found then raise exception 'Consultation was not found'; end if;

  is_authorized_participant :=
    consultation_row.patient_id = private.current_patient_id()
    or (
      consultation_row.doctor_id = private.current_doctor_id()
      and private.has_active_doctor_employment(
        consultation_row.doctor_id, consultation_row.hospital_id
      )
    )
    or exists (
      select 1 from public.guest_consultation_requests guest_request
      where guest_request.id = consultation_row.guest_request_id
        and guest_request.submitted_by = (select auth.uid())
    );

  if not is_authorized_participant
    or consultation_row.consultation_type not in ('online', 'guest_online')
    or consultation_row.status not in ('approved', 'scheduled', 'in_progress') then
    raise exception 'An approved online consultation participant is required';
  end if;

  select * into online_request
  from public.online_consultation_requests request
  where request.official_consultation_id = consultation_row.id;
  if online_request.id is not null
    and (
      online_request.consultation_channel <> 'video'
      or online_request.request_status not in (
        'confirmed', 'awaiting_contact', 'video_ready', 'in_progress'
      )
    ) then
    raise exception 'Video is not the confirmed channel for this request';
  end if;
  if now() < consultation_row.appointment_date - interval '15 minutes'
    or now() >= consultation_row.appointment_date + interval '4 hours' then
    raise exception 'The video room is outside its scheduled join window';
  end if;

  select * into session_row
  from public.video_sessions
  where consultation_id = target_consultation_id
    and provider = 'jitsi'
    and status in ('ready', 'active')
    and starts_at = consultation_row.appointment_date
    and expires_at > now();
  if not found or session_row.join_url !~ '^https://meet[.]jit[.]si/cnph-[0-9a-f]{32}$' then
    raise exception 'The approved video room is not ready';
  end if;
  return session_row.join_url;
end
$function$;

CREATE OR REPLACE FUNCTION public.get_authorized_medical_document_download(target_document_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  document_row public.medical_documents;
  access_log_id bigint;
  is_external boolean;
begin
  select * into document_row
  from public.medical_documents
  where id = target_document_id;
  if not found then raise exception 'Medical document was not found'; end if;

  access_log_id := public.record_clinical_access(
    'medical_document', target_document_id, 'download'
  );
  is_external := document_row.hospital_id is not null
    and private.current_hospital_id() is not null
    and document_row.hospital_id <> private.current_hospital_id();

  return jsonb_build_object(
    'storage_bucket', document_row.storage_bucket,
    'storage_path', document_row.storage_path,
    'expires_in_seconds', 60,
    'watermark_required', is_external,
    'access_log_id', access_log_id
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.get_consultation_patient_context(target_consultation_id uuid)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  consultation_row public.consultations;
  patient_row public.patients;
  user_row public.users;
  context_result jsonb;
  records jsonb := '[]'::jsonb;
  diagnoses jsonb := '[]'::jsonb;
  prescriptions jsonb := '[]'::jsonb;
  lab_requests jsonb := '[]'::jsonb;
  lab_results jsonb := '[]'::jsonb;
  documents jsonb := '[]'::jsonb;
  plans jsonb := '[]'::jsonb;
begin
  select * into consultation_row
  from public.consultations where id = target_consultation_id;
  if not found or consultation_row.patient_id is null then
    raise exception 'A linked consultation patient is required';
  end if;
  if consultation_row.patient_id <> private.current_patient_id()
    and (
      consultation_row.doctor_id <> private.current_doctor_id()
      or not private.actor_has_category_access(
        consultation_row.patient_id, 'consultations'
      )
    ) then
    raise exception 'The consultation patient context is not authorized';
  end if;

  select * into patient_row from public.patients where id = consultation_row.patient_id;
  select * into user_row from public.users where id = patient_row.user_id;

  if private.actor_has_category_access(patient_row.id, 'medical_records') then
    select coalesce(jsonb_agg(jsonb_build_object(
      'record', to_jsonb(record),
      'originating_hospital', hospital.hospital_name,
      'authoring_doctor', doctor.display_name,
      'record_date', record.record_date,
      'record_status', 'final',
      'external_read_only', record.hospital_id <> consultation_row.hospital_id
    ) order by record.record_date desc), '[]'::jsonb)
    into records
    from public.medical_records record
    join public.hospitals hospital on hospital.id = record.hospital_id
    join public.doctors doctor on doctor.id = record.doctor_id
    where record.patient_id = patient_row.id
      and private.can_access_clinical_record(
        record.patient_id, record.hospital_id, 'medical_records', record.id, 'view'
      );
  end if;

  if private.actor_has_category_access(patient_row.id, 'diagnoses') then
    select coalesce(jsonb_agg(jsonb_build_object(
      'record', to_jsonb(record), 'originating_hospital', hospital.hospital_name,
      'authoring_doctor', doctor.display_name, 'record_date', record.confirmed_at,
      'record_status', 'final',
      'external_read_only', record.hospital_id <> consultation_row.hospital_id
    ) order by record.confirmed_at desc), '[]'::jsonb)
    into diagnoses
    from public.diagnoses record
    join public.hospitals hospital on hospital.id = record.hospital_id
    join public.doctors doctor on doctor.id = record.doctor_id
    where record.patient_id = patient_row.id
      and private.can_access_clinical_record(
        record.patient_id, record.hospital_id, 'diagnoses', record.id, 'view'
      );
  end if;

  if private.actor_has_category_access(patient_row.id, 'prescriptions') then
    select coalesce(jsonb_agg(jsonb_build_object(
      'record', to_jsonb(record), 'originating_hospital', hospital.hospital_name,
      'authoring_doctor', doctor.display_name, 'record_date', record.created_at,
      'record_status', 'final',
      'external_read_only', record.hospital_id <> consultation_row.hospital_id
    ) order by record.created_at desc), '[]'::jsonb)
    into prescriptions
    from public.prescriptions record
    join public.hospitals hospital on hospital.id = record.hospital_id
    join public.doctors doctor on doctor.id = record.doctor_id
    where record.patient_id = patient_row.id
      and private.can_access_clinical_record(
        record.patient_id, record.hospital_id, 'prescriptions', record.id, 'view'
      );
  end if;

  if private.actor_has_category_access(patient_row.id, 'laboratory_requests') then
    select coalesce(jsonb_agg(jsonb_build_object(
      'record', to_jsonb(record), 'originating_hospital', hospital.hospital_name,
      'authoring_doctor', doctor.display_name, 'record_date', record.requested_at,
      'record_status', record.status,
      'external_read_only', record.hospital_id <> consultation_row.hospital_id
    ) order by record.requested_at desc), '[]'::jsonb)
    into lab_requests
    from public.laboratory_requests record
    join public.hospitals hospital on hospital.id = record.hospital_id
    join public.doctors doctor on doctor.id = record.doctor_id
    where record.patient_id = patient_row.id
      and private.can_access_clinical_record(
        record.patient_id, record.hospital_id, 'laboratory_requests', record.id, 'view'
      );
  end if;

  if private.actor_has_category_access(patient_row.id, 'laboratory_results') then
    select coalesce(jsonb_agg(jsonb_build_object(
      'record', to_jsonb(record), 'originating_hospital', hospital.hospital_name,
      'authoring_doctor', doctor.display_name, 'record_date', record.uploaded_at,
      'record_status', record.verification_status,
      'external_read_only', record.hospital_id <> consultation_row.hospital_id
    ) order by record.uploaded_at desc), '[]'::jsonb)
    into lab_results
    from public.laboratory_results record
    join public.hospitals hospital on hospital.id = record.hospital_id
    join public.doctors doctor on doctor.id = record.doctor_id
    where record.patient_id = patient_row.id
      and private.can_access_clinical_record(
        record.patient_id, record.hospital_id, 'laboratory_results', record.id, 'view'
      );
  end if;

  if private.actor_has_category_access(patient_row.id, 'medical_documents') then
    select coalesce(jsonb_agg(jsonb_build_object(
      'record', to_jsonb(record), 'originating_hospital', hospital.hospital_name,
      'authoring_doctor', doctor.display_name, 'record_date', record.created_at,
      'record_status', record.record_status,
      'external_read_only', record.hospital_id is distinct from consultation_row.hospital_id
    ) order by record.created_at desc), '[]'::jsonb)
    into documents
    from public.medical_documents record
    left join public.hospitals hospital on hospital.id = record.hospital_id
    left join public.doctors doctor on doctor.id = record.author_doctor_id
    where record.patient_id = patient_row.id
      and private.can_access_clinical_record(
        record.patient_id, record.hospital_id, 'medical_documents', record.id, 'view'
      );
  end if;

  if private.actor_has_category_access(patient_row.id, 'treatment_plans') then
    select coalesce(jsonb_agg(jsonb_build_object(
      'record', to_jsonb(record), 'originating_hospital', hospital.hospital_name,
      'authoring_doctor', doctor.display_name, 'record_date', record.created_at,
      'record_status', record.status,
      'external_read_only', record.hospital_id <> consultation_row.hospital_id
    ) order by record.created_at desc), '[]'::jsonb)
    into plans
    from public.treatment_plans record
    join public.hospitals hospital on hospital.id = record.hospital_id
    join public.doctors doctor on doctor.id = record.doctor_id
    where record.patient_id = patient_row.id
      and private.can_access_clinical_record(
        record.patient_id, record.hospital_id, 'treatment_plans', record.id, 'view'
      );
  end if;

  context_result := jsonb_build_object(
    'patient_id', patient_row.id,
    'demographics', jsonb_build_object(
      'first_name', user_row.first_name, 'last_name', user_row.last_name,
      'birth_date', user_row.birth_date, 'sex', user_row.sex,
      'mobile_number', user_row.mobile_number, 'address', user_row.address,
      'patient_number', patient_row.patient_number
    ),
    'allergies_medications', case
      when private.actor_has_category_access(patient_row.id, 'allergies_medications')
      then jsonb_build_object(
        'allergies', consultation_row.allergies,
        'current_medications', consultation_row.current_medications,
        'source_hospital_id', consultation_row.hospital_id,
        'consultation_id', consultation_row.id
      ) else null end,
    'medical_records', records,
    'diagnoses', diagnoses,
    'prescriptions', prescriptions,
    'laboratory_requests', lab_requests,
    'laboratory_results', lab_results,
    'medical_documents', documents,
    'treatment_plans', plans
  );

  insert into public.medical_record_access_logs(
    patient_id, actor_user_id, actor_role, resource_type, resource_id,
    access_type, metadata, success
  ) values (
    patient_row.id, private.current_user_id(), private.current_role(),
    'consultation_patient_context', consultation_row.id, 'view',
    jsonb_build_object('consultation_id', consultation_row.id), true
  );
  return context_result;
end
$function$;

CREATE OR REPLACE FUNCTION public.get_guest_consultation_request_tracking(target_reference text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  request_row public.guest_consultation_requests;
  official_consultation public.consultations;
begin
  if (select auth.uid()) is null then
    raise exception 'Sign in with the verified request account to track this request';
  end if;

  select * into request_row
  from public.guest_consultation_requests request
  where request.reference_number = btrim(target_reference)
     or request.id::text = btrim(target_reference);
  if not found or not (
    request_row.submitted_by = (select auth.uid())
    or private.is_hospital_admin_for(request_row.preferred_hospital_id)
    or request_row.assigned_doctor_id = private.current_doctor_id()
  ) then
    raise exception 'Guest consultation request was not found';
  end if;

  select * into official_consultation
  from public.consultations consultation
  where consultation.guest_request_id = request_row.id
  order by consultation.created_at desc
  limit 1;

  return jsonb_build_object(
    'request_id', request_row.id,
    'reference_number', request_row.reference_number,
    'status', request_row.request_status,
    'identity_review_status', request_row.identity_review_status,
    'review_notes', request_row.identity_review_notes,
    'rejection_reason', request_row.rejection_reason,
    'hospital_id', request_row.preferred_hospital_id,
    'department_id', request_row.preferred_department_id,
    'doctor_id', request_row.assigned_doctor_id,
    'preferred_schedule', request_row.preferred_schedule,
    'consultation_id', official_consultation.id,
    'confirmed_schedule', official_consultation.appointment_date,
    'consultation_status', official_consultation.status,
    'consultation_type', official_consultation.consultation_type,
    'updated_at', request_row.updated_at
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.get_online_consultation_request_tracking(target_reference text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  request_row public.online_consultation_requests;
  doctor_name text;
  department_name text;
begin
  select * into request_row
  from public.online_consultation_requests request
  where request.reference_number = upper(btrim(target_reference))
     or request.id::text = btrim(target_reference)
  limit 1;

  if not found or not private.can_access_online_request(request_row.id) then
    raise exception 'The tracked request was not found for this verified account';
  end if;

  select doctor.display_name into doctor_name
  from public.doctors doctor where doctor.id = request_row.assigned_doctor_id;
  select department.department_name into department_name
  from public.hospital_departments department
  where department.id = request_row.requested_department_id;

  return jsonb_build_object(
    'request_id', request_row.id,
    'reference_number', request_row.reference_number,
    'status', request_row.request_status,
    'preferred_schedule', request_row.preferred_schedule,
    'proposed_schedule', request_row.proposed_schedule,
    'confirmed_schedule', request_row.confirmed_schedule,
    'registered_phone', request_row.phone_number_snapshot,
    'department', department_name,
    'doctor', doctor_name,
    'channel', request_row.consultation_channel,
    'consultation_id', request_row.official_consultation_id,
    'additional_information_request', request_row.additional_information_request,
    'contact_attempt_status', request_row.contact_attempt_status,
    'rejection_reason', request_row.rejection_reason,
    'cancellation_reason', request_row.cancellation_reason,
    'video_may_be_requested', request_row.request_status in ('confirmed', 'awaiting_contact', 'video_ready', 'in_progress')
      and request_row.consultation_channel = 'video'
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.get_patient_medical_records(target_patient_id uuid)
 RETURNS SETOF medical_records
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not private.actor_has_category_access(target_patient_id, 'medical_records') then
    raise exception 'Medical-record category access is not authorized';
  end if;
  insert into public.medical_record_access_logs(
    patient_id, actor_user_id, actor_role, resource_type, access_type,
    metadata, success
  ) values (
    target_patient_id, private.current_user_id(), private.current_role(),
    'medical_records', 'list', jsonb_build_object('category', 'medical_records'), true
  );
  return query
  select record.*
  from public.medical_records record
  where record.patient_id = target_patient_id
    and private.can_access_clinical_record(
      record.patient_id, record.hospital_id,
      'medical_records', record.id, 'view'
    )
  order by record.record_date desc, record.created_at desc;
end
$function$;

CREATE OR REPLACE FUNCTION private.guard_clinical_consultation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.status is distinct from old.status and new.status in ('in_progress','completed') then
    if new.doctor_id is distinct from private.current_doctor_id()
      or not private.has_active_doctor_employment(new.doctor_id,new.hospital_id) then
      raise exception 'Only the assigned active doctor may start or complete clinical care';
    end if;
    if new.consultation_type in ('online','guest_online') and
      (now()<new.appointment_date-interval '15 minutes' or now()>=new.appointment_date+interval '4 hours') then
      raise exception 'The consultation is outside its appointment window';
    end if;
    if new.status='completed' and (
      length(btrim(coalesce(new.consultation_summary,'')))<10
      or length(btrim(coalesce(new.confirmed_diagnosis,'')))<3
      or length(btrim(coalesce(new.treatment_plan,'')))<5
      or (nullif(btrim(new.current_symptoms),'') is null and new.vitals_recorded_at is null
        and nullif(btrim(new.relevant_medical_history),'') is null and nullif(btrim(new.doctor_notes),'') is null)
    ) then raise exception 'Complete the structured checkup, diagnosis, treatment plan and consultation summary'; end if;
  end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION private.guard_document_review()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if new.origin_type is distinct from old.origin_type or new.uploaded_by is distinct from old.uploaded_by then
  raise exception 'Document provenance and uploader are immutable'; end if;
 if new.review_state is distinct from old.review_state or new.reviewed_by is distinct from old.reviewed_by
  or new.reviewed_at is distinct from old.reviewed_at or new.review_rejection_reason is distinct from old.review_rejection_reason then
  if private.current_doctor_id() is null or new.reviewed_by is distinct from private.current_user_id()
    or new.reviewed_at is null or old.review_state<>'unreviewed'
    or not private.can_access_clinical_record(new.patient_id,new.hospital_id,'medical_documents',new.id,'view') then
   raise exception 'Only an authorized treating doctor may review the original document'; end if;
 end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION private.guard_online_request_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare c public.consultations; role text:=private.current_role();
begin
  if new.patient_id is distinct from old.patient_id or new.submitted_by is distinct from old.submitted_by
    or new.hospital_id is distinct from old.hospital_id or new.created_at is distinct from old.created_at then
    raise exception 'Online request identity and hospital are immutable'; end if;
  if old.official_consultation_id is not null and new.official_consultation_id is distinct from old.official_consultation_id then
    raise exception 'The official consultation reference is immutable'; end if;
  if new.request_status is not distinct from old.request_status then return new; end if;
  if old.request_status in ('completed','rejected','cancelled','no_show','patient_unreachable','face_to_face_recommended') then
    raise exception 'Terminal online requests cannot be reopened'; end if;
  if not (
    (old.request_status in ('submitted','under_review','more_information_required','schedule_proposed') and new.request_status in ('under_review','more_information_required','schedule_proposed','confirmed','rejected','cancelled','patient_unreachable'))
    or (old.request_status in ('confirmed','awaiting_contact','video_ready') and new.request_status in ('awaiting_contact','video_ready','in_progress','cancelled','no_show','patient_unreachable','face_to_face_recommended'))
    or (old.request_status='in_progress' and new.request_status in ('completed','cancelled','face_to_face_recommended'))
  ) then raise exception 'Invalid online request predecessor state'; end if;
  if old.request_status in ('submitted','under_review','more_information_required','schedule_proposed') and role<>'patient'
    and not private.is_hospital_admin_for(new.hospital_id) then raise exception 'Hospital review is required before clinical care'; end if;
  if new.request_status='face_to_face_recommended' and new.assigned_doctor_id is distinct from private.current_doctor_id() then
    raise exception 'Only the assigned doctor may recommend clinical follow-up'; end if;
  if role='patient' then
    if new.patient_id is distinct from private.current_patient_id() or new.submitted_by is distinct from private.current_user_id()
      or not ((new.request_status='cancelled' and old.request_status<>'in_progress')
        or (old.request_status in ('more_information_required','schedule_proposed') and new.request_status='under_review' and nullif(btrim(new.patient_response),'') is not null)
        or (old.request_status='schedule_proposed' and new.request_status='confirmed'
          and new.confirmed_schedule=old.proposed_schedule and new.assigned_doctor_id=old.assigned_doctor_id
          and new.consultation_channel=old.consultation_channel and new.reviewed_by=old.reviewed_by)) then
      raise exception 'The requested transition is not an authorized patient action'; end if;
  elsif not (private.is_hospital_admin_for(new.hospital_id) or new.assigned_doctor_id=private.current_doctor_id()) then
    raise exception 'The current care team cannot change this request'; end if;
  if new.request_status in ('confirmed','awaiting_contact','video_ready','in_progress','completed','no_show') then
    select * into c from public.consultations where id=new.official_consultation_id;
    if c.id is null or c.patient_id<>new.patient_id or c.hospital_id<>new.hospital_id or c.doctor_id<>new.assigned_doctor_id then
      raise exception 'This request requires its matching official consultation'; end if;
  end if;
  if new.request_status in ('no_show','patient_unreachable') and new.official_consultation_id is not null then
    select * into c from public.consultations where id=new.official_consultation_id;
    if now()<c.appointment_date+interval '30 minutes' or c.started_at is not null or c.status='in_progress'
      or old.contact_attempted_at is null or nullif(btrim(old.contact_attempt_notes),'') is null then
      raise exception 'A missed visit requires 30 elapsed minutes, a recorded contact attempt and no clinical start'; end if;
  end if;
  if new.request_status in ('in_progress','completed') then
    if c.status::text<>new.request_status or new.assigned_doctor_id is distinct from private.current_doctor_id() then
      raise exception 'Use the assigned doctor clinical start and structured completion workflow'; end if;
  end if;
  if new.request_status='video_ready' and not exists(select 1 from public.video_sessions where consultation_id=c.id and status in ('ready','active')) then
    raise exception 'A prepared authorized video room is required'; end if;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION private.guard_prescription_order_reference()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if tg_op='UPDATE' and new.order_id is distinct from old.order_id then raise exception 'Prescription order provenance is immutable'; end if;
 if new.order_id is not null and not exists(select 1 from public.prescription_orders o where o.id=new.order_id
   and o.patient_id=new.patient_id and o.doctor_id=new.doctor_id and o.hospital_id=new.hospital_id
   and o.status='issued' and o.issued_by=private.current_user_id()) then raise exception 'Prescription must match its authorized official order'; end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION private.guard_source_document_record()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if new.source_document_id is not null and not exists(select 1 from public.medical_documents d
   where d.id=new.source_document_id and d.patient_id=new.patient_id and d.review_state='approved'
     and d.reviewed_by=private.current_user_id() and new.doctor_id=private.current_doctor_id()) then
  raise exception 'Official supporting-document entries require an authorized doctor review'; end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION public.handle_new_auth_user()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  selected_role_id smallint;
  app_user_id uuid;
  is_patient_registration boolean :=
    coalesce(new.raw_user_meta_data->>'registration_source', '') =
      'patient_self_service';
begin
  if coalesce(new.is_anonymous, false) then
    return new;
  end if;

  select id into selected_role_id
  from public.roles
  where role_name = case
    when is_patient_registration then 'patient'
    else 'guest'
  end;

  if selected_role_id is null then
    raise exception 'Required application role is not configured';
  end if;

  insert into public.users(
    id,
    auth_user_id,
    role_id,
    first_name,
    last_name,
    email,
    mobile_number,
    birth_date,
    sex,
    address,
    account_status
  ) values (
    new.id,
    new.id,
    selected_role_id,
    coalesce(new.raw_user_meta_data->>'first_name', ''),
    coalesce(new.raw_user_meta_data->>'last_name', ''),
    new.email,
    coalesce(
      nullif(pg_catalog.btrim(coalesce(new.phone, '')), ''),
      nullif(
        pg_catalog.btrim(
          coalesce(new.raw_user_meta_data->>'mobile_number', '')
        ),
        ''
      )
    ),
    nullif(
      pg_catalog.btrim(coalesce(new.raw_user_meta_data->>'birth_date', '')),
      ''
    )::date,
    nullif(
      pg_catalog.btrim(coalesce(new.raw_user_meta_data->>'sex', '')),
      ''
    )::public.sex_type,
    nullif(
      pg_catalog.btrim(coalesce(new.raw_user_meta_data->>'address', '')),
      ''
    ),
    'active'
  )
  on conflict(auth_user_id) do update
  set role_id = case
        when is_patient_registration then excluded.role_id
        else public.users.role_id
      end,
      updated_at = now()
  returning id into app_user_id;

  if is_patient_registration then
    insert into public.patients(
      user_id,
      identity_verification_status,
      account_activation_status,
      profile_status,
      activated_at
    ) values (
      app_user_id,
      'pending',
      'active',
      'official',
      now()
    )
    on conflict(user_id) do update
    set account_activation_status = 'active',
        profile_status = 'official',
        activated_at = coalesce(public.patients.activated_at, now()),
        updated_at = now();
  end if;

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.has_active_doctor_employment(target_doctor_id uuid, target_hospital_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(exists (
    select 1
    from public.doctor_hospital_employments employment
    join public.doctors doctor on doctor.id = employment.doctor_id
    where employment.doctor_id = target_doctor_id
      and employment.hospital_id = target_hospital_id
      and employment.employment_status = 'active'
      and employment.is_verified
      and employment.starts_at <= now()
      and (employment.ends_at is null or employment.ends_at > now())
      and doctor.user_id = private.current_user_id()
  ), false)
$function$;

CREATE OR REPLACE FUNCTION private.has_online_reviewer(target_hospital uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select exists (select 1 from public.users u join public.roles r on r.id=u.role_id
    where u.hospital_id=target_hospital and u.account_status='active' and r.role_name='hospital_admin');
$function$;

CREATE OR REPLACE FUNCTION private.has_permission(target_permission text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(exists (
    select 1
    from public.users app_user
    join public.role_permissions permission on permission.role_id = app_user.role_id
    where app_user.auth_user_id = (select auth.uid())
      and app_user.account_status = 'active'
      and permission.permission = target_permission
      and permission.is_allowed
  ),false)
$function$;

CREATE OR REPLACE FUNCTION public.hospital_analytics()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
declare
  target_hospital uuid := private.current_hospital_id();
  result jsonb;
begin
  if private.current_role() = 'doctor' then
    select hospital_id into target_hospital
    from public.doctors where id = private.current_doctor_id();
  end if;
  if private.current_role() not in ('hospital_admin','doctor')
    or not private.has_permission('analytics.hospital.read')
    or target_hospital is null then
    raise exception 'Hospital-scoped analytics access is required';
  end if;

  select jsonb_build_object(
    'hospital_id',target_hospital,
    'consultations_total',(select count(*) from public.consultations c where c.hospital_id=target_hospital),
    'consultations_by_status',(select coalesce(jsonb_object_agg(status,total),'{}'::jsonb) from (
      select c.status::text status,count(*) total
      from public.consultations c where c.hospital_id=target_hospital group by c.status
    ) grouped),
    'consultations_by_doctor',(select coalesce(jsonb_agg(to_jsonb(grouped) order by grouped.consultations desc),'[]'::jsonb) from (
      select d.id doctor_id,d.display_name,count(c.id) consultations
      from public.doctors d
      left join public.consultations c on c.doctor_id=d.id and c.hospital_id=target_hospital
      where d.hospital_id=target_hospital
      group by d.id,d.display_name
    ) grouped),
    'doctor_activity',(select coalesce(jsonb_agg(to_jsonb(grouped) order by grouped.consultation_events desc),'[]'::jsonb) from (
      select d.id doctor_id,d.display_name,
        count(distinct c.id) consultations,
        count(distinct history.id) consultation_events,
        count(distinct audit.id) audit_events
      from public.doctors d
      join public.users app_user on app_user.id=d.user_id
      left join public.consultations c on c.doctor_id=d.id and c.hospital_id=target_hospital
      left join public.consultation_status_history history on history.consultation_id=c.id
      left join public.audit_logs audit on audit.user_id=app_user.id and audit.hospital_id=target_hospital
      where d.hospital_id=target_hospital
      group by d.id,d.display_name
    ) grouped),
    'active_doctors',(select count(*) from public.doctors d where d.hospital_id=target_hospital and d.availability_status<>'unavailable'),
    'patients',(select count(*) from public.patients p where p.primary_hospital_id=target_hospital),
    'available_beds',(select coalesce(sum(b.available_beds),0) from public.hospital_beds b where b.hospital_id=target_hospital),
    'available_rooms',(select coalesce(sum(r.available_rooms),0) from public.hospital_rooms r where r.hospital_id=target_hospital),
    'room_occupancy',(select jsonb_build_object(
      'total',coalesce(sum(r.total_rooms),0),
      'occupied',coalesce(sum(r.occupied_rooms),0),
      'available',coalesce(sum(r.available_rooms),0),
      'utilization_percent',case when coalesce(sum(r.total_rooms),0)=0 then 0
        else round(100.0*sum(r.occupied_rooms)/sum(r.total_rooms),2) end
    ) from public.hospital_rooms r where r.hospital_id=target_hospital),
    'er_utilization',(select coalesce(jsonb_agg(jsonb_build_object(
      'status',e.status,
      'patient_count',e.current_patient_count,
      'capacity',e.maximum_capacity,
      'available_beds',e.available_beds,
      'utilization_percent',case when e.maximum_capacity=0 then 0
        else round(100.0*e.current_patient_count/e.maximum_capacity,2) end
    )),'[]'::jsonb) from public.emergency_room_status e where e.hospital_id=target_hospital),
    'er',(select coalesce(jsonb_agg(to_jsonb(e)),'[]'::jsonb) from public.emergency_room_status e where e.hospital_id=target_hospital),
    'generated_at',now()
  ) into result;
  return result;
end;
$function$;

CREATE OR REPLACE FUNCTION public.invalidate_video_session_after_consultation_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.appointment_date is distinct from old.appointment_date then
    update public.video_sessions
    set status = 'cancelled',
        ended_at = coalesce(ended_at, now()),
        expires_at = least(coalesce(expires_at, now()), now())
    where consultation_id = new.id
      and status not in ('ended','cancelled','failed');
  elsif new.status is distinct from old.status
    and new.status in ('rejected','cancelled','completed') then
    update public.video_sessions
    set status = case when new.status = 'completed' then 'ended' else 'cancelled' end,
        ended_at = coalesce(ended_at, now()),
        expires_at = least(coalesce(expires_at, now()), now())
    where consultation_id = new.id
      and status not in ('ended','cancelled','failed');
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.is_active_care_relationship(target_relationship_id uuid, target_patient_id uuid, target_hospital_id uuid, target_doctor_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(exists (
    select 1
    from public.patient_care_relationships relationship
    where relationship.id = target_relationship_id
      and relationship.patient_id = target_patient_id
      and relationship.hospital_id = target_hospital_id
      and relationship.doctor_id = target_doctor_id
      and relationship.status = 'active'
      and coalesce(relationship.starts_at, relationship.approved_at, relationship.requested_at) <= now()
      and (relationship.expires_at is null or relationship.expires_at > now())
      and (relationship.ended_at is null or relationship.ended_at > now())
      and (
        relationship.consultation_id is null
        or exists (
          select 1
          from public.consultations consultation
          where consultation.id = relationship.consultation_id
            and consultation.patient_id = relationship.patient_id
            and consultation.hospital_id = relationship.hospital_id
            and consultation.doctor_id = relationship.doctor_id
            and consultation.status in ('approved', 'scheduled', 'in_progress')
        )
      )
      and exists (
        select 1
        from public.doctor_patient_assignments assignment
        where assignment.patient_id = relationship.patient_id
          and assignment.doctor_id = relationship.doctor_id
          and assignment.care_relationship_id = relationship.id
          and assignment.assignment_status = 'active'
          and assignment.ended_at is null
      )
  ), false)
$function$;

CREATE OR REPLACE FUNCTION private.is_consultation_participant(target_consultation_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(exists (
    select 1 from public.consultations consultation
    where consultation.id = target_consultation_id and (
      consultation.patient_id = private.current_patient_id()
      or consultation.doctor_id = private.current_doctor_id()
      or (consultation.guest_request_id is not null and private.can_access_guest_request(consultation.guest_request_id))
      or private.is_hospital_admin_for(consultation.hospital_id)
    )
  ), false)
$function$;

CREATE OR REPLACE FUNCTION private.is_doctor_slot_available(target_doctor_id uuid, target_hospital_id uuid, target_type consultation_type, target_start timestamp with time zone, excluded_consultation_id uuid DEFAULT NULL::uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    private.meets_reservation_lead_time(target_start)
    and (target_type not in ('online','guest_online') or private.has_online_reviewer(target_hospital_id))
    and exists (
      select 1
      from public.doctors doctor
      join public.hospitals hospital on hospital.id = doctor.hospital_id
      where doctor.id = target_doctor_id
        and doctor.hospital_id = target_hospital_id
        and doctor.availability_status <> 'unavailable'
        and hospital.verification_status = 'verified'
        and hospital.operating_status in ('open', 'limited')
    )
    and exists (
      select 1
      from public.doctor_schedules schedule
      where schedule.doctor_id = target_doctor_id
        and schedule.is_active
        and (
          schedule.consultation_type = target_type
          or (
            target_type = 'guest_online'
            and schedule.consultation_type = 'online'
          )
        )
        and schedule.day_of_week = extract(
          dow from target_start at time zone 'Asia/Manila'
        )::integer
        and (target_start at time zone 'Asia/Manila')::time >= schedule.starts_at
        and (target_start at time zone 'Asia/Manila')::time
          + make_interval(mins => schedule.slot_minutes) <= schedule.ends_at
        and not exists (
          select 1
          from public.consultations consultation
          where consultation.doctor_id = target_doctor_id
            and consultation.id is distinct from excluded_consultation_id
            and consultation.status not in ('rejected', 'cancelled')
            and consultation.appointment_date
              < target_start + make_interval(mins => schedule.slot_minutes)
            and consultation.appointment_date
              > target_start - make_interval(mins => schedule.slot_minutes)
        )
    ),
    false
  )
$function$;

CREATE OR REPLACE FUNCTION private.is_hospital_admin_for(target_hospital_id uuid)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    private.is_super_admin()
    or (
      private.current_role() = 'hospital_admin'
      and private.current_hospital_id() = target_hospital_id
    ),
    false
  )
$function$;

CREATE OR REPLACE FUNCTION private.is_storage_upload_owner(object_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    (select auth.uid()) is not null
    and private.current_user_id() is not null
    and (storage.foldername(object_name))[2] = (select auth.uid())::text,
    false
  )
$function$;

CREATE OR REPLACE FUNCTION private.is_super_admin()
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(private.current_role() = 'super_admin', false)
$function$;

CREATE OR REPLACE FUNCTION public.issue_prescription_order(order_payload jsonb, idempotency_key text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
#variable_conflict use_variable
declare doctor public.doctors; patient_id uuid:=(order_payload->>'patient_id')::uuid;
  consultation_id uuid:=nullif(order_payload->>'consultation_id','')::uuid;
  assignment_id uuid:=nullif(order_payload->>'assignment_id','')::uuid;
  order_row public.prescription_orders; medication jsonb; medication_ids jsonb; notification_status text;
begin
  select * into doctor from public.doctors where id=private.current_doctor_id();
  if doctor.id is null or auth.uid() is null or not private.has_active_doctor_employment(doctor.id,doctor.hospital_id)
    or not (private.can_access_clinical_record(patient_id,doctor.hospital_id,'prescriptions',null,'create')
      or private.can_create_assigned_patient_document(patient_id,doctor.hospital_id)) then
    raise exception 'An authorized active prescriber is required'; end if;
  if not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null and not coalesce(is_anonymous,false)) then
    raise exception 'A verified prescriber account is required'; end if;
  if consultation_id is not null and not exists (select 1 from public.consultations c
    where c.id=consultation_id and c.patient_id=patient_id and c.doctor_id=doctor.id
      and c.hospital_id=doctor.hospital_id and c.status in ('approved','scheduled','in_progress','completed')) then
    raise exception 'The selected consultation is not assigned to this prescriber'; end if;
  if assignment_id is not null and not exists(select 1 from public.doctor_patient_assignments a
    where a.id=assignment_id and a.patient_id=patient_id and a.doctor_id=doctor.id and a.hospital_id=doctor.hospital_id
      and a.assignment_status='active' and a.ended_at is null) then raise exception 'The care assignment is not active'; end if;
  if consultation_id is null and assignment_id is null then raise exception 'A consultation or active care assignment is required'; end if;
  if length(coalesce(idempotency_key,''))<16 or length(idempotency_key)>160 then raise exception 'An issuance idempotency key is required'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(doctor.id::text||':'||idempotency_key,0));
  select * into order_row from public.prescription_orders o where o.doctor_id=doctor.id and o.idempotency_key=$2;
  if found then
    if order_row.payload_fingerprint is distinct from md5(order_payload::text) then raise exception 'This issuance key belongs to a different order'; end if;
  else
    if jsonb_typeof(order_payload->'medications') is distinct from 'array'
      or jsonb_array_length(order_payload->'medications') not between 1 and 50 then raise exception 'Supply the complete medication list'; end if;
    insert into public.prescription_orders(patient_id,doctor_id,hospital_id,consultation_id,assignment_id,issued_by,diagnosis_reason,idempotency_key,payload_fingerprint)
    values(patient_id,doctor.id,doctor.hospital_id,consultation_id,assignment_id,private.current_user_id(),
      btrim(order_payload->>'diagnosis_reason'),$2,md5(order_payload::text)) returning * into order_row;
    for medication in select value from jsonb_array_elements(order_payload->'medications') loop
      if exists(select 1 from unnest(array['medication_name','dosage','frequency','duration','medication_form_strength','route','exact_dose','quantity_to_dispense']) key
        where nullif(btrim(medication->>key),'') is null) then raise exception 'Every medication requires complete dispensing directions'; end if;
      insert into public.prescriptions(order_id,patient_id,doctor_id,hospital_id,consultation_id,assignment_id,
        diagnosis_reason,medication_name,dosage,frequency,duration,medication_form_strength,route,exact_dose,quantity_to_dispense,
        refills,start_date,end_date,is_prn,prn_reason,maximum_daily_dose,instructions)
      values(order_row.id,patient_id,doctor.id,doctor.hospital_id,consultation_id,assignment_id,order_row.diagnosis_reason,
        btrim(medication->>'medication_name'),btrim(medication->>'dosage'),btrim(medication->>'frequency'),btrim(medication->>'duration'),
        btrim(medication->>'medication_form_strength'),btrim(medication->>'route'),btrim(medication->>'exact_dose'),btrim(medication->>'quantity_to_dispense'),
        (medication->>'refills')::integer,(medication->>'start_date')::date,nullif(medication->>'end_date','')::date,
        coalesce((medication->>'is_prn')::boolean,false),nullif(btrim(medication->>'prn_reason'),''),
        nullif(btrim(medication->>'maximum_daily_dose'),''),nullif(btrim(medication->>'instructions'),''));
    end loop;
  end if;
  select jsonb_agg(id order by created_at,id) into medication_ids from public.prescriptions where order_id=order_row.id;
  notification_status:=private.queue_prescription_order_notification(order_row.id);
  return jsonb_build_object('order_id',order_row.id,'medication_ids',medication_ids,'notification_status',notification_status);
end $function$;

CREATE OR REPLACE FUNCTION public.link_existing_patient(target_patient_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  doctor_row public.doctors;
  current_app_user_id uuid;
  request_id uuid;
  patient_auth_user_id uuid;
  employment_is_active boolean := true;
begin
  current_app_user_id := private.current_user_id();
  if (select auth.uid()) is null
    or current_app_user_id is null
    or private.current_doctor_id() is null
    or not private.has_permission('patients.manage') then
    raise exception 'An authorized doctor session is required';
  end if;

  select * into doctor_row
  from public.doctors doctor
  where doctor.id = private.current_doctor_id();

  if not found or doctor_row.hospital_id is null then
    raise exception 'An active hospital doctor profile is required';
  end if;

  if pg_catalog.to_regclass('public.doctor_hospital_employments') is not null then
    execute $sql$
      select exists (
        select 1
        from public.doctor_hospital_employments employment
        where employment.doctor_id = $1
          and employment.hospital_id = $2
          and employment.employment_status = 'active'
          and employment.is_verified
          and employment.starts_at <= now()
          and (employment.ends_at is null or employment.ends_at > now())
      )
    $sql$
    into employment_is_active
    using doctor_row.id, doctor_row.hospital_id;
  end if;

  if not employment_is_active then
    raise exception 'The doctor is not actively verified at this hospital';
  end if;

  select app_user.auth_user_id into patient_auth_user_id
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where patient.id = target_patient_id
    and app_user.account_status = 'active'
    and patient.account_activation_status = 'active'
    and patient.profile_status = 'official';

  if not found then
    raise exception 'The selected active patient account was not found';
  end if;

  select request.id into request_id
  from public.patient_connection_requests request
  where request.doctor_id = doctor_row.id
    and request.patient_id = target_patient_id
    and request.status = 'requested'
    and request.expires_at > now()
  order by request.requested_at desc
  limit 1;

  if request_id is null then
    insert into public.patient_connection_requests(
      patient_id,
      hospital_id,
      doctor_id,
      requested_by
    ) values (
      target_patient_id,
      doctor_row.hospital_id,
      doctor_row.id,
      current_app_user_id
    )
    returning id into request_id;

    insert into public.notifications(
      user_id,
      title,
      message,
      notification_type,
      reference_id,
      data
    ) values (
      patient_auth_user_id,
      'Clinician connection request',
      'A verified clinician requested to connect with your patient account.',
      'access_request',
      request_id,
      pg_catalog.jsonb_build_object(
        'connection_request_id', request_id,
        'doctor_id', doctor_row.id,
        'hospital_id', doctor_row.hospital_id,
        'status', 'requested'
      )
    );
  end if;

  return request_id;
end
$function$;

CREATE OR REPLACE FUNCTION public.link_guest_patient_account(target_request_id uuid, target_user_id uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare patient_id uuid; request_row public.guest_consultation_requests;
begin
  select * into request_row from public.guest_consultation_requests where id=target_request_id for update;
  if not found or request_row.assigned_doctor_id<>private.current_doctor_id() then raise exception 'Only the assigned doctor may complete conversion'; end if;
  if not exists(select 1 from public.users app_user join public.roles role on role.id=app_user.role_id
    where app_user.id=target_user_id and role.role_name='patient' and app_user.account_status in ('pending','active')) then
    raise exception 'A patient user profile prepared by the account service is required';
  end if;
  update public.patients set user_id=target_user_id,profile_status='official',account_activation_status='active',activated_at=now(),
    converted_from_guest=true,converted_at=coalesce(converted_at,now())
  where guest_request_id=target_request_id returning id into patient_id;
  if patient_id is null then raise exception 'Temporary patient profile was not found'; end if;
  return patient_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.link_guest_patient_to_consultation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.patient_id is null and new.guest_request_id is not null then
    select patient.id into new.patient_id
    from public.patients as patient
    where patient.guest_request_id = new.guest_request_id
    order by patient.created_at desc
    limit 1;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.list_available_consultation_slots(target_doctor_id uuid, target_type consultation_type, horizon_days integer DEFAULT 30)
 RETURNS TABLE(starts_at timestamp with time zone, ends_at timestamp with time zone)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  with requested_window as (
    select
      (now() at time zone 'Asia/Manila')::date as first_date,
      least(greatest(coalesce(horizon_days, 30), 1), 60) as day_count
  ),
  calendar_dates as (
    select generated_date.value::date as local_date
    from requested_window bounds,
    lateral generate_series(
      bounds.first_date::timestamp,
      (bounds.first_date + bounds.day_count - 1)::timestamp,
      interval '1 day'
    ) as generated_date(value)
  ),
  published_slots as (
    select
      generated_local_start.value at time zone 'Asia/Manila' as slot_start,
      schedule.slot_minutes
    from public.doctor_schedules schedule
    join calendar_dates calendar
      on schedule.day_of_week = extract(dow from calendar.local_date)::integer,
    lateral generate_series(
      calendar.local_date + schedule.starts_at,
      calendar.local_date + schedule.ends_at
        - make_interval(mins => schedule.slot_minutes),
      make_interval(mins => schedule.slot_minutes)
    ) as generated_local_start(value)
    where schedule.doctor_id = target_doctor_id
      and schedule.is_active
      and (
        schedule.consultation_type = target_type
        or (
          target_type = 'guest_online'::public.consultation_type
          and schedule.consultation_type = 'online'::public.consultation_type
        )
      )
  )
  select
    slot.slot_start as starts_at,
    slot.slot_start + make_interval(mins => slot.slot_minutes) as ends_at
  from published_slots slot
  join public.doctors doctor on doctor.id = target_doctor_id
  where private.is_doctor_slot_available(
    target_doctor_id, doctor.hospital_id,
    target_type, slot.slot_start, null
  )
  order by slot.slot_start
  limit 240
$function$;

CREATE OR REPLACE FUNCTION public.list_online_booking_hospitals()
 RETURNS TABLE(hospital_id uuid)
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select h.id from public.hospitals h where h.verification_status='verified' and h.operating_status in ('open','limited') and private.has_online_reviewer(h.id);
$function$;

CREATE OR REPLACE FUNCTION public.list_patient_sharing_relationships()
 RETURNS jsonb
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce(jsonb_agg(row_to_json(r)),'[]'::jsonb) from (
  select relationship.id,relationship.status,h.hospital_name,d.display_name,
    (select jsonb_agg(jsonb_build_object('grant_id',g.id,'status',g.status,'expires_at',g.expires_at,
      'categories',(select jsonb_agg(s.record_category) from public.patient_access_scopes s where s.grant_id=g.id)))
     from public.patient_access_grants g where g.care_relationship_id=relationship.id and g.status='active' and g.revoked_at is null) as grants
  from public.patient_care_relationships relationship join public.hospitals h on h.id=relationship.hospital_id
    left join public.doctors d on d.id=relationship.doctor_id
  where relationship.patient_id=private.current_patient_id() and relationship.status='active'
  order by relationship.created_at desc
 ) r;
$function$;

CREATE OR REPLACE FUNCTION private.lock_consultation_reservation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 perform private.lock_doctor_schedule(new.doctor_id);
 if tg_op='UPDATE' then
   if new.appointment_date is not distinct from old.appointment_date then return new; end if;
 end if;
 if new.consultation_type<>'emergency' and not private.is_doctor_slot_available(
   new.doctor_id,new.hospital_id,new.consultation_type,new.appointment_date,new.id)
 then raise exception 'The selected appointment slot is unavailable'; end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION private.lock_doctor_schedule(target_doctor uuid)
 RETURNS void
 LANGUAGE sql
 SET search_path TO ''
AS $function$
  select pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended('doctor-schedule:' || target_doctor::text, 0));
$function$;

CREATE OR REPLACE FUNCTION public.log_audit_event()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  row_data jsonb := case when tg_op = 'DELETE' then to_jsonb(old) else to_jsonb(new) end;
  target_hospital_id uuid;
begin
  target_hospital_id := coalesce(
    nullif(row_data ->> 'hospital_id', '')::uuid,
    nullif(row_data ->> 'preferred_hospital_id', '')::uuid,
    nullif(row_data ->> 'primary_hospital_id', '')::uuid
  );

  insert into public.audit_logs (user_id, hospital_id, action, module, record_id)
  values (
    private.current_user_id(),
    target_hospital_id,
    lower(tg_op),
    tg_table_name,
    nullif(row_data ->> 'id', '')::uuid
  );

  if tg_op = 'DELETE' then
    return old;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.log_user_security_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.account_status is distinct from old.account_status then
    insert into public.security_logs(actor_auth_user_id,event_type,severity,success,metadata)
    values(
      (select auth.uid()),'account_status_changed',
      case when new.account_status='active' then 'info' else 'warning' end,
      true,
      jsonb_build_object(
        'target_user_id',new.id,
        'old_status',old.account_status,
        'new_status',new.account_status
      )
    );
  end if;
  if new.role_id is distinct from old.role_id then
    insert into public.security_logs(actor_auth_user_id,event_type,severity,success,metadata)
    values(
      (select auth.uid()),'account_role_changed','warning',true,
      jsonb_build_object(
        'target_user_id',new.id,
        'old_role_id',old.role_id,
        'new_role_id',new.role_id
      )
    );
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.mark_conversation_read(target_conversation_id uuid)
 RETURNS integer
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  changed integer;
begin
  if not private.can_participate_conversation(target_conversation_id) then
    raise exception 'Conversation is not accessible';
  end if;

  update public.chat_messages
  set delivered_at = coalesce(delivered_at, now()),
      read_at = coalesce(read_at, now())
  where conversation_id = target_conversation_id
    and sender_id <> (select auth.uid())
    and read_at is null;
  get diagnostics changed = row_count;
  return changed;
end
$function$;

CREATE OR REPLACE FUNCTION private.mark_guest_request_approved_for_consultation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.guest_request_id is not null
    and new.status in ('approved', 'scheduled') then
    update public.guest_consultation_requests request
    set request_status = 'approved',
        assigned_doctor_id = new.doctor_id,
        reviewed_by = coalesce(request.reviewed_by, private.current_user_id()),
        reviewed_at = coalesce(request.reviewed_at, now()),
        identity_review_status = 'verified',
        updated_at = now()
    where request.id = new.guest_request_id
      and request.request_status in ('otp_verified', 'pending_doctor_review');
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.mark_notification_read(target_notification_id uuid)
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  update public.notifications set is_read=true,read_at=coalesce(read_at,now())
  where id=target_notification_id and user_id=(select auth.uid());
  if not found then raise exception 'Notification was not found'; end if;
end;
$function$;

CREATE OR REPLACE FUNCTION private.medication_summary(target_patient uuid, target_date date, target_order uuid DEFAULT NULL::uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select string_agg(concat(p.medication_name,' â€” ',p.exact_dose,'; ',p.route,'; ',
   case when p.is_prn then 'PRN: '||p.prn_reason||'; maximum daily dose: '||p.maximum_daily_dose else p.frequency end,
   '; duration: ',p.duration,case when p.instructions is not null then '; '||p.instructions else '' end),E'\n' order by p.created_at,p.id)
 from public.prescriptions p join public.prescription_orders o on o.id=p.order_id
 where p.patient_id=target_patient and o.status='issued' and p.electronically_signed_by is not null
   and ((target_order is not null and o.id=target_order) or
     (target_order is null and p.start_date<=target_date and (p.end_date is null or p.end_date>=target_date)));
$function$;

CREATE OR REPLACE FUNCTION private.meets_reservation_lead_time(target_start timestamp with time zone)
 RETURNS boolean
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select target_start is not null
    and target_start >= now() + interval '24 hours'
$function$;

CREATE OR REPLACE FUNCTION public.nearby_hospitals(user_latitude double precision, user_longitude double precision, radius_km double precision DEFAULT 100)
 RETURNS TABLE(id uuid, hospital_name text, classification_name text, address text, latitude numeric, longitude numeric, contact_number text, emergency_contact_number text, operating_status hospital_operating_status, distance_km double precision)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  select
    h.id,
    h.hospital_name,
    hc.classification_name,
    h.address,
    h.latitude,
    h.longitude,
    h.contact_number,
    h.emergency_contact_number,
    h.operating_status,
    6371 * acos(least(1, greatest(-1,
      cos(radians(user_latitude))
      * cos(radians(h.latitude::double precision))
      * cos(radians(h.longitude::double precision) - radians(user_longitude))
      + sin(radians(user_latitude))
      * sin(radians(h.latitude::double precision))
    ))) as distance_km
  from public.hospitals h
  left join public.hospital_classifications hc on hc.id = h.classification_id
  where h.verification_status = 'verified'
    and h.operating_status in ('open', 'limited')
    and h.latitude is not null
    and h.longitude is not null
    and 6371 * acos(least(1, greatest(-1,
      cos(radians(user_latitude))
      * cos(radians(h.latitude::double precision))
      * cos(radians(h.longitude::double precision) - radians(user_longitude))
      + sin(radians(user_latitude))
      * sin(radians(h.latitude::double precision))
    ))) <= radius_km
  order by distance_km;
$function$;

CREATE OR REPLACE FUNCTION private.notification_action_path(target_type text, target_data jsonb)
 RETURNS text
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
 select case when target_type='hospital_alert' then '/hospitals' else '/notification' end;
$function$;

CREATE OR REPLACE FUNCTION private.notification_delivery_status(notification_id uuid)
 RETURNS text
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
 select coalesce((select case o.status when 'delivered' then 'sent' when 'failed' then 'failed'
   when 'cancelled' then 'disabled' else 'queued' end from public.notification_outbox o where o.notification_id=$1 and o.channel='email'),'disabled');
$function$;

CREATE OR REPLACE FUNCTION public.notification_email_allowed(target_notification uuid)
 RETURNS boolean
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare n public.notifications; pref public.notification_preferences; allowed boolean;
begin
 select * into n from public.notifications where id=target_notification;
 if n.id is null then return false; end if;
 if coalesce((n.data->>'authorized_manual_email')::boolean,false) then return true; end if;
 select * into pref from public.notification_preferences where user_id=n.user_id;
 if not coalesce(pref.email_enabled,false) then return false; end if;
 allowed:=case n.notification_type when 'medication_reminder' then coalesce(pref.medication_reminders,false)
  when 'prescription' then coalesce(pref.prescriptions,true) when 'appointment_reminder' then coalesce(pref.appointment_reminders,true)
  when 'medical_result' then coalesce(pref.medical_results,true) when 'consultation_update' then coalesce(pref.consultation_updates,true)
  when 'account_activation' then coalesce(pref.consultation_updates,true) when 'message' then coalesce(pref.messages,true)
  when 'hospital_alert' then coalesce(pref.hospital_alerts,true) else true end;
 if not allowed then return false; end if;
 if n.notification_type='medication_reminder' and n.data ? 'summary_date' then
  return (n.data->>'summary_date')::date=(now() at time zone 'Asia/Manila')::date;
 end if;
 return true;
end $function$;

CREATE OR REPLACE FUNCTION public.notify_chat_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare conversation_row public.chat_conversations; recipient uuid;
begin
  select * into conversation_row from public.chat_conversations where id=new.conversation_id;
  if new.sender_id=(select app_user.auth_user_id from public.doctors d join public.users app_user on app_user.id=d.user_id where d.id=conversation_row.doctor_id) then
    if conversation_row.patient_id is not null then
      select app_user.auth_user_id into recipient from public.patients patient join public.users app_user on app_user.id=patient.user_id where patient.id=conversation_row.patient_id;
    else select submitted_by into recipient from public.guest_consultation_requests where id=conversation_row.guest_request_id; end if;
  else
    select app_user.auth_user_id into recipient from public.doctors d join public.users app_user on app_user.id=d.user_id where d.id=conversation_row.doctor_id;
  end if;
  perform private.enqueue_notification(recipient,'New message','You received a consultation message','message',new.id,
    jsonb_build_object('conversation_id',new.conversation_id));
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.notify_consultation_status_change()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  patient_recipient uuid;
  doctor_recipient uuid;
  event_key text;
  safe_data jsonb;
begin
  if tg_op = 'UPDATE' then
    if new.status is not distinct from old.status
      and new.appointment_date is not distinct from old.appointment_date then
      return new;
    end if;
  end if;

  if new.patient_id is not null then
    select app_user.auth_user_id into patient_recipient
    from public.patients patient
    join public.users app_user on app_user.id = patient.user_id
    where patient.id = new.patient_id;
  elsif new.guest_request_id is not null then
    select submitted_by into patient_recipient
    from public.guest_consultation_requests
    where id = new.guest_request_id;
  end if;

  select app_user.auth_user_id into doctor_recipient
  from public.doctors doctor
  join public.users app_user on app_user.id = doctor.user_id
  where doctor.id = new.doctor_id;

  event_key := new.status::text || ':' || new.appointment_date::text;
  safe_data := jsonb_build_object(
    'status',new.status,
    'appointment_date',new.appointment_date,
    'hospital_id',new.hospital_id,
    'event_key',event_key
  );

  perform private.enqueue_notification(
    patient_recipient,
    'Consultation update',
    'Your consultation is now ' || replace(new.status::text,'_',' '),
    'consultation_update',new.id,safe_data
  );
  perform private.enqueue_notification(
    doctor_recipient,
    'Consultation assignment update',
    'An assigned consultation is now ' || replace(new.status::text,'_',' '),
    'consultation_update',new.id,safe_data
  );
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.notify_hospital_announcement()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.published_at > now() or (new.expires_at is not null and new.expires_at <= now()) then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if new.title is not distinct from old.title
      and new.message is not distinct from old.message
      and new.published_at is not distinct from old.published_at
      and new.expires_at is not distinct from old.expires_at then
      return new;
    end if;
  end if;
  perform private.enqueue_hospital_audience(
    new.hospital_id,
    new.title,
    new.message,
    'hospital_alert',
    new.id,
    jsonb_build_object(
      'hospital_id',new.hospital_id,
      'is_global',new.is_global,
      'event_key','announcement:' || new.published_at::text
    )
  );
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.notify_hospital_status_alert()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  new_data jsonb := to_jsonb(new);
  old_data jsonb := to_jsonb(old);
  target_hospital uuid;
  new_status text;
  old_status text;
  reference uuid;
begin
  target_hospital := case when tg_table_name = 'hospitals'
    then new.id else (new_data->>'hospital_id')::uuid end;
  reference := new.id;
  new_status := coalesce(new_data->>'operating_status',new_data->>'status');
  old_status := coalesce(old_data->>'operating_status',old_data->>'status');
  if new_status is not distinct from old_status then return new; end if;

  perform private.enqueue_hospital_audience(
    target_hospital,
    'Hospital status update',
    'A hospital availability status changed to ' || replace(new_status,'_',' ') || '.',
    'hospital_alert',
    reference,
    jsonb_build_object(
      'hospital_id',target_hospital,
      'source',tg_table_name,
      'status',new_status,
      'event_key',tg_table_name || ':' || clock_timestamp()::text
    )
  );
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.notify_laboratory_result_ready()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare recipient uuid;
begin
  if tg_op = 'UPDATE' then
    if new.verification_status is not distinct from old.verification_status then
      return new;
    end if;
  end if;
  if new.verification_status not in ('doctor_confirmed','doctor_modified','saved_to_patient_record') then
    return new;
  end if;

  update public.document_processing_jobs
  set status = 'completed',
      completed_at = coalesce(completed_at,now()),
      last_error = null,
      updated_at = now()
  where laboratory_result_id = new.id
    and status in ('queued','ocr_processing','ai_analysis_pending','pending_doctor_review');

  select app_user.auth_user_id into recipient
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where patient.id = new.patient_id;
  perform private.enqueue_notification(
    recipient,'Medical result reviewed',
    'A doctor-reviewed laboratory result is ready in your care record.',
    'medical_result',new.id,
    jsonb_build_object(
      'status',new.verification_status,
      'event_key','doctor_reviewed',
      'dedupe_key','medical_result:' || new.id::text || ':doctor_reviewed'
    )
  );
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.notify_patient_account_activation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare recipient uuid;
begin
  if new.user_id is null
    or new.account_activation_status <> 'active'
    or new.profile_status <> 'official' then
    return new;
  end if;
  if tg_op = 'UPDATE' then
    if old.user_id is not distinct from new.user_id
      and old.account_activation_status is not distinct from new.account_activation_status
      and old.profile_status is not distinct from new.profile_status then
      return new;
    end if;
  end if;
  select auth_user_id into recipient from public.users where id = new.user_id;
  perform private.enqueue_notification(
    recipient,'Patient account activated',
    'Your CareNavigator patient account is active and ready to use.',
    'account_activation',new.id,
    jsonb_build_object('status','active','event_key','active')
  );
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.notify_prescription_created()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  recipient uuid;
begin
  if new.order_id is not null then return new; end if;
  select app_user.auth_user_id into recipient
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where patient.id = new.patient_id;
  perform private.enqueue_notification(
    recipient,
    'New prescription',
    'A doctor added a prescription to your care record.',
    'prescription',
    new.id,
    jsonb_build_object(
      'consultation_id', new.consultation_id,
      'assignment_id', new.assignment_id,
      'event_key', 'created'
    )
  );
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.platform_analytics()
 RETURNS jsonb
 LANGUAGE plpgsql
 STABLE
 SET search_path TO ''
AS $function$
begin
  if not private.is_super_admin() or not private.has_permission('analytics.platform.read') then
    raise exception 'Platform analytics permission is required';
  end if;
  return jsonb_build_object(
    'hospitals',(select count(*) from public.hospitals),
    'verified_hospitals',(select count(*) from public.hospitals where verification_status='verified'),
    'users',(select count(*) from public.users),
    'doctors',(select count(*) from public.doctors),
    'patients',(select count(*) from public.patients),
    'consultations',(select count(*) from public.consultations),
    'ai_assessments',(select count(*) from public.ai_assessments),
    'messages',(select count(*) from public.chat_messages),
    'generated_at',now()
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.protect_chat_message()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.conversation_id is distinct from old.conversation_id or new.sender_id is distinct from old.sender_id
    or new.message is distinct from old.message or new.attachment_path is distinct from old.attachment_path
    or new.sent_at is distinct from old.sent_at or new.message_type is distinct from old.message_type then
    raise exception 'Sent message content and ownership are immutable';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.protect_hospital_approval_fields()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare actor_role text := private.current_role();
begin
  -- Database/service-role maintenance and super-admin approval workflows keep
  -- full control. Hospital administrators retain their normal scoped profile
  -- update policy but cannot self-approve or transfer the hospital record.
  if (select auth.uid()) is null or actor_role='super_admin' then return new; end if;
  if actor_role<>'hospital_admin' or old.id is distinct from private.current_hospital_id() then
    raise exception 'Hospital update is not authorized';
  end if;
  if new.id is distinct from old.id
    or new.verification_status is distinct from old.verification_status
    or new.created_by is distinct from old.created_by
    or new.created_at is distinct from old.created_at then
    raise exception 'Hospital administrators cannot change approval or ownership fields';
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.protect_laboratory_confirmation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.verification_status in ('doctor_confirmed','doctor_modified','saved_to_patient_record') and (
    new.confirmed_by is null or new.confirmed_by<>new.doctor_id or new.doctor_confirmed_findings is null or new.confirmed_at is null
  ) then raise exception 'Doctor confirmation is required before this result becomes official'; end if;
  if (select auth.uid()) is not null and new.verification_status in ('doctor_confirmed','doctor_modified','saved_to_patient_record')
    and new.confirmed_by<>private.current_doctor_id() then raise exception 'Only the responsible doctor may confirm this result'; end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.protect_reserved_schedule()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare doctor_id uuid; reservation record;
begin
  if tg_op='INSERT' then doctor_id:=new.doctor_id; else doctor_id:=old.doctor_id; end if;
  perform private.lock_doctor_schedule(doctor_id);
  if tg_op='UPDATE' and new.doctor_id is distinct from old.doctor_id then
    raise exception 'Schedule ownership is immutable';
  end if;
  if tg_op<>'INSERT' then
    for reservation in select c.appointment_date from public.consultations c
      where c.doctor_id=old.doctor_id and c.status not in ('cancelled','rejected','completed')
        and c.appointment_date+interval '4 hours'>now()
        and c.consultation_type in (old.consultation_type,
          case when old.consultation_type='online' then 'guest_online'::public.consultation_type else old.consultation_type end)
        and extract(dow from c.appointment_date at time zone 'Asia/Manila')::integer=old.day_of_week
        and (c.appointment_date at time zone 'Asia/Manila')::time>=old.starts_at
        and (c.appointment_date at time zone 'Asia/Manila')::time<old.ends_at
    loop
      if tg_op='DELETE' then raise exception 'This schedule has reserved appointments'; end if;
      if not new.is_active or new.consultation_type<>old.consultation_type or new.day_of_week<>old.day_of_week
        or new.slot_minutes<>old.slot_minutes
        or (reservation.appointment_date at time zone 'Asia/Manila')::time<new.starts_at
        or (reservation.appointment_date at time zone 'Asia/Manila')::time+make_interval(mins=>new.slot_minutes)>new.ends_at then
        raise exception 'The change would invalidate a reserved appointment';
      end if;
    end loop;
  end if;
  if tg_op<>'DELETE' then
    if new.is_active and new.consultation_type in ('online','guest_online') and not exists (
      select 1 from public.doctors d where d.id=new.doctor_id and private.has_online_reviewer(d.hospital_id)
    ) then raise exception 'An active hospital reviewer is required to publish online booking'; end if;
    return new;
  end if;
  return old;
end $function$;

CREATE OR REPLACE FUNCTION public.protect_user_privileges()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  actor_role text := private.current_role();
begin
  if (select auth.uid()) is null or actor_role = 'super_admin' then
    return new;
  end if;

  if actor_role = 'hospital_admin' and old.hospital_id = private.current_hospital_id() then
    if new.auth_user_id is distinct from old.auth_user_id
       or new.role_id is distinct from old.role_id
       or new.hospital_id is distinct from old.hospital_id then
      raise exception 'Hospital administrators cannot change identity, role, or hospital assignment directly';
    end if;
    return new;
  end if;

  if old.auth_user_id = (select auth.uid()) then
    if actor_role='guest' and new.role_id=(select id from public.roles where role_name='patient')
      and new.account_status=old.account_status and new.hospital_id is not distinct from old.hospital_id
      and new.auth_user_id=old.auth_user_id
      and exists (select 1 from public.patients p join public.consultations c on c.patient_id=p.id
        join public.guest_consultation_requests g on g.id=c.guest_request_id
        join auth.users a on a.id=g.submitted_by
        where p.user_id=old.id and p.profile_status='official' and p.account_activation_status='active'
          and g.submitted_by=auth.uid() and a.email_confirmed_at is not null
          and lower(a.email)=lower(g.email) and g.request_status in ('consultation_scheduled','consultation_completed')) then
      return new;
    end if;
    if new.auth_user_id is distinct from old.auth_user_id
       or new.role_id is distinct from old.role_id
       or new.hospital_id is distinct from old.hospital_id
       or new.account_status is distinct from old.account_status then
      raise exception 'Role, hospital, identity, and account status are protected';
    end if;
    return new;
  end if;

  raise exception 'Not authorized to update this user';
end;
$function$;

CREATE OR REPLACE FUNCTION private.queue_confirmed_consultation_email()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  recipient_auth_id uuid;
  queued_notification_id uuid;
  notification_message text;
  notification_key text := 'online-consultation-confirmed-email:' || new.id::text;
begin
  if new.request_status <> 'confirmed'
    or new.consultation_channel <> 'email'
    or (
      old.request_status = 'confirmed'
      and old.consultation_channel = 'email'
    ) then
    return new;
  end if;

  select app_user.auth_user_id into recipient_auth_id
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where patient.id = new.patient_id;

  if recipient_auth_id is null then
    raise exception 'The confirmed patient has no registered email account';
  end if;

  notification_message := format(
    'Your online consultation request %s is confirmed for %s. The hospital will contact you through your registered email address.',
    new.reference_number,
    to_char(new.confirmed_schedule at time zone 'Asia/Manila', 'FMMonth DD, YYYY at HH12:MI AM')
  );

  insert into public.notifications(
    user_id, title, message, notification_type, reference_id,
    data, action_path, dedupe_key
  ) values (
    recipient_auth_id,
    'Online consultation confirmed',
    notification_message,
    'consultation_update',
    new.official_consultation_id,
    jsonb_build_object(
      'online_request_id', new.id,
      'reference_number', new.reference_number,
      'confirmed_schedule', new.confirmed_schedule,
      'consultation_channel', 'email',
      'hospital_id', new.hospital_id,
      'department_id', new.requested_department_id,
      'doctor_id', new.assigned_doctor_id
    ),
    '/patient/appointments',
    notification_key
  )
  on conflict (user_id, dedupe_key) where dedupe_key is not null
  do nothing
  returning id into queued_notification_id;

  if queued_notification_id is null then
    select notification.id into queued_notification_id
    from public.notifications notification
    where notification.user_id = recipient_auth_id
      and notification.dedupe_key = notification_key;
  end if;

  insert into public.notification_outbox(
    notification_id, user_id, channel
  ) values (
    queued_notification_id, recipient_auth_id, 'email'
  )
  on conflict (notification_id, channel) do nothing;

  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.queue_notification_deliveries()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare pref public.notification_preferences; allowed boolean;
begin
 if new.user_id is null then return new; end if;
 select * into pref from public.notification_preferences where user_id=new.user_id;
 allowed:=case new.notification_type
   when 'consultation_update' then coalesce(pref.consultation_updates,true)
   when 'account_activation' then coalesce(pref.consultation_updates,true)
   when 'appointment_reminder' then coalesce(pref.appointment_reminders,true)
   when 'medical_result' then coalesce(pref.medical_results,true)
   when 'prescription' then coalesce(pref.prescriptions,true)
   when 'medication_reminder' then coalesce(pref.medication_reminders,true)
   when 'message' then coalesce(pref.messages,true)
   when 'hospital_alert' then coalesce(pref.hospital_alerts,true) else true end;
 if coalesce((new.data->>'authorized_manual_email')::boolean,false) or (allowed and coalesce(pref.email_enabled,false)) then
  insert into public.notification_outbox(notification_id,user_id,channel) values(new.id,new.user_id,'email') on conflict do nothing;
 end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION public.queue_patient_email(target_patient_id uuid DEFAULT NULL::uuid, target_order_id uuid DEFAULT NULL::uuid, message_kind text DEFAULT 'medication_reminder'::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare patient_id uuid:=coalesce(target_patient_id,private.current_patient_id()); recipient uuid; content text; notification_id uuid;
  today date:=(now() at time zone 'Asia/Manila')::date; doctor public.doctors;
begin
 if auth.uid() is null or not exists(select 1 from auth.users where id=auth.uid() and email_confirmed_at is not null and not coalesce(is_anonymous,false)) then
   raise exception 'A verified account is required' using errcode='42501'; end if;
 select * into doctor from public.doctors where id=private.current_doctor_id();
 if patient_id is null or (patient_id is distinct from private.current_patient_id() and
   (doctor.id is null or not private.has_active_doctor_employment(doctor.id,doctor.hospital_id)
    or not (private.can_access_clinical_record(patient_id,doctor.hospital_id,'prescriptions',null,'view')
      or private.can_create_assigned_patient_document(patient_id,doctor.hospital_id)))) then
   raise exception 'This patient is not accessible to the caller' using errcode='42501'; end if;
 select u.auth_user_id into recipient from public.patients p join public.users u on u.id=p.user_id
   join auth.users a on a.id=u.auth_user_id where p.id=patient_id and u.account_status='active' and a.email_confirmed_at is not null;
 if recipient is null then raise exception 'The patient does not have a verified active email account'; end if;
 if message_kind='prescription' then
   if target_order_id is null or not exists(select 1 from public.prescription_orders where id=target_order_id and prescription_orders.patient_id=queue_patient_email.patient_id and status='issued') then
     raise exception 'An official prescription order is required'; end if;
 elsif message_kind='medication_reminder' and target_order_id is not null then raise exception 'Daily summaries are filtered by the current Manila date';
 elsif message_kind<>'medication_reminder' then raise exception 'Unsupported email action'; end if;
 content:=private.medication_summary(patient_id,today,target_order_id);
 if content is null then raise exception 'No eligible official prescriptions are available'; end if;
 notification_id:=private.enqueue_notification(recipient,case when message_kind='prescription' then 'Prescription order' else 'Daily medication summary' end,
   content,message_kind,target_order_id,jsonb_build_object('authorized_manual_email',true,'requested_by',auth.uid(),
     'dedupe_key','manual:'||message_kind||':'||patient_id::text||':'||coalesce(target_order_id::text,today::text)));
 -- An earlier automatic notification must not authorize a manual send implicitly.
 insert into public.notification_outbox(notification_id,user_id,channel) values(notification_id,recipient,'email') on conflict do nothing;
 return jsonb_build_object('notification_id',notification_id,'status',private.notification_delivery_status(notification_id));
end $function$;

CREATE OR REPLACE FUNCTION private.queue_prescription_order_notification(target_order uuid)
 RETURNS text
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare o public.prescription_orders; recipient uuid; notification_id uuid; content text;
begin
 select * into o from public.prescription_orders where id=target_order;
 select u.auth_user_id into recipient from public.patients p join public.users u on u.id=p.user_id where p.id=o.patient_id;
 content:=private.medication_summary(o.patient_id,(now() at time zone 'Asia/Manila')::date,o.id);
 notification_id:=private.enqueue_notification(recipient,'New prescription order',coalesce(content,'The official prescription record is available in CareNavigator.'),
   'prescription',o.id,jsonb_build_object('order_id',o.id,'dedupe_key','prescription_order:'||o.id::text));
 return private.notification_delivery_status(notification_id);
end $function$;

CREATE OR REPLACE FUNCTION public.reassign_consultation_doctor(target_consultation_id uuid, new_doctor_id uuid, reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  consultation_row public.consultations;
  relationship_row public.patient_care_relationships;
  consent_row public.patient_consents;
begin
  select * into consultation_row
  from public.consultations
  where id = target_consultation_id
  for update;
  if not found or not private.is_hospital_admin_for(consultation_row.hospital_id) then
    raise exception 'Hospital administration authorization is required';
  end if;
  if consultation_row.status not in ('approved', 'scheduled') then
    raise exception 'Only an approved or scheduled consultation may be reassigned';
  end if;
  if nullif(btrim(reason), '') is null then
    raise exception 'A reassignment reason is required';
  end if;
  if not exists (
    select 1 from public.doctor_hospital_employments employment
    where employment.doctor_id = new_doctor_id
      and employment.hospital_id = consultation_row.hospital_id
      and employment.employment_status = 'active'
      and employment.is_verified
      and (employment.ends_at is null or employment.ends_at > now())
  ) then
    raise exception 'The replacement doctor is not actively employed and verified';
  end if;

  perform set_config('app.authorized_reassignment', 'on', true);
  update public.consultations
  set doctor_id = new_doctor_id, updated_at = now()
  where id = consultation_row.id;

  select * into relationship_row
  from public.patient_care_relationships
  where consultation_id = consultation_row.id
  order by created_at desc limit 1;
  select * into consent_row
  from public.patient_consents
  where care_relationship_id = relationship_row.id
    and is_granted and revoked_at is null
  order by version_sequence desc, created_at desc limit 1;

  perform private.activate_relationship_access(
    relationship_row.id, consent_row.id, new_doctor_id,
    consultation_row.id, coalesce(consent_row.metadata->'selected_records', '[]'::jsonb)
  );
  insert into public.audit_logs(user_id, hospital_id, action, module, record_id, metadata)
  values (
    private.current_user_id(), consultation_row.hospital_id,
    'reassign', 'consultations', consultation_row.id,
    jsonb_build_object(
      'from_doctor_id', consultation_row.doctor_id,
      'to_doctor_id', new_doctor_id,
      'reason', btrim(reason)
    )
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.recommend_hospitals(user_latitude double precision, user_longitude double precision, required_department text DEFAULT NULL::text, required_services text[] DEFAULT '{}'::text[], required_specialization text DEFAULT NULL::text, requires_emergency boolean DEFAULT false, radius_km double precision DEFAULT 100, result_limit integer DEFAULT 10)
 RETURNS TABLE(hospital_id uuid, hospital_name text, classification_name text, address text, distance_km double precision, match_score numeric, match_reasons text[], er_status text, available_beds bigint, available_rooms bigint)
 LANGUAGE sql
 STABLE
 SET search_path TO ''
AS $function$
  with candidates as (
    select h.*,classification.classification_name,
      6371*acos(least(1,greatest(-1,
        cos(radians(user_latitude))*cos(radians(h.latitude::double precision))*cos(radians(h.longitude::double precision)-radians(user_longitude))
        +sin(radians(user_latitude))*sin(radians(h.latitude::double precision))))) as distance,
      er.status::text as er_state,
      coalesce((select sum(b.available_beds)::bigint from public.hospital_beds b where b.hospital_id=h.id),0) beds,
      coalesce((select sum(r.available_rooms)::bigint from public.hospital_rooms r where r.hospital_id=h.id),0) rooms,
      exists(select 1 from public.hospital_departments d where d.hospital_id=h.id and d.availability_status<>'unavailable'
        and (required_department is null or d.department_name ilike '%'||required_department||'%')) department_match,
      exists(select 1 from public.doctors d where d.hospital_id=h.id and d.availability_status<>'unavailable'
        and (required_specialization is null or d.specialization ilike '%'||required_specialization||'%')) specialist_match,
      coalesce((select count(*) from unnest(coalesce(required_services,'{}'::text[])) requested
        where exists(select 1 from public.hospital_services s where s.hospital_id=h.id and s.availability_status<>'unavailable'
          and (s.service_name ilike '%'||requested||'%' or requested=any(s.tags)))),0) service_matches
    from public.hospitals h
    left join public.hospital_classifications classification on classification.id=h.classification_id
    left join public.emergency_room_status er on er.hospital_id=h.id
    where h.verification_status='verified' and h.operating_status in ('open','limited') and h.latitude is not null and h.longitude is not null
  )
  select id,hospital_name,classification_name,address,distance,
    round((greatest(0,20*(1-least(distance/greatest(radius_km,0.001),1)))
      +case when required_department is null or department_match then 20 else 0 end
      +case when cardinality(coalesce(required_services,'{}'::text[]))=0 then 20 else 20*service_matches::numeric/cardinality(required_services) end
      +case when required_specialization is null or specialist_match then 20 else 0 end
      +case when not requires_emergency or er_state in ('available','limited') then 20 else 0 end)::numeric,3),
    array_remove(array[
      case when required_department is not null and department_match then 'Required department available' end,
      case when cardinality(coalesce(required_services,'{}'::text[]))>0 and service_matches>0 then service_matches||' required service(s) matched' end,
      case when required_specialization is not null and specialist_match then 'Required specialist available' end,
      case when requires_emergency and er_state in ('available','limited') then 'Emergency room accepting patients' end,
      case when beds>0 then beds||' bed(s) available' end
    ],null)::text[],er_state,beds,rooms
  from candidates
  where distance<=greatest(radius_km,0) and (not requires_emergency or er_state in ('available','limited'))
  order by 6 desc,distance
  limit least(greatest(result_limit,1),50)
$function$;

CREATE OR REPLACE FUNCTION public.record_clinical_access(target_resource_type text, target_resource_id uuid, target_action text)
 RETURNS bigint
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  target_patient_id uuid;
  record_source_hospital_id uuid;
  target_category text;
  matching_grant public.patient_access_grants;
  created_log_id bigint;
begin
  if private.current_user_id() is null then
    raise exception 'An active account is required';
  end if;
  if target_action not in ('view', 'download') then
    raise exception 'Clinical access action must be view or download';
  end if;

  case target_resource_type
    when 'medical_record' then
      select record.patient_id, record.hospital_id, 'medical_records'
      into target_patient_id, record_source_hospital_id, target_category
      from public.medical_records record
      where record.id = target_resource_id;
    when 'laboratory_result' then
      select result.patient_id, result.hospital_id, 'laboratory_results'
      into target_patient_id, record_source_hospital_id, target_category
      from public.laboratory_results result
      where result.id = target_resource_id;
    when 'medical_document' then
      select document.patient_id, document.hospital_id, 'medical_documents'
      into target_patient_id, record_source_hospital_id, target_category
      from public.medical_documents document
      where document.id = target_resource_id;
    when 'consultation_attachment' then
      select coalesce(attachment.patient_id, consultation.patient_id),
             consultation.hospital_id, 'consultations'
      into target_patient_id, record_source_hospital_id, target_category
      from public.consultation_attachments attachment
      join public.consultations consultation
        on consultation.id = attachment.consultation_id
      where attachment.id = target_resource_id;
    when 'prescription' then
      select prescription.patient_id, prescription.hospital_id, 'prescriptions'
      into target_patient_id, record_source_hospital_id, target_category
      from public.prescriptions prescription
      where prescription.id = target_resource_id;
    when 'diagnosis' then
      select diagnosis.patient_id, diagnosis.hospital_id, 'diagnoses'
      into target_patient_id, record_source_hospital_id, target_category
      from public.diagnoses diagnosis
      where diagnosis.id = target_resource_id;
    when 'laboratory_request' then
      select request.patient_id, request.hospital_id, 'laboratory_requests'
      into target_patient_id, record_source_hospital_id, target_category
      from public.laboratory_requests request
      where request.id = target_resource_id;
    when 'treatment_plan' then
      select plan.patient_id, plan.hospital_id, 'treatment_plans'
      into target_patient_id, record_source_hospital_id, target_category
      from public.treatment_plans plan
      where plan.id = target_resource_id;
    when 'consultation' then
      select consultation.patient_id, consultation.hospital_id, 'consultations'
      into target_patient_id, record_source_hospital_id, target_category
      from public.consultations consultation
      where consultation.id = target_resource_id;
    else
      raise exception 'Unsupported clinical resource type';
  end case;

  if target_patient_id is null or not private.can_access_clinical_record(
    target_patient_id, record_source_hospital_id,
    target_category, target_resource_id, target_action
  ) then
    raise exception 'Clinical resource was not found or is not authorized for this action';
  end if;

  select grant_row.* into matching_grant
  from public.patient_access_grants grant_row
  join public.patient_access_scopes scope on scope.grant_id = grant_row.id
  where grant_row.patient_id = target_patient_id
    and grant_row.receiving_doctor_id = private.current_doctor_id()
    and (
      grant_row.source_hospital_id = record_source_hospital_id
      or (
        record_source_hospital_id is null
        and target_category = 'medical_documents'
      )
    )
    and grant_row.status = 'active'
    and grant_row.expires_at > now()
    and grant_row.revoked_at is null
    and scope.record_category = target_category
  order by grant_row.activated_at desc
  limit 1;

  insert into public.medical_record_access_logs(
    patient_id, actor_user_id, actor_role, resource_type, resource_id,
    access_type, metadata, grant_id, care_relationship_id,
    source_hospital_id, receiving_hospital_id, success
  ) values (
    target_patient_id, private.current_user_id(), private.current_role(),
    target_resource_type, target_resource_id, target_action,
    jsonb_build_object('category', target_category),
    matching_grant.id, matching_grant.care_relationship_id,
    record_source_hospital_id, matching_grant.receiving_hospital_id, true
  ) returning id into created_log_id;
  return created_log_id;
end
$function$;

CREATE OR REPLACE FUNCTION public.record_consultation_status_history()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' or new.status is distinct from old.status then
    insert into public.consultation_status_history (consultation_id, old_status, new_status, changed_by, reason)
    values (new.id, case when tg_op = 'UPDATE' then old.status else null end, new.status, private.current_user_id(), new.rejection_reason);
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.record_guest_status_history()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' or new.request_status is distinct from old.request_status then
    insert into public.guest_request_status_history (request_id, old_status, new_status, changed_by, reason)
    values (new.id, case when tg_op = 'UPDATE' then old.request_status else null end, new.request_status, private.current_user_id(), new.rejection_reason);
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.record_online_request_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if tg_op = 'INSERT' or new.request_status is distinct from old.request_status then
    insert into public.online_consultation_request_status_history(
      request_id, from_status, to_status, changed_by
    ) values (
      new.id,
      case when tg_op = 'UPDATE' then old.request_status else null end,
      new.request_status,
      private.current_user_id()
    );
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.record_patient_checkup(target_patient_id uuid, checkup_payload jsonb, recorded_at timestamp with time zone DEFAULT now())
 RETURNS medical_records
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  doctor_row public.doctors;
  result_row public.medical_records;
  height_value numeric;
  weight_value numeric;
  systolic_value smallint;
  diastolic_value smallint;
  temperature_value numeric;
  heart_rate_value smallint;
  respiratory_rate_value smallint;
  oxygen_value numeric;
begin
  if not private.has_permission('records.write') then
    raise exception 'Medical record write permission is required';
  end if;
  if checkup_payload is null or jsonb_typeof(checkup_payload) <> 'object' then
    raise exception 'Checkup data must be a JSON object';
  end if;

  select * into doctor_row
  from public.doctors
  where id = private.current_doctor_id();
  if not found or not private.can_access_patient(target_patient_id) then
    raise exception 'Patient record access is not authorized';
  end if;

  height_value := nullif(btrim(checkup_payload->>'height_cm'), '')::numeric;
  weight_value := nullif(btrim(checkup_payload->>'weight_kg'), '')::numeric;
  systolic_value := nullif(btrim(checkup_payload->>'blood_pressure_systolic'), '')::smallint;
  diastolic_value := nullif(btrim(checkup_payload->>'blood_pressure_diastolic'), '')::smallint;
  temperature_value := nullif(btrim(checkup_payload->>'body_temperature_c'), '')::numeric;
  heart_rate_value := nullif(btrim(checkup_payload->>'heart_rate_bpm'), '')::smallint;
  respiratory_rate_value := nullif(btrim(checkup_payload->>'respiratory_rate_bpm'), '')::smallint;
  oxygen_value := nullif(btrim(checkup_payload->>'oxygen_saturation_percent'), '')::numeric;

  if height_value is not null and (height_value < 30 or height_value > 250) then
    raise exception 'Height must be between 30 and 250 cm';
  end if;
  if weight_value is not null and (weight_value < 1 or weight_value > 500) then
    raise exception 'Weight must be between 1 and 500 kg';
  end if;
  if systolic_value is not null and (systolic_value < 50 or systolic_value > 300) then
    raise exception 'Systolic blood pressure must be between 50 and 300 mmHg';
  end if;
  if diastolic_value is not null and (diastolic_value < 30 or diastolic_value > 200) then
    raise exception 'Diastolic blood pressure must be between 30 and 200 mmHg';
  end if;
  if systolic_value is not null and diastolic_value is not null and systolic_value <= diastolic_value then
    raise exception 'Systolic blood pressure must be higher than diastolic pressure';
  end if;
  if temperature_value is not null and (temperature_value < 25 or temperature_value > 45) then
    raise exception 'Temperature must be between 25 and 45 Â°C';
  end if;
  if heart_rate_value is not null and (heart_rate_value < 20 or heart_rate_value > 250) then
    raise exception 'Heart rate must be between 20 and 250 bpm';
  end if;
  if respiratory_rate_value is not null and (respiratory_rate_value < 5 or respiratory_rate_value > 80) then
    raise exception 'Respiratory rate must be between 5 and 80 breaths/min';
  end if;
  if oxygen_value is not null and (oxygen_value < 50 or oxygen_value > 100) then
    raise exception 'Oxygen saturation must be between 50 and 100 percent';
  end if;
  if not (
    nullif(btrim(checkup_payload->>'reason_for_visit'), '') is not null
    or height_value is not null
    or weight_value is not null
    or systolic_value is not null
    or diastolic_value is not null
    or temperature_value is not null
    or heart_rate_value is not null
    or respiratory_rate_value is not null
    or oxygen_value is not null
    or nullif(btrim(checkup_payload->>'current_symptoms'), '') is not null
    or nullif(btrim(checkup_payload->>'relevant_medical_history'), '') is not null
    or nullif(btrim(checkup_payload->>'previous_surgeries'), '') is not null
    or nullif(btrim(checkup_payload->>'smoking_status'), '') is not null
    or nullif(btrim(checkup_payload->>'alcohol_use'), '') is not null
    or nullif(btrim(checkup_payload->>'pregnancy_status'), '') is not null
    or nullif(btrim(checkup_payload->>'doctor_notes'), '') is not null
    or (
      jsonb_typeof(checkup_payload->'known_medical_conditions') = 'array'
      and jsonb_array_length(checkup_payload->'known_medical_conditions') > 0
    )
    or (
      jsonb_typeof(checkup_payload->'allergies') = 'array'
      and jsonb_array_length(checkup_payload->'allergies') > 0
    )
    or (
      jsonb_typeof(checkup_payload->'current_medications') = 'array'
      and jsonb_array_length(checkup_payload->'current_medications') > 0
    )
  ) then
    raise exception 'Add at least one checkup detail before saving';
  end if;

  insert into public.medical_records (
    patient_id,
    doctor_id,
    hospital_id,
    record_type,
    title,
    description,
    record_date,
    reason_for_visit,
    height_cm,
    weight_kg,
    bmi,
    blood_pressure_systolic,
    blood_pressure_diastolic,
    body_temperature_c,
    heart_rate_bpm,
    respiratory_rate_bpm,
    oxygen_saturation_percent,
    vitals_recorded_at,
    current_symptoms,
    known_medical_conditions,
    allergies,
    current_medications,
    relevant_medical_history,
    previous_surgeries,
    smoking_status,
    alcohol_use,
    pregnancy_status,
    doctor_notes
  ) values (
    target_patient_id,
    doctor_row.id,
    doctor_row.hospital_id,
    'checkup',
    coalesce(nullif(btrim(checkup_payload->>'reason_for_visit'), ''), 'Patient checkup'),
    nullif(btrim(checkup_payload->>'doctor_notes'), ''),
    coalesce(recorded_at, now())::date,
    nullif(btrim(checkup_payload->>'reason_for_visit'), ''),
    height_value,
    weight_value,
    case
      when height_value is not null and weight_value is not null
        then round(weight_value / power(height_value / 100, 2), 2)
      else null
    end,
    systolic_value,
    diastolic_value,
    temperature_value,
    heart_rate_value,
    respiratory_rate_value,
    oxygen_value,
    case
      when height_value is not null
        or weight_value is not null
        or systolic_value is not null
        or diastolic_value is not null
        or temperature_value is not null
        or heart_rate_value is not null
        or respiratory_rate_value is not null
        or oxygen_value is not null
        then coalesce(recorded_at, now())
      else null
    end,
    nullif(btrim(checkup_payload->>'current_symptoms'), ''),
    case when jsonb_typeof(checkup_payload->'known_medical_conditions') = 'array'
      then array(select jsonb_array_elements_text(checkup_payload->'known_medical_conditions'))
      else '{}'::text[] end,
    case when jsonb_typeof(checkup_payload->'allergies') = 'array'
      then array(select jsonb_array_elements_text(checkup_payload->'allergies'))
      else '{}'::text[] end,
    case when jsonb_typeof(checkup_payload->'current_medications') = 'array'
      then array(select jsonb_array_elements_text(checkup_payload->'current_medications'))
      else '{}'::text[] end,
    nullif(btrim(checkup_payload->>'relevant_medical_history'), ''),
    nullif(btrim(checkup_payload->>'previous_surgeries'), ''),
    nullif(btrim(checkup_payload->>'smoking_status'), ''),
    nullif(btrim(checkup_payload->>'alcohol_use'), ''),
    nullif(btrim(checkup_payload->>'pregnancy_status'), ''),
    nullif(btrim(checkup_payload->>'doctor_notes'), '')
  )
  returning * into result_row;

  return result_row;
end;
$function$;

CREATE OR REPLACE FUNCTION public.rename_own_medical_document(target_document_id uuid, target_title text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if private.current_role() <> 'patient'
    or target_document_id is null
    or nullif(btrim(target_title), '') is null
    or length(btrim(target_title)) > 180 then
    raise exception 'A patient file and a title of 1 to 180 characters are required';
  end if;

  update public.medical_documents
  set title = btrim(target_title)
  where id = target_document_id
    and uploaded_by = private.current_user_id()
    and patient_id = private.current_patient_id()
    and document_type in ('lab_result', 'prescription');

  if not found then
    raise exception 'Patients may edit only lab or prescription files they uploaded themselves';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION public.replace_hospital_service_doctors(target_service_id uuid, target_doctor_ids uuid[] DEFAULT '{}'::uuid[], target_primary_doctor_id uuid DEFAULT NULL::uuid)
 RETURNS SETOF hospital_service_doctors
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  target_hospital_id uuid;
  normalized_doctor_ids uuid[];
  expected_count integer;
  inserted_count integer;
begin
  select service.hospital_id
    into target_hospital_id
  from public.hospital_services service
  where service.id = target_service_id;

  if target_hospital_id is null then
    raise exception 'Hospital service was not found';
  end if;
  if not private.is_hospital_admin_for(target_hospital_id) then
    raise exception 'Not authorized to manage this hospital service';
  end if;

  select coalesce(array_agg(distinct doctor_id), '{}'::uuid[])
    into normalized_doctor_ids
  from unnest(coalesce(target_doctor_ids, '{}'::uuid[])) doctor_id;

  expected_count := cardinality(normalized_doctor_ids);
  if target_primary_doctor_id is not null
     and not (target_primary_doctor_id = any(normalized_doctor_ids)) then
    raise exception 'Primary doctor must be assigned to the service';
  end if;

  delete from public.hospital_service_doctors assignment
  where assignment.service_id = target_service_id;

  insert into public.hospital_service_doctors (
    hospital_id,
    service_id,
    doctor_id,
    is_primary
  )
  select
    target_hospital_id,
    target_service_id,
    doctor.id,
    coalesce(doctor.id = target_primary_doctor_id, false)
  from public.doctors doctor
  where doctor.hospital_id = target_hospital_id
    and doctor.id = any(normalized_doctor_ids);

  get diagnostics inserted_count = row_count;
  if inserted_count <> expected_count then
    raise exception 'One or more selected doctors do not belong to this hospital';
  end if;

  return query
  select assignment.*
  from public.hospital_service_doctors assignment
  where assignment.service_id = target_service_id
  order by assignment.is_primary desc, assignment.created_at;
end;
$function$;

CREATE OR REPLACE FUNCTION public.request_patient_care_relationship(target_hospital_id uuid, target_doctor_id uuid, target_relationship_type text, target_purpose text, target_categories text[], requested_expiry timestamp with time zone)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  patient_row public.patients;
  app_user public.users;
  relationship_id uuid;
  category text;
begin
  if private.current_patient_id() is null or private.current_user_id() is null then
    raise exception 'An authenticated patient is required';
  end if;
  if target_relationship_type not in ('second_opinion', 'ongoing_outpatient_care', 'transfer') then
    raise exception 'Choose second opinion, ongoing outpatient care, or transfer';
  end if;
  if nullif(btrim(target_purpose), '') is null
    or requested_expiry is null
    or requested_expiry <= now()
    or requested_expiry > now() + interval '365 days' then
    raise exception 'A purpose and expiry within one year are required';
  end if;
  if target_doctor_id is not null and not exists (
    select 1
    from public.doctor_hospital_employments employment
    where employment.doctor_id = target_doctor_id
      and employment.hospital_id = target_hospital_id
      and employment.employment_status = 'active'
      and employment.is_verified
      and (employment.ends_at is null or employment.ends_at > now())
  ) then
    raise exception 'The requested doctor is not actively employed at this hospital';
  end if;
  if cardinality(target_categories) = 0 then
    raise exception 'Choose at least one record category';
  end if;
  foreach category in array target_categories loop
    if not private.valid_record_category(category) then
      raise exception 'Unsupported record category: %', category;
    end if;
  end loop;

  select * into patient_row from public.patients where id = private.current_patient_id();
  select * into app_user from public.users where id = private.current_user_id();

  insert into public.patient_care_relationships(
    patient_id, hospital_id, doctor_id, relationship_type, purpose,
    status, requested_at, expires_at, created_by
  ) values (
    patient_row.id, target_hospital_id, target_doctor_id,
    target_relationship_type, btrim(target_purpose),
    'requested', now(), requested_expiry, app_user.id
  ) returning id into relationship_id;

  insert into public.patient_consents(
    patient_id, consent_type, consent_version, is_granted, granted_at,
    captured_by, metadata, care_relationship_id, source_hospital_id,
    receiving_hospital_id, purpose, categories, permitted_actions,
    record_selection_mode, expires_at, granted_by, version_sequence
  ) values (
    patient_row.id, target_relationship_type || '_access', relationship_id::text,
    true, now(), (select auth.uid()), jsonb_build_object('requested_by_patient', true),
    relationship_id, coalesce(patient_row.primary_hospital_id, target_hospital_id),
    target_hospital_id, btrim(target_purpose), target_categories,
    array['view', 'download', 'create']::text[], 'categories',
    requested_expiry, app_user.id, 1
  );

  return relationship_id;
end
$function$;

CREATE OR REPLACE FUNCTION public.reschedule_consultation(target_consultation_id uuid, scheduled_for timestamp with time zone)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  consultation_row public.consultations;
begin
  if (select auth.uid()) is null or scheduled_for is null or scheduled_for <= now() then
    raise exception 'A signed-in patient and a future appointment time are required';
  end if;

  select * into consultation_row
  from public.consultations
  where id = target_consultation_id
  for update;

  if not found
    or private.current_patient_id() is null
    or consultation_row.patient_id is distinct from private.current_patient_id() then
    raise exception 'The consultation is not accessible to this patient';
  end if;
  if consultation_row.status not in ('approved','scheduled') then
    raise exception 'Only an approved or scheduled consultation may be rescheduled';
  end if;

  perform private.lock_doctor_schedule(consultation_row.doctor_id);
  if not private.is_doctor_slot_available(
    consultation_row.doctor_id,
    consultation_row.hospital_id,
    consultation_row.consultation_type,
    scheduled_for,
    consultation_row.id
  ) then
    raise exception 'The selected appointment slot is unavailable';
  end if;

  update public.consultations
  set appointment_date = scheduled_for
  where id = target_consultation_id
  returning * into consultation_row;

  return jsonb_build_object(
    'id', consultation_row.id,
    'status', consultation_row.status,
    'appointment_date', consultation_row.appointment_date
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.respond_online_consultation_request(target_request_id uuid, response_action text, response_text text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.online_consultation_requests;
begin
  select * into r from public.online_consultation_requests where id=target_request_id for update;
  if not found or auth.uid() is null or r.patient_id is distinct from private.current_patient_id()
    or r.submitted_by is distinct from private.current_user_id() then raise exception 'This request is not owned by the current patient'; end if;
  if response_action='information' and r.request_status='more_information_required' then
    if length(btrim(coalesce(response_text,'')))<5 then raise exception 'Enter the information requested by the hospital'; end if;
    update public.online_consultation_requests set patient_response=btrim(response_text),request_status='under_review' where id=r.id;
  elsif response_action='decline' and r.request_status='schedule_proposed' then
    update public.online_consultation_requests set patient_response=coalesce(nullif(btrim(response_text),''),'Schedule declined'),
      request_status='under_review',proposed_schedule=null where id=r.id;
  elsif response_action='accept' and r.request_status='schedule_proposed' then
    return public.review_online_consultation_request(r.id,'confirmed',r.assigned_doctor_id,r.proposed_schedule,r.consultation_channel,'Patient accepted approved proposal');
  else raise exception 'The patient action does not match the current request state'; end if;
  return jsonb_build_object('request_id',r.id,'status','under_review','slot_reserved',false);
end $function$;

CREATE OR REPLACE FUNCTION public.review_guest_consultation(target_request_id uuid, decision text, target_doctor_id uuid DEFAULT NULL::uuid, target_appointment_date timestamp with time zone DEFAULT NULL::timestamp with time zone, review_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  request_row public.guest_consultation_requests;
  normalized_decision text := lower(btrim(coalesce(decision, '')));
  chosen_doctor uuid;
  scheduled_time timestamptz;
  target_type public.consultation_type;
  temporary_patient_id uuid;
  created_consultation_id uuid;
  relationship_id uuid;
  consent_id uuid;
begin
  if not (
    private.has_permission('patients.manage')
    or private.has_permission('hospital.manage')
  ) then
    raise exception 'Guest consultation review permission is required';
  end if;

  select * into request_row
  from public.guest_consultation_requests
  where id = target_request_id
  for update;
  if not found then
    raise exception 'Guest consultation request was not found';
  end if;
  if not (
    private.is_hospital_admin_for(request_row.preferred_hospital_id)
    or request_row.assigned_doctor_id = private.current_doctor_id()
  ) then
    raise exception 'Not authorized to review this request';
  end if;
  if request_row.request_status in (
    'rejected', 'consultation_scheduled', 'consultation_completed', 'cancelled'
  ) then
    raise exception 'This request is already in a terminal or scheduled state';
  end if;
  if normalized_decision not in ('approved', 'rejected') then
    raise exception 'Decision must be approved or rejected';
  end if;

  if normalized_decision = 'rejected' then
    if nullif(btrim(review_notes), '') is null then
      raise exception 'A rejection reason is required';
    end if;
    update public.guest_consultation_requests
    set request_status = 'rejected',
        reviewed_by = private.current_user_id(),
        reviewed_at = now(),
        rejection_reason = btrim(review_notes),
        identity_review_notes = btrim(review_notes),
        updated_at = now()
    where id = target_request_id;
    return jsonb_build_object(
      'request_id', target_request_id,
      'patient_id', null,
      'consultation_id', null,
      'status', 'rejected'
    );
  end if;

  chosen_doctor := coalesce(
    target_doctor_id, request_row.assigned_doctor_id, private.current_doctor_id()
  );
  scheduled_time := coalesce(
    target_appointment_date, request_row.preferred_schedule
  );
  target_type := case request_row.preferred_consultation_type
    when 'face_to_face'::public.consultation_type
      then 'face_to_face'::public.consultation_type
    else 'guest_online'::public.consultation_type
  end;

  if chosen_doctor is null
    or scheduled_time is null
    or scheduled_time <= now() then
    raise exception 'An available doctor and future appointment time are required';
  end if;
  if not exists (
    select 1
    from public.doctors doctor
    join public.doctor_hospital_employments employment
      on employment.doctor_id = doctor.id
     and employment.hospital_id = request_row.preferred_hospital_id
    where doctor.id = chosen_doctor
      and doctor.hospital_id = request_row.preferred_hospital_id
      and (
        request_row.preferred_department_id is null
        or doctor.department_id = request_row.preferred_department_id
      )
      and doctor.availability_status <> 'unavailable'
      and employment.employment_status = 'active'
      and employment.is_verified
      and employment.starts_at <= now()
      and (employment.ends_at is null or employment.ends_at > now())
  ) then
    raise exception 'The selected doctor is not verified and active for this hospital';
  end if;

  perform private.lock_doctor_schedule(chosen_doctor);
  if not private.is_doctor_slot_available(
    chosen_doctor, request_row.preferred_hospital_id,
    target_type, scheduled_time, null
  ) then
    raise exception 'The selected appointment slot is unavailable';
  end if;

  select id into temporary_patient_id
  from public.patients
  where guest_request_id = target_request_id;
  if temporary_patient_id is null then
    select p.id into temporary_patient_id from public.patients p
    join public.users u on u.id=p.user_id join auth.users a on a.id=u.auth_user_id
    where a.id=request_row.submitted_by and a.email_confirmed_at is not null
      and lower(a.email)=lower(request_row.email);
  end if;
  if temporary_patient_id is null then
    insert into public.patients(
      created_by_doctor, guest_request_id, primary_hospital_id,
      allergies, existing_conditions, identity_verification_status,
      account_activation_status, converted_from_guest, profile_status
    ) values (
      chosen_doctor, target_request_id, request_row.preferred_hospital_id,
      request_row.allergies, request_row.existing_conditions, 'verified',
      'pending', true, 'temporary'
    ) returning id into temporary_patient_id;
  end if;

  insert into public.patient_hospital_identifiers(
    patient_id, hospital_id, local_mrn, status, verified_at
  ) values (
    temporary_patient_id, request_row.preferred_hospital_id,
    request_row.reference_number, 'active', now()
  )
  on conflict (patient_id, hospital_id) do update
    set status = 'active',
        verified_at = coalesce(
          public.patient_hospital_identifiers.verified_at, excluded.verified_at
        ),
        updated_at = now();

  insert into public.patient_care_relationships(
    patient_id, hospital_id, doctor_id, relationship_type, purpose,
    status, requested_at, expires_at, created_by
  ) values (
    temporary_patient_id, request_row.preferred_hospital_id,
    chosen_doctor, 'consultation', 'reviewed_guest_consultation',
    'requested', now(), greatest(
      scheduled_time + interval '7 days', now() + interval '30 days'
    ), private.current_user_id()
  ) returning id into relationship_id;

  insert into public.patient_consents(
    patient_id, consent_type, consent_version, is_granted, granted_at,
    captured_by, metadata, care_relationship_id, source_hospital_id,
    receiving_hospital_id, purpose, categories, permitted_actions,
    record_selection_mode, expires_at, granted_by, version_sequence
  ) values (
    temporary_patient_id, 'guest_consultation_access',
    relationship_id::text, request_row.consent_at is not null,
    request_row.consent_at, (select auth.uid()),
    jsonb_build_object(
      'guest_request_id', request_row.id,
      'reference_number', request_row.reference_number,
      'consent_captured_during_submission', true
    ),
    relationship_id, request_row.preferred_hospital_id,
    request_row.preferred_hospital_id, 'reviewed_guest_consultation',
    array[
      'consultations', 'medical_records', 'diagnoses', 'prescriptions',
      'laboratory_requests', 'laboratory_results', 'medical_documents',
      'clinical_notes', 'allergies_medications', 'treatment_plans'
    ]::text[],
    array['view', 'download', 'create']::text[], 'categories',
    greatest(scheduled_time + interval '7 days', now() + interval '30 days'),
    private.current_user_id(), 1
  ) returning id into consent_id;

  if request_row.consent_at is null then
    raise exception 'Recorded guest consent is required before approval';
  end if;

  insert into public.consultations(
    patient_id, guest_request_id, doctor_id, hospital_id, department_id,
    consultation_type, appointment_date, status, chief_complaint,
    approved_by, approved_at
  ) values (
    temporary_patient_id, target_request_id, chosen_doctor,
    request_row.preferred_hospital_id, request_row.preferred_department_id,
    target_type, scheduled_time, 'scheduled',
    request_row.consultation_reason, private.current_user_id(), now()
  ) returning id into created_consultation_id;

  update public.patient_care_relationships
  set consultation_id = created_consultation_id, updated_at = now()
  where id = relationship_id;
  perform private.activate_relationship_access(
    relationship_id, consent_id, chosen_doctor,
    created_consultation_id, '[]'::jsonb
  );

  update public.guest_consultation_requests
  set request_status = 'consultation_scheduled',
      assigned_doctor_id = chosen_doctor,
      reviewed_by = private.current_user_id(),
      reviewed_at = now(),
      identity_review_status = 'verified',
      identity_review_notes = nullif(btrim(review_notes), ''),
      updated_at = now()
  where id = target_request_id;

  return jsonb_build_object(
    'request_id', target_request_id,
    'reference_number', request_row.reference_number,
    'patient_id', temporary_patient_id,
    'consultation_id', created_consultation_id,
    'status', 'consultation_scheduled'
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.review_hospital_application(target_hospital_id uuid, decision verification_status, decision_note text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  normalized_note text := btrim(coalesce(decision_note, ''));
  actor_user_id uuid := private.current_user_id();
begin
  if not private.is_super_admin() then
    raise exception 'Super administrator access is required';
  end if;
  if decision not in ('verified'::public.verification_status, 'rejected'::public.verification_status) then
    raise exception 'Hospital verification decision must be verified or rejected';
  end if;
  if char_length(normalized_note) < 5 or char_length(normalized_note) > 1000 then
    raise exception 'A verification note between 5 and 1000 characters is required';
  end if;

  update public.hospitals
  set verification_status = decision,
      verification_notes = normalized_note,
      verification_decided_at = now(),
      verification_decided_by = actor_user_id
  where id = target_hospital_id;

  if not found then
    raise exception 'Hospital was not found';
  end if;

  insert into public.audit_logs(user_id, hospital_id, action, module, record_id, metadata)
  values (
    actor_user_id,
    target_hospital_id,
    'hospital_verification_decision',
    'hospitals',
    target_hospital_id,
    jsonb_build_object('decision', decision, 'note', normalized_note)
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.review_online_consultation_request(target_request_id uuid, decision text, target_doctor_id uuid DEFAULT NULL::uuid, target_confirmed_schedule timestamp with time zone DEFAULT NULL::timestamp with time zone, target_channel text DEFAULT NULL::text, review_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  request_row public.online_consultation_requests;
  chosen_doctor_id uuid;
  chosen_schedule timestamptz;
  normalized_decision text := lower(btrim(coalesce(decision, '')));
  normalized_channel text := nullif(lower(btrim(coalesce(target_channel, ''))), '');
  consultation_id uuid;
begin
  -- Accept the retired wire value during a rolling client deployment, but
  -- persist and act on it as email only.
  if normalized_channel = 'sms_assisted' then
    normalized_channel := 'email';
  end if;

  if (select auth.uid()) is null or private.current_user_id() is null then
    raise exception 'An authenticated reviewer is required';
  end if;

  select * into request_row
  from public.online_consultation_requests
  where id = target_request_id
  for update;

  if not found then
    raise exception 'Online consultation request was not found';
  end if;
  if not private.is_hospital_admin_for(request_row.hospital_id) and not (
    normalized_decision='confirmed' and request_row.request_status='schedule_proposed'
    and request_row.patient_id=private.current_patient_id() and request_row.submitted_by=private.current_user_id()
    and target_doctor_id=request_row.assigned_doctor_id and target_confirmed_schedule=request_row.proposed_schedule
    and normalized_channel=request_row.consultation_channel and request_row.reviewed_by is not null
  ) then
    raise exception 'Hospital acceptance is required for this request';
  end if;
  if request_row.request_status in ('confirmed','awaiting_contact','video_ready','in_progress','completed','rejected','cancelled','no_show','face_to_face_recommended','patient_unreachable') then
    raise exception 'This request is already in a terminal or confirmed state';
  end if;

  if normalized_decision = 'under_review' then
    update public.online_consultation_requests
    set request_status = 'under_review', reviewed_by = private.current_user_id(),
        reviewed_at = now(), updated_at = now()
    where id = request_row.id;
  elsif normalized_decision = 'more_information_required' then
    if nullif(btrim(review_notes), '') is null then
      raise exception 'Describe the additional information required';
    end if;
    update public.online_consultation_requests
    set request_status = 'more_information_required',
        additional_information_request = btrim(review_notes),
        reviewed_by = private.current_user_id(), reviewed_at = now(), updated_at = now()
    where id = request_row.id;
  elsif normalized_decision = 'schedule_proposed' then
    chosen_doctor_id := coalesce(target_doctor_id, request_row.requested_doctor_id);
    chosen_schedule := coalesce(target_confirmed_schedule, request_row.preferred_schedule);
    if normalized_channel is not null
      and normalized_channel not in ('call', 'email', 'video') then
      raise exception 'Choose call, email, or video consultation';
    end if;
    if chosen_doctor_id is null or chosen_schedule is null
      or not private.is_doctor_slot_available(
        chosen_doctor_id, request_row.hospital_id, 'online', chosen_schedule, null
      ) then
      raise exception 'Choose an eligible doctor and currently available proposal';
    end if;
    update public.online_consultation_requests
    set request_status = 'schedule_proposed',
        assigned_doctor_id = chosen_doctor_id,
        proposed_schedule = chosen_schedule,
        consultation_channel = coalesce(normalized_channel, consultation_channel, 'video'),
        reviewed_by = private.current_user_id(), reviewed_at = now(), updated_at = now()
    where id = request_row.id;
  elsif normalized_decision in ('rejected', 'cancelled') then
    if normalized_decision = 'rejected' and nullif(btrim(review_notes), '') is null then
      raise exception 'A rejection reason is required';
    end if;
    update public.online_consultation_requests
    set request_status = normalized_decision,
        rejection_reason = case when normalized_decision = 'rejected' then btrim(review_notes) else rejection_reason end,
        cancellation_reason = case when normalized_decision = 'cancelled' then btrim(review_notes) else cancellation_reason end,
        reviewed_by = private.current_user_id(), reviewed_at = now(), updated_at = now()
    where id = request_row.id;
    perform private.revoke_relationship_access(
      request_row.care_relationship_id, normalized_decision, review_notes
    );
  elsif normalized_decision = 'confirmed' then
    chosen_doctor_id := coalesce(target_doctor_id, request_row.assigned_doctor_id, request_row.requested_doctor_id);
    chosen_schedule := coalesce(
      target_confirmed_schedule, request_row.proposed_schedule, request_row.preferred_schedule
    );
    if normalized_channel is null
      or normalized_channel not in ('call', 'email', 'video') then
      raise exception 'Choose call, email, or video consultation';
    end if;
    if normalized_channel = 'email'
      and nullif(btrim(request_row.profile_email), '') is null then
      raise exception 'The patient must have a registered email address for email contact';
    end if;
    if chosen_doctor_id is null or chosen_schedule is null then
      raise exception 'A verified doctor and confirmed schedule are required';
    end if;
    if not exists (
      select 1
      from public.doctors doctor
      join public.doctor_hospital_employments employment
        on employment.doctor_id = doctor.id
       and employment.hospital_id = request_row.hospital_id
      where doctor.id = chosen_doctor_id
        and doctor.department_id = request_row.requested_department_id
        and doctor.availability_status <> 'unavailable'
        and employment.employment_status = 'active'
        and employment.is_verified
        and employment.starts_at <= now()
        and (employment.ends_at is null or employment.ends_at > now())
    ) then
      raise exception 'The selected doctor is not verified and active at this hospital';
    end if;

    perform private.lock_doctor_schedule(chosen_doctor_id);
    if not private.is_doctor_slot_available(
      chosen_doctor_id, request_row.hospital_id, 'online', chosen_schedule, null
    ) then
      raise exception 'The selected appointment slot is no longer available';
    end if;

    insert into public.consultations(
      patient_id, doctor_id, hospital_id, department_id,
      consultation_type, appointment_date, status, chief_complaint,
      approved_by, approved_at
    ) values (
      request_row.patient_id, chosen_doctor_id, request_row.hospital_id,
      request_row.requested_department_id, 'online', chosen_schedule,
      'scheduled', request_row.medical_concern,
      private.current_user_id(), now()
    ) returning id into consultation_id;

    perform private.activate_relationship_access(
      request_row.care_relationship_id,
      request_row.consent_id,
      chosen_doctor_id,
      consultation_id,
      request_row.selected_records
    );

    update public.online_consultation_requests
    set request_status = 'confirmed',
        assigned_doctor_id = chosen_doctor_id,
        confirmed_schedule = chosen_schedule,
        consultation_channel = normalized_channel,
        official_consultation_id = consultation_id,
        reviewed_by = coalesce(request_row.reviewed_by,private.current_user_id()), reviewed_at = coalesce(request_row.reviewed_at,now()), updated_at = now()
    where id = request_row.id;
  else
    raise exception 'Unsupported online request decision';
  end if;

  select * into request_row
  from public.online_consultation_requests
  where id = target_request_id;

  return jsonb_build_object(
    'request_id', request_row.id,
    'reference_number', request_row.reference_number,
    'status', request_row.request_status,
    'consultation_id', request_row.official_consultation_id,
    'assigned_doctor_id', request_row.assigned_doctor_id,
    'confirmed_schedule', request_row.confirmed_schedule,
    'channel', request_row.consultation_channel,
    'slot_reserved', request_row.official_consultation_id is not null
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.review_patient_document(target_document_id uuid, decision text, review_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare d public.medical_documents; doctor public.doctors; record_id uuid;
begin
  select * into d from public.medical_documents where id=target_document_id for update;
  select * into doctor from public.doctors where id=private.current_doctor_id();
  if d.id is null or d.origin_type<>'patient_supplied' or doctor.id is null
    or not private.has_active_doctor_employment(doctor.id,doctor.hospital_id)
    or not (private.can_access_clinical_record(d.patient_id,d.hospital_id,'medical_documents',d.id,'view')) then
    raise exception 'An authorized active treating doctor must review this patient document'; end if;
  if d.review_state<>'unreviewed' then
    return jsonb_build_object('document_id',d.id,'review_state',d.review_state,'already_reviewed',true);
  end if;
  if decision not in ('approved','rejected') then raise exception 'Choose approve or reject'; end if;
  if decision='rejected' and nullif(btrim(review_notes),'') is null then raise exception 'A rejection reason is required'; end if;
  update public.medical_documents set review_state=decision,reviewed_by=private.current_user_id(),reviewed_at=now(),
    review_rejection_reason=case when decision='rejected' then btrim(review_notes) else null end where id=d.id;
  if decision='approved' then
    insert into public.medical_records(patient_id,doctor_id,hospital_id,record_type,title,description,record_date,source_document_id)
    values(d.patient_id,doctor.id,doctor.hospital_id,'document_review','Reviewed supporting document: '||d.title,
      coalesce(nullif(btrim(review_notes),''),'Doctor reviewed the original patient-supplied document. AI extraction remains preliminary.'),now(),d.id)
    returning id into record_id;
  end if;
  return jsonb_build_object('document_id',d.id,'review_state',decision,'medical_record_id',record_id);
end $function$;

CREATE OR REPLACE FUNCTION private.revoke_ended_assignment_access()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if old.ended_at is null
    and (
      new.ended_at is not null
      or new.assignment_status in ('ended', 'revoked')
    )
    and new.care_relationship_id is not null then
    update public.patient_access_grants grant_row
    set status = 'revoked',
        revoked_at = coalesce(grant_row.revoked_at, now()),
        revoked_by = private.current_user_id(),
        revocation_reason = coalesce(
          grant_row.revocation_reason,
          new.ended_reason,
          'Doctor assignment ended'
        ),
        updated_at = now()
    where grant_row.care_relationship_id = new.care_relationship_id
      and grant_row.receiving_doctor_id = new.doctor_id
      and grant_row.status in ('requested', 'active', 'suspended')
      and grant_row.revoked_at is null;

    update public.patient_care_relationships relationship
    set status = case
          when relationship.status = 'completed' then 'completed'
          else 'revoked'
        end,
        ended_at = coalesce(relationship.ended_at, now()),
        termination_reason = coalesce(
          relationship.termination_reason,
          new.ended_reason,
          'Doctor assignment ended'
        ),
        updated_at = now()
    where relationship.id = new.care_relationship_id
      and relationship.status in ('requested', 'approved', 'active');
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.revoke_patient_access_grant(target_grant_id uuid, reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  grant_row public.patient_access_grants;
begin
  select * into grant_row
  from public.patient_access_grants
  where id = target_grant_id
  for update;
  if not found or grant_row.patient_id is distinct from private.current_patient_id() then
    raise exception 'The access grant was not found for this patient';
  end if;

  update public.patient_consents
  set is_granted = false,
      revoked_at = coalesce(revoked_at, now()),
      revocation_reason = nullif(btrim(reason), ''),
      updated_at = now()
  where id = grant_row.consent_id;

  perform private.revoke_relationship_access(
    grant_row.care_relationship_id, 'revoked', reason
  );
end
$function$;

CREATE OR REPLACE FUNCTION private.revoke_relationship_access(target_relationship_id uuid, target_status text, target_reason text)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  update public.patient_care_relationships
  set status = case when target_status = 'completed' then 'completed' else 'revoked' end,
      ended_at = coalesce(ended_at, now()),
      termination_reason = coalesce(nullif(btrim(target_reason), ''), target_status),
      updated_at = now()
  where id = target_relationship_id;

  update public.patient_access_grants
  set status = 'revoked',
      revoked_at = coalesce(revoked_at, now()),
      revoked_by = private.current_user_id(),
      revocation_reason = coalesce(nullif(btrim(target_reason), ''), target_status),
      updated_at = now()
  where care_relationship_id = target_relationship_id
    and status in ('requested', 'active', 'suspended')
    and revoked_at is null;

  update public.doctor_patient_assignments
  set assignment_status = 'ended',
      ended_at = coalesce(ended_at, now()),
      ended_reason = coalesce(nullif(btrim(target_reason), ''), target_status)
  where care_relationship_id = target_relationship_id
    and ended_at is null;
end
$function$;

CREATE OR REPLACE FUNCTION public.save_hospital_service(service_payload jsonb, target_doctor_ids uuid[] DEFAULT '{}'::uuid[], target_primary_doctor_id uuid DEFAULT NULL::uuid)
 RETURNS uuid
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  target_service_id uuid := nullif(service_payload ->> 'id', '')::uuid;
  target_hospital_id uuid := nullif(service_payload ->> 'hospital_id', '')::uuid;
  delivery_modes_value text[];
  tags_value text[];
begin
  if target_hospital_id is null then
    raise exception 'Hospital is required';
  end if;
  if not private.is_hospital_admin_for(target_hospital_id) then
    raise exception 'Not authorized to manage services for this hospital';
  end if;

  select coalesce(array_agg(value), array['in_person']::text[])
    into delivery_modes_value
  from jsonb_array_elements_text(
    coalesce(service_payload -> 'delivery_modes', '["in_person"]'::jsonb)
  ) value;
  select coalesce(array_agg(value), '{}'::text[])
    into tags_value
  from jsonb_array_elements_text(
    coalesce(service_payload -> 'tags', '[]'::jsonb)
  ) value;

  if target_service_id is null then
    insert into public.hospital_services (
      hospital_id,
      department_id,
      category_id,
      service_name,
      service_code,
      description,
      availability_status,
      operating_hours,
      delivery_modes,
      appointment_required,
      accepts_walk_ins,
      fee_min,
      fee_max,
      fee_notes,
      contact_number,
      booking_url,
      preparation_instructions,
      tags,
      last_updated
    ) values (
      target_hospital_id,
      nullif(service_payload ->> 'department_id', '')::uuid,
      nullif(service_payload ->> 'category_id', '')::uuid,
      btrim(service_payload ->> 'service_name'),
      nullif(btrim(service_payload ->> 'service_code'), ''),
      coalesce(service_payload ->> 'description', ''),
      coalesce(nullif(service_payload ->> 'availability_status', ''), 'available')::public.availability_status,
      coalesce(service_payload -> 'operating_hours', '{}'::jsonb),
      delivery_modes_value,
      coalesce((service_payload ->> 'appointment_required')::boolean, false),
      coalesce((service_payload ->> 'accepts_walk_ins')::boolean, true),
      nullif(service_payload ->> 'fee_min', '')::numeric,
      nullif(service_payload ->> 'fee_max', '')::numeric,
      nullif(btrim(service_payload ->> 'fee_notes'), ''),
      nullif(btrim(service_payload ->> 'contact_number'), ''),
      nullif(btrim(service_payload ->> 'booking_url'), ''),
      nullif(btrim(service_payload ->> 'preparation_instructions'), ''),
      tags_value,
      now()
    )
    returning id into target_service_id;
  else
    update public.hospital_services service
    set
      department_id = nullif(service_payload ->> 'department_id', '')::uuid,
      category_id = nullif(service_payload ->> 'category_id', '')::uuid,
      service_name = btrim(service_payload ->> 'service_name'),
      service_code = nullif(btrim(service_payload ->> 'service_code'), ''),
      description = coalesce(service_payload ->> 'description', ''),
      availability_status = coalesce(nullif(service_payload ->> 'availability_status', ''), 'available')::public.availability_status,
      operating_hours = coalesce(service_payload -> 'operating_hours', '{}'::jsonb),
      delivery_modes = delivery_modes_value,
      appointment_required = coalesce((service_payload ->> 'appointment_required')::boolean, false),
      accepts_walk_ins = coalesce((service_payload ->> 'accepts_walk_ins')::boolean, true),
      fee_min = nullif(service_payload ->> 'fee_min', '')::numeric,
      fee_max = nullif(service_payload ->> 'fee_max', '')::numeric,
      fee_notes = nullif(btrim(service_payload ->> 'fee_notes'), ''),
      contact_number = nullif(btrim(service_payload ->> 'contact_number'), ''),
      booking_url = nullif(btrim(service_payload ->> 'booking_url'), ''),
      preparation_instructions = nullif(btrim(service_payload ->> 'preparation_instructions'), ''),
      tags = tags_value,
      last_updated = now()
    where service.id = target_service_id
      and service.hospital_id = target_hospital_id;

    if not found then
      raise exception 'Hospital service was not found';
    end if;
  end if;

  perform public.replace_hospital_service_doctors(
    target_service_id,
    target_doctor_ids,
    target_primary_doctor_id
  );
  return target_service_id;
end;
$function$;

CREATE OR REPLACE FUNCTION public.search_existing_patients(search_query text)
 RETURNS TABLE(patient_id uuid, display_name text, email text)
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  normalized_query text := pg_catalog.lower(
    pg_catalog.btrim(coalesce(search_query, ''))
  );
begin
  if (select auth.uid()) is null
    or private.current_doctor_id() is null
    or not private.has_permission('patients.manage') then
    raise exception 'An authorized doctor session is required';
  end if;

  if pg_catalog.length(normalized_query) < 2 then
    raise exception 'Enter at least 2 characters';
  end if;

  return query
  select
    patient.id,
    pg_catalog.btrim(
      pg_catalog.concat_ws(' ', app_user.first_name, app_user.last_name)
    ),
    coalesce(app_user.email, '')
  from public.patients patient
  join public.users app_user on app_user.id = patient.user_id
  where app_user.account_status = 'active'
    and patient.account_activation_status = 'active'
    and patient.profile_status = 'official'
    and (
      pg_catalog.strpos(
        pg_catalog.lower(
          pg_catalog.concat_ws(' ', app_user.first_name, app_user.last_name)
        ),
        normalized_query
      ) > 0
      or pg_catalog.strpos(
        pg_catalog.lower(coalesce(app_user.email, '')),
        normalized_query
      ) > 0
    )
  order by
    case when pg_catalog.lower(app_user.email) = normalized_query then 0 else 1 end,
    case when pg_catalog.lower(
      pg_catalog.btrim(
        pg_catalog.concat_ws(' ', app_user.first_name, app_user.last_name)
      )
    ) = normalized_query then 0 else 1 end,
    app_user.last_name,
    app_user.first_name,
    app_user.email
  limit 100;
end
$function$;

CREATE OR REPLACE FUNCTION private.seed_demo_hospital_capabilities()
 RETURNS void
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
with department_catalog(hospital_id, department_name, description) as (
  values
    ('20000000-0000-4000-8000-000000000001'::uuid, 'Cardiology', 'Heart and cardiovascular evaluation'),
    ('20000000-0000-4000-8000-000000000001'::uuid, 'Nephrology', 'Kidney care and renal medicine'),
    ('20000000-0000-4000-8000-000000000001'::uuid, 'Orthopedics', 'Bone, joint, and musculoskeletal care'),
    ('20000000-0000-4000-8000-000000000002'::uuid, 'Oncology', 'Cancer evaluation and coordinated care'),
    ('20000000-0000-4000-8000-000000000002'::uuid, 'Radiology', 'Diagnostic imaging and image-guided assessment'),
    ('20000000-0000-4000-8000-000000000002'::uuid, 'Rehabilitation Medicine', 'Recovery, mobility, and functional rehabilitation'),
    ('20000000-0000-4000-8000-000000000003'::uuid, 'Neurology', 'Brain, spine, and nervous-system care'),
    ('20000000-0000-4000-8000-000000000003'::uuid, 'Ophthalmology', 'Medical and surgical eye care'),
    ('20000000-0000-4000-8000-000000000003'::uuid, 'Otorhinolaryngology', 'Ear, nose, and throat care'),
    ('20000000-0000-4000-8000-000000000004'::uuid, 'Cardiology', 'Heart and cardiovascular evaluation'),
    ('20000000-0000-4000-8000-000000000004'::uuid, 'Psychiatry', 'Mental health assessment and treatment'),
    ('20000000-0000-4000-8000-000000000004'::uuid, 'Pulmonology', 'Lung and respiratory care'),
    ('20000000-0000-4000-8000-000000000005'::uuid, 'Nephrology', 'Kidney care and renal medicine'),
    ('20000000-0000-4000-8000-000000000005'::uuid, 'Orthopedics', 'Bone, joint, and musculoskeletal care'),
    ('20000000-0000-4000-8000-000000000005'::uuid, 'Urology', 'Urinary tract and urologic care'),
    ('20000000-0000-4000-8000-000000000006'::uuid, 'Diagnostic Imaging', 'General diagnostic imaging services'),
    ('20000000-0000-4000-8000-000000000006'::uuid, 'Family Medicine', 'Comprehensive first-contact and continuing care'),
    ('20000000-0000-4000-8000-000000000007'::uuid, 'Anesthesiology', 'Anesthesia assessment and perioperative support'),
    ('20000000-0000-4000-8000-000000000007'::uuid, 'Community Health', 'Screening, prevention, and community-based care'),
    ('20000000-0000-4000-8000-000000000007'::uuid, 'Family Medicine', 'Comprehensive first-contact and continuing care')
)
insert into public.hospital_departments (hospital_id, department_name, description)
select hospital_id, department_name, description
from department_catalog
on conflict (hospital_id, department_name) do update
set description = excluded.description,
    availability_status = 'available';

with service_catalog(
  hospital_id, department_name, service_name, category_name, description,
  appointment_required, accepts_walk_ins, tags
) as (
  values
    ('20000000-0000-4000-8000-000000000001'::uuid, 'Cardiology', 'Cardiology Consultation', 'Medical Consultation', 'Heart and cardiovascular specialist assessment', true, false, array['cardiology','heart','cardiac']::text[]),
    ('20000000-0000-4000-8000-000000000001'::uuid, 'Nephrology', 'Hemodialysis', 'Medical Consultation', 'Scheduled renal replacement therapy', true, false, array['nephrology','kidney','dialysis']::text[]),
    ('20000000-0000-4000-8000-000000000001'::uuid, 'Orthopedics', 'Orthopedic Consultation', 'Medical Consultation', 'Bone, joint, and musculoskeletal assessment', true, true, array['orthopedics','bone','joint']::text[]),
    ('20000000-0000-4000-8000-000000000002'::uuid, 'Oncology', 'Oncology Consultation', 'Medical Consultation', 'Cancer evaluation and care planning', true, false, array['oncology','cancer']::text[]),
    ('20000000-0000-4000-8000-000000000002'::uuid, 'Radiology', 'Diagnostic Imaging', 'Diagnostics & Imaging', 'General radiography and imaging assessment', true, true, array['radiology','imaging','x-ray']::text[]),
    ('20000000-0000-4000-8000-000000000002'::uuid, 'Rehabilitation Medicine', 'Physical Rehabilitation', 'Rehabilitation & Therapy', 'Mobility and functional recovery program', true, false, array['rehabilitation','physical-therapy','mobility']::text[]),
    ('20000000-0000-4000-8000-000000000003'::uuid, 'Neurology', 'Neurology Consultation', 'Medical Consultation', 'Brain, spine, and nervous-system assessment', true, false, array['neurology','brain','nerves']::text[]),
    ('20000000-0000-4000-8000-000000000003'::uuid, 'Ophthalmology', 'Eye Clinic', 'Medical Consultation', 'Medical eye assessment and follow-up', true, true, array['ophthalmology','eye','vision']::text[]),
    ('20000000-0000-4000-8000-000000000003'::uuid, 'Otorhinolaryngology', 'ENT Consultation', 'Medical Consultation', 'Ear, nose, and throat assessment', true, true, array['ent','ear','nose','throat']::text[]),
    ('20000000-0000-4000-8000-000000000004'::uuid, 'Cardiology', 'Cardiology Consultation', 'Medical Consultation', 'Heart and cardiovascular specialist assessment', true, false, array['cardiology','heart','cardiac']::text[]),
    ('20000000-0000-4000-8000-000000000004'::uuid, 'Psychiatry', 'Behavioral Health Consultation', 'Medical Consultation', 'Mental health assessment and treatment planning', true, false, array['psychiatry','mental-health','behavioral-health']::text[]),
    ('20000000-0000-4000-8000-000000000004'::uuid, 'Pulmonology', 'Pulmonary Consultation', 'Medical Consultation', 'Lung and respiratory specialist assessment', true, true, array['pulmonology','lung','respiratory']::text[]),
    ('20000000-0000-4000-8000-000000000005'::uuid, 'Nephrology', 'Renal Consultation', 'Medical Consultation', 'Kidney and renal medicine assessment', true, true, array['nephrology','kidney','renal']::text[]),
    ('20000000-0000-4000-8000-000000000005'::uuid, 'Orthopedics', 'Fracture and Trauma Care', 'Surgical Services', 'Assessment and management of fractures and orthopedic trauma', false, true, array['orthopedics','fracture','trauma']::text[]),
    ('20000000-0000-4000-8000-000000000005'::uuid, 'Urology', 'Urology Consultation', 'Medical Consultation', 'Urinary tract and urologic assessment', true, true, array['urology','urinary']::text[]),
    ('20000000-0000-4000-8000-000000000006'::uuid, 'Diagnostic Imaging', 'Ultrasound Imaging', 'Diagnostics & Imaging', 'General diagnostic ultrasound examination', true, true, array['ultrasound','imaging','diagnostics']::text[]),
    ('20000000-0000-4000-8000-000000000006'::uuid, 'Family Medicine', 'Family Medicine Consultation', 'Medical Consultation', 'First-contact care for patients and families', true, true, array['family-medicine','primary-care']::text[]),
    ('20000000-0000-4000-8000-000000000007'::uuid, 'Anesthesiology', 'Pre-anesthesia Assessment', 'Surgical Services', 'Preoperative anesthesia risk assessment', true, false, array['anesthesiology','preoperative']::text[]),
    ('20000000-0000-4000-8000-000000000007'::uuid, 'Community Health', 'Community Health Screening', 'Preventive & Wellness', 'Preventive risk screening and health guidance', false, true, array['community-health','screening','prevention']::text[]),
    ('20000000-0000-4000-8000-000000000007'::uuid, 'Family Medicine', 'Family Medicine Consultation', 'Medical Consultation', 'First-contact care for patients and families', true, true, array['family-medicine','primary-care']::text[])
)
insert into public.hospital_services (
  hospital_id, department_id, category_id, service_name, description,
  delivery_modes, appointment_required, accepts_walk_ins, tags, operating_hours
)
select
  catalog.hospital_id,
  department.id,
  category.id,
  catalog.service_name,
  catalog.description,
  array['in_person']::text[],
  catalog.appointment_required,
  catalog.accepts_walk_ins,
  catalog.tags,
  '{"weekdays":"08:00-17:00"}'::jsonb
from service_catalog catalog
join public.hospital_departments department
  on department.hospital_id = catalog.hospital_id
 and department.department_name = catalog.department_name
join public.healthcare_service_categories category
  on category.category_name = catalog.category_name
on conflict (hospital_id, service_name) do update
set department_id = excluded.department_id,
    category_id = excluded.category_id,
    description = excluded.description,
    delivery_modes = excluded.delivery_modes,
    appointment_required = excluded.appointment_required,
    accepts_walk_ins = excluded.accepts_walk_ins,
    tags = excluded.tags,
    operating_hours = excluded.operating_hours,
    availability_status = 'available',
    last_updated = now();

end;
$function$;

CREATE OR REPLACE FUNCTION public.send_chat_message(target_conversation_id uuid, message_body text DEFAULT NULL::text, attachment_paths text[] DEFAULT '{}'::text[])
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  new_message_id uuid;
  path text;
begin
  if not private.can_send_to_conversation(target_conversation_id) then
    raise exception 'Conversation is not active or accessible';
  end if;
  if nullif(btrim(message_body), '') is null
    and cardinality(coalesce(attachment_paths, '{}'::text[])) = 0 then
    raise exception 'Message or attachment is required';
  end if;

  insert into public.chat_messages(
    conversation_id,
    sender_id,
    message,
    attachment_path,
    message_type
  ) values (
    target_conversation_id,
    (select auth.uid()),
    nullif(btrim(message_body), ''),
    case
      when cardinality(coalesce(attachment_paths, '{}'::text[])) = 1
        then attachment_paths[1]
      else null
    end,
    case
      when cardinality(coalesce(attachment_paths, '{}'::text[])) > 0
        and nullif(btrim(message_body), '') is null then 'document'
      else 'text'
    end
  )
  returning id into new_message_id;

  foreach path in array coalesce(attachment_paths, '{}'::text[]) loop
    insert into public.chat_message_attachments(
      message_id,
      uploaded_by,
      storage_path,
      file_name
    ) values (
      new_message_id,
      (select auth.uid()),
      path,
      coalesce(nullif(regexp_replace(path, '^.*/', ''), ''), 'attachment')
    );
  end loop;

  update public.chat_conversations
  set updated_at = now()
  where id = target_conversation_id;

  return new_message_id;
end
$function$;

CREATE OR REPLACE FUNCTION public.set_guest_reference_number()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.reference_number is null or btrim(new.reference_number) = '' then
    new.reference_number := format(
      'CNPH-GUEST-%s-%s',
      to_char(current_date, 'YYYY'),
      lpad(nextval('public.guest_consultation_reference_seq')::text, 6, '0')
    );
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.set_medical_document_ai_state()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.origin_type='patient_supplied' then
    new.review_state:='unreviewed'; new.reviewed_by:=null; new.reviewed_at:=null; new.review_rejection_reason:=null;
  end if;
  new.ai_analysis_status:=case when new.document_type in ('lab_result','diagnostic_result','prescription') then 'pending' else 'not_requested' end;
  new.ai_summary:=null; new.ai_extracted_data:=null; new.ai_analysis_error:=null; new.ai_analyzed_at:=null;
  return new;
end $function$;

CREATE OR REPLACE FUNCTION private.set_medical_document_provenance()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  current_doctor public.doctors;
begin
  if new.uploaded_by is distinct from private.current_user_id() then
    raise exception 'Medical document author must match the authenticated application user';
  end if;

  select * into current_doctor
  from public.doctors doctor
  where doctor.id = private.current_doctor_id();

  if current_doctor.id is not null then
    new.author_doctor_id := current_doctor.id;
    new.hospital_id := current_doctor.hospital_id;
    new.origin_type := 'hospital_generated';
    if not (
      private.can_access_clinical_record(
        new.patient_id, current_doctor.hospital_id,
        'medical_documents', null, 'create'
      )
      or private.can_create_assigned_patient_document(
        new.patient_id, current_doctor.hospital_id
      )
    ) then
      raise exception 'The doctor is not authorized to add a document for this care relationship';
    end if;
  elsif new.patient_id = private.current_patient_id() then
    new.author_doctor_id := null;
    new.hospital_id := null;
    new.origin_type := 'patient_supplied';
  else
    raise exception 'Only the patient or an authorized treating doctor may upload this document';
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION private.set_online_request_reference()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if nullif(btrim(new.reference_number), '') is null then
    new.reference_number := 'ONL-' || to_char(now() at time zone 'Asia/Manila', 'YYYYMMDD')
      || '-' || lpad(nextval('public.online_consultation_reference_seq')::text, 6, '0');
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.set_patient_number()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.patient_number is null or btrim(new.patient_number) = '' then
    new.patient_number := format('CNPH-%s-%s', to_char(current_date, 'YYYY'), lpad(nextval('public.patient_number_seq')::text, 7, '0'));
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_system_setting_actor()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  new.updated_by := private.current_user_id();
  new.updated_at := now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.set_updated_at()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
begin
  new.updated_at = now();
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.standardize_guest_request_identity()
 RETURNS trigger
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  name_parts text[];
begin
  if nullif(btrim(new.first_name), '') is null
    or nullif(btrim(new.last_name), '') is null then
    name_parts := regexp_split_to_array(btrim(coalesce(new.full_name, '')), '\s+');
    if nullif(btrim(new.first_name), '') is null then
      new.first_name := nullif(btrim(name_parts[1]), '');
    end if;
    if nullif(btrim(new.last_name), '') is null
      and array_length(name_parts, 1) > 1 then
      new.last_name := nullif(
        btrim(array_to_string(name_parts[2:array_length(name_parts, 1)], ' ')),
        ''
      );
    end if;
  end if;
  new.first_name := nullif(btrim(new.first_name), '');
  new.last_name := nullif(btrim(new.last_name), '');
  if new.first_name is null or new.last_name is null then
    raise exception 'First and last names are required for a consultation request';
  end if;
  new.full_name := btrim(concat_ws(' ', new.first_name, new.last_name));
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.storage_path_owner(object_name text)
 RETURNS boolean
 LANGUAGE sql
 STABLE SECURITY DEFINER
 SET search_path TO ''
AS $function$
  select coalesce(
    private.current_user_id() is not null
    and (storage.foldername(object_name))[1]=(select auth.uid())::text,
    false
  )
$function$;

CREATE OR REPLACE FUNCTION public.submit_guest_consultation_request(request_payload jsonb, idempotency_key text)
 RETURNS uuid
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare account auth.users; request_id uuid;
begin
  select * into account from auth.users where id=auth.uid();
  if not found or account.email_confirmed_at is null or coalesce(account.is_anonymous,false)
    or lower(account.email) is distinct from lower(btrim(request_payload->>'email'))
    or private.current_user_id() is null then raise exception 'Verify this request email before submitting'; end if;
  if length(coalesce(idempotency_key,''))<16 or length(idempotency_key)>160 then raise exception 'A submission idempotency key is required'; end if;
  perform pg_catalog.pg_advisory_xact_lock(pg_catalog.hashtextextended(account.id::text||':'||idempotency_key,0));
  select id into request_id from public.guest_consultation_requests where submitted_by=account.id and submission_key=idempotency_key;
  if found then return request_id; end if;
  if length(btrim(coalesce(request_payload->>'symptoms','')))<10
    or nullif(btrim(request_payload->>'symptom_duration'),'') is null then raise exception 'Complete the care concern and symptom duration'; end if;
  if request_payload->>'preferred_consultation_type' not in ('face_to_face','guest_online') then raise exception 'Invalid guest care mode'; end if;
  if not exists (select 1 from public.hospital_departments d join public.hospitals h on h.id=d.hospital_id
    where d.id=(request_payload->>'preferred_department_id')::uuid
      and h.id=(request_payload->>'preferred_hospital_id')::uuid and h.verification_status='verified'
      and h.operating_status in ('open','limited') and d.availability_status<>'unavailable'
      and (request_payload->>'preferred_consultation_type'<>'guest_online' or private.has_online_reviewer(h.id))) then
    raise exception 'Choose an eligible hospital and department'; end if;
  insert into public.guest_consultation_requests(submitted_by,submission_key,first_name,last_name,full_name,
    birth_date,sex,mobile_number,email,address,symptoms,symptom_duration,consultation_reason,
    preferred_hospital_id,preferred_department_id,preferred_consultation_type,preferred_schedule,otp_verified_at,consent_at)
  values(account.id,idempotency_key,btrim(request_payload->>'first_name'),btrim(request_payload->>'last_name'),
    btrim(concat_ws(' ',request_payload->>'first_name',request_payload->>'last_name')),
    (request_payload->>'birth_date')::date,(request_payload->>'sex')::public.sex_type,
    btrim(request_payload->>'mobile_number'),lower(account.email),btrim(request_payload->>'address'),
    btrim(request_payload->>'symptoms'),btrim(request_payload->>'symptom_duration'),btrim(request_payload->>'symptoms'),
    (request_payload->>'preferred_hospital_id')::uuid,(request_payload->>'preferred_department_id')::uuid,
    (request_payload->>'preferred_consultation_type')::public.consultation_type,(request_payload->>'preferred_schedule')::timestamptz,now(),now())
  returning id into request_id;
  return request_id;
end $function$;

CREATE OR REPLACE FUNCTION public.submit_online_consultation_request(request_payload jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  patient_row public.patients;
  user_row public.users;
  hospital_row public.hospitals;
  target_hospital_id uuid := nullif(request_payload->>'hospital_id', '')::uuid;
  target_department_id uuid := nullif(request_payload->>'department_id', '')::uuid;
  requested_doctor_id uuid := nullif(request_payload->>'requested_doctor_id', '')::uuid;
  preferred_time timestamptz := nullif(request_payload->>'preferred_schedule', '')::timestamptz;
  concern text := btrim(coalesce(request_payload->>'medical_concern', ''));
  duration_text text := btrim(coalesce(request_payload->>'symptom_duration', ''));
  categories text[] := array(
    select distinct value
    from jsonb_array_elements_text(coalesce(request_payload->'shared_categories', '[]'::jsonb)) value
  );
  selected_records jsonb := coalesce(request_payload->'selected_records', '[]'::jsonb);
  supporting_ids uuid[] := array(
    select value::uuid
    from jsonb_array_elements_text(coalesce(request_payload->'supporting_document_ids', '[]'::jsonb)) value
    where value ~* '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
  );
  selection_mode text;
  relationship_id uuid;
  consent_id uuid;
  request_id uuid;
  request_reference text;
  category text;
begin
  if (select auth.uid()) is null
    or private.current_patient_id() is null
    or private.current_user_id() is null then
    raise exception 'An authenticated patient profile is required';
  end if;

  select * into patient_row
  from public.patients
  where id = private.current_patient_id();
  select * into user_row
  from public.users
  where id = private.current_user_id();
  select * into hospital_row
  from public.hospitals
  where id = target_hospital_id;

  if not found
    or hospital_row.verification_status <> 'verified'
    or hospital_row.operating_status not in ('open', 'limited') then
    raise exception 'A verified operating hospital is required';
  end if;
  if not private.has_online_reviewer(hospital_row.id) then
    raise exception 'An active hospital reviewer is required for online care';
  end if;
  if nullif(btrim(user_row.mobile_number), '') is null
    or nullif(btrim(user_row.first_name), '') is null
    or nullif(btrim(user_row.last_name), '') is null then
    raise exception 'Update the account profile and registered phone before requesting care';
  end if;
  if target_department_id is null or not exists (
    select 1 from public.hospital_departments department
    where department.id = target_department_id
      and department.hospital_id = hospital_row.id
      and department.availability_status <> 'unavailable'
  ) then
    raise exception 'Choose an available department at the selected hospital';
  end if;
  if requested_doctor_id is not null and not exists (
    select 1
    from public.doctors doctor
    join public.doctor_hospital_employments employment
      on employment.doctor_id = doctor.id and employment.hospital_id = hospital_row.id
    where doctor.id = requested_doctor_id
      and doctor.department_id = target_department_id
      and doctor.availability_status <> 'unavailable'
      and employment.employment_status = 'active'
      and employment.is_verified
      and (employment.ends_at is null or employment.ends_at > now())
  ) then
    raise exception 'The requested doctor is not actively employed in this department';
  end if;
  if preferred_time is null or preferred_time <= now()
    or preferred_time > now() + interval '180 days' then
    raise exception 'Choose a preferred time within the next 180 days';
  end if;
  if length(concern) < 10 or length(concern) > 2000
    or length(duration_text) < 1 or length(duration_text) > 200 then
    raise exception 'A care concern and symptom duration are required';
  end if;
  if cardinality(categories) = 0 then
    categories := array[
      'consultations', 'medical_records', 'diagnoses', 'prescriptions',
      'laboratory_requests', 'laboratory_results', 'medical_documents',
      'clinical_notes', 'allergies_medications', 'treatment_plans'
    ]::text[];
  end if;
  foreach category in array categories loop
    if not private.valid_record_category(category) then
      raise exception 'Unsupported shared record category: %', category;
    end if;
  end loop;
  if jsonb_typeof(selected_records) <> 'array' then
    raise exception 'Selected records must be an array';
  end if;

  if exists (select 1 from unnest(supporting_ids) id where not exists (
    select 1 from public.medical_documents d where d.id=id and d.patient_id=patient_row.id
  )) then raise exception 'Supporting documents must belong to the requesting patient'; end if;
  if cardinality(supporting_ids)>0 and not ('medical_documents'=any(categories)) then
    raise exception 'Consent to share the supporting medical documents is required';
  end if;
  selection_mode := case when jsonb_array_length(selected_records)>0 then 'selected_records' else 'categories' end;
  selected_records := selected_records || coalesce((select jsonb_agg(jsonb_build_object(
    'category','medical_documents','source_table','medical_documents','record_id',id)) from unnest(supporting_ids) id),'[]'::jsonb);
  perform private.validate_record_selections(patient_row.id,categories,selected_records);

  insert into public.patient_care_relationships(
    patient_id, hospital_id, doctor_id, relationship_type, purpose, status,
    requested_at, expires_at, created_by
  ) values (
    patient_row.id, hospital_row.id, requested_doctor_id,
    'consultation', 'reviewed_online_consultation', 'requested',
    now(), preferred_time + interval '7 days', user_row.id
  ) returning id into relationship_id;

  insert into public.patient_consents(
    patient_id, consent_type, consent_version, is_granted, granted_at,
    captured_by, metadata, care_relationship_id, source_hospital_id,
    receiving_hospital_id, purpose, categories, permitted_actions,
    record_selection_mode, expires_at, granted_by, version_sequence
  ) values (
    patient_row.id,
    'reviewed_online_consultation_access',
    relationship_id::text,
    true,
    now(),
    (select auth.uid()),
    jsonb_build_object(
      'request_source', 'patient_account',
      'phone_snapshot', user_row.mobile_number,
      'selected_records_count', jsonb_array_length(selected_records), 'selected_records',selected_records
    ),
    relationship_id,
    coalesce(patient_row.primary_hospital_id, hospital_row.id),
    hospital_row.id,
    'reviewed_online_consultation',
    categories,
    array['view', 'download', 'create']::text[],
    case when jsonb_array_length(selected_records) > 0
      then 'selected_records' else 'categories' end,
    preferred_time + interval '7 days',
    user_row.id,
    1
  ) returning id into consent_id;

  insert into public.online_consultation_requests(
    reference_number, patient_id, submitted_by,
    profile_first_name, profile_last_name, profile_email,
    phone_number_snapshot, birth_date_snapshot, address_snapshot,
    hospital_id, requested_department_id, requested_doctor_id,
    medical_concern, symptom_duration, preferred_schedule,
    supporting_document_ids, shared_categories, selected_records,
    consent_id, care_relationship_id, request_status
  ) values (
    '', patient_row.id, user_row.id,
    user_row.first_name, user_row.last_name, user_row.email,
    user_row.mobile_number, user_row.birth_date, user_row.address,
    hospital_row.id, target_department_id, requested_doctor_id,
    concern, duration_text, preferred_time,
    supporting_ids, categories, selected_records,
    consent_id, relationship_id, 'submitted'
  ) returning id, reference_number into request_id, request_reference;

  update public.patient_care_relationships
  set online_request_id = request_id, updated_at = now()
  where id = relationship_id;

  return jsonb_build_object(
    'request_id', request_id,
    'reference_number', request_reference,
    'status', 'submitted',
    'preferred_schedule', preferred_time,
    'phone_number', user_row.mobile_number,
    'slot_reserved', false
  );
end
$function$;

CREATE OR REPLACE FUNCTION public.sync_completed_consultation_clinical_records()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.status <> 'completed' or new.patient_id is null then return new; end if;

  if nullif(btrim(new.confirmed_diagnosis), '') is not null then
    insert into public.diagnoses (
      patient_id, consultation_id, doctor_id, hospital_id, diagnosis, is_primary, confirmed_at, source
    ) values (
      new.patient_id, new.id, new.doctor_id, new.hospital_id, btrim(new.confirmed_diagnosis), true,
      coalesce(new.completed_at, now()), 'consultation_completion'
    )
    on conflict (consultation_id) where is_primary do update
    set diagnosis = excluded.diagnosis,
        doctor_id = excluded.doctor_id,
        hospital_id = excluded.hospital_id,
        confirmed_at = excluded.confirmed_at,
        updated_at = now();
  end if;

  if nullif(btrim(new.treatment_plan), '') is not null then
    insert into public.treatment_plans (
      patient_id, consultation_id, doctor_id, hospital_id, plan, status, source
    ) values (
      new.patient_id, new.id, new.doctor_id, new.hospital_id, btrim(new.treatment_plan), 'active', 'consultation_completion'
    )
    on conflict (consultation_id) where source = 'consultation_completion' do update
    set plan = excluded.plan,
        doctor_id = excluded.doctor_id,
        hospital_id = excluded.hospital_id,
        updated_at = now();
  end if;

  insert into public.medical_records (
    patient_id,
    doctor_id,
    hospital_id,
    consultation_id,
    record_type,
    title,
    description,
    confirmed_diagnosis,
    treatment_plan,
    record_date,
    reason_for_visit,
    height_cm,
    weight_kg,
    bmi,
    blood_pressure_systolic,
    blood_pressure_diastolic,
    body_temperature_c,
    heart_rate_bpm,
    respiratory_rate_bpm,
    oxygen_saturation_percent,
    vitals_recorded_at,
    current_symptoms,
    known_medical_conditions,
    allergies,
    current_medications,
    relevant_medical_history,
    previous_surgeries,
    smoking_status,
    alcohol_use,
    pregnancy_status,
    doctor_notes
  ) values (
    new.patient_id,
    new.doctor_id,
    new.hospital_id,
    new.id,
    'consultation_checkup',
    coalesce(nullif(btrim(new.chief_complaint), ''), 'Consultation checkup'),
    nullif(btrim(new.consultation_summary), ''),
    nullif(btrim(new.confirmed_diagnosis), ''),
    nullif(btrim(new.treatment_plan), ''),
    coalesce(new.completed_at, now())::date,
    nullif(btrim(new.chief_complaint), ''),
    new.height_cm,
    new.weight_kg,
    case
      when new.height_cm is not null and new.weight_kg is not null
        then round(new.weight_kg / power(new.height_cm / 100, 2), 2)
      else null
    end,
    new.blood_pressure_systolic,
    new.blood_pressure_diastolic,
    new.body_temperature_c,
    new.heart_rate_bpm,
    new.respiratory_rate_bpm,
    new.oxygen_saturation_percent,
    new.vitals_recorded_at,
    new.current_symptoms,
    coalesce(new.known_medical_conditions, '{}'::text[]),
    coalesce(new.allergies, '{}'::text[]),
    coalesce(new.current_medications, '{}'::text[]),
    new.relevant_medical_history,
    new.previous_surgeries,
    new.smoking_status,
    new.alcohol_use,
    new.pregnancy_status,
    new.doctor_notes
  )
  on conflict (consultation_id) where record_type = 'consultation_checkup' do update
  set title = excluded.title,
      description = excluded.description,
      confirmed_diagnosis = excluded.confirmed_diagnosis,
      treatment_plan = excluded.treatment_plan,
      record_date = excluded.record_date,
      reason_for_visit = excluded.reason_for_visit,
      height_cm = excluded.height_cm,
      weight_kg = excluded.weight_kg,
      bmi = excluded.bmi,
      blood_pressure_systolic = excluded.blood_pressure_systolic,
      blood_pressure_diastolic = excluded.blood_pressure_diastolic,
      body_temperature_c = excluded.body_temperature_c,
      heart_rate_bpm = excluded.heart_rate_bpm,
      respiratory_rate_bpm = excluded.respiratory_rate_bpm,
      oxygen_saturation_percent = excluded.oxygen_saturation_percent,
      vitals_recorded_at = excluded.vitals_recorded_at,
      current_symptoms = excluded.current_symptoms,
      known_medical_conditions = excluded.known_medical_conditions,
      allergies = excluded.allergies,
      current_medications = excluded.current_medications,
      relevant_medical_history = excluded.relevant_medical_history,
      previous_surgeries = excluded.previous_surgeries,
      smoking_status = excluded.smoking_status,
      alcohol_use = excluded.alcohol_use,
      pregnancy_status = excluded.pregnancy_status,
      doctor_notes = excluded.doctor_notes,
      updated_at = now();

  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.sync_consultation_care_access()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  relationship_row public.patient_care_relationships;
  consent_row public.patient_consents;
  selected_records jsonb := '[]'::jsonb;
begin
  select * into relationship_row
  from public.patient_care_relationships relationship
  where relationship.consultation_id = new.id
  order by relationship.created_at desc
  limit 1;

  if relationship_row.id is null then
    return new;
  end if;

  if new.status in ('approved', 'scheduled', 'in_progress') then
    select * into consent_row
    from public.patient_consents consent
    where consent.care_relationship_id = relationship_row.id
      and consent.is_granted
      and consent.revoked_at is null
      and (consent.expires_at is null or consent.expires_at > now())
    order by consent.version_sequence desc, consent.created_at desc
    limit 1;

    if consent_row.id is not null then
      selected_records := coalesce(consent_row.metadata->'selected_records', '[]'::jsonb);
      perform private.activate_relationship_access(
        relationship_row.id, consent_row.id, new.doctor_id, new.id, selected_records
      );
    end if;
  elsif new.status in ('completed', 'cancelled', 'rejected') then
    perform private.revoke_relationship_access(
      relationship_row.id, new.status::text,
      coalesce(new.rejection_reason, 'Consultation ' || new.status::text)
    );
  end if;

  update public.online_consultation_requests request
  set request_status = case new.status
        when 'in_progress' then 'in_progress'
        when 'completed' then 'completed'
        when 'cancelled' then 'cancelled'
        when 'rejected' then 'rejected'
        else request.request_status
      end,
      updated_at = now()
  where request.official_consultation_id = new.id
    and new.status in ('in_progress', 'completed', 'cancelled', 'rejected')
    and request.request_status not in ('no_show','patient_unreachable','face_to_face_recommended','rejected','cancelled','completed');

  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.sync_doctor_profile_image()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
begin
  update public.doctors
  set profile_image_url = new.profile_image_url
  where user_id = new.id;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.sync_email_delivery_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 update public.notifications set email_delivery_status=case new.status
   when 'delivered' then 'sent' when 'failed' then 'failed' when 'cancelled' then 'disabled' else 'queued' end
 where id=new.notification_id;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION private.sync_employment_termination()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.employment_status in ('suspended', 'ended', 'revoked')
    or (new.ends_at is not null and new.ends_at <= now()) then
    update public.patient_access_grants
    set status = 'revoked', revoked_at = coalesce(revoked_at, now()),
        revocation_reason = coalesce(revocation_reason, 'Doctor employment ended'),
        updated_at = now()
    where receiving_doctor_id = new.doctor_id
      and receiving_hospital_id = new.hospital_id
      and status in ('requested', 'active', 'suspended')
      and revoked_at is null;

    update public.patient_care_relationships
    set status = 'revoked', ended_at = coalesce(ended_at, now()),
        termination_reason = coalesce(termination_reason, 'Doctor employment ended'),
        updated_at = now()
    where doctor_id = new.doctor_id
      and hospital_id = new.hospital_id
      and status in ('requested', 'approved', 'active');

    update public.doctor_patient_assignments
    set assignment_status = 'ended', ended_at = coalesce(ended_at, now()),
        ended_reason = coalesce(ended_reason, 'Doctor employment ended')
    where doctor_id = new.doctor_id
      and hospital_id = new.hospital_id
      and ended_at is null;
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION private.sync_rescheduled_consultation()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.appointment_date is not distinct from old.appointment_date then return new; end if;
  update public.online_consultation_requests set confirmed_schedule=new.appointment_date
    where official_consultation_id=new.id;
  update public.patient_care_relationships set expires_at=new.appointment_date+interval '7 days'
    where consultation_id=new.id and status in ('requested','active');
  update public.patient_access_grants set expires_at=new.appointment_date+interval '7 days'
    where consultation_id=new.id and status in ('requested','active');
  update public.patient_consents set expires_at=new.appointment_date+interval '7 days'
    where care_relationship_id in (select id from public.patient_care_relationships where consultation_id=new.id)
      and revoked_at is null;
  update public.video_sessions set starts_at=new.appointment_date,expires_at=new.appointment_date+interval '4 hours'
    where consultation_id=new.id and status='cancelled';
  update public.notification_outbox o set status='cancelled',last_error='Appointment rescheduled'
    from public.notifications n where n.id=o.notification_id and n.reference_id=new.id
      and n.notification_type='appointment_reminder' and o.status in ('pending','failed');
  return new;
end $function$;

CREATE OR REPLACE FUNCTION private.sync_video_session_request_status()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.status in ('ready', 'active') then
    update public.online_consultation_requests request
    set request_status = case
          when request.request_status in ('confirmed', 'awaiting_contact') then 'video_ready'
          else request.request_status
        end,
        updated_at = now()
    where request.official_consultation_id = new.consultation_id
      and request.consultation_channel = 'video';
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.transition_consultation(target_consultation_id uuid, target_status consultation_status, transition_notes text DEFAULT NULL::text, scheduled_for timestamp with time zone DEFAULT NULL::timestamp with time zone, clinical_payload jsonb DEFAULT '{}'::jsonb)
 RETURNS jsonb
 LANGUAGE plpgsql
 SET search_path TO ''
AS $function$
declare
  result_row public.consultations;
  next_height numeric;
  next_weight numeric;
begin
  if not (
    private.has_permission('consultations.read_own')
    or private.has_permission('hospital.manage')
  ) then
    raise exception 'Consultation workflow permission is required';
  end if;

  select * into result_row
  from public.consultations
  where id = target_consultation_id
  for update;
  if not found or not private.is_consultation_participant(target_consultation_id) then
    raise exception 'Consultation was not found or is not accessible';
  end if;

  if scheduled_for is not null and scheduled_for is distinct from result_row.appointment_date then
    if target_status not in ('approved', 'scheduled') then
      raise exception 'Only an approved or scheduled consultation may be rescheduled';
    end if;
    perform private.lock_doctor_schedule(result_row.doctor_id);
    if not private.is_doctor_slot_available(
      result_row.doctor_id,
      result_row.hospital_id,
      result_row.consultation_type,
      scheduled_for,
      result_row.id
    ) then
      raise exception 'The selected appointment slot is unavailable';
    end if;
  end if;

  next_height := result_row.height_cm;
  next_weight := result_row.weight_kg;
  if private.current_doctor_id() = result_row.doctor_id then
    if clinical_payload ? 'height_cm' then
      next_height := nullif(btrim(clinical_payload->>'height_cm'), '')::numeric;
    end if;
    if clinical_payload ? 'weight_kg' then
      next_weight := nullif(btrim(clinical_payload->>'weight_kg'), '')::numeric;
    end if;
  end if;

  update public.consultations
  set
    status = target_status,
    appointment_date = coalesce(scheduled_for, appointment_date),
    rejection_reason = case
      when target_status = 'rejected' then nullif(btrim(transition_notes), '')
      else rejection_reason
    end,
    doctor_notes = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'doctor_notes'
        then nullif(btrim(clinical_payload->>'doctor_notes'), '')
      else doctor_notes
    end,
    confirmed_diagnosis = case
      when private.current_doctor_id() = doctor_id
        then coalesce(clinical_payload->>'confirmed_diagnosis', confirmed_diagnosis)
      else confirmed_diagnosis
    end,
    treatment_plan = case
      when private.current_doctor_id() = doctor_id
        then coalesce(clinical_payload->>'treatment_plan', treatment_plan)
      else treatment_plan
    end,
    consultation_summary = case
      when private.current_doctor_id() = doctor_id
        then coalesce(clinical_payload->>'consultation_summary', consultation_summary)
      else consultation_summary
    end,
    height_cm = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'height_cm'
        then next_height
      else height_cm
    end,
    weight_kg = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'weight_kg'
        then next_weight
      else weight_kg
    end,
    bmi = case
      when private.current_doctor_id() = doctor_id
        and (clinical_payload ? 'height_cm' or clinical_payload ? 'weight_kg')
        and next_height is not null
        and next_weight is not null
        then round(next_weight / power(next_height / 100, 2), 2)
      when private.current_doctor_id() = doctor_id
        and (clinical_payload ? 'height_cm' or clinical_payload ? 'weight_kg')
        then null
      else bmi
    end,
    blood_pressure_systolic = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'blood_pressure_systolic'
        then nullif(btrim(clinical_payload->>'blood_pressure_systolic'), '')::smallint
      else blood_pressure_systolic
    end,
    blood_pressure_diastolic = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'blood_pressure_diastolic'
        then nullif(btrim(clinical_payload->>'blood_pressure_diastolic'), '')::smallint
      else blood_pressure_diastolic
    end,
    body_temperature_c = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'body_temperature_c'
        then nullif(btrim(clinical_payload->>'body_temperature_c'), '')::numeric
      else body_temperature_c
    end,
    heart_rate_bpm = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'heart_rate_bpm'
        then nullif(btrim(clinical_payload->>'heart_rate_bpm'), '')::smallint
      else heart_rate_bpm
    end,
    respiratory_rate_bpm = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'respiratory_rate_bpm'
        then nullif(btrim(clinical_payload->>'respiratory_rate_bpm'), '')::smallint
      else respiratory_rate_bpm
    end,
    oxygen_saturation_percent = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'oxygen_saturation_percent'
        then nullif(btrim(clinical_payload->>'oxygen_saturation_percent'), '')::numeric
      else oxygen_saturation_percent
    end,
    vitals_recorded_at = case
      when private.current_doctor_id() = doctor_id
        and (
          nullif(btrim(clinical_payload->>'height_cm'), '') is not null
          or nullif(btrim(clinical_payload->>'weight_kg'), '') is not null
          or nullif(btrim(clinical_payload->>'blood_pressure_systolic'), '') is not null
          or nullif(btrim(clinical_payload->>'blood_pressure_diastolic'), '') is not null
          or nullif(btrim(clinical_payload->>'body_temperature_c'), '') is not null
          or nullif(btrim(clinical_payload->>'heart_rate_bpm'), '') is not null
          or nullif(btrim(clinical_payload->>'respiratory_rate_bpm'), '') is not null
          or nullif(btrim(clinical_payload->>'oxygen_saturation_percent'), '') is not null
        ) then coalesce(vitals_recorded_at, now())
      when private.current_doctor_id() = doctor_id
        and (
          clinical_payload ? 'height_cm'
          or clinical_payload ? 'weight_kg'
          or clinical_payload ? 'blood_pressure_systolic'
          or clinical_payload ? 'blood_pressure_diastolic'
          or clinical_payload ? 'body_temperature_c'
          or clinical_payload ? 'heart_rate_bpm'
          or clinical_payload ? 'respiratory_rate_bpm'
          or clinical_payload ? 'oxygen_saturation_percent'
        ) then null
      else vitals_recorded_at
    end,
    current_symptoms = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'current_symptoms'
        then nullif(btrim(clinical_payload->>'current_symptoms'), '')
      else current_symptoms
    end,
    known_medical_conditions = case
      when private.current_doctor_id() = doctor_id
        and jsonb_typeof(clinical_payload->'known_medical_conditions') = 'array'
        then array(select jsonb_array_elements_text(clinical_payload->'known_medical_conditions'))
      else known_medical_conditions
    end,
    allergies = case
      when private.current_doctor_id() = doctor_id
        and jsonb_typeof(clinical_payload->'allergies') = 'array'
        then array(select jsonb_array_elements_text(clinical_payload->'allergies'))
      else allergies
    end,
    current_medications = case
      when private.current_doctor_id() = doctor_id
        and jsonb_typeof(clinical_payload->'current_medications') = 'array'
        then array(select jsonb_array_elements_text(clinical_payload->'current_medications'))
      else current_medications
    end,
    relevant_medical_history = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'relevant_medical_history'
        then nullif(btrim(clinical_payload->>'relevant_medical_history'), '')
      else relevant_medical_history
    end,
    previous_surgeries = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'previous_surgeries'
        then nullif(btrim(clinical_payload->>'previous_surgeries'), '')
      else previous_surgeries
    end,
    smoking_status = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'smoking_status'
        then nullif(btrim(clinical_payload->>'smoking_status'), '')
      else smoking_status
    end,
    alcohol_use = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'alcohol_use'
        then nullif(btrim(clinical_payload->>'alcohol_use'), '')
      else alcohol_use
    end,
    pregnancy_status = case
      when private.current_doctor_id() = doctor_id and clinical_payload ? 'pregnancy_status'
        then nullif(btrim(clinical_payload->>'pregnancy_status'), '')
      else pregnancy_status
    end,
    approved_by = case
      when target_status in ('approved', 'scheduled') then private.current_user_id()
      else approved_by
    end,
    approved_at = case
      when target_status in ('approved', 'scheduled') then coalesce(approved_at, now())
      else approved_at
    end,
    rejected_at = case
      when target_status = 'rejected' then now()
      else rejected_at
    end
  where id = target_consultation_id
  returning * into result_row;

  if result_row.guest_request_id is not null then
    update public.guest_consultation_requests
    set request_status = case target_status
      when 'completed' then 'consultation_completed'::public.guest_request_status
      when 'cancelled' then 'cancelled'::public.guest_request_status
      else request_status
    end
    where id = result_row.guest_request_id;
  end if;

  return jsonb_build_object(
    'id', result_row.id,
    'status', result_row.status,
    'appointment_date', result_row.appointment_date,
    'completed_at', result_row.completed_at
  );
end;
$function$;

CREATE OR REPLACE FUNCTION public.transition_online_consultation_request(target_request_id uuid, target_status text, transition_notes text DEFAULT NULL::text)
 RETURNS jsonb
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare r public.online_consultation_requests; c public.consultations;
begin
  select * into r from public.online_consultation_requests where id=target_request_id for update;
  if not found or auth.uid() is null or private.current_role() not in ('doctor','hospital_admin')
    or (r.assigned_doctor_id is distinct from private.current_doctor_id() and not private.is_hospital_admin_for(r.hospital_id)) then
    raise exception 'This online request is not assigned to the current care team';
  end if;
  select * into c from public.consultations where id=r.official_consultation_id for update;
  if not found or r.request_status not in ('confirmed','awaiting_contact','video_ready','in_progress') then
    raise exception 'Only a confirmed active request may enter the consultation workflow';
  end if;
  if target_status='completed' then raise exception 'Complete the consultation using the structured checkup'; end if;
  if target_status='in_progress' then
    perform public.transition_consultation(c.id,'in_progress',transition_notes);
  elsif target_status='video_ready' then
    perform public.ensure_video_session(c.id,'jitsi');
  elsif target_status='awaiting_contact' then
    if nullif(btrim(transition_notes),'') is null then raise exception 'Record the contact attempt'; end if;
    update public.online_consultation_requests set request_status=case when r.request_status='in_progress' then 'in_progress' else 'awaiting_contact' end,
      contact_attempt_status='attempted',contact_attempted_at=now(),contact_attempt_notes=btrim(transition_notes)
      where id=r.id;
  elsif target_status in ('no_show','patient_unreachable') then
    if now()<c.appointment_date+interval '30 minutes' or c.started_at is not null or c.status='in_progress'
      or r.contact_attempted_at is null or nullif(btrim(r.contact_attempt_notes),'') is null then
      raise exception 'A missed visit requires 30 elapsed minutes, a recorded contact attempt and no clinical start';
    end if;
    if nullif(btrim(transition_notes),'') is null then raise exception 'Record the missed-visit outcome'; end if;
    update public.online_consultation_requests set request_status=target_status,outcome_notes=btrim(transition_notes) where id=r.id;
  elsif target_status='face_to_face_recommended' then
    if r.assigned_doctor_id is distinct from private.current_doctor_id() then raise exception 'Only the assigned doctor may recommend clinical follow-up'; end if;
    if nullif(btrim(transition_notes),'') is null then raise exception 'A recommendation reason is required'; end if;
    update public.online_consultation_requests set request_status=target_status,outcome_notes=btrim(transition_notes),
      additional_information_request=btrim(transition_notes) where id=r.id;
  else raise exception 'Unsupported online transition'; end if;
  return (select jsonb_build_object('request_id',id,'status',request_status,'consultation_id',official_consultation_id)
    from public.online_consultation_requests where id=r.id);
end $function$;

CREATE OR REPLACE FUNCTION public.update_emergency_capacity(target_record_id uuid, total_capacity integer, occupied_capacity integer, closed_unstaffed_capacity integer, reserved_capacity integer, reported_patient_count integer, manual_status_override text DEFAULT NULL::text, manual_override_reason text DEFAULT NULL::text)
 RETURNS emergency_room_status
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  target_row public.emergency_room_status;
  normalized_override text := nullif(btrim(coalesce(manual_status_override, '')), '');
begin
  if (select auth.uid()) is null
    or private.current_user_id() is null
    or not private.has_permission('hospital.manage') then
    raise exception 'An authorized hospital operations account is required';
  end if;

  select * into target_row
  from public.emergency_room_status status_row
  where status_row.id = target_record_id
  for update;

  if not found then
    raise exception 'Emergency capacity record was not found';
  end if;

  if not private.is_hospital_admin_for(target_row.hospital_id) then
    raise exception 'You cannot update emergency capacity for this hospital';
  end if;

  if total_capacity is null
    or occupied_capacity is null
    or closed_unstaffed_capacity is null
    or reserved_capacity is null
    or reported_patient_count is null
    or total_capacity < 0
    or occupied_capacity < 0
    or closed_unstaffed_capacity < 0
    or reserved_capacity < 0
    or reported_patient_count < 0 then
    raise exception 'Emergency capacity requires non-negative whole numbers';
  end if;

  if occupied_capacity + closed_unstaffed_capacity + reserved_capacity
      > total_capacity then
    raise exception 'Occupied, unavailable, and reserved beds cannot exceed total ER capacity';
  end if;

  if normalized_override is not null
    and normalized_override not in ('limited', 'full', 'temporarily_closed') then
    raise exception 'Unsupported emergency status override';
  end if;

  if normalized_override is not null
    and length(btrim(coalesce(manual_override_reason, ''))) not between 3 and 500 then
    raise exception 'Explain why the automatic status is being overridden';
  end if;

  update public.emergency_room_status status_row
  set
    maximum_capacity = total_capacity,
    occupied_beds = occupied_capacity,
    closed_or_unstaffed_beds = closed_unstaffed_capacity,
    reserved_beds = reserved_capacity,
    current_patient_count = reported_patient_count,
    status_override = normalized_override::public.emergency_room_state,
    override_reason = case
      when normalized_override is null then null
      else btrim(manual_override_reason)
    end,
    capacity_source = 'manual'
  where status_row.id = target_record_id
  returning * into target_row;

  return target_row;
end
$function$;

CREATE OR REPLACE FUNCTION public.update_own_patient_profile(patient_profile_update jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  updated_patient_id uuid;
  normalized_blood_type text := nullif(
    pg_catalog.btrim(
      coalesce(patient_profile_update->>'blood_type', '')
    ),
    ''
  );
begin
  if (select auth.uid()) is null then
    raise exception 'An authenticated account is required';
  end if;

  if patient_profile_update is null
    or jsonb_typeof(patient_profile_update) <> 'object' then
    raise exception 'A valid patient profile update is required';
  end if;

  if normalized_blood_type is not null
    and normalized_blood_type not in (
      'A+', 'A-', 'B+', 'B-', 'AB+', 'AB-', 'O+', 'O-'
    ) then
    raise exception 'The selected blood type is not valid';
  end if;

  update public.patients as patient
  set blood_type = normalized_blood_type,
      emergency_contact = coalesce(
        patient_profile_update->'emergency_contact',
        '{}'::jsonb
      ),
      allergies = array(
        select jsonb_array_elements_text(
          coalesce(
            patient_profile_update->'allergies',
            '[]'::jsonb
          )
        )
      ),
      existing_conditions = array(
        select jsonb_array_elements_text(
          coalesce(
            patient_profile_update->'existing_conditions',
            '[]'::jsonb
          )
        )
      ),
      updated_at = now()
  from public.users as app_user
  where app_user.id = patient.user_id
    and app_user.auth_user_id = (select auth.uid())
  returning patient.id into updated_patient_id;

  if updated_patient_id is null then
    raise exception 'Patient profile not found';
  end if;
end;
$function$;

CREATE OR REPLACE FUNCTION private.valid_record_category(target_category text)
 RETURNS boolean
 LANGUAGE sql
 IMMUTABLE
 SET search_path TO ''
AS $function$
  select target_category = any (array[
    'consultations', 'medical_records', 'diagnoses', 'prescriptions',
    'laboratory_requests', 'laboratory_results', 'medical_documents',
    'clinical_notes', 'allergies_medications', 'treatment_plans'
  ]::text[])
$function$;

CREATE OR REPLACE FUNCTION public.validate_clinical_relationships()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare consultation_patient uuid; consultation_guest uuid; consultation_hospital uuid; consultation_doctor uuid;
begin
  if not exists (select 1 from public.doctors d where d.id=new.doctor_id and d.hospital_id=new.hospital_id) then
    raise exception 'Clinical record doctor must belong to its hospital';
  end if;
  if new.consultation_id is not null then
    select c.patient_id,c.guest_request_id,c.hospital_id,c.doctor_id into consultation_patient,consultation_guest,consultation_hospital,consultation_doctor
    from public.consultations c where c.id=new.consultation_id;
    if consultation_hospital is null
      or (consultation_patient is distinct from new.patient_id and not (
        consultation_patient is null and consultation_guest is not null and exists(
          select 1 from public.patients p where p.id=new.patient_id and p.guest_request_id=consultation_guest
        )
      ))
      or consultation_hospital is distinct from new.hospital_id or consultation_doctor is distinct from new.doctor_id then
      raise exception 'Clinical record does not match its consultation';
    end if;
  end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.validate_consultation_identity_source()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.patient_id is not null
    and new.guest_request_id is not null
    and not exists (
      select 1
      from public.patients patient
      where patient.id = new.patient_id
        and patient.guest_request_id = new.guest_request_id
    ) then
    raise exception 'Consultation patient and guest request must identify the same intake';
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.validate_consultation_relationships()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not exists (select 1 from public.doctors d where d.id=new.doctor_id and d.hospital_id=new.hospital_id) then
    raise exception 'Consultation doctor must belong to the consultation hospital';
  end if;
  if new.department_id is not null and not exists (
    select 1 from public.hospital_departments d where d.id=new.department_id and d.hospital_id=new.hospital_id
  ) then raise exception 'Consultation department must belong to the consultation hospital'; end if;
  if new.guest_request_id is not null and not exists (
    select 1 from public.guest_consultation_requests g where g.id=new.guest_request_id
      and g.preferred_hospital_id=new.hospital_id and (g.assigned_doctor_id is null or g.assigned_doctor_id=new.doctor_id)
  ) then raise exception 'Guest request, doctor, and hospital do not match'; end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.validate_conversation_relationships()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  consultation_row public.consultations;
begin
  if new.consultation_id is null then
    if new.patient_id is null
      or new.guest_request_id is not null
      or not exists (
        select 1
        from public.doctor_patient_assignments assignment
        where assignment.doctor_id = new.doctor_id
          and assignment.patient_id = new.patient_id
          and assignment.assignment_status = 'active'
          and assignment.ended_at is null
      ) then
      raise exception 'Direct conversation participants must have an active assignment';
    end if;
    return new;
  end if;

  select *
  into consultation_row
  from public.consultations
  where id = new.consultation_id;
  if not found
    or consultation_row.doctor_id is distinct from new.doctor_id
    or consultation_row.patient_id is distinct from new.patient_id
    or consultation_row.guest_request_id is distinct from new.guest_request_id then
    raise exception 'Conversation participants must match the consultation';
  end if;
  return new;
end
$function$;

CREATE OR REPLACE FUNCTION public.validate_doctor_user_relationship()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if not exists (
    select 1 from public.users app_user join public.roles role on role.id=app_user.role_id
    where app_user.id=new.user_id and app_user.hospital_id=new.hospital_id and role.role_name='doctor'
  ) then raise exception 'Doctor profile must reference a doctor user in the same hospital'; end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION private.validate_document_reference()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
 if new.reference_type='prescription_order' then
  if new.origin_type<>'hospital_generated' or not exists(select 1 from public.prescription_orders o
    where o.id=new.reference_id and o.patient_id=new.patient_id and o.doctor_id=private.current_doctor_id()
      and o.hospital_id=new.hospital_id) then raise exception 'The attachment must match this doctor official order'; end if;
 end if;
 return new;
end $function$;

CREATE OR REPLACE FUNCTION public.validate_guest_hospital_relationships()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.preferred_department_id is not null and not exists (
    select 1 from public.hospital_departments d where d.id=new.preferred_department_id and d.hospital_id=new.preferred_hospital_id
  ) then raise exception 'Preferred department must belong to the preferred hospital'; end if;
  if new.assigned_doctor_id is not null and not exists (
    select 1 from public.doctors d where d.id=new.assigned_doctor_id and d.hospital_id=new.preferred_hospital_id
  ) then raise exception 'Assigned doctor must belong to the preferred hospital'; end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.validate_hospital_department_relationship()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
begin
  if new.department_id is not null and not exists (
    select 1 from public.hospital_departments department where department.id=new.department_id and department.hospital_id=new.hospital_id
  ) then raise exception 'Department must belong to the same hospital'; end if;
  return new;
end;
$function$;

CREATE OR REPLACE FUNCTION public.validate_prescription_relationships()
 RETURNS trigger
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare
  consultation_row public.consultations;
  assignment_row public.doctor_patient_assignments;
begin
  if new.assignment_id is not null then
    select * into assignment_row
    from public.doctor_patient_assignments assignment
    where assignment.id = new.assignment_id
      and assignment.assignment_status = 'active'
      and assignment.ended_at is null;

    if not found
      or assignment_row.patient_id is distinct from new.patient_id
      or assignment_row.doctor_id is distinct from new.doctor_id
      or assignment_row.hospital_id is null then
      raise exception 'Prescription does not match an active doctor-patient assignment';
    end if;
    new.hospital_id := assignment_row.hospital_id;
  end if;

  if new.consultation_id is not null then
    select * into consultation_row
    from public.consultations consultation
    where consultation.id = new.consultation_id;

    if not found
      or consultation_row.patient_id is distinct from new.patient_id
      or consultation_row.doctor_id is distinct from new.doctor_id then
      raise exception 'Prescription does not match its consultation';
    end if;
    if new.assignment_id is not null
      and consultation_row.hospital_id is distinct from assignment_row.hospital_id then
      raise exception 'Prescription consultation and assignment hospitals do not match';
    end if;
    new.hospital_id := consultation_row.hospital_id;
  elsif new.assignment_id is null then
    raise exception 'Prescription requires a consultation or active assignment';
  end if;

  return new;
end
$function$;

CREATE OR REPLACE FUNCTION private.validate_record_selections(target_patient uuid, categories text[], selections jsonb)
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO ''
AS $function$
declare item jsonb; owner_id uuid; source_name text;
begin
  if jsonb_typeof(selections)<>'array' then raise exception 'Selected records must be an array'; end if;
  for item in select value from jsonb_array_elements(selections) loop
    source_name:=item->>'source_table';
    if not ((item->>'category')=any(categories)) or source_name is distinct from (item->>'category')
      or source_name not in ('consultations','medical_records','diagnoses','prescriptions','laboratory_requests','laboratory_results','medical_documents','treatment_plans') then
      raise exception 'Unsupported selected record scope';
    end if;
    execute format('select patient_id from public.%I where id=$1',source_name) into owner_id using (item->>'record_id')::uuid;
    if owner_id is distinct from target_patient then raise exception 'Selected records must belong to the requesting patient'; end if;
  end loop;
end $function$;

alter table "public"."ai_assessment_recommendations" add constraint "ai_assessment_recommendations_rank_check" CHECK ((rank > 0));

alter table "public"."ai_assessments" add constraint "ai_assessments_check" CHECK ((num_nonnulls(user_id, patient_id, guest_request_id) >= 1));

alter table "public"."care_assistant_conversations" add constraint "care_assistant_conversations_id_length" CHECK (((char_length(id) >= 1) AND (char_length(id) <= 160)));

alter table "public"."care_assistant_conversations" add constraint "care_assistant_conversations_payload_object" CHECK ((jsonb_typeof(payload) = 'object'::text));

alter table "public"."care_assistant_conversations" add constraint "care_assistant_conversations_title_length" CHECK (((char_length(btrim(title)) >= 1) AND (char_length(btrim(title)) <= 60)));

alter table "public"."chat_conversations" add constraint "chat_conversations_check" CHECK ((num_nonnulls(patient_id, guest_request_id) = 1));

alter table "public"."chat_message_attachments" add constraint "chat_message_attachments_size_bytes_check" CHECK (((size_bytes IS NULL) OR (size_bytes >= 0)));

alter table "public"."chat_messages" add constraint "chat_messages_check" CHECK (((message IS NOT NULL) OR (attachment_path IS NOT NULL)));

alter table "public"."chat_messages" add constraint "chat_messages_message_type_check" CHECK ((message_type = ANY (ARRAY['text'::text, 'image'::text, 'document'::text, 'system'::text])));

alter table "public"."clinical_record_addenda" add constraint "clinical_record_addenda_addendum_text_check" CHECK (((length(btrim(addendum_text)) >= 2) AND (length(btrim(addendum_text)) <= 10000)));

alter table "public"."clinical_record_addenda" add constraint "clinical_record_addenda_correction_reason_check" CHECK (((length(btrim(correction_reason)) >= 2) AND (length(btrim(correction_reason)) <= 2000)));

alter table "public"."consultation_attachments" add constraint "consultation_attachments_check" CHECK ((num_nonnulls(patient_id, guest_request_id) = 1));

alter table "public"."consultation_attachments" add constraint "consultation_attachments_size_bytes_check" CHECK (((size_bytes IS NULL) OR (size_bytes >= 0)));

alter table "public"."consultations" add constraint "consultations_checkup_vitals_range" CHECK ((((height_cm IS NULL) OR ((height_cm >= (30)::numeric) AND (height_cm <= (250)::numeric))) AND ((weight_kg IS NULL) OR ((weight_kg >= (1)::numeric) AND (weight_kg <= (500)::numeric))) AND ((bmi IS NULL) OR (bmi > (0)::numeric)) AND ((blood_pressure_systolic IS NULL) OR ((blood_pressure_systolic >= 50) AND (blood_pressure_systolic <= 300))) AND ((blood_pressure_diastolic IS NULL) OR ((blood_pressure_diastolic >= 30) AND (blood_pressure_diastolic <= 200))) AND ((blood_pressure_systolic IS NULL) OR (blood_pressure_diastolic IS NULL) OR (blood_pressure_systolic > blood_pressure_diastolic)) AND ((body_temperature_c IS NULL) OR ((body_temperature_c >= (25)::numeric) AND (body_temperature_c <= (45)::numeric))) AND ((heart_rate_bpm IS NULL) OR ((heart_rate_bpm >= 20) AND (heart_rate_bpm <= 250))) AND ((respiratory_rate_bpm IS NULL) OR ((respiratory_rate_bpm >= 5) AND (respiratory_rate_bpm <= 80))) AND ((oxygen_saturation_percent IS NULL) OR ((oxygen_saturation_percent >= (50)::numeric) AND (oxygen_saturation_percent <= (100)::numeric)))));

alter table "public"."consultations" add constraint "consultations_identity_source_check" CHECK ((num_nonnulls(patient_id, guest_request_id) >= 1));

alter table "public"."consultations" add constraint "consultations_meeting_link_must_be_null" CHECK ((meeting_link IS NULL));

alter table "public"."diagnoses" add constraint "diagnoses_diagnosis_check" CHECK (((length(btrim(diagnosis)) >= 2) AND (length(btrim(diagnosis)) <= 4000)));

alter table "public"."diagnoses" add constraint "diagnoses_source_check" CHECK ((source = ANY (ARRAY['manual'::text, 'consultation_completion'::text])));

alter table "public"."doctor_hospital_employments" add constraint "doctor_hospital_employments_check" CHECK (((ends_at IS NULL) OR (ends_at >= starts_at)));

alter table "public"."doctor_hospital_employments" add constraint "doctor_hospital_employments_employment_status_check" CHECK ((employment_status = ANY (ARRAY['pending'::text, 'active'::text, 'suspended'::text, 'ended'::text, 'revoked'::text])));

alter table "public"."doctor_patient_assignments" add constraint "doctor_patient_assignments_check" CHECK (((ended_at IS NULL) OR (ended_at >= assigned_at)));

alter table "public"."doctor_patient_assignments" add constraint "doctor_patient_assignments_status_check" CHECK ((assignment_status = ANY (ARRAY['active'::text, 'ended'::text, 'revoked'::text])));

alter table "public"."doctor_schedules" add constraint "doctor_schedules_check" CHECK ((ends_at > starts_at));

alter table "public"."doctor_schedules" add constraint "doctor_schedules_day_of_week_check" CHECK (((day_of_week >= 0) AND (day_of_week <= 6)));

alter table "public"."doctor_schedules" add constraint "doctor_schedules_slot_minutes_check" CHECK (((slot_minutes >= 10) AND (slot_minutes <= 240)));

alter table "public"."doctors" add constraint "doctors_consultation_fee_check" CHECK (((consultation_fee IS NULL) OR (consultation_fee >= (0)::numeric)));

alter table "public"."document_processing_jobs" add constraint "document_processing_jobs_attempt_count_check" CHECK ((attempt_count >= 0));

alter table "public"."document_processing_jobs" add constraint "document_processing_jobs_check" CHECK ((num_nonnulls(medical_document_id, laboratory_result_id) >= 1));

alter table "public"."document_processing_jobs" add constraint "document_processing_jobs_status_check" CHECK ((status = ANY (ARRAY['queued'::text, 'ocr_processing'::text, 'ai_analysis_pending'::text, 'pending_doctor_review'::text, 'completed'::text, 'failed'::text, 'cancelled'::text])));

alter table "public"."emergency_access_events" add constraint "emergency_access_events_check" CHECK ((expires_at > started_at));

alter table "public"."emergency_access_events" add constraint "emergency_access_events_check1" CHECK ((expires_at <= (started_at + '04:00:00'::interval)));

alter table "public"."emergency_access_events" add constraint "emergency_access_events_reason_check" CHECK (((length(btrim(reason)) >= 10) AND (length(btrim(reason)) <= 2000)));

alter table "public"."emergency_access_events" add constraint "emergency_access_events_status_check" CHECK ((status = ANY (ARRAY['active'::text, 'ended'::text, 'revoked'::text, 'expired'::text, 'under_review'::text])));

alter table "public"."emergency_room_status" add constraint "emergency_capacity_available_check" CHECK ((available_beds = (((maximum_capacity - occupied_beds) - closed_or_unstaffed_beds) - reserved_beds)));

alter table "public"."emergency_room_status" add constraint "emergency_capacity_components_check" CHECK (((occupied_beds >= 0) AND (closed_or_unstaffed_beds >= 0) AND (reserved_beds >= 0) AND (((occupied_beds + closed_or_unstaffed_beds) + reserved_beds) <= maximum_capacity)));

alter table "public"."emergency_room_status" add constraint "emergency_capacity_override_check" CHECK (((status_override IS NULL) OR (status_override = ANY (ARRAY['limited'::emergency_room_state, 'full'::emergency_room_state, 'temporarily_closed'::emergency_room_state]))));

alter table "public"."emergency_room_status" add constraint "emergency_capacity_override_reason_check" CHECK (((status_override IS NULL) OR ((length(btrim(COALESCE(override_reason, ''::text))) >= 3) AND (length(btrim(COALESCE(override_reason, ''::text))) <= 500))));

alter table "public"."emergency_room_status" add constraint "emergency_capacity_source_check" CHECK ((capacity_source = ANY (ARRAY['manual'::text, 'integration'::text])));

alter table "public"."emergency_room_status" add constraint "emergency_room_status_available_beds_check" CHECK ((available_beds >= 0));

alter table "public"."emergency_room_status" add constraint "emergency_room_status_current_patient_count_check" CHECK ((current_patient_count >= 0));

alter table "public"."emergency_room_status" add constraint "emergency_room_status_maximum_capacity_check" CHECK ((maximum_capacity >= 0));

alter table "public"."guest_consultation_requests" add constraint "guest_consultation_requests_latitude_check" CHECK (((latitude >= ('-90'::integer)::numeric) AND (latitude <= (90)::numeric)));

alter table "public"."guest_consultation_requests" add constraint "guest_consultation_requests_longitude_check" CHECK (((longitude >= ('-180'::integer)::numeric) AND (longitude <= (180)::numeric)));

alter table "public"."guest_consultation_requests" add constraint "guest_requests_preferred_consultation_type_check" CHECK ((preferred_consultation_type = ANY (ARRAY['face_to_face'::consultation_type, 'guest_online'::consultation_type])));

alter table "public"."healthcare_service_categories" add constraint "healthcare_service_categories_category_name_check" CHECK (((length(btrim(category_name)) >= 2) AND (length(btrim(category_name)) <= 120)));

alter table "public"."healthcare_service_categories" add constraint "healthcare_service_categories_display_order_check" CHECK ((display_order >= 0));

alter table "public"."hospital_announcements" add constraint "hospital_announcements_check" CHECK (((is_global AND (hospital_id IS NULL)) OR ((NOT is_global) AND (hospital_id IS NOT NULL))));

alter table "public"."hospital_announcements" add constraint "hospital_announcements_check1" CHECK (((expires_at IS NULL) OR (expires_at > published_at)));

alter table "public"."hospital_beds" add constraint "hospital_beds_available_beds_check" CHECK ((available_beds >= 0));

alter table "public"."hospital_beds" add constraint "hospital_beds_check" CHECK (((available_beds + occupied_beds) <= total_beds));

alter table "public"."hospital_beds" add constraint "hospital_beds_occupied_beds_check" CHECK ((occupied_beds >= 0));

alter table "public"."hospital_beds" add constraint "hospital_beds_total_beds_check" CHECK ((total_beds >= 0));

alter table "public"."hospital_facility_status" add constraint "hospital_facility_status_available_units_check" CHECK (((available_units IS NULL) OR (available_units >= 0)));

alter table "public"."hospital_facility_status" add constraint "hospital_facility_status_facility_type_check" CHECK ((facility_type = ANY (ARRAY['icu'::text, 'operating_room'::text, 'ambulance'::text, 'laboratory'::text, 'pharmacy'::text])));

alter table "public"."hospital_rooms" add constraint "hospital_rooms_available_rooms_check" CHECK ((available_rooms >= 0));

alter table "public"."hospital_rooms" add constraint "hospital_rooms_check" CHECK (((available_rooms + occupied_rooms) <= total_rooms));

alter table "public"."hospital_rooms" add constraint "hospital_rooms_occupied_rooms_check" CHECK ((occupied_rooms >= 0));

alter table "public"."hospital_rooms" add constraint "hospital_rooms_total_rooms_check" CHECK ((total_rooms >= 0));

alter table "public"."hospital_services" add constraint "hospital_services_code_format" CHECK (((service_code IS NULL) OR (service_code ~ '^[A-Za-z0-9][A-Za-z0-9._-]{0,39}$'::text)));

alter table "public"."hospital_services" add constraint "hospital_services_delivery_modes_valid" CHECK (((cardinality(delivery_modes) > 0) AND (delivery_modes <@ ARRAY['in_person'::text, 'online'::text, 'home_service'::text, 'emergency'::text])));

alter table "public"."hospital_services" add constraint "hospital_services_fee_max_valid" CHECK (((fee_max IS NULL) OR (fee_max >= (0)::numeric)));

alter table "public"."hospital_services" add constraint "hospital_services_fee_min_valid" CHECK (((fee_min IS NULL) OR (fee_min >= (0)::numeric)));

alter table "public"."hospital_services" add constraint "hospital_services_fee_range_valid" CHECK (((fee_min IS NULL) OR (fee_max IS NULL) OR (fee_max >= fee_min)));

alter table "public"."hospital_services" add constraint "hospital_services_name_not_blank" CHECK (((length(btrim(service_name)) >= 2) AND (length(btrim(service_name)) <= 180)));

alter table "public"."hospital_services" add constraint "hospital_services_operating_hours_object" CHECK ((jsonb_typeof(operating_hours) = 'object'::text));

alter table "public"."hospital_services" add constraint "hospital_services_tags_limit" CHECK ((cardinality(tags) <= 20));

alter table "public"."hospitals" add constraint "hospitals_latitude_check" CHECK (((latitude >= ('-90'::integer)::numeric) AND (latitude <= (90)::numeric)));

alter table "public"."hospitals" add constraint "hospitals_longitude_check" CHECK (((longitude >= ('-180'::integer)::numeric) AND (longitude <= (180)::numeric)));

alter table "public"."laboratory_requests" add constraint "laboratory_requests_priority_check" CHECK ((priority = ANY (ARRAY['routine'::text, 'urgent'::text, 'stat'::text])));

alter table "public"."laboratory_requests" add constraint "laboratory_requests_status_check" CHECK ((status = ANY (ARRAY['requested'::text, 'scheduled'::text, 'collected'::text, 'completed'::text, 'cancelled'::text])));

alter table "public"."laboratory_requests" add constraint "laboratory_requests_test_name_check" CHECK (((length(btrim(test_name)) >= 2) AND (length(btrim(test_name)) <= 300)));

alter table "public"."maintenance_windows" add constraint "maintenance_windows_check" CHECK ((ends_at > starts_at));

alter table "public"."medical_documents" add constraint "medical_documents_ai_analysis_status_check" CHECK ((ai_analysis_status = ANY (ARRAY['not_requested'::text, 'pending'::text, 'processing'::text, 'completed'::text, 'failed'::text])));

alter table "public"."medical_documents" add constraint "medical_documents_diagnostic_result_details_check" CHECK (((document_type <> 'diagnostic_result'::text) OR ((result_category IS NOT NULL) AND (NULLIF(btrim(test_procedure_name), ''::text) IS NOT NULL) AND ((performed_or_collected_date IS NULL) OR (result_date IS NULL) OR (result_date >= performed_or_collected_date)))));

alter table "public"."medical_documents" add constraint "medical_documents_origin_type_check" CHECK ((origin_type = ANY (ARRAY['hospital_generated'::text, 'patient_supplied'::text, 'external_import'::text, 'legacy_unknown'::text])));

alter table "public"."medical_documents" add constraint "medical_documents_result_category_check" CHECK (((result_category IS NULL) OR (result_category = ANY (ARRAY['laboratory'::text, 'x_ray'::text, 'ct_scan'::text, 'mri'::text, 'ultrasound'::text, 'ecg'::text, 'pathology'::text, 'other'::text]))));

alter table "public"."medical_documents" add constraint "medical_documents_review_state_check" CHECK ((review_state = ANY (ARRAY['unreviewed'::text, 'approved'::text, 'rejected'::text])));

alter table "public"."medical_documents" add constraint "medical_documents_size_bytes_check" CHECK (((size_bytes IS NULL) OR (size_bytes >= 0)));

alter table "public"."medical_documents" add constraint "medical_documents_storage_bucket_check" CHECK ((storage_bucket = ANY (ARRAY['laboratory-results'::text, 'scanned-medical-results'::text, 'medical-documents'::text, 'prescriptions'::text, 'consultation-attachments'::text])));

alter table "public"."medical_record_access_logs" add constraint "medical_record_access_logs_access_type_check" CHECK ((access_type = ANY (ARRAY['list'::text, 'view'::text, 'download'::text, 'export'::text])));

alter table "public"."medical_records" add constraint "medical_records_checkup_vitals_range" CHECK ((((height_cm IS NULL) OR ((height_cm >= (30)::numeric) AND (height_cm <= (250)::numeric))) AND ((weight_kg IS NULL) OR ((weight_kg >= (1)::numeric) AND (weight_kg <= (500)::numeric))) AND ((bmi IS NULL) OR (bmi > (0)::numeric)) AND ((blood_pressure_systolic IS NULL) OR ((blood_pressure_systolic >= 50) AND (blood_pressure_systolic <= 300))) AND ((blood_pressure_diastolic IS NULL) OR ((blood_pressure_diastolic >= 30) AND (blood_pressure_diastolic <= 200))) AND ((blood_pressure_systolic IS NULL) OR (blood_pressure_diastolic IS NULL) OR (blood_pressure_systolic > blood_pressure_diastolic)) AND ((body_temperature_c IS NULL) OR ((body_temperature_c >= (25)::numeric) AND (body_temperature_c <= (45)::numeric))) AND ((heart_rate_bpm IS NULL) OR ((heart_rate_bpm >= 20) AND (heart_rate_bpm <= 250))) AND ((respiratory_rate_bpm IS NULL) OR ((respiratory_rate_bpm >= 5) AND (respiratory_rate_bpm <= 80))) AND ((oxygen_saturation_percent IS NULL) OR ((oxygen_saturation_percent >= (50)::numeric) AND (oxygen_saturation_percent <= (100)::numeric)))));

alter table "public"."notification_outbox" add constraint "notification_outbox_attempt_count_check" CHECK ((attempt_count >= 0));

alter table "public"."notification_outbox" add constraint "notification_outbox_channel_check" CHECK ((channel = 'email'::text));

alter table "public"."notification_outbox" add constraint "notification_outbox_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'processing'::text, 'delivered'::text, 'failed'::text, 'cancelled'::text])));

alter table "public"."notifications" add constraint "notifications_action_path_check" CHECK (((action_path IS NULL) OR ((action_path ~~ '/%'::text) AND (action_path !~~ '//%'::text))));

alter table "public"."notifications" add constraint "notifications_check" CHECK ((num_nonnulls(user_id, guest_request_id) >= 1));

alter table "public"."notifications" add constraint "notifications_email_delivery_status_check" CHECK ((email_delivery_status = ANY (ARRAY['disabled'::text, 'queued'::text, 'sent'::text, 'failed'::text])));

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_check" CHECK ((preferred_schedule > created_at));

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_consultation_channel_check" CHECK ((consultation_channel = ANY (ARRAY['call'::text, 'email'::text, 'video'::text])));

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_medical_concern_check" CHECK (((length(btrim(medical_concern)) >= 10) AND (length(btrim(medical_concern)) <= 2000)));

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_request_status_check" CHECK ((request_status = ANY (ARRAY['submitted'::text, 'under_review'::text, 'more_information_required'::text, 'schedule_proposed'::text, 'confirmed'::text, 'awaiting_contact'::text, 'video_ready'::text, 'in_progress'::text, 'completed'::text, 'patient_unreachable'::text, 'rejected'::text, 'cancelled'::text, 'no_show'::text, 'face_to_face_recommended'::text])));

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_symptom_duration_check" CHECK (((length(btrim(symptom_duration)) >= 1) AND (length(btrim(symptom_duration)) <= 200)));

alter table "public"."patient_access_grants" add constraint "patient_access_grants_check" CHECK ((expires_at > created_at));

alter table "public"."patient_access_grants" add constraint "patient_access_grants_selection_mode_check" CHECK ((selection_mode = ANY (ARRAY['categories'::text, 'selected_records'::text])));

alter table "public"."patient_access_grants" add constraint "patient_access_grants_status_check" CHECK ((status = ANY (ARRAY['requested'::text, 'active'::text, 'suspended'::text, 'revoked'::text, 'expired'::text])));

alter table "public"."patient_access_scopes" add constraint "patient_access_scopes_record_category_check" CHECK ((record_category = ANY (ARRAY['consultations'::text, 'medical_records'::text, 'diagnoses'::text, 'prescriptions'::text, 'laboratory_requests'::text, 'laboratory_results'::text, 'medical_documents'::text, 'clinical_notes'::text, 'allergies_medications'::text, 'treatment_plans'::text])));

alter table "public"."patient_care_relationships" add constraint "patient_care_relationships_check" CHECK (((expires_at IS NULL) OR (starts_at IS NULL) OR (expires_at > starts_at)));

alter table "public"."patient_care_relationships" add constraint "patient_care_relationships_relationship_type_check" CHECK ((relationship_type = ANY (ARRAY['consultation'::text, 'referral'::text, 'second_opinion'::text, 'ongoing_outpatient_care'::text, 'transfer'::text, 'emergency'::text])));

alter table "public"."patient_care_relationships" add constraint "patient_care_relationships_status_check" CHECK ((status = ANY (ARRAY['requested'::text, 'approved'::text, 'active'::text, 'completed'::text, 'revoked'::text, 'expired'::text])));

alter table "public"."patient_connection_requests" add constraint "patient_connection_requests_check" CHECK ((expires_at > requested_at));

alter table "public"."patient_connection_requests" add constraint "patient_connection_requests_status_check" CHECK ((status = ANY (ARRAY['requested'::text, 'approved'::text, 'rejected'::text, 'cancelled'::text, 'expired'::text])));

alter table "public"."patient_consents" add constraint "patient_consents_check" CHECK (((is_granted AND (granted_at IS NOT NULL) AND (revoked_at IS NULL)) OR (NOT is_granted)));

alter table "public"."patient_consents" add constraint "patient_consents_expiry_check" CHECK (((expires_at IS NULL) OR (granted_at IS NULL) OR (expires_at > granted_at)));

alter table "public"."patient_consents" add constraint "patient_consents_selection_mode_check" CHECK ((record_selection_mode = ANY (ARRAY['categories'::text, 'selected_records'::text])));

alter table "public"."patient_hospital_identifiers" add constraint "patient_hospital_identifiers_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'active'::text, 'merged'::text, 'retired'::text, 'quarantined'::text])));

alter table "public"."patient_representatives" add constraint "patient_representatives_authority_type_check" CHECK ((authority_type = ANY (ARRAY['guardian'::text, 'parent'::text, 'healthcare_proxy'::text, 'legal_representative'::text])));

alter table "public"."patient_representatives" add constraint "patient_representatives_verification_status_check" CHECK ((verification_status = ANY (ARRAY['pending'::text, 'verified'::text, 'rejected'::text, 'revoked'::text, 'expired'::text])));

alter table "public"."patients" add constraint "patients_blood_type_check" CHECK (((blood_type IS NULL) OR (blood_type = ANY (ARRAY['A+'::text, 'A-'::text, 'B+'::text, 'B-'::text, 'AB+'::text, 'AB-'::text, 'O+'::text, 'O-'::text]))));

alter table "public"."patients" add constraint "patients_profile_status_check" CHECK ((profile_status = ANY (ARRAY['temporary'::text, 'activation_pending'::text, 'official'::text, 'duplicate_review'::text, 'rejected'::text])));

alter table "public"."prescription_orders" add constraint "prescription_orders_status_check" CHECK ((status = ANY (ARRAY['issued'::text, 'voided'::text])));

alter table "public"."prescriptions" add constraint "prescriptions_clinical_context_required" CHECK (((consultation_id IS NOT NULL) OR (assignment_id IS NOT NULL)));

alter table "public"."prescriptions" add constraint "prescriptions_date_order" CHECK (((end_date IS NULL) OR (start_date IS NULL) OR (end_date >= start_date)));

alter table "public"."prescriptions" add constraint "prescriptions_prn_details" CHECK (((NOT is_prn) OR ((NULLIF(btrim(prn_reason), ''::text) IS NOT NULL) AND (NULLIF(btrim(maximum_daily_dose), ''::text) IS NOT NULL))));

alter table "public"."prescriptions" add constraint "prescriptions_refills_range" CHECK (((refills IS NULL) OR ((refills >= 0) AND (refills <= 99))));

alter table "public"."prescriptions" add constraint "prescriptions_signature_method" CHECK (((signature_method IS NULL) OR (signature_method = 'authenticated_account_attestation'::text)));

alter table "public"."roles" add constraint "roles_role_name_check" CHECK ((role_name = ANY (ARRAY['guest'::text, 'patient'::text, 'doctor'::text, 'hospital_admin'::text, 'super_admin'::text])));

alter table "public"."security_logs" add constraint "security_logs_severity_check" CHECK ((severity = ANY (ARRAY['info'::text, 'warning'::text, 'critical'::text])));

alter table "public"."treatment_plans" add constraint "treatment_plans_check" CHECK (((ends_on IS NULL) OR (starts_on IS NULL) OR (ends_on >= starts_on)));

alter table "public"."treatment_plans" add constraint "treatment_plans_plan_check" CHECK (((length(btrim(plan)) >= 2) AND (length(btrim(plan)) <= 10000)));

alter table "public"."treatment_plans" add constraint "treatment_plans_source_check" CHECK ((source = ANY (ARRAY['manual'::text, 'consultation_completion'::text])));

alter table "public"."treatment_plans" add constraint "treatment_plans_status_check" CHECK ((status = ANY (ARRAY['planned'::text, 'active'::text, 'completed'::text, 'cancelled'::text])));

alter table "public"."users" add constraint "users_address_latitude_check" CHECK (((address_latitude IS NULL) OR ((address_latitude >= ('-90'::integer)::double precision) AND (address_latitude <= (90)::double precision))));

alter table "public"."users" add constraint "users_address_longitude_check" CHECK (((address_longitude IS NULL) OR ((address_longitude >= ('-180'::integer)::double precision) AND (address_longitude <= (180)::double precision))));

alter table "public"."video_sessions" add constraint "video_sessions_check" CHECK (((ended_at IS NULL) OR (started_at IS NULL) OR (ended_at >= started_at)));

alter table "public"."video_sessions" add constraint "video_sessions_status_check" CHECK ((status = ANY (ARRAY['pending'::text, 'ready'::text, 'active'::text, 'ended'::text, 'cancelled'::text, 'failed'::text])));

alter table "public"."ai_assessment_recommendations" add constraint "ai_assessment_recommendations_pkey" PRIMARY KEY (id);

alter table "public"."ai_assessments" add constraint "ai_assessments_pkey" PRIMARY KEY (id);

alter table "public"."ai_configurations" add constraint "ai_configurations_pkey" PRIMARY KEY (id);

alter table "public"."appointment_reminder_jobs" add constraint "appointment_reminder_jobs_pkey" PRIMARY KEY (consultation_id, appointment_date);

alter table "public"."audit_logs" add constraint "audit_logs_pkey" PRIMARY KEY (id);

alter table "public"."care_assistant_conversations" add constraint "care_assistant_conversations_pkey" PRIMARY KEY (user_id, id);

alter table "public"."chat_conversations" add constraint "chat_conversations_pkey" PRIMARY KEY (id);

alter table "public"."chat_message_attachments" add constraint "chat_message_attachments_pkey" PRIMARY KEY (id);

alter table "public"."chat_messages" add constraint "chat_messages_pkey" PRIMARY KEY (id);

alter table "public"."clinical_record_addenda" add constraint "clinical_record_addenda_pkey" PRIMARY KEY (id);

alter table "public"."clinical_record_quarantine" add constraint "clinical_record_quarantine_pkey" PRIMARY KEY (id);

alter table "public"."consultation_attachments" add constraint "consultation_attachments_pkey" PRIMARY KEY (id);

alter table "public"."consultation_status_history" add constraint "consultation_status_history_pkey" PRIMARY KEY (id);

alter table "public"."consultations" add constraint "consultations_pkey" PRIMARY KEY (id);

alter table "public"."diagnoses" add constraint "diagnoses_pkey" PRIMARY KEY (id);

alter table "public"."doctor_hospital_employments" add constraint "doctor_hospital_employments_pkey" PRIMARY KEY (id);

alter table "public"."doctor_patient_assignments" add constraint "doctor_patient_assignments_pkey" PRIMARY KEY (id);

alter table "public"."doctor_schedules" add constraint "doctor_schedules_pkey" PRIMARY KEY (id);

alter table "public"."doctors" add constraint "doctors_pkey" PRIMARY KEY (id);

alter table "public"."document_processing_jobs" add constraint "document_processing_jobs_pkey" PRIMARY KEY (id);

alter table "public"."emergency_access_events" add constraint "emergency_access_events_pkey" PRIMARY KEY (id);

alter table "public"."emergency_room_status" add constraint "emergency_room_status_pkey" PRIMARY KEY (id);

alter table "public"."guest_consultation_requests" add constraint "guest_consultation_requests_pkey" PRIMARY KEY (id);

alter table "public"."guest_request_status_history" add constraint "guest_request_status_history_pkey" PRIMARY KEY (id);

alter table "public"."healthcare_service_categories" add constraint "healthcare_service_categories_pkey" PRIMARY KEY (id);

alter table "public"."hospital_announcements" add constraint "hospital_announcements_pkey" PRIMARY KEY (id);

alter table "public"."hospital_beds" add constraint "hospital_beds_pkey" PRIMARY KEY (id);

alter table "public"."hospital_classifications" add constraint "hospital_classifications_pkey" PRIMARY KEY (id);

alter table "public"."hospital_departments" add constraint "hospital_departments_pkey" PRIMARY KEY (id);

alter table "public"."hospital_facility_status" add constraint "hospital_facility_status_pkey" PRIMARY KEY (id);

alter table "public"."hospital_rooms" add constraint "hospital_rooms_pkey" PRIMARY KEY (id);

alter table "public"."hospital_service_doctors" add constraint "hospital_service_doctors_pkey" PRIMARY KEY (id);

alter table "public"."hospital_services" add constraint "hospital_services_pkey" PRIMARY KEY (id);

alter table "public"."hospitals" add constraint "hospitals_pkey" PRIMARY KEY (id);

alter table "public"."laboratory_requests" add constraint "laboratory_requests_pkey" PRIMARY KEY (id);

alter table "public"."laboratory_results" add constraint "laboratory_results_pkey" PRIMARY KEY (id);

alter table "public"."maintenance_windows" add constraint "maintenance_windows_pkey" PRIMARY KEY (id);

alter table "public"."medical_documents" add constraint "medical_documents_pkey" PRIMARY KEY (id);

alter table "public"."medical_record_access_logs" add constraint "medical_record_access_logs_pkey" PRIMARY KEY (id);

alter table "public"."medical_records" add constraint "medical_records_pkey" PRIMARY KEY (id);

alter table "public"."medication_summary_days" add constraint "medication_summary_days_pkey" PRIMARY KEY (patient_id, local_date);

alter table "public"."notification_outbox" add constraint "notification_outbox_pkey" PRIMARY KEY (id);

alter table "public"."notification_preferences" add constraint "notification_preferences_pkey" PRIMARY KEY (user_id);

alter table "public"."notifications" add constraint "notifications_pkey" PRIMARY KEY (id);

alter table "public"."online_consultation_request_status_history" add constraint "online_consultation_request_status_history_pkey" PRIMARY KEY (id);

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_pkey" PRIMARY KEY (id);

alter table "public"."patient_access_grants" add constraint "patient_access_grants_pkey" PRIMARY KEY (id);

alter table "public"."patient_access_record_selections" add constraint "patient_access_record_selections_pkey" PRIMARY KEY (id);

alter table "public"."patient_access_scopes" add constraint "patient_access_scopes_pkey" PRIMARY KEY (id);

alter table "public"."patient_care_relationships" add constraint "patient_care_relationships_pkey" PRIMARY KEY (id);

alter table "public"."patient_connection_requests" add constraint "patient_connection_requests_pkey" PRIMARY KEY (id);

alter table "public"."patient_consents" add constraint "patient_consents_pkey" PRIMARY KEY (id);

alter table "public"."patient_hospital_identifiers" add constraint "patient_hospital_identifiers_pkey" PRIMARY KEY (id);

alter table "public"."patient_representatives" add constraint "patient_representatives_pkey" PRIMARY KEY (id);

alter table "public"."patients" add constraint "patients_pkey" PRIMARY KEY (id);

alter table "public"."prescription_orders" add constraint "prescription_orders_pkey" PRIMARY KEY (id);

alter table "public"."prescriptions" add constraint "prescriptions_pkey" PRIMARY KEY (id);

alter table "public"."role_permissions" add constraint "role_permissions_pkey" PRIMARY KEY (id);

alter table "public"."roles" add constraint "roles_pkey" PRIMARY KEY (id);

alter table "public"."security_logs" add constraint "security_logs_pkey" PRIMARY KEY (id);

alter table "public"."system_settings" add constraint "system_settings_pkey" PRIMARY KEY (key);

alter table "public"."treatment_plans" add constraint "treatment_plans_pkey" PRIMARY KEY (id);

alter table "public"."users" add constraint "users_pkey" PRIMARY KEY (id);

alter table "public"."video_sessions" add constraint "video_sessions_pkey" PRIMARY KEY (id);

alter table "public"."ai_assessment_recommendations" add constraint "ai_assessment_recommendations_assessment_id_hospital_id_key" UNIQUE (assessment_id, hospital_id);

alter table "public"."ai_assessment_recommendations" add constraint "ai_assessment_recommendations_assessment_id_rank_key" UNIQUE (assessment_id, rank);

alter table "public"."ai_configurations" add constraint "ai_configurations_configuration_key_key" UNIQUE (configuration_key);

alter table "public"."chat_conversations" add constraint "chat_conversations_consultation_id_key" UNIQUE (consultation_id);

alter table "public"."chat_message_attachments" add constraint "chat_message_attachments_storage_path_key" UNIQUE (storage_path);

alter table "public"."clinical_record_quarantine" add constraint "clinical_record_quarantine_source_table_record_id_key" UNIQUE (source_table, record_id);

alter table "public"."consultation_attachments" add constraint "consultation_attachments_storage_path_key" UNIQUE (storage_path);

alter table "public"."doctor_hospital_employments" add constraint "doctor_hospital_employments_doctor_id_hospital_id_key" UNIQUE (doctor_id, hospital_id);

alter table "public"."doctor_patient_assignments" add constraint "doctor_patient_assignments_doctor_id_patient_id_assigned_at_key" UNIQUE (doctor_id, patient_id, assigned_at);

alter table "public"."doctor_schedules" add constraint "doctor_schedules_doctor_id_day_of_week_starts_at_consultati_key" UNIQUE (doctor_id, day_of_week, starts_at, consultation_type);

alter table "public"."doctors" add constraint "doctors_id_hospital_key" UNIQUE (id, hospital_id);

alter table "public"."doctors" add constraint "doctors_license_number_key" UNIQUE (license_number);

alter table "public"."doctors" add constraint "doctors_user_id_key" UNIQUE (user_id);

alter table "public"."emergency_room_status" add constraint "emergency_room_status_hospital_id_key" UNIQUE (hospital_id);

alter table "public"."guest_consultation_requests" add constraint "guest_consultation_requests_reference_number_key" UNIQUE (reference_number);

alter table "public"."healthcare_service_categories" add constraint "healthcare_service_categories_category_name_key" UNIQUE (category_name);

alter table "public"."hospital_beds" add constraint "hospital_beds_hospital_id_department_id_bed_type_key" UNIQUE (hospital_id, department_id, bed_type);

alter table "public"."hospital_classifications" add constraint "hospital_classifications_classification_name_key" UNIQUE (classification_name);

alter table "public"."hospital_departments" add constraint "hospital_departments_hospital_id_department_name_key" UNIQUE (hospital_id, department_name);

alter table "public"."hospital_facility_status" add constraint "hospital_facility_status_hospital_id_facility_type_key" UNIQUE (hospital_id, facility_type);

alter table "public"."hospital_rooms" add constraint "hospital_rooms_hospital_id_room_type_key" UNIQUE (hospital_id, room_type);

alter table "public"."hospital_service_doctors" add constraint "hospital_service_doctors_service_id_doctor_id_key" UNIQUE (service_id, doctor_id);

alter table "public"."hospital_services" add constraint "hospital_services_hospital_id_service_name_key" UNIQUE (hospital_id, service_name);

alter table "public"."hospital_services" add constraint "hospital_services_id_hospital_key" UNIQUE (id, hospital_id);

alter table "public"."hospitals" add constraint "hospitals_hospital_name_address_key" UNIQUE (hospital_name, address);

alter table "public"."medical_documents" add constraint "medical_documents_storage_bucket_storage_path_key" UNIQUE (storage_bucket, storage_path);

alter table "public"."notification_outbox" add constraint "notification_outbox_notification_id_channel_key" UNIQUE (notification_id, channel);

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_reference_number_key" UNIQUE (reference_number);

alter table "public"."patient_access_record_selections" add constraint "patient_access_record_selecti_grant_id_source_table_record__key" UNIQUE (grant_id, source_table, record_id);

alter table "public"."patient_access_scopes" add constraint "patient_access_scopes_grant_id_record_category_key" UNIQUE (grant_id, record_category);

alter table "public"."patient_consents" add constraint "patient_consents_patient_id_consent_type_consent_version_key" UNIQUE (patient_id, consent_type, consent_version);

alter table "public"."patient_hospital_identifiers" add constraint "patient_hospital_identifiers_hospital_id_local_mrn_key" UNIQUE (hospital_id, local_mrn);

alter table "public"."patient_hospital_identifiers" add constraint "patient_hospital_identifiers_patient_id_hospital_id_key" UNIQUE (patient_id, hospital_id);

alter table "public"."patient_representatives" add constraint "patient_representatives_patient_id_representative_user_id_a_key" UNIQUE (patient_id, representative_user_id, authority_type);

alter table "public"."patients" add constraint "patients_patient_number_key" UNIQUE (patient_number);

alter table "public"."patients" add constraint "patients_user_id_key" UNIQUE (user_id);

alter table "public"."prescription_orders" add constraint "prescription_orders_doctor_id_idempotency_key_key" UNIQUE (doctor_id, idempotency_key);

alter table "public"."role_permissions" add constraint "role_permissions_role_id_permission_key" UNIQUE (role_id, permission);

alter table "public"."roles" add constraint "roles_role_name_key" UNIQUE (role_name);

alter table "public"."users" add constraint "users_auth_user_id_key" UNIQUE (auth_user_id);

alter table "public"."video_sessions" add constraint "video_sessions_consultation_id_key" UNIQUE (consultation_id);

alter table "public"."video_sessions" add constraint "video_sessions_provider_room_name_key" UNIQUE (provider, room_name);

alter table "public"."ai_assessment_recommendations" add constraint "ai_assessment_recommendations_assessment_id_fkey" FOREIGN KEY (assessment_id) REFERENCES ai_assessments(id) ON DELETE CASCADE;

alter table "public"."ai_assessment_recommendations" add constraint "ai_assessment_recommendations_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE CASCADE;

alter table "public"."ai_assessments" add constraint "ai_assessments_guest_request_id_fkey" FOREIGN KEY (guest_request_id) REFERENCES guest_consultation_requests(id) ON DELETE CASCADE;

alter table "public"."ai_assessments" add constraint "ai_assessments_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE;

alter table "public"."ai_assessments" add constraint "ai_assessments_recommended_hospital_id_fkey" FOREIGN KEY (recommended_hospital_id) REFERENCES hospitals(id) ON DELETE SET NULL;

alter table "public"."ai_assessments" add constraint "ai_assessments_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

alter table "public"."ai_configurations" add constraint "ai_configurations_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL;

alter table "public"."appointment_reminder_jobs" add constraint "appointment_reminder_jobs_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id) ON DELETE CASCADE;

alter table "public"."audit_logs" add constraint "audit_logs_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE SET NULL;

alter table "public"."audit_logs" add constraint "audit_logs_user_id_fkey" FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE SET NULL;

alter table "public"."care_assistant_conversations" add constraint "care_assistant_conversations_user_id_fkey" FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

alter table "public"."chat_conversations" add constraint "chat_conversations_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id) ON DELETE CASCADE;

alter table "public"."chat_conversations" add constraint "chat_conversations_doctor_id_fkey" FOREIGN KEY (doctor_id) REFERENCES doctors(id) ON DELETE CASCADE;

alter table "public"."chat_conversations" add constraint "chat_conversations_guest_request_id_fkey" FOREIGN KEY (guest_request_id) REFERENCES guest_consultation_requests(id) ON DELETE CASCADE;

alter table "public"."chat_conversations" add constraint "chat_conversations_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE;

alter table "public"."chat_message_attachments" add constraint "chat_message_attachments_message_id_fkey" FOREIGN KEY (message_id) REFERENCES chat_messages(id) ON DELETE CASCADE;

alter table "public"."chat_message_attachments" add constraint "chat_message_attachments_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES auth.users(id) ON DELETE RESTRICT;

alter table "public"."chat_messages" add constraint "chat_messages_conversation_id_fkey" FOREIGN KEY (conversation_id) REFERENCES chat_conversations(id) ON DELETE CASCADE;

alter table "public"."chat_messages" add constraint "chat_messages_sender_id_fkey" FOREIGN KEY (sender_id) REFERENCES auth.users(id) ON DELETE RESTRICT;

alter table "public"."clinical_record_addenda" add constraint "clinical_record_addenda_author_doctor_id_fkey" FOREIGN KEY (author_doctor_id) REFERENCES doctors(id) ON DELETE RESTRICT;

alter table "public"."clinical_record_addenda" add constraint "clinical_record_addenda_author_user_id_fkey" FOREIGN KEY (author_user_id) REFERENCES users(id) ON DELETE RESTRICT;

alter table "public"."clinical_record_addenda" add constraint "clinical_record_addenda_originating_hospital_id_fkey" FOREIGN KEY (originating_hospital_id) REFERENCES hospitals(id) ON DELETE RESTRICT;

alter table "public"."clinical_record_addenda" add constraint "clinical_record_addenda_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE;

alter table "public"."clinical_record_addenda" add constraint "clinical_record_addenda_supersedes_addendum_id_fkey" FOREIGN KEY (supersedes_addendum_id) REFERENCES clinical_record_addenda(id) ON DELETE RESTRICT;

alter table "public"."clinical_record_quarantine" add constraint "clinical_record_quarantine_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE SET NULL;

alter table "public"."clinical_record_quarantine" add constraint "clinical_record_quarantine_resolved_by_fkey" FOREIGN KEY (resolved_by) REFERENCES users(id);

alter table "public"."consultation_attachments" add constraint "consultation_attachments_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id) ON DELETE CASCADE;

alter table "public"."consultation_attachments" add constraint "consultation_attachments_guest_request_id_fkey" FOREIGN KEY (guest_request_id) REFERENCES guest_consultation_requests(id) ON DELETE CASCADE;

alter table "public"."consultation_attachments" add constraint "consultation_attachments_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE;

alter table "public"."consultation_attachments" add constraint "consultation_attachments_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES auth.users(id) ON DELETE RESTRICT;

alter table "public"."consultation_status_history" add constraint "consultation_status_history_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES users(id) ON DELETE SET NULL;

alter table "public"."consultation_status_history" add constraint "consultation_status_history_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id) ON DELETE CASCADE;

alter table "public"."consultations" add constraint "consultations_approved_by_fkey" FOREIGN KEY (approved_by) REFERENCES users(id) ON DELETE SET NULL;

alter table "public"."consultations" add constraint "consultations_department_id_fkey" FOREIGN KEY (department_id) REFERENCES hospital_departments(id) ON DELETE SET NULL;

alter table "public"."consultations" add constraint "consultations_doctor_id_fkey" FOREIGN KEY (doctor_id) REFERENCES doctors(id) ON DELETE RESTRICT;

alter table "public"."consultations" add constraint "consultations_follow_up_of_fkey" FOREIGN KEY (follow_up_of) REFERENCES consultations(id) ON DELETE SET NULL;

alter table "public"."consultations" add constraint "consultations_guest_request_id_fkey" FOREIGN KEY (guest_request_id) REFERENCES guest_consultation_requests(id) ON DELETE RESTRICT;

alter table "public"."consultations" add constraint "consultations_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE RESTRICT;

alter table "public"."consultations" add constraint "consultations_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE RESTRICT;

alter table "public"."diagnoses" add constraint "diagnoses_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id) ON DELETE RESTRICT;

alter table "public"."diagnoses" add constraint "diagnoses_doctor_id_fkey" FOREIGN KEY (doctor_id) REFERENCES doctors(id) ON DELETE RESTRICT;

alter table "public"."diagnoses" add constraint "diagnoses_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE RESTRICT;

alter table "public"."diagnoses" add constraint "diagnoses_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE RESTRICT;

alter table "public"."doctor_hospital_employments" add constraint "doctor_hospital_employments_doctor_id_fkey" FOREIGN KEY (doctor_id) REFERENCES doctors(id) ON DELETE CASCADE;

alter table "public"."doctor_hospital_employments" add constraint "doctor_hospital_employments_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE CASCADE;

alter table "public"."doctor_hospital_employments" add constraint "doctor_hospital_employments_verified_by_fkey" FOREIGN KEY (verified_by) REFERENCES users(id);

alter table "public"."doctor_patient_assignments" add constraint "doctor_patient_assignments_care_relationship_id_fkey" FOREIGN KEY (care_relationship_id) REFERENCES patient_care_relationships(id) ON DELETE SET NULL;

alter table "public"."doctor_patient_assignments" add constraint "doctor_patient_assignments_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id);

alter table "public"."doctor_patient_assignments" add constraint "doctor_patient_assignments_doctor_id_fkey" FOREIGN KEY (doctor_id) REFERENCES doctors(id) ON DELETE CASCADE;

alter table "public"."doctor_patient_assignments" add constraint "doctor_patient_assignments_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id);

alter table "public"."doctor_patient_assignments" add constraint "doctor_patient_assignments_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE;

alter table "public"."doctor_schedules" add constraint "doctor_schedules_doctor_id_fkey" FOREIGN KEY (doctor_id) REFERENCES doctors(id) ON DELETE CASCADE;

alter table "public"."doctors" add constraint "doctors_created_by_admin_fkey" FOREIGN KEY (created_by_admin) REFERENCES users(id) ON DELETE SET NULL;

alter table "public"."doctors" add constraint "doctors_department_id_fkey" FOREIGN KEY (department_id) REFERENCES hospital_departments(id) ON DELETE SET NULL;

alter table "public"."doctors" add constraint "doctors_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE RESTRICT;

alter table "public"."doctors" add constraint "doctors_user_id_fkey" FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

alter table "public"."document_processing_jobs" add constraint "document_processing_jobs_laboratory_result_id_fkey" FOREIGN KEY (laboratory_result_id) REFERENCES laboratory_results(id) ON DELETE CASCADE;

alter table "public"."document_processing_jobs" add constraint "document_processing_jobs_medical_document_id_fkey" FOREIGN KEY (medical_document_id) REFERENCES medical_documents(id) ON DELETE CASCADE;

alter table "public"."document_processing_jobs" add constraint "document_processing_jobs_requested_by_fkey" FOREIGN KEY (requested_by) REFERENCES doctors(id) ON DELETE RESTRICT;

alter table "public"."emergency_access_events" add constraint "emergency_access_events_doctor_id_fkey" FOREIGN KEY (doctor_id) REFERENCES doctors(id) ON DELETE RESTRICT;

alter table "public"."emergency_access_events" add constraint "emergency_access_events_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE RESTRICT;

alter table "public"."emergency_access_events" add constraint "emergency_access_events_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE;

alter table "public"."emergency_access_events" add constraint "emergency_access_events_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES users(id);

alter table "public"."emergency_room_status" add constraint "emergency_room_status_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE CASCADE;

alter table "public"."emergency_room_status" add constraint "emergency_room_status_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL;

alter table "public"."guest_consultation_requests" add constraint "guest_consultation_requests_assigned_doctor_id_fkey" FOREIGN KEY (assigned_doctor_id) REFERENCES doctors(id) ON DELETE SET NULL;

alter table "public"."guest_consultation_requests" add constraint "guest_consultation_requests_preferred_department_id_fkey" FOREIGN KEY (preferred_department_id) REFERENCES hospital_departments(id) ON DELETE SET NULL;

alter table "public"."guest_consultation_requests" add constraint "guest_consultation_requests_preferred_hospital_id_fkey" FOREIGN KEY (preferred_hospital_id) REFERENCES hospitals(id) ON DELETE SET NULL;

alter table "public"."guest_consultation_requests" add constraint "guest_consultation_requests_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES users(id) ON DELETE SET NULL;

alter table "public"."guest_consultation_requests" add constraint "guest_consultation_requests_submitted_by_fkey" FOREIGN KEY (submitted_by) REFERENCES auth.users(id) ON DELETE SET NULL;

alter table "public"."guest_request_status_history" add constraint "guest_request_status_history_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES users(id) ON DELETE SET NULL;

alter table "public"."guest_request_status_history" add constraint "guest_request_status_history_request_id_fkey" FOREIGN KEY (request_id) REFERENCES guest_consultation_requests(id) ON DELETE CASCADE;

alter table "public"."hospital_announcements" add constraint "hospital_announcements_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;

alter table "public"."hospital_announcements" add constraint "hospital_announcements_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE CASCADE;

alter table "public"."hospital_beds" add constraint "hospital_beds_department_id_fkey" FOREIGN KEY (department_id) REFERENCES hospital_departments(id) ON DELETE SET NULL;

alter table "public"."hospital_beds" add constraint "hospital_beds_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE CASCADE;

alter table "public"."hospital_departments" add constraint "hospital_departments_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE CASCADE;

alter table "public"."hospital_facility_status" add constraint "hospital_facility_status_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE CASCADE;

alter table "public"."hospital_rooms" add constraint "hospital_rooms_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE CASCADE;

alter table "public"."hospital_service_doctors" add constraint "hospital_service_doctors_doctor_id_hospital_id_fkey" FOREIGN KEY (doctor_id, hospital_id) REFERENCES doctors(id, hospital_id) ON DELETE CASCADE;

alter table "public"."hospital_service_doctors" add constraint "hospital_service_doctors_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE CASCADE;

alter table "public"."hospital_service_doctors" add constraint "hospital_service_doctors_service_id_hospital_id_fkey" FOREIGN KEY (service_id, hospital_id) REFERENCES hospital_services(id, hospital_id) ON DELETE CASCADE;

alter table "public"."hospital_services" add constraint "hospital_services_category_id_fkey" FOREIGN KEY (category_id) REFERENCES healthcare_service_categories(id) ON DELETE SET NULL;

alter table "public"."hospital_services" add constraint "hospital_services_department_id_fkey" FOREIGN KEY (department_id) REFERENCES hospital_departments(id) ON DELETE SET NULL;

alter table "public"."hospital_services" add constraint "hospital_services_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE CASCADE;

alter table "public"."hospitals" add constraint "hospitals_classification_id_fkey" FOREIGN KEY (classification_id) REFERENCES hospital_classifications(id) ON DELETE SET NULL;

alter table "public"."hospitals" add constraint "hospitals_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE SET NULL;

alter table "public"."hospitals" add constraint "hospitals_verification_decided_by_fkey" FOREIGN KEY (verification_decided_by) REFERENCES users(id) ON DELETE SET NULL;

alter table "public"."laboratory_requests" add constraint "laboratory_requests_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id) ON DELETE SET NULL;

alter table "public"."laboratory_requests" add constraint "laboratory_requests_doctor_id_fkey" FOREIGN KEY (doctor_id) REFERENCES doctors(id) ON DELETE RESTRICT;

alter table "public"."laboratory_requests" add constraint "laboratory_requests_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE RESTRICT;

alter table "public"."laboratory_requests" add constraint "laboratory_requests_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE RESTRICT;

alter table "public"."laboratory_results" add constraint "laboratory_results_confirmed_by_fkey" FOREIGN KEY (confirmed_by) REFERENCES doctors(id) ON DELETE SET NULL;

alter table "public"."laboratory_results" add constraint "laboratory_results_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id) ON DELETE SET NULL;

alter table "public"."laboratory_results" add constraint "laboratory_results_doctor_id_fkey" FOREIGN KEY (doctor_id) REFERENCES doctors(id) ON DELETE RESTRICT;

alter table "public"."laboratory_results" add constraint "laboratory_results_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE RESTRICT;

alter table "public"."laboratory_results" add constraint "laboratory_results_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE RESTRICT;

alter table "public"."laboratory_results" add constraint "laboratory_results_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES doctors(id) ON DELETE SET NULL;

alter table "public"."laboratory_results" add constraint "laboratory_results_source_document_id_fkey" FOREIGN KEY (source_document_id) REFERENCES medical_documents(id) ON DELETE SET NULL;

alter table "public"."maintenance_windows" add constraint "maintenance_windows_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(id) ON DELETE SET NULL;

alter table "public"."medical_documents" add constraint "medical_documents_author_doctor_id_fkey" FOREIGN KEY (author_doctor_id) REFERENCES doctors(id);

alter table "public"."medical_documents" add constraint "medical_documents_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id) ON DELETE SET NULL;

alter table "public"."medical_documents" add constraint "medical_documents_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE SET NULL;

alter table "public"."medical_documents" add constraint "medical_documents_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE;

alter table "public"."medical_documents" add constraint "medical_documents_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES users(id);

alter table "public"."medical_documents" add constraint "medical_documents_uploaded_by_fkey" FOREIGN KEY (uploaded_by) REFERENCES users(id) ON DELETE RESTRICT;

alter table "public"."medical_record_access_logs" add constraint "medical_record_access_logs_actor_user_id_fkey" FOREIGN KEY (actor_user_id) REFERENCES users(id) ON DELETE SET NULL;

alter table "public"."medical_record_access_logs" add constraint "medical_record_access_logs_care_relationship_id_fkey" FOREIGN KEY (care_relationship_id) REFERENCES patient_care_relationships(id);

alter table "public"."medical_record_access_logs" add constraint "medical_record_access_logs_grant_id_fkey" FOREIGN KEY (grant_id) REFERENCES patient_access_grants(id);

alter table "public"."medical_record_access_logs" add constraint "medical_record_access_logs_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE;

alter table "public"."medical_record_access_logs" add constraint "medical_record_access_logs_receiving_hospital_id_fkey" FOREIGN KEY (receiving_hospital_id) REFERENCES hospitals(id);

alter table "public"."medical_record_access_logs" add constraint "medical_record_access_logs_source_hospital_id_fkey" FOREIGN KEY (source_hospital_id) REFERENCES hospitals(id);

alter table "public"."medical_records" add constraint "medical_records_confirmed_by_fkey" FOREIGN KEY (confirmed_by) REFERENCES doctors(id) ON DELETE SET NULL;

alter table "public"."medical_records" add constraint "medical_records_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id) ON DELETE SET NULL;

alter table "public"."medical_records" add constraint "medical_records_doctor_id_fkey" FOREIGN KEY (doctor_id) REFERENCES doctors(id) ON DELETE RESTRICT;

alter table "public"."medical_records" add constraint "medical_records_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE RESTRICT;

alter table "public"."medical_records" add constraint "medical_records_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE RESTRICT;

alter table "public"."medical_records" add constraint "medical_records_source_document_id_fkey" FOREIGN KEY (source_document_id) REFERENCES medical_documents(id);

alter table "public"."medical_records" add constraint "medical_records_source_laboratory_result_id_fkey" FOREIGN KEY (source_laboratory_result_id) REFERENCES laboratory_results(id) ON DELETE SET NULL;

alter table "public"."medication_summary_days" add constraint "medication_summary_days_notification_id_fkey" FOREIGN KEY (notification_id) REFERENCES notifications(id);

alter table "public"."medication_summary_days" add constraint "medication_summary_days_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id);

alter table "public"."notification_outbox" add constraint "notification_outbox_notification_id_fkey" FOREIGN KEY (notification_id) REFERENCES notifications(id) ON DELETE CASCADE;

alter table "public"."notification_outbox" add constraint "notification_outbox_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table "public"."notification_preferences" add constraint "notification_preferences_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table "public"."notifications" add constraint "notifications_guest_request_id_fkey" FOREIGN KEY (guest_request_id) REFERENCES guest_consultation_requests(id) ON DELETE CASCADE;

alter table "public"."notifications" add constraint "notifications_user_id_fkey" FOREIGN KEY (user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table "public"."online_consultation_request_status_history" add constraint "online_consultation_request_status_history_changed_by_fkey" FOREIGN KEY (changed_by) REFERENCES users(id);

alter table "public"."online_consultation_request_status_history" add constraint "online_consultation_request_status_history_request_id_fkey" FOREIGN KEY (request_id) REFERENCES online_consultation_requests(id) ON DELETE CASCADE;

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_assigned_doctor_id_fkey" FOREIGN KEY (assigned_doctor_id) REFERENCES doctors(id) ON DELETE SET NULL;

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_care_relationship_id_fkey" FOREIGN KEY (care_relationship_id) REFERENCES patient_care_relationships(id) ON DELETE RESTRICT;

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_consent_id_fkey" FOREIGN KEY (consent_id) REFERENCES patient_consents(id) ON DELETE RESTRICT;

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE RESTRICT;

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_official_consultation_id_fkey" FOREIGN KEY (official_consultation_id) REFERENCES consultations(id) ON DELETE SET NULL;

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE RESTRICT;

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_requested_department_id_fkey" FOREIGN KEY (requested_department_id) REFERENCES hospital_departments(id) ON DELETE RESTRICT;

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_requested_doctor_id_fkey" FOREIGN KEY (requested_doctor_id) REFERENCES doctors(id) ON DELETE SET NULL;

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_reviewed_by_fkey" FOREIGN KEY (reviewed_by) REFERENCES users(id);

alter table "public"."online_consultation_requests" add constraint "online_consultation_requests_submitted_by_fkey" FOREIGN KEY (submitted_by) REFERENCES users(id) ON DELETE RESTRICT;

alter table "public"."patient_access_grants" add constraint "patient_access_grants_care_relationship_id_fkey" FOREIGN KEY (care_relationship_id) REFERENCES patient_care_relationships(id) ON DELETE CASCADE;

alter table "public"."patient_access_grants" add constraint "patient_access_grants_consent_id_fkey" FOREIGN KEY (consent_id) REFERENCES patient_consents(id) ON DELETE RESTRICT;

alter table "public"."patient_access_grants" add constraint "patient_access_grants_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id) ON DELETE SET NULL;

alter table "public"."patient_access_grants" add constraint "patient_access_grants_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE;

alter table "public"."patient_access_grants" add constraint "patient_access_grants_receiving_doctor_id_fkey" FOREIGN KEY (receiving_doctor_id) REFERENCES doctors(id) ON DELETE RESTRICT;

alter table "public"."patient_access_grants" add constraint "patient_access_grants_receiving_hospital_id_fkey" FOREIGN KEY (receiving_hospital_id) REFERENCES hospitals(id) ON DELETE RESTRICT;

alter table "public"."patient_access_grants" add constraint "patient_access_grants_revoked_by_fkey" FOREIGN KEY (revoked_by) REFERENCES users(id);

alter table "public"."patient_access_grants" add constraint "patient_access_grants_source_hospital_id_fkey" FOREIGN KEY (source_hospital_id) REFERENCES hospitals(id) ON DELETE RESTRICT;

alter table "public"."patient_access_record_selections" add constraint "patient_access_record_selections_grant_id_fkey" FOREIGN KEY (grant_id) REFERENCES patient_access_grants(id) ON DELETE CASCADE;

alter table "public"."patient_access_scopes" add constraint "patient_access_scopes_grant_id_fkey" FOREIGN KEY (grant_id) REFERENCES patient_access_grants(id) ON DELETE CASCADE;

alter table "public"."patient_care_relationships" add constraint "patient_care_relationships_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id) ON DELETE SET NULL;

alter table "public"."patient_care_relationships" add constraint "patient_care_relationships_created_by_fkey" FOREIGN KEY (created_by) REFERENCES users(id);

alter table "public"."patient_care_relationships" add constraint "patient_care_relationships_doctor_id_fkey" FOREIGN KEY (doctor_id) REFERENCES doctors(id) ON DELETE SET NULL;

alter table "public"."patient_care_relationships" add constraint "patient_care_relationships_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE CASCADE;

alter table "public"."patient_care_relationships" add constraint "patient_care_relationships_online_request_id_fkey" FOREIGN KEY (online_request_id) REFERENCES online_consultation_requests(id);

alter table "public"."patient_care_relationships" add constraint "patient_care_relationships_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE;

alter table "public"."patient_connection_requests" add constraint "patient_connection_requests_doctor_id_fkey" FOREIGN KEY (doctor_id) REFERENCES doctors(id) ON DELETE CASCADE;

alter table "public"."patient_connection_requests" add constraint "patient_connection_requests_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE CASCADE;

alter table "public"."patient_connection_requests" add constraint "patient_connection_requests_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE;

alter table "public"."patient_connection_requests" add constraint "patient_connection_requests_requested_by_fkey" FOREIGN KEY (requested_by) REFERENCES users(id) ON DELETE RESTRICT;

alter table "public"."patient_consents" add constraint "patient_consents_captured_by_fkey" FOREIGN KEY (captured_by) REFERENCES auth.users(id) ON DELETE RESTRICT;

alter table "public"."patient_consents" add constraint "patient_consents_care_relationship_id_fkey" FOREIGN KEY (care_relationship_id) REFERENCES patient_care_relationships(id) ON DELETE SET NULL;

alter table "public"."patient_consents" add constraint "patient_consents_granted_by_fkey" FOREIGN KEY (granted_by) REFERENCES users(id);

alter table "public"."patient_consents" add constraint "patient_consents_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE;

alter table "public"."patient_consents" add constraint "patient_consents_receiving_hospital_id_fkey" FOREIGN KEY (receiving_hospital_id) REFERENCES hospitals(id) ON DELETE RESTRICT;

alter table "public"."patient_consents" add constraint "patient_consents_replaces_consent_id_fkey" FOREIGN KEY (replaces_consent_id) REFERENCES patient_consents(id) ON DELETE SET NULL;

alter table "public"."patient_consents" add constraint "patient_consents_source_hospital_id_fkey" FOREIGN KEY (source_hospital_id) REFERENCES hospitals(id) ON DELETE RESTRICT;

alter table "public"."patient_hospital_identifiers" add constraint "patient_hospital_identifiers_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE CASCADE;

alter table "public"."patient_hospital_identifiers" add constraint "patient_hospital_identifiers_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE;

alter table "public"."patient_representatives" add constraint "patient_representatives_evidence_document_id_fkey" FOREIGN KEY (evidence_document_id) REFERENCES medical_documents(id) ON DELETE SET NULL;

alter table "public"."patient_representatives" add constraint "patient_representatives_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE CASCADE;

alter table "public"."patient_representatives" add constraint "patient_representatives_representative_user_id_fkey" FOREIGN KEY (representative_user_id) REFERENCES users(id) ON DELETE CASCADE;

alter table "public"."patient_representatives" add constraint "patient_representatives_verified_by_fkey" FOREIGN KEY (verified_by) REFERENCES users(id);

alter table "public"."patients" add constraint "patients_created_by_doctor_fkey" FOREIGN KEY (created_by_doctor) REFERENCES doctors(id) ON DELETE SET NULL;

alter table "public"."patients" add constraint "patients_guest_request_id_fkey" FOREIGN KEY (guest_request_id) REFERENCES guest_consultation_requests(id) ON DELETE SET NULL;

alter table "public"."patients" add constraint "patients_primary_hospital_id_fkey" FOREIGN KEY (primary_hospital_id) REFERENCES hospitals(id) ON DELETE SET NULL;

alter table "public"."patients" add constraint "patients_user_id_fkey" FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE;

alter table "public"."prescription_orders" add constraint "prescription_orders_assignment_id_fkey" FOREIGN KEY (assignment_id) REFERENCES doctor_patient_assignments(id);

alter table "public"."prescription_orders" add constraint "prescription_orders_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id);

alter table "public"."prescription_orders" add constraint "prescription_orders_doctor_id_fkey" FOREIGN KEY (doctor_id) REFERENCES doctors(id);

alter table "public"."prescription_orders" add constraint "prescription_orders_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id);

alter table "public"."prescription_orders" add constraint "prescription_orders_issued_by_fkey" FOREIGN KEY (issued_by) REFERENCES users(id);

alter table "public"."prescription_orders" add constraint "prescription_orders_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id);

alter table "public"."prescriptions" add constraint "prescriptions_assignment_id_fkey" FOREIGN KEY (assignment_id) REFERENCES doctor_patient_assignments(id) ON DELETE RESTRICT;

alter table "public"."prescriptions" add constraint "prescriptions_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id) ON DELETE RESTRICT;

alter table "public"."prescriptions" add constraint "prescriptions_doctor_id_fkey" FOREIGN KEY (doctor_id) REFERENCES doctors(id) ON DELETE RESTRICT;

alter table "public"."prescriptions" add constraint "prescriptions_electronically_signed_by_fkey" FOREIGN KEY (electronically_signed_by) REFERENCES users(id);

alter table "public"."prescriptions" add constraint "prescriptions_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE RESTRICT;

alter table "public"."prescriptions" add constraint "prescriptions_order_id_fkey" FOREIGN KEY (order_id) REFERENCES prescription_orders(id);

alter table "public"."prescriptions" add constraint "prescriptions_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE RESTRICT;

alter table "public"."role_permissions" add constraint "role_permissions_role_id_fkey" FOREIGN KEY (role_id) REFERENCES roles(id) ON DELETE CASCADE;

alter table "public"."security_logs" add constraint "security_logs_actor_auth_user_id_fkey" FOREIGN KEY (actor_auth_user_id) REFERENCES auth.users(id) ON DELETE SET NULL;

alter table "public"."system_settings" add constraint "system_settings_updated_by_fkey" FOREIGN KEY (updated_by) REFERENCES users(id) ON DELETE SET NULL;

alter table "public"."treatment_plans" add constraint "treatment_plans_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id) ON DELETE RESTRICT;

alter table "public"."treatment_plans" add constraint "treatment_plans_doctor_id_fkey" FOREIGN KEY (doctor_id) REFERENCES doctors(id) ON DELETE RESTRICT;

alter table "public"."treatment_plans" add constraint "treatment_plans_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE RESTRICT;

alter table "public"."treatment_plans" add constraint "treatment_plans_patient_id_fkey" FOREIGN KEY (patient_id) REFERENCES patients(id) ON DELETE RESTRICT;

alter table "public"."users" add constraint "users_auth_user_id_fkey" FOREIGN KEY (auth_user_id) REFERENCES auth.users(id) ON DELETE CASCADE;

alter table "public"."users" add constraint "users_hospital_id_fkey" FOREIGN KEY (hospital_id) REFERENCES hospitals(id) ON DELETE SET NULL;

alter table "public"."users" add constraint "users_role_id_fkey" FOREIGN KEY (role_id) REFERENCES roles(id);

alter table "public"."video_sessions" add constraint "video_sessions_consultation_id_fkey" FOREIGN KEY (consultation_id) REFERENCES consultations(id) ON DELETE CASCADE;

alter table "public"."video_sessions" add constraint "video_sessions_created_by_fkey" FOREIGN KEY (created_by) REFERENCES auth.users(id) ON DELETE RESTRICT;

CREATE INDEX ai_assessment_recommendations_hospital_idx ON public.ai_assessment_recommendations USING btree (hospital_id);

CREATE INDEX ai_assessments_guest_request_idx ON public.ai_assessments USING btree (guest_request_id) WHERE (guest_request_id IS NOT NULL);

CREATE INDEX ai_assessments_patient_idx ON public.ai_assessments USING btree (patient_id, created_at DESC) WHERE (patient_id IS NOT NULL);

CREATE INDEX ai_assessments_recommended_hospital_idx ON public.ai_assessments USING btree (recommended_hospital_id) WHERE (recommended_hospital_id IS NOT NULL);

CREATE INDEX ai_assessments_user_idx ON public.ai_assessments USING btree (user_id, created_at DESC) WHERE (user_id IS NOT NULL);

CREATE INDEX ai_configurations_active_idx ON public.ai_configurations USING btree (purpose, is_active);

CREATE INDEX ai_configurations_updated_by_idx ON public.ai_configurations USING btree (updated_by);

CREATE INDEX announcements_active_idx ON public.hospital_announcements USING btree (hospital_id, published_at DESC);

CREATE INDEX announcements_created_by_idx ON public.hospital_announcements USING btree (created_by) WHERE (created_by IS NOT NULL);

CREATE INDEX assessment_recommendations_assessment_idx ON public.ai_assessment_recommendations USING btree (assessment_id, rank);

CREATE INDEX assignments_patient_active_idx ON public.doctor_patient_assignments USING btree (patient_id, doctor_id) WHERE (ended_at IS NULL);

CREATE INDEX audit_logs_hospital_created_idx ON public.audit_logs USING btree (hospital_id, created_at DESC);

CREATE INDEX audit_logs_user_created_idx ON public.audit_logs USING btree (user_id, created_at DESC);

CREATE INDEX beds_department_idx ON public.hospital_beds USING btree (department_id) WHERE (department_id IS NOT NULL);

CREATE INDEX beds_hospital_idx ON public.hospital_beds USING btree (hospital_id);

CREATE INDEX care_assistant_conversations_user_history_idx ON public.care_assistant_conversations USING btree (user_id, is_pinned DESC, updated_at DESC);

CREATE INDEX care_relationships_actor_idx ON public.patient_care_relationships USING btree (patient_id, hospital_id, doctor_id, status, expires_at);

CREATE INDEX care_relationships_consultation_idx ON public.patient_care_relationships USING btree (consultation_id) WHERE (consultation_id IS NOT NULL);

CREATE INDEX care_relationships_online_request_idx ON public.patient_care_relationships USING btree (online_request_id) WHERE (online_request_id IS NOT NULL);

CREATE INDEX chat_attachments_message_idx ON public.chat_message_attachments USING btree (message_id, created_at);

CREATE INDEX chat_conversations_doctor_idx ON public.chat_conversations USING btree (doctor_id);

CREATE INDEX chat_conversations_guest_request_idx ON public.chat_conversations USING btree (guest_request_id) WHERE (guest_request_id IS NOT NULL);

CREATE INDEX chat_conversations_patient_idx ON public.chat_conversations USING btree (patient_id) WHERE (patient_id IS NOT NULL);

CREATE INDEX chat_conversations_relationship_idx ON public.chat_conversations USING btree (doctor_id, patient_id, updated_at DESC);

CREATE INDEX chat_message_attachments_uploaded_by_idx ON public.chat_message_attachments USING btree (uploaded_by);

CREATE INDEX chat_messages_conversation_idx ON public.chat_messages USING btree (conversation_id, sent_at);

CREATE INDEX chat_messages_sender_idx ON public.chat_messages USING btree (sender_id, sent_at DESC);

CREATE INDEX clinical_addenda_record_idx ON public.clinical_record_addenda USING btree (source_table, record_id, created_at);

CREATE INDEX consultation_attachments_consultation_idx ON public.consultation_attachments USING btree (consultation_id, created_at);

CREATE INDEX consultation_attachments_guest_request_idx ON public.consultation_attachments USING btree (guest_request_id);

CREATE INDEX consultation_attachments_patient_idx ON public.consultation_attachments USING btree (patient_id);

CREATE INDEX consultation_attachments_uploaded_by_idx ON public.consultation_attachments USING btree (uploaded_by);

CREATE INDEX consultation_status_history_changed_by_idx ON public.consultation_status_history USING btree (changed_by);

CREATE INDEX consultation_status_history_consultation_idx ON public.consultation_status_history USING btree (consultation_id, created_at);

CREATE INDEX consultations_approved_by_idx ON public.consultations USING btree (approved_by);

CREATE INDEX consultations_department_idx ON public.consultations USING btree (department_id);

CREATE INDEX consultations_doctor_idx ON public.consultations USING btree (doctor_id, appointment_date DESC);

CREATE INDEX consultations_follow_up_of_idx ON public.consultations USING btree (follow_up_of);

CREATE INDEX consultations_guest_request_idx ON public.consultations USING btree (guest_request_id, appointment_date DESC) WHERE (guest_request_id IS NOT NULL);

CREATE INDEX consultations_hospital_status_idx ON public.consultations USING btree (hospital_id, status, appointment_date);

CREATE INDEX consultations_patient_idx ON public.consultations USING btree (patient_id, appointment_date DESC) WHERE (patient_id IS NOT NULL);

CREATE INDEX consultations_upcoming_reminders_idx ON public.consultations USING btree (appointment_date, id) WHERE (status = ANY (ARRAY['approved'::consultation_status, 'scheduled'::consultation_status]));

CREATE INDEX departments_hospital_idx ON public.hospital_departments USING btree (hospital_id, availability_status);

CREATE INDEX diagnoses_doctor_idx ON public.diagnoses USING btree (doctor_id);

CREATE INDEX diagnoses_hospital_idx ON public.diagnoses USING btree (hospital_id);

CREATE INDEX diagnoses_patient_idx ON public.diagnoses USING btree (patient_id, confirmed_at DESC);

CREATE INDEX doctor_employments_actor_idx ON public.doctor_hospital_employments USING btree (doctor_id, hospital_id, employment_status, ends_at);

CREATE INDEX doctor_schedules_lookup_idx ON public.doctor_schedules USING btree (doctor_id, day_of_week, is_active);

CREATE INDEX doctors_created_by_admin_idx ON public.doctors USING btree (created_by_admin) WHERE (created_by_admin IS NOT NULL);

CREATE INDEX doctors_department_idx ON public.doctors USING btree (department_id) WHERE (department_id IS NOT NULL);

CREATE INDEX doctors_hospital_status_idx ON public.doctors USING btree (hospital_id, availability_status);

CREATE INDEX document_jobs_laboratory_result_idx ON public.document_processing_jobs USING btree (laboratory_result_id);

CREATE INDEX document_jobs_medical_document_idx ON public.document_processing_jobs USING btree (medical_document_id);

CREATE INDEX document_jobs_queue_idx ON public.document_processing_jobs USING btree (status, created_at) WHERE (status = ANY (ARRAY['queued'::text, 'ocr_processing'::text, 'ai_analysis_pending'::text, 'failed'::text]));

CREATE INDEX document_jobs_requested_by_idx ON public.document_processing_jobs USING btree (requested_by);

CREATE INDEX emergency_access_actor_idx ON public.emergency_access_events USING btree (patient_id, doctor_id, hospital_id, status, expires_at);

CREATE INDEX facility_status_hospital_idx ON public.hospital_facility_status USING btree (hospital_id, facility_type);

CREATE INDEX guest_request_history_changed_by_idx ON public.guest_request_status_history USING btree (changed_by);

CREATE INDEX guest_requests_department_idx ON public.guest_consultation_requests USING btree (preferred_department_id) WHERE (preferred_department_id IS NOT NULL);

CREATE INDEX guest_requests_doctor_idx ON public.guest_consultation_requests USING btree (assigned_doctor_id, request_status) WHERE (assigned_doctor_id IS NOT NULL);

CREATE INDEX guest_requests_review_idx ON public.guest_consultation_requests USING btree (preferred_hospital_id, request_status, created_at);

CREATE INDEX guest_requests_reviewed_by_idx ON public.guest_consultation_requests USING btree (reviewed_by);

CREATE INDEX guest_requests_submitter_idx ON public.guest_consultation_requests USING btree (submitted_by, created_at DESC);

CREATE INDEX guest_status_history_request_idx ON public.guest_request_status_history USING btree (request_id, created_at);

CREATE INDEX healthcare_service_categories_directory_idx ON public.healthcare_service_categories USING btree (is_active, display_order, category_name);

CREATE INDEX hospital_service_doctors_doctor_hospital_idx ON public.hospital_service_doctors USING btree (doctor_id, hospital_id);

CREATE INDEX hospital_service_doctors_doctor_idx ON public.hospital_service_doctors USING btree (doctor_id, service_id);

CREATE INDEX hospital_service_doctors_hospital_idx ON public.hospital_service_doctors USING btree (hospital_id, service_id);

CREATE INDEX hospital_service_doctors_service_hospital_idx ON public.hospital_service_doctors USING btree (service_id, hospital_id);

CREATE INDEX hospital_services_category_idx ON public.hospital_services USING btree (category_id, availability_status) WHERE (category_id IS NOT NULL);

CREATE INDEX hospital_services_tags_gin_idx ON public.hospital_services USING gin (tags);

CREATE INDEX hospitals_classification_idx ON public.hospitals USING btree (classification_id);

CREATE INDEX hospitals_coordinates_idx ON public.hospitals USING btree (latitude, longitude) WHERE ((latitude IS NOT NULL) AND (longitude IS NOT NULL));

CREATE INDEX hospitals_created_by_idx ON public.hospitals USING btree (created_by) WHERE (created_by IS NOT NULL);

CREATE INDEX hospitals_public_directory_idx ON public.hospitals USING btree (verification_status, operating_status, province, city);

CREATE INDEX laboratory_requests_consultation_idx ON public.laboratory_requests USING btree (consultation_id);

CREATE INDEX laboratory_requests_doctor_status_idx ON public.laboratory_requests USING btree (doctor_id, status, due_at);

CREATE INDEX laboratory_requests_hospital_idx ON public.laboratory_requests USING btree (hospital_id);

CREATE INDEX laboratory_requests_patient_idx ON public.laboratory_requests USING btree (patient_id, requested_at DESC);

CREATE INDEX laboratory_results_confirmed_by_idx ON public.laboratory_results USING btree (confirmed_by);

CREATE INDEX laboratory_results_consultation_idx ON public.laboratory_results USING btree (consultation_id) WHERE (consultation_id IS NOT NULL);

CREATE INDEX laboratory_results_hospital_idx ON public.laboratory_results USING btree (hospital_id, uploaded_at DESC);

CREATE INDEX laboratory_results_patient_idx ON public.laboratory_results USING btree (patient_id, uploaded_at DESC);

CREATE INDEX laboratory_results_reviewed_by_idx ON public.laboratory_results USING btree (reviewed_by);

CREATE INDEX laboratory_results_source_document_idx ON public.laboratory_results USING btree (source_document_id);

CREATE INDEX laboratory_results_status_idx ON public.laboratory_results USING btree (doctor_id, verification_status, uploaded_at);

CREATE INDEX maintenance_windows_active_idx ON public.maintenance_windows USING btree (is_active, starts_at, ends_at);

CREATE INDEX maintenance_windows_created_by_idx ON public.maintenance_windows USING btree (created_by);

CREATE INDEX medical_access_logs_actor_idx ON public.medical_record_access_logs USING btree (actor_user_id, created_at DESC);

CREATE INDEX medical_access_logs_patient_idx ON public.medical_record_access_logs USING btree (patient_id, created_at DESC);

CREATE INDEX medical_access_logs_resource_idx ON public.medical_record_access_logs USING btree (resource_type, resource_id, created_at DESC);

CREATE INDEX medical_documents_consultation_idx ON public.medical_documents USING btree (consultation_id);

CREATE INDEX medical_documents_hospital_idx ON public.medical_documents USING btree (hospital_id);

CREATE INDEX medical_documents_patient_idx ON public.medical_documents USING btree (patient_id, created_at DESC);

CREATE INDEX medical_documents_reference_idx ON public.medical_documents USING btree (reference_id, reference_type);

CREATE INDEX medical_documents_uploaded_by_idx ON public.medical_documents USING btree (uploaded_by);

CREATE INDEX medical_records_confirmed_by_idx ON public.medical_records USING btree (confirmed_by);

CREATE INDEX medical_records_consultation_idx ON public.medical_records USING btree (consultation_id) WHERE (consultation_id IS NOT NULL);

CREATE INDEX medical_records_doctor_idx ON public.medical_records USING btree (doctor_id, record_date DESC);

CREATE INDEX medical_records_hospital_idx ON public.medical_records USING btree (hospital_id, record_date DESC);

CREATE INDEX medical_records_patient_date_idx ON public.medical_records USING btree (patient_id, record_date DESC);

CREATE INDEX medical_records_source_result_idx ON public.medical_records USING btree (source_laboratory_result_id);

CREATE INDEX notification_outbox_delivery_idx ON public.notification_outbox USING btree (status, next_attempt_at) WHERE (status = ANY (ARRAY['pending'::text, 'failed'::text]));

CREATE INDEX notification_outbox_user_idx ON public.notification_outbox USING btree (user_id);

CREATE INDEX notifications_guest_request_idx ON public.notifications USING btree (guest_request_id, created_at DESC) WHERE (guest_request_id IS NOT NULL);

CREATE INDEX notifications_unread_idx ON public.notifications USING btree (user_id, created_at DESC) WHERE (NOT is_read);

CREATE INDEX online_request_history_idx ON public.online_consultation_request_status_history USING btree (request_id, created_at);

CREATE INDEX online_requests_doctor_queue_idx ON public.online_consultation_requests USING btree (assigned_doctor_id, request_status, confirmed_schedule);

CREATE INDEX online_requests_hospital_queue_idx ON public.online_consultation_requests USING btree (hospital_id, request_status, created_at);

CREATE INDEX online_requests_patient_idx ON public.online_consultation_requests USING btree (patient_id, created_at DESC);

CREATE INDEX patient_access_grants_actor_idx ON public.patient_access_grants USING btree (patient_id, receiving_doctor_id, receiving_hospital_id, status, expires_at);

CREATE INDEX patient_access_grants_source_idx ON public.patient_access_grants USING btree (patient_id, source_hospital_id, status, expires_at);

CREATE INDEX patient_access_record_selection_idx ON public.patient_access_record_selections USING btree (grant_id, record_category, record_id);

CREATE INDEX patient_access_scopes_category_idx ON public.patient_access_scopes USING btree (grant_id, record_category);

CREATE INDEX patient_connection_requests_hospital_queue_idx ON public.patient_connection_requests USING btree (hospital_id, status, requested_at DESC);

CREATE INDEX patient_connection_requests_patient_queue_idx ON public.patient_connection_requests USING btree (patient_id, status, requested_at DESC);

CREATE INDEX patient_connection_requests_requester_idx ON public.patient_connection_requests USING btree (requested_by);

CREATE INDEX patient_consents_access_idx ON public.patient_consents USING btree (patient_id, receiving_hospital_id, care_relationship_id, expires_at) WHERE (is_granted AND (revoked_at IS NULL));

CREATE INDEX patient_consents_captured_by_idx ON public.patient_consents USING btree (captured_by);

CREATE INDEX patient_consents_patient_idx ON public.patient_consents USING btree (patient_id, consent_type);

CREATE INDEX patient_identifiers_patient_idx ON public.patient_hospital_identifiers USING btree (patient_id, status);

CREATE INDEX patients_created_by_idx ON public.patients USING btree (created_by_doctor) WHERE (created_by_doctor IS NOT NULL);

CREATE INDEX patients_guest_request_idx ON public.patients USING btree (guest_request_id) WHERE (guest_request_id IS NOT NULL);

CREATE INDEX patients_primary_hospital_idx ON public.patients USING btree (primary_hospital_id);

CREATE INDEX prescriptions_assignment_idx ON public.prescriptions USING btree (assignment_id) WHERE (assignment_id IS NOT NULL);

CREATE INDEX prescriptions_consultation_idx ON public.prescriptions USING btree (consultation_id);

CREATE INDEX prescriptions_doctor_idx ON public.prescriptions USING btree (doctor_id, created_at DESC);

CREATE INDEX prescriptions_hospital_idx ON public.prescriptions USING btree (hospital_id);

CREATE INDEX prescriptions_order_idx ON public.prescriptions USING btree (order_id);

CREATE INDEX prescriptions_patient_idx ON public.prescriptions USING btree (patient_id, created_at DESC);

CREATE INDEX role_permissions_role_idx ON public.role_permissions USING btree (role_id, is_allowed);

CREATE INDEX rooms_hospital_idx ON public.hospital_rooms USING btree (hospital_id, status);

CREATE INDEX security_logs_actor_idx ON public.security_logs USING btree (actor_auth_user_id);

CREATE INDEX security_logs_event_idx ON public.security_logs USING btree (severity, event_type, created_at DESC);

CREATE INDEX services_department_idx ON public.hospital_services USING btree (department_id) WHERE (department_id IS NOT NULL);

CREATE INDEX services_hospital_idx ON public.hospital_services USING btree (hospital_id, availability_status);

CREATE INDEX system_settings_public_idx ON public.system_settings USING btree (is_public, key);

CREATE INDEX system_settings_updated_by_idx ON public.system_settings USING btree (updated_by);

CREATE INDEX treatment_plans_consultation_idx ON public.treatment_plans USING btree (consultation_id);

CREATE INDEX treatment_plans_doctor_idx ON public.treatment_plans USING btree (doctor_id);

CREATE INDEX treatment_plans_hospital_idx ON public.treatment_plans USING btree (hospital_id);

CREATE INDEX treatment_plans_patient_idx ON public.treatment_plans USING btree (patient_id, created_at DESC);

CREATE INDEX users_hospital_idx ON public.users USING btree (hospital_id) WHERE (hospital_id IS NOT NULL);

CREATE INDEX users_role_idx ON public.users USING btree (role_id);

CREATE INDEX video_sessions_created_by_idx ON public.video_sessions USING btree (created_by);

CREATE INDEX video_sessions_status_starts_idx ON public.video_sessions USING btree (status, starts_at);

CREATE UNIQUE INDEX chat_conversations_direct_relationship_uidx ON public.chat_conversations USING btree (doctor_id, patient_id) WHERE (consultation_id IS NULL);

CREATE UNIQUE INDEX consultations_id_patient_hospital_key ON public.consultations USING btree (id, patient_id, hospital_id);

CREATE UNIQUE INDEX consultations_one_active_start_idx ON public.consultations USING btree (doctor_id, appointment_date) WHERE (status <> ALL (ARRAY['rejected'::consultation_status, 'cancelled'::consultation_status]));

CREATE UNIQUE INDEX departments_id_hospital_key ON public.hospital_departments USING btree (id, hospital_id);

CREATE UNIQUE INDEX diagnoses_one_primary_idx ON public.diagnoses USING btree (consultation_id) WHERE is_primary;

CREATE UNIQUE INDEX doctor_assignments_active_relationship_uidx ON public.doctor_patient_assignments USING btree (care_relationship_id) WHERE ((care_relationship_id IS NOT NULL) AND (ended_at IS NULL) AND (assignment_status = 'active'::text));

CREATE UNIQUE INDEX doctor_patient_active_unique_idx ON public.doctor_patient_assignments USING btree (doctor_id, patient_id) WHERE (ended_at IS NULL);

CREATE UNIQUE INDEX document_jobs_one_active_result_idx ON public.document_processing_jobs USING btree (laboratory_result_id) WHERE ((laboratory_result_id IS NOT NULL) AND (status = ANY (ARRAY['queued'::text, 'ocr_processing'::text, 'ai_analysis_pending'::text, 'pending_doctor_review'::text])));

CREATE UNIQUE INDEX guest_submission_idempotency ON public.guest_consultation_requests USING btree (submitted_by, submission_key) WHERE (submission_key IS NOT NULL);

CREATE UNIQUE INDEX healthcare_service_categories_name_ci_key ON public.healthcare_service_categories USING btree (lower(category_name));

CREATE UNIQUE INDEX hospital_services_code_key ON public.hospital_services USING btree (hospital_id, lower(service_code)) WHERE (service_code IS NOT NULL);

CREATE UNIQUE INDEX hospital_services_name_ci_key ON public.hospital_services USING btree (hospital_id, lower(service_name));

CREATE UNIQUE INDEX medical_records_consultation_checkup_unique ON public.medical_records USING btree (consultation_id) WHERE (record_type = 'consultation_checkup'::text);

CREATE UNIQUE INDEX notifications_dedupe_key_idx ON public.notifications USING btree (user_id, dedupe_key) WHERE (dedupe_key IS NOT NULL);

CREATE UNIQUE INDEX patient_access_grants_active_source_uidx ON public.patient_access_grants USING btree (care_relationship_id, source_hospital_id, receiving_hospital_id, receiving_doctor_id) WHERE ((status = ANY (ARRAY['requested'::text, 'active'::text])) AND (revoked_at IS NULL));

CREATE UNIQUE INDEX patient_connection_requests_pending_uidx ON public.patient_connection_requests USING btree (doctor_id, patient_id) WHERE (status = 'requested'::text);

CREATE UNIQUE INDEX treatment_plans_consultation_completion_idx ON public.treatment_plans USING btree (consultation_id) WHERE (source = 'consultation_completion'::text);

alter table "public"."ai_assessment_recommendations" enable row level security;

revoke all on table "public"."ai_assessment_recommendations" from public,anon,authenticated;

alter table "public"."ai_assessments" enable row level security;

revoke all on table "public"."ai_assessments" from public,anon,authenticated;

alter table "public"."ai_configurations" enable row level security;

revoke all on table "public"."ai_configurations" from public,anon,authenticated;

alter table "public"."appointment_reminder_jobs" enable row level security;

revoke all on table "public"."appointment_reminder_jobs" from public,anon,authenticated;

alter table "public"."audit_logs" enable row level security;

revoke all on table "public"."audit_logs" from public,anon,authenticated;

alter table "public"."care_assistant_conversations" enable row level security;

revoke all on table "public"."care_assistant_conversations" from public,anon,authenticated;

alter table "public"."chat_conversations" enable row level security;

revoke all on table "public"."chat_conversations" from public,anon,authenticated;

alter table "public"."chat_message_attachments" enable row level security;

revoke all on table "public"."chat_message_attachments" from public,anon,authenticated;

alter table "public"."chat_messages" enable row level security;

revoke all on table "public"."chat_messages" from public,anon,authenticated;

alter table "public"."clinical_record_addenda" enable row level security;

revoke all on table "public"."clinical_record_addenda" from public,anon,authenticated;

alter table "public"."clinical_record_quarantine" enable row level security;

revoke all on table "public"."clinical_record_quarantine" from public,anon,authenticated;

alter table "public"."consultation_attachments" enable row level security;

revoke all on table "public"."consultation_attachments" from public,anon,authenticated;

alter table "public"."consultation_status_history" enable row level security;

revoke all on table "public"."consultation_status_history" from public,anon,authenticated;

alter table "public"."consultations" enable row level security;

revoke all on table "public"."consultations" from public,anon,authenticated;

alter table "public"."diagnoses" enable row level security;

revoke all on table "public"."diagnoses" from public,anon,authenticated;

alter table "public"."doctor_hospital_employments" enable row level security;

revoke all on table "public"."doctor_hospital_employments" from public,anon,authenticated;

alter table "public"."doctor_patient_assignments" enable row level security;

revoke all on table "public"."doctor_patient_assignments" from public,anon,authenticated;

alter table "public"."doctor_schedules" enable row level security;

revoke all on table "public"."doctor_schedules" from public,anon,authenticated;

alter table "public"."doctors" enable row level security;

revoke all on table "public"."doctors" from public,anon,authenticated;

alter table "public"."document_processing_jobs" enable row level security;

revoke all on table "public"."document_processing_jobs" from public,anon,authenticated;

alter table "public"."emergency_access_events" enable row level security;

revoke all on table "public"."emergency_access_events" from public,anon,authenticated;

alter table "public"."emergency_room_status" enable row level security;

revoke all on table "public"."emergency_room_status" from public,anon,authenticated;

alter table "public"."guest_consultation_requests" enable row level security;

revoke all on table "public"."guest_consultation_requests" from public,anon,authenticated;

alter table "public"."guest_request_status_history" enable row level security;

revoke all on table "public"."guest_request_status_history" from public,anon,authenticated;

alter table "public"."healthcare_service_categories" enable row level security;

revoke all on table "public"."healthcare_service_categories" from public,anon,authenticated;

alter table "public"."hospital_announcements" enable row level security;

revoke all on table "public"."hospital_announcements" from public,anon,authenticated;

alter table "public"."hospital_beds" enable row level security;

revoke all on table "public"."hospital_beds" from public,anon,authenticated;

alter table "public"."hospital_classifications" enable row level security;

revoke all on table "public"."hospital_classifications" from public,anon,authenticated;

alter table "public"."hospital_departments" enable row level security;

revoke all on table "public"."hospital_departments" from public,anon,authenticated;

alter table "public"."hospital_facility_status" enable row level security;

revoke all on table "public"."hospital_facility_status" from public,anon,authenticated;

alter table "public"."hospital_rooms" enable row level security;

revoke all on table "public"."hospital_rooms" from public,anon,authenticated;

alter table "public"."hospital_service_doctors" enable row level security;

revoke all on table "public"."hospital_service_doctors" from public,anon,authenticated;

alter table "public"."hospital_services" enable row level security;

revoke all on table "public"."hospital_services" from public,anon,authenticated;

alter table "public"."hospitals" enable row level security;

revoke all on table "public"."hospitals" from public,anon,authenticated;

alter table "public"."laboratory_requests" enable row level security;

revoke all on table "public"."laboratory_requests" from public,anon,authenticated;

alter table "public"."laboratory_results" enable row level security;

revoke all on table "public"."laboratory_results" from public,anon,authenticated;

alter table "public"."maintenance_windows" enable row level security;

revoke all on table "public"."maintenance_windows" from public,anon,authenticated;

alter table "public"."medical_documents" enable row level security;

revoke all on table "public"."medical_documents" from public,anon,authenticated;

alter table "public"."medical_record_access_logs" enable row level security;

revoke all on table "public"."medical_record_access_logs" from public,anon,authenticated;

alter table "public"."medical_records" enable row level security;

revoke all on table "public"."medical_records" from public,anon,authenticated;

alter table "public"."medication_summary_days" enable row level security;

revoke all on table "public"."medication_summary_days" from public,anon,authenticated;

alter table "public"."notification_outbox" enable row level security;

revoke all on table "public"."notification_outbox" from public,anon,authenticated;

alter table "public"."notification_preferences" enable row level security;

revoke all on table "public"."notification_preferences" from public,anon,authenticated;

alter table "public"."notifications" enable row level security;

revoke all on table "public"."notifications" from public,anon,authenticated;

alter table "public"."online_consultation_request_status_history" enable row level security;

revoke all on table "public"."online_consultation_request_status_history" from public,anon,authenticated;

alter table "public"."online_consultation_requests" enable row level security;

revoke all on table "public"."online_consultation_requests" from public,anon,authenticated;

alter table "public"."patient_access_grants" enable row level security;

revoke all on table "public"."patient_access_grants" from public,anon,authenticated;

alter table "public"."patient_access_record_selections" enable row level security;

revoke all on table "public"."patient_access_record_selections" from public,anon,authenticated;

alter table "public"."patient_access_scopes" enable row level security;

revoke all on table "public"."patient_access_scopes" from public,anon,authenticated;

alter table "public"."patient_care_relationships" enable row level security;

revoke all on table "public"."patient_care_relationships" from public,anon,authenticated;

alter table "public"."patient_connection_requests" enable row level security;

revoke all on table "public"."patient_connection_requests" from public,anon,authenticated;

alter table "public"."patient_consents" enable row level security;

revoke all on table "public"."patient_consents" from public,anon,authenticated;

alter table "public"."patient_hospital_identifiers" enable row level security;

revoke all on table "public"."patient_hospital_identifiers" from public,anon,authenticated;

alter table "public"."patient_representatives" enable row level security;

revoke all on table "public"."patient_representatives" from public,anon,authenticated;

alter table "public"."patients" enable row level security;

revoke all on table "public"."patients" from public,anon,authenticated;

alter table "public"."prescription_orders" enable row level security;

revoke all on table "public"."prescription_orders" from public,anon,authenticated;

alter table "public"."prescriptions" enable row level security;

revoke all on table "public"."prescriptions" from public,anon,authenticated;

alter table "public"."role_permissions" enable row level security;

revoke all on table "public"."role_permissions" from public,anon,authenticated;

alter table "public"."roles" enable row level security;

revoke all on table "public"."roles" from public,anon,authenticated;

alter table "public"."security_logs" enable row level security;

revoke all on table "public"."security_logs" from public,anon,authenticated;

alter table "public"."system_settings" enable row level security;

revoke all on table "public"."system_settings" from public,anon,authenticated;

alter table "public"."treatment_plans" enable row level security;

revoke all on table "public"."treatment_plans" from public,anon,authenticated;

alter table "public"."users" enable row level security;

revoke all on table "public"."users" from public,anon,authenticated;

alter table "public"."video_sessions" enable row level security;

revoke all on table "public"."video_sessions" from public,anon,authenticated;

grant DELETE on table "public"."ai_assessment_recommendations" to "anon";

grant INSERT on table "public"."ai_assessment_recommendations" to "anon";

grant REFERENCES on table "public"."ai_assessment_recommendations" to "anon";

grant SELECT on table "public"."ai_assessment_recommendations" to "anon";

grant TRIGGER on table "public"."ai_assessment_recommendations" to "anon";

grant TRUNCATE on table "public"."ai_assessment_recommendations" to "anon";

grant UPDATE on table "public"."ai_assessment_recommendations" to "anon";

grant DELETE on table "public"."ai_configurations" to "anon";

grant INSERT on table "public"."ai_configurations" to "anon";

grant REFERENCES on table "public"."ai_configurations" to "anon";

grant SELECT on table "public"."ai_configurations" to "anon";

grant TRIGGER on table "public"."ai_configurations" to "anon";

grant TRUNCATE on table "public"."ai_configurations" to "anon";

grant UPDATE on table "public"."ai_configurations" to "anon";

grant DELETE on table "public"."chat_message_attachments" to "anon";

grant INSERT on table "public"."chat_message_attachments" to "anon";

grant REFERENCES on table "public"."chat_message_attachments" to "anon";

grant SELECT on table "public"."chat_message_attachments" to "anon";

grant TRIGGER on table "public"."chat_message_attachments" to "anon";

grant TRUNCATE on table "public"."chat_message_attachments" to "anon";

grant UPDATE on table "public"."chat_message_attachments" to "anon";

grant DELETE on table "public"."consultation_attachments" to "anon";

grant INSERT on table "public"."consultation_attachments" to "anon";

grant REFERENCES on table "public"."consultation_attachments" to "anon";

grant SELECT on table "public"."consultation_attachments" to "anon";

grant TRIGGER on table "public"."consultation_attachments" to "anon";

grant TRUNCATE on table "public"."consultation_attachments" to "anon";

grant UPDATE on table "public"."consultation_attachments" to "anon";

grant DELETE on table "public"."consultation_status_history" to "anon";

grant INSERT on table "public"."consultation_status_history" to "anon";

grant REFERENCES on table "public"."consultation_status_history" to "anon";

grant SELECT on table "public"."consultation_status_history" to "anon";

grant TRIGGER on table "public"."consultation_status_history" to "anon";

grant TRUNCATE on table "public"."consultation_status_history" to "anon";

grant UPDATE on table "public"."consultation_status_history" to "anon";

grant DELETE on table "public"."diagnoses" to "anon";

grant INSERT on table "public"."diagnoses" to "anon";

grant REFERENCES on table "public"."diagnoses" to "anon";

grant SELECT on table "public"."diagnoses" to "anon";

grant TRIGGER on table "public"."diagnoses" to "anon";

grant TRUNCATE on table "public"."diagnoses" to "anon";

grant UPDATE on table "public"."diagnoses" to "anon";

grant DELETE on table "public"."doctor_schedules" to "anon";

grant INSERT on table "public"."doctor_schedules" to "anon";

grant REFERENCES on table "public"."doctor_schedules" to "anon";

grant SELECT on table "public"."doctor_schedules" to "anon";

grant TRIGGER on table "public"."doctor_schedules" to "anon";

grant TRUNCATE on table "public"."doctor_schedules" to "anon";

grant UPDATE on table "public"."doctor_schedules" to "anon";

grant DELETE on table "public"."doctors" to "anon";

grant INSERT on table "public"."doctors" to "anon";

grant REFERENCES on table "public"."doctors" to "anon";

grant SELECT on table "public"."doctors" to "anon";

grant TRIGGER on table "public"."doctors" to "anon";

grant TRUNCATE on table "public"."doctors" to "anon";

grant UPDATE on table "public"."doctors" to "anon";

grant DELETE on table "public"."document_processing_jobs" to "anon";

grant INSERT on table "public"."document_processing_jobs" to "anon";

grant REFERENCES on table "public"."document_processing_jobs" to "anon";

grant SELECT on table "public"."document_processing_jobs" to "anon";

grant TRIGGER on table "public"."document_processing_jobs" to "anon";

grant TRUNCATE on table "public"."document_processing_jobs" to "anon";

grant UPDATE on table "public"."document_processing_jobs" to "anon";

grant DELETE on table "public"."emergency_room_status" to "anon";

grant INSERT on table "public"."emergency_room_status" to "anon";

grant REFERENCES on table "public"."emergency_room_status" to "anon";

grant SELECT on table "public"."emergency_room_status" to "anon";

grant TRIGGER on table "public"."emergency_room_status" to "anon";

grant TRUNCATE on table "public"."emergency_room_status" to "anon";

grant UPDATE on table "public"."emergency_room_status" to "anon";

grant DELETE on table "public"."guest_request_status_history" to "anon";

grant INSERT on table "public"."guest_request_status_history" to "anon";

grant REFERENCES on table "public"."guest_request_status_history" to "anon";

grant SELECT on table "public"."guest_request_status_history" to "anon";

grant TRIGGER on table "public"."guest_request_status_history" to "anon";

grant TRUNCATE on table "public"."guest_request_status_history" to "anon";

grant UPDATE on table "public"."guest_request_status_history" to "anon";

grant DELETE on table "public"."healthcare_service_categories" to "anon";

grant INSERT on table "public"."healthcare_service_categories" to "anon";

grant REFERENCES on table "public"."healthcare_service_categories" to "anon";

grant SELECT on table "public"."healthcare_service_categories" to "anon";

grant TRIGGER on table "public"."healthcare_service_categories" to "anon";

grant TRUNCATE on table "public"."healthcare_service_categories" to "anon";

grant UPDATE on table "public"."healthcare_service_categories" to "anon";

grant DELETE on table "public"."hospital_announcements" to "anon";

grant INSERT on table "public"."hospital_announcements" to "anon";

grant REFERENCES on table "public"."hospital_announcements" to "anon";

grant SELECT on table "public"."hospital_announcements" to "anon";

grant TRIGGER on table "public"."hospital_announcements" to "anon";

grant TRUNCATE on table "public"."hospital_announcements" to "anon";

grant UPDATE on table "public"."hospital_announcements" to "anon";

grant DELETE on table "public"."hospital_beds" to "anon";

grant INSERT on table "public"."hospital_beds" to "anon";

grant REFERENCES on table "public"."hospital_beds" to "anon";

grant SELECT on table "public"."hospital_beds" to "anon";

grant TRIGGER on table "public"."hospital_beds" to "anon";

grant TRUNCATE on table "public"."hospital_beds" to "anon";

grant UPDATE on table "public"."hospital_beds" to "anon";

grant DELETE on table "public"."hospital_classifications" to "anon";

grant INSERT on table "public"."hospital_classifications" to "anon";

grant REFERENCES on table "public"."hospital_classifications" to "anon";

grant SELECT on table "public"."hospital_classifications" to "anon";

grant TRIGGER on table "public"."hospital_classifications" to "anon";

grant TRUNCATE on table "public"."hospital_classifications" to "anon";

grant UPDATE on table "public"."hospital_classifications" to "anon";

grant DELETE on table "public"."hospital_departments" to "anon";

grant INSERT on table "public"."hospital_departments" to "anon";

grant REFERENCES on table "public"."hospital_departments" to "anon";

grant SELECT on table "public"."hospital_departments" to "anon";

grant TRIGGER on table "public"."hospital_departments" to "anon";

grant TRUNCATE on table "public"."hospital_departments" to "anon";

grant UPDATE on table "public"."hospital_departments" to "anon";

grant DELETE on table "public"."hospital_facility_status" to "anon";

grant INSERT on table "public"."hospital_facility_status" to "anon";

grant REFERENCES on table "public"."hospital_facility_status" to "anon";

grant SELECT on table "public"."hospital_facility_status" to "anon";

grant TRIGGER on table "public"."hospital_facility_status" to "anon";

grant TRUNCATE on table "public"."hospital_facility_status" to "anon";

grant UPDATE on table "public"."hospital_facility_status" to "anon";

grant DELETE on table "public"."hospital_rooms" to "anon";

grant INSERT on table "public"."hospital_rooms" to "anon";

grant REFERENCES on table "public"."hospital_rooms" to "anon";

grant SELECT on table "public"."hospital_rooms" to "anon";

grant TRIGGER on table "public"."hospital_rooms" to "anon";

grant TRUNCATE on table "public"."hospital_rooms" to "anon";

grant UPDATE on table "public"."hospital_rooms" to "anon";

grant DELETE on table "public"."hospital_service_doctors" to "anon";

grant INSERT on table "public"."hospital_service_doctors" to "anon";

grant REFERENCES on table "public"."hospital_service_doctors" to "anon";

grant SELECT on table "public"."hospital_service_doctors" to "anon";

grant TRIGGER on table "public"."hospital_service_doctors" to "anon";

grant TRUNCATE on table "public"."hospital_service_doctors" to "anon";

grant UPDATE on table "public"."hospital_service_doctors" to "anon";

grant DELETE on table "public"."hospital_services" to "anon";

grant INSERT on table "public"."hospital_services" to "anon";

grant REFERENCES on table "public"."hospital_services" to "anon";

grant SELECT on table "public"."hospital_services" to "anon";

grant TRIGGER on table "public"."hospital_services" to "anon";

grant TRUNCATE on table "public"."hospital_services" to "anon";

grant UPDATE on table "public"."hospital_services" to "anon";

grant DELETE on table "public"."hospitals" to "anon";

grant INSERT on table "public"."hospitals" to "anon";

grant REFERENCES on table "public"."hospitals" to "anon";

grant SELECT on table "public"."hospitals" to "anon";

grant TRIGGER on table "public"."hospitals" to "anon";

grant TRUNCATE on table "public"."hospitals" to "anon";

grant UPDATE on table "public"."hospitals" to "anon";

grant DELETE on table "public"."laboratory_requests" to "anon";

grant INSERT on table "public"."laboratory_requests" to "anon";

grant REFERENCES on table "public"."laboratory_requests" to "anon";

grant SELECT on table "public"."laboratory_requests" to "anon";

grant TRIGGER on table "public"."laboratory_requests" to "anon";

grant TRUNCATE on table "public"."laboratory_requests" to "anon";

grant UPDATE on table "public"."laboratory_requests" to "anon";

grant DELETE on table "public"."maintenance_windows" to "anon";

grant INSERT on table "public"."maintenance_windows" to "anon";

grant REFERENCES on table "public"."maintenance_windows" to "anon";

grant SELECT on table "public"."maintenance_windows" to "anon";

grant TRIGGER on table "public"."maintenance_windows" to "anon";

grant TRUNCATE on table "public"."maintenance_windows" to "anon";

grant UPDATE on table "public"."maintenance_windows" to "anon";

grant DELETE on table "public"."medical_documents" to "anon";

grant INSERT on table "public"."medical_documents" to "anon";

grant REFERENCES on table "public"."medical_documents" to "anon";

grant SELECT on table "public"."medical_documents" to "anon";

grant TRIGGER on table "public"."medical_documents" to "anon";

grant TRUNCATE on table "public"."medical_documents" to "anon";

grant UPDATE on table "public"."medical_documents" to "anon";

grant DELETE on table "public"."medical_record_access_logs" to "anon";

grant INSERT on table "public"."medical_record_access_logs" to "anon";

grant REFERENCES on table "public"."medical_record_access_logs" to "anon";

grant SELECT on table "public"."medical_record_access_logs" to "anon";

grant TRIGGER on table "public"."medical_record_access_logs" to "anon";

grant TRUNCATE on table "public"."medical_record_access_logs" to "anon";

grant UPDATE on table "public"."medical_record_access_logs" to "anon";

grant DELETE on table "public"."medication_summary_days" to "anon";

grant INSERT on table "public"."medication_summary_days" to "anon";

grant REFERENCES on table "public"."medication_summary_days" to "anon";

grant SELECT on table "public"."medication_summary_days" to "anon";

grant TRIGGER on table "public"."medication_summary_days" to "anon";

grant TRUNCATE on table "public"."medication_summary_days" to "anon";

grant UPDATE on table "public"."medication_summary_days" to "anon";

grant DELETE on table "public"."notification_outbox" to "anon";

grant INSERT on table "public"."notification_outbox" to "anon";

grant REFERENCES on table "public"."notification_outbox" to "anon";

grant SELECT on table "public"."notification_outbox" to "anon";

grant TRIGGER on table "public"."notification_outbox" to "anon";

grant TRUNCATE on table "public"."notification_outbox" to "anon";

grant UPDATE on table "public"."notification_outbox" to "anon";

grant DELETE on table "public"."notification_preferences" to "anon";

grant INSERT on table "public"."notification_preferences" to "anon";

grant REFERENCES on table "public"."notification_preferences" to "anon";

grant SELECT on table "public"."notification_preferences" to "anon";

grant TRIGGER on table "public"."notification_preferences" to "anon";

grant TRUNCATE on table "public"."notification_preferences" to "anon";

grant UPDATE on table "public"."notification_preferences" to "anon";

grant REFERENCES on table "public"."patient_consents" to "anon";

grant SELECT on table "public"."patient_consents" to "anon";

grant TRIGGER on table "public"."patient_consents" to "anon";

grant TRUNCATE on table "public"."patient_consents" to "anon";

grant DELETE on table "public"."role_permissions" to "anon";

grant INSERT on table "public"."role_permissions" to "anon";

grant REFERENCES on table "public"."role_permissions" to "anon";

grant SELECT on table "public"."role_permissions" to "anon";

grant TRIGGER on table "public"."role_permissions" to "anon";

grant TRUNCATE on table "public"."role_permissions" to "anon";

grant UPDATE on table "public"."role_permissions" to "anon";

grant DELETE on table "public"."roles" to "anon";

grant INSERT on table "public"."roles" to "anon";

grant REFERENCES on table "public"."roles" to "anon";

grant SELECT on table "public"."roles" to "anon";

grant TRIGGER on table "public"."roles" to "anon";

grant TRUNCATE on table "public"."roles" to "anon";

grant UPDATE on table "public"."roles" to "anon";

grant DELETE on table "public"."security_logs" to "anon";

grant INSERT on table "public"."security_logs" to "anon";

grant REFERENCES on table "public"."security_logs" to "anon";

grant SELECT on table "public"."security_logs" to "anon";

grant TRIGGER on table "public"."security_logs" to "anon";

grant TRUNCATE on table "public"."security_logs" to "anon";

grant UPDATE on table "public"."security_logs" to "anon";

grant DELETE on table "public"."system_settings" to "anon";

grant INSERT on table "public"."system_settings" to "anon";

grant REFERENCES on table "public"."system_settings" to "anon";

grant SELECT on table "public"."system_settings" to "anon";

grant TRIGGER on table "public"."system_settings" to "anon";

grant TRUNCATE on table "public"."system_settings" to "anon";

grant UPDATE on table "public"."system_settings" to "anon";

grant DELETE on table "public"."treatment_plans" to "anon";

grant INSERT on table "public"."treatment_plans" to "anon";

grant REFERENCES on table "public"."treatment_plans" to "anon";

grant SELECT on table "public"."treatment_plans" to "anon";

grant TRIGGER on table "public"."treatment_plans" to "anon";

grant TRUNCATE on table "public"."treatment_plans" to "anon";

grant UPDATE on table "public"."treatment_plans" to "anon";

grant DELETE on table "public"."ai_assessment_recommendations" to "authenticated";

grant INSERT on table "public"."ai_assessment_recommendations" to "authenticated";

grant REFERENCES on table "public"."ai_assessment_recommendations" to "authenticated";

grant SELECT on table "public"."ai_assessment_recommendations" to "authenticated";

grant TRIGGER on table "public"."ai_assessment_recommendations" to "authenticated";

grant TRUNCATE on table "public"."ai_assessment_recommendations" to "authenticated";

grant UPDATE on table "public"."ai_assessment_recommendations" to "authenticated";

grant DELETE on table "public"."ai_assessments" to "authenticated";

grant INSERT on table "public"."ai_assessments" to "authenticated";

grant REFERENCES on table "public"."ai_assessments" to "authenticated";

grant SELECT on table "public"."ai_assessments" to "authenticated";

grant TRIGGER on table "public"."ai_assessments" to "authenticated";

grant TRUNCATE on table "public"."ai_assessments" to "authenticated";

grant UPDATE on table "public"."ai_assessments" to "authenticated";

grant DELETE on table "public"."ai_configurations" to "authenticated";

grant INSERT on table "public"."ai_configurations" to "authenticated";

grant REFERENCES on table "public"."ai_configurations" to "authenticated";

grant SELECT on table "public"."ai_configurations" to "authenticated";

grant TRIGGER on table "public"."ai_configurations" to "authenticated";

grant TRUNCATE on table "public"."ai_configurations" to "authenticated";

grant UPDATE on table "public"."ai_configurations" to "authenticated";

grant DELETE on table "public"."audit_logs" to "authenticated";

grant INSERT on table "public"."audit_logs" to "authenticated";

grant REFERENCES on table "public"."audit_logs" to "authenticated";

grant SELECT on table "public"."audit_logs" to "authenticated";

grant TRIGGER on table "public"."audit_logs" to "authenticated";

grant TRUNCATE on table "public"."audit_logs" to "authenticated";

grant UPDATE on table "public"."audit_logs" to "authenticated";

grant DELETE on table "public"."care_assistant_conversations" to "authenticated";

grant INSERT on table "public"."care_assistant_conversations" to "authenticated";

grant REFERENCES on table "public"."care_assistant_conversations" to "authenticated";

grant SELECT on table "public"."care_assistant_conversations" to "authenticated";

grant TRIGGER on table "public"."care_assistant_conversations" to "authenticated";

grant TRUNCATE on table "public"."care_assistant_conversations" to "authenticated";

grant UPDATE on table "public"."care_assistant_conversations" to "authenticated";

grant DELETE on table "public"."chat_conversations" to "authenticated";

grant INSERT on table "public"."chat_conversations" to "authenticated";

grant REFERENCES on table "public"."chat_conversations" to "authenticated";

grant SELECT on table "public"."chat_conversations" to "authenticated";

grant TRIGGER on table "public"."chat_conversations" to "authenticated";

grant TRUNCATE on table "public"."chat_conversations" to "authenticated";

grant UPDATE on table "public"."chat_conversations" to "authenticated";

grant DELETE on table "public"."chat_message_attachments" to "authenticated";

grant INSERT on table "public"."chat_message_attachments" to "authenticated";

grant REFERENCES on table "public"."chat_message_attachments" to "authenticated";

grant SELECT on table "public"."chat_message_attachments" to "authenticated";

grant TRIGGER on table "public"."chat_message_attachments" to "authenticated";

grant TRUNCATE on table "public"."chat_message_attachments" to "authenticated";

grant UPDATE on table "public"."chat_message_attachments" to "authenticated";

grant DELETE on table "public"."chat_messages" to "authenticated";

grant INSERT on table "public"."chat_messages" to "authenticated";

grant REFERENCES on table "public"."chat_messages" to "authenticated";

grant SELECT on table "public"."chat_messages" to "authenticated";

grant TRIGGER on table "public"."chat_messages" to "authenticated";

grant TRUNCATE on table "public"."chat_messages" to "authenticated";

grant INSERT on table "public"."clinical_record_addenda" to "authenticated";

grant SELECT on table "public"."clinical_record_addenda" to "authenticated";

grant DELETE on table "public"."consultation_attachments" to "authenticated";

grant INSERT on table "public"."consultation_attachments" to "authenticated";

grant REFERENCES on table "public"."consultation_attachments" to "authenticated";

grant SELECT on table "public"."consultation_attachments" to "authenticated";

grant TRIGGER on table "public"."consultation_attachments" to "authenticated";

grant TRUNCATE on table "public"."consultation_attachments" to "authenticated";

grant UPDATE on table "public"."consultation_attachments" to "authenticated";

grant DELETE on table "public"."consultation_status_history" to "authenticated";

grant INSERT on table "public"."consultation_status_history" to "authenticated";

grant REFERENCES on table "public"."consultation_status_history" to "authenticated";

grant SELECT on table "public"."consultation_status_history" to "authenticated";

grant TRIGGER on table "public"."consultation_status_history" to "authenticated";

grant TRUNCATE on table "public"."consultation_status_history" to "authenticated";

grant UPDATE on table "public"."consultation_status_history" to "authenticated";

grant REFERENCES on table "public"."consultations" to "authenticated";

grant SELECT on table "public"."consultations" to "authenticated";

grant TRIGGER on table "public"."consultations" to "authenticated";

grant TRUNCATE on table "public"."consultations" to "authenticated";

grant UPDATE on table "public"."consultations" to "authenticated";

grant DELETE on table "public"."diagnoses" to "authenticated";

grant INSERT on table "public"."diagnoses" to "authenticated";

grant REFERENCES on table "public"."diagnoses" to "authenticated";

grant SELECT on table "public"."diagnoses" to "authenticated";

grant TRIGGER on table "public"."diagnoses" to "authenticated";

grant TRUNCATE on table "public"."diagnoses" to "authenticated";

grant UPDATE on table "public"."diagnoses" to "authenticated";

grant SELECT on table "public"."doctor_hospital_employments" to "authenticated";

grant REFERENCES on table "public"."doctor_patient_assignments" to "authenticated";

grant SELECT on table "public"."doctor_patient_assignments" to "authenticated";

grant TRIGGER on table "public"."doctor_patient_assignments" to "authenticated";

grant TRUNCATE on table "public"."doctor_patient_assignments" to "authenticated";

grant DELETE on table "public"."doctor_schedules" to "authenticated";

grant INSERT on table "public"."doctor_schedules" to "authenticated";

grant REFERENCES on table "public"."doctor_schedules" to "authenticated";

grant SELECT on table "public"."doctor_schedules" to "authenticated";

grant TRIGGER on table "public"."doctor_schedules" to "authenticated";

grant TRUNCATE on table "public"."doctor_schedules" to "authenticated";

grant UPDATE on table "public"."doctor_schedules" to "authenticated";

grant DELETE on table "public"."doctors" to "authenticated";

grant INSERT on table "public"."doctors" to "authenticated";

grant REFERENCES on table "public"."doctors" to "authenticated";

grant SELECT on table "public"."doctors" to "authenticated";

grant TRIGGER on table "public"."doctors" to "authenticated";

grant TRUNCATE on table "public"."doctors" to "authenticated";

grant UPDATE on table "public"."doctors" to "authenticated";

grant DELETE on table "public"."document_processing_jobs" to "authenticated";

grant INSERT on table "public"."document_processing_jobs" to "authenticated";

grant REFERENCES on table "public"."document_processing_jobs" to "authenticated";

grant SELECT on table "public"."document_processing_jobs" to "authenticated";

grant TRIGGER on table "public"."document_processing_jobs" to "authenticated";

grant TRUNCATE on table "public"."document_processing_jobs" to "authenticated";

grant UPDATE on table "public"."document_processing_jobs" to "authenticated";

grant SELECT on table "public"."emergency_access_events" to "authenticated";

grant DELETE on table "public"."emergency_room_status" to "authenticated";

grant INSERT on table "public"."emergency_room_status" to "authenticated";

grant REFERENCES on table "public"."emergency_room_status" to "authenticated";

grant SELECT on table "public"."emergency_room_status" to "authenticated";

grant TRIGGER on table "public"."emergency_room_status" to "authenticated";

grant TRUNCATE on table "public"."emergency_room_status" to "authenticated";

grant UPDATE on table "public"."emergency_room_status" to "authenticated";

grant DELETE on table "public"."guest_consultation_requests" to "authenticated";

grant INSERT on table "public"."guest_consultation_requests" to "authenticated";

grant REFERENCES on table "public"."guest_consultation_requests" to "authenticated";

grant SELECT on table "public"."guest_consultation_requests" to "authenticated";

grant TRIGGER on table "public"."guest_consultation_requests" to "authenticated";

grant TRUNCATE on table "public"."guest_consultation_requests" to "authenticated";

grant UPDATE on table "public"."guest_consultation_requests" to "authenticated";

grant DELETE on table "public"."guest_request_status_history" to "authenticated";

grant INSERT on table "public"."guest_request_status_history" to "authenticated";

grant REFERENCES on table "public"."guest_request_status_history" to "authenticated";

grant SELECT on table "public"."guest_request_status_history" to "authenticated";

grant TRIGGER on table "public"."guest_request_status_history" to "authenticated";

grant TRUNCATE on table "public"."guest_request_status_history" to "authenticated";

grant UPDATE on table "public"."guest_request_status_history" to "authenticated";

grant DELETE on table "public"."healthcare_service_categories" to "authenticated";

grant INSERT on table "public"."healthcare_service_categories" to "authenticated";

grant REFERENCES on table "public"."healthcare_service_categories" to "authenticated";

grant SELECT on table "public"."healthcare_service_categories" to "authenticated";

grant TRIGGER on table "public"."healthcare_service_categories" to "authenticated";

grant TRUNCATE on table "public"."healthcare_service_categories" to "authenticated";

grant UPDATE on table "public"."healthcare_service_categories" to "authenticated";

grant DELETE on table "public"."hospital_announcements" to "authenticated";

grant INSERT on table "public"."hospital_announcements" to "authenticated";

grant REFERENCES on table "public"."hospital_announcements" to "authenticated";

grant SELECT on table "public"."hospital_announcements" to "authenticated";

grant TRIGGER on table "public"."hospital_announcements" to "authenticated";

grant TRUNCATE on table "public"."hospital_announcements" to "authenticated";

grant UPDATE on table "public"."hospital_announcements" to "authenticated";

grant DELETE on table "public"."hospital_beds" to "authenticated";

grant INSERT on table "public"."hospital_beds" to "authenticated";

grant REFERENCES on table "public"."hospital_beds" to "authenticated";

grant SELECT on table "public"."hospital_beds" to "authenticated";

grant TRIGGER on table "public"."hospital_beds" to "authenticated";

grant TRUNCATE on table "public"."hospital_beds" to "authenticated";

grant UPDATE on table "public"."hospital_beds" to "authenticated";

grant DELETE on table "public"."hospital_classifications" to "authenticated";

grant INSERT on table "public"."hospital_classifications" to "authenticated";

grant REFERENCES on table "public"."hospital_classifications" to "authenticated";

grant SELECT on table "public"."hospital_classifications" to "authenticated";

grant TRIGGER on table "public"."hospital_classifications" to "authenticated";

grant TRUNCATE on table "public"."hospital_classifications" to "authenticated";

grant UPDATE on table "public"."hospital_classifications" to "authenticated";

grant DELETE on table "public"."hospital_departments" to "authenticated";

grant INSERT on table "public"."hospital_departments" to "authenticated";

grant REFERENCES on table "public"."hospital_departments" to "authenticated";

grant SELECT on table "public"."hospital_departments" to "authenticated";

grant TRIGGER on table "public"."hospital_departments" to "authenticated";

grant TRUNCATE on table "public"."hospital_departments" to "authenticated";

grant UPDATE on table "public"."hospital_departments" to "authenticated";

grant DELETE on table "public"."hospital_facility_status" to "authenticated";

grant INSERT on table "public"."hospital_facility_status" to "authenticated";

grant REFERENCES on table "public"."hospital_facility_status" to "authenticated";

grant SELECT on table "public"."hospital_facility_status" to "authenticated";

grant TRIGGER on table "public"."hospital_facility_status" to "authenticated";

grant TRUNCATE on table "public"."hospital_facility_status" to "authenticated";

grant UPDATE on table "public"."hospital_facility_status" to "authenticated";

grant DELETE on table "public"."hospital_rooms" to "authenticated";

grant INSERT on table "public"."hospital_rooms" to "authenticated";

grant REFERENCES on table "public"."hospital_rooms" to "authenticated";

grant SELECT on table "public"."hospital_rooms" to "authenticated";

grant TRIGGER on table "public"."hospital_rooms" to "authenticated";

grant TRUNCATE on table "public"."hospital_rooms" to "authenticated";

grant UPDATE on table "public"."hospital_rooms" to "authenticated";

grant DELETE on table "public"."hospital_service_doctors" to "authenticated";

grant INSERT on table "public"."hospital_service_doctors" to "authenticated";

grant REFERENCES on table "public"."hospital_service_doctors" to "authenticated";

grant SELECT on table "public"."hospital_service_doctors" to "authenticated";

grant TRIGGER on table "public"."hospital_service_doctors" to "authenticated";

grant TRUNCATE on table "public"."hospital_service_doctors" to "authenticated";

grant UPDATE on table "public"."hospital_service_doctors" to "authenticated";

grant DELETE on table "public"."hospital_services" to "authenticated";

grant INSERT on table "public"."hospital_services" to "authenticated";

grant REFERENCES on table "public"."hospital_services" to "authenticated";

grant SELECT on table "public"."hospital_services" to "authenticated";

grant TRIGGER on table "public"."hospital_services" to "authenticated";

grant TRUNCATE on table "public"."hospital_services" to "authenticated";

grant UPDATE on table "public"."hospital_services" to "authenticated";

grant DELETE on table "public"."hospitals" to "authenticated";

grant INSERT on table "public"."hospitals" to "authenticated";

grant REFERENCES on table "public"."hospitals" to "authenticated";

grant SELECT on table "public"."hospitals" to "authenticated";

grant TRIGGER on table "public"."hospitals" to "authenticated";

grant TRUNCATE on table "public"."hospitals" to "authenticated";

grant UPDATE on table "public"."hospitals" to "authenticated";

grant DELETE on table "public"."laboratory_requests" to "authenticated";

grant INSERT on table "public"."laboratory_requests" to "authenticated";

grant REFERENCES on table "public"."laboratory_requests" to "authenticated";

grant SELECT on table "public"."laboratory_requests" to "authenticated";

grant TRIGGER on table "public"."laboratory_requests" to "authenticated";

grant TRUNCATE on table "public"."laboratory_requests" to "authenticated";

grant UPDATE on table "public"."laboratory_requests" to "authenticated";

grant DELETE on table "public"."laboratory_results" to "authenticated";

grant INSERT on table "public"."laboratory_results" to "authenticated";

grant REFERENCES on table "public"."laboratory_results" to "authenticated";

grant SELECT on table "public"."laboratory_results" to "authenticated";

grant TRIGGER on table "public"."laboratory_results" to "authenticated";

grant TRUNCATE on table "public"."laboratory_results" to "authenticated";

grant UPDATE on table "public"."laboratory_results" to "authenticated";

grant DELETE on table "public"."maintenance_windows" to "authenticated";

grant INSERT on table "public"."maintenance_windows" to "authenticated";

grant REFERENCES on table "public"."maintenance_windows" to "authenticated";

grant SELECT on table "public"."maintenance_windows" to "authenticated";

grant TRIGGER on table "public"."maintenance_windows" to "authenticated";

grant TRUNCATE on table "public"."maintenance_windows" to "authenticated";

grant UPDATE on table "public"."maintenance_windows" to "authenticated";

grant DELETE on table "public"."medical_documents" to "authenticated";

grant INSERT on table "public"."medical_documents" to "authenticated";

grant REFERENCES on table "public"."medical_documents" to "authenticated";

grant SELECT on table "public"."medical_documents" to "authenticated";

grant TRIGGER on table "public"."medical_documents" to "authenticated";

grant TRUNCATE on table "public"."medical_documents" to "authenticated";

grant UPDATE on table "public"."medical_documents" to "authenticated";

grant DELETE on table "public"."medical_record_access_logs" to "authenticated";

grant REFERENCES on table "public"."medical_record_access_logs" to "authenticated";

grant SELECT on table "public"."medical_record_access_logs" to "authenticated";

grant TRIGGER on table "public"."medical_record_access_logs" to "authenticated";

grant TRUNCATE on table "public"."medical_record_access_logs" to "authenticated";

grant UPDATE on table "public"."medical_record_access_logs" to "authenticated";

grant DELETE on table "public"."medical_records" to "authenticated";

grant INSERT on table "public"."medical_records" to "authenticated";

grant REFERENCES on table "public"."medical_records" to "authenticated";

grant SELECT on table "public"."medical_records" to "authenticated";

grant TRIGGER on table "public"."medical_records" to "authenticated";

grant TRUNCATE on table "public"."medical_records" to "authenticated";

grant UPDATE on table "public"."medical_records" to "authenticated";

grant DELETE on table "public"."medication_summary_days" to "authenticated";

grant INSERT on table "public"."medication_summary_days" to "authenticated";

grant REFERENCES on table "public"."medication_summary_days" to "authenticated";

grant SELECT on table "public"."medication_summary_days" to "authenticated";

grant TRIGGER on table "public"."medication_summary_days" to "authenticated";

grant TRUNCATE on table "public"."medication_summary_days" to "authenticated";

grant UPDATE on table "public"."medication_summary_days" to "authenticated";

grant DELETE on table "public"."notification_outbox" to "authenticated";

grant INSERT on table "public"."notification_outbox" to "authenticated";

grant REFERENCES on table "public"."notification_outbox" to "authenticated";

grant SELECT on table "public"."notification_outbox" to "authenticated";

grant TRIGGER on table "public"."notification_outbox" to "authenticated";

grant TRUNCATE on table "public"."notification_outbox" to "authenticated";

grant UPDATE on table "public"."notification_outbox" to "authenticated";

grant DELETE on table "public"."notification_preferences" to "authenticated";

grant INSERT on table "public"."notification_preferences" to "authenticated";

grant REFERENCES on table "public"."notification_preferences" to "authenticated";

grant SELECT on table "public"."notification_preferences" to "authenticated";

grant TRIGGER on table "public"."notification_preferences" to "authenticated";

grant TRUNCATE on table "public"."notification_preferences" to "authenticated";

grant UPDATE on table "public"."notification_preferences" to "authenticated";

grant DELETE on table "public"."notifications" to "authenticated";

grant INSERT on table "public"."notifications" to "authenticated";

grant REFERENCES on table "public"."notifications" to "authenticated";

grant SELECT on table "public"."notifications" to "authenticated";

grant TRIGGER on table "public"."notifications" to "authenticated";

grant TRUNCATE on table "public"."notifications" to "authenticated";

grant SELECT on table "public"."online_consultation_request_status_history" to "authenticated";

grant SELECT on table "public"."online_consultation_requests" to "authenticated";

grant SELECT on table "public"."patient_access_grants" to "authenticated";

grant SELECT on table "public"."patient_access_record_selections" to "authenticated";

grant SELECT on table "public"."patient_access_scopes" to "authenticated";

grant SELECT on table "public"."patient_care_relationships" to "authenticated";

grant SELECT on table "public"."patient_connection_requests" to "authenticated";

grant REFERENCES on table "public"."patient_consents" to "authenticated";

grant SELECT on table "public"."patient_consents" to "authenticated";

grant TRIGGER on table "public"."patient_consents" to "authenticated";

grant TRUNCATE on table "public"."patient_consents" to "authenticated";

grant SELECT on table "public"."patient_hospital_identifiers" to "authenticated";

grant SELECT on table "public"."patient_representatives" to "authenticated";

grant DELETE on table "public"."patients" to "authenticated";

grant INSERT on table "public"."patients" to "authenticated";

grant REFERENCES on table "public"."patients" to "authenticated";

grant SELECT on table "public"."patients" to "authenticated";

grant TRIGGER on table "public"."patients" to "authenticated";

grant TRUNCATE on table "public"."patients" to "authenticated";

grant UPDATE on table "public"."patients" to "authenticated";

grant DELETE on table "public"."prescription_orders" to "authenticated";

grant INSERT on table "public"."prescription_orders" to "authenticated";

grant REFERENCES on table "public"."prescription_orders" to "authenticated";

grant SELECT on table "public"."prescription_orders" to "authenticated";

grant TRIGGER on table "public"."prescription_orders" to "authenticated";

grant TRUNCATE on table "public"."prescription_orders" to "authenticated";

grant UPDATE on table "public"."prescription_orders" to "authenticated";

grant DELETE on table "public"."prescriptions" to "authenticated";

grant INSERT on table "public"."prescriptions" to "authenticated";

grant REFERENCES on table "public"."prescriptions" to "authenticated";

grant SELECT on table "public"."prescriptions" to "authenticated";

grant TRIGGER on table "public"."prescriptions" to "authenticated";

grant TRUNCATE on table "public"."prescriptions" to "authenticated";

grant UPDATE on table "public"."prescriptions" to "authenticated";

grant DELETE on table "public"."role_permissions" to "authenticated";

grant INSERT on table "public"."role_permissions" to "authenticated";

grant REFERENCES on table "public"."role_permissions" to "authenticated";

grant SELECT on table "public"."role_permissions" to "authenticated";

grant TRIGGER on table "public"."role_permissions" to "authenticated";

grant TRUNCATE on table "public"."role_permissions" to "authenticated";

grant UPDATE on table "public"."role_permissions" to "authenticated";

grant DELETE on table "public"."roles" to "authenticated";

grant INSERT on table "public"."roles" to "authenticated";

grant REFERENCES on table "public"."roles" to "authenticated";

grant SELECT on table "public"."roles" to "authenticated";

grant TRIGGER on table "public"."roles" to "authenticated";

grant TRUNCATE on table "public"."roles" to "authenticated";

grant UPDATE on table "public"."roles" to "authenticated";

grant DELETE on table "public"."security_logs" to "authenticated";

grant INSERT on table "public"."security_logs" to "authenticated";

grant REFERENCES on table "public"."security_logs" to "authenticated";

grant SELECT on table "public"."security_logs" to "authenticated";

grant TRIGGER on table "public"."security_logs" to "authenticated";

grant TRUNCATE on table "public"."security_logs" to "authenticated";

grant UPDATE on table "public"."security_logs" to "authenticated";

grant DELETE on table "public"."system_settings" to "authenticated";

grant INSERT on table "public"."system_settings" to "authenticated";

grant REFERENCES on table "public"."system_settings" to "authenticated";

grant SELECT on table "public"."system_settings" to "authenticated";

grant TRIGGER on table "public"."system_settings" to "authenticated";

grant TRUNCATE on table "public"."system_settings" to "authenticated";

grant UPDATE on table "public"."system_settings" to "authenticated";

grant DELETE on table "public"."treatment_plans" to "authenticated";

grant INSERT on table "public"."treatment_plans" to "authenticated";

grant REFERENCES on table "public"."treatment_plans" to "authenticated";

grant SELECT on table "public"."treatment_plans" to "authenticated";

grant TRIGGER on table "public"."treatment_plans" to "authenticated";

grant TRUNCATE on table "public"."treatment_plans" to "authenticated";

grant UPDATE on table "public"."treatment_plans" to "authenticated";

grant DELETE on table "public"."users" to "authenticated";

grant INSERT on table "public"."users" to "authenticated";

grant REFERENCES on table "public"."users" to "authenticated";

grant SELECT on table "public"."users" to "authenticated";

grant TRIGGER on table "public"."users" to "authenticated";

grant TRUNCATE on table "public"."users" to "authenticated";

grant UPDATE on table "public"."users" to "authenticated";

grant DELETE on table "public"."ai_assessment_recommendations" to "service_role";

grant INSERT on table "public"."ai_assessment_recommendations" to "service_role";

grant REFERENCES on table "public"."ai_assessment_recommendations" to "service_role";

grant SELECT on table "public"."ai_assessment_recommendations" to "service_role";

grant TRIGGER on table "public"."ai_assessment_recommendations" to "service_role";

grant TRUNCATE on table "public"."ai_assessment_recommendations" to "service_role";

grant UPDATE on table "public"."ai_assessment_recommendations" to "service_role";

grant DELETE on table "public"."ai_assessments" to "service_role";

grant INSERT on table "public"."ai_assessments" to "service_role";

grant REFERENCES on table "public"."ai_assessments" to "service_role";

grant SELECT on table "public"."ai_assessments" to "service_role";

grant TRIGGER on table "public"."ai_assessments" to "service_role";

grant TRUNCATE on table "public"."ai_assessments" to "service_role";

grant UPDATE on table "public"."ai_assessments" to "service_role";

grant DELETE on table "public"."ai_configurations" to "service_role";

grant INSERT on table "public"."ai_configurations" to "service_role";

grant REFERENCES on table "public"."ai_configurations" to "service_role";

grant SELECT on table "public"."ai_configurations" to "service_role";

grant TRIGGER on table "public"."ai_configurations" to "service_role";

grant TRUNCATE on table "public"."ai_configurations" to "service_role";

grant UPDATE on table "public"."ai_configurations" to "service_role";

grant DELETE on table "public"."appointment_reminder_jobs" to "service_role";

grant INSERT on table "public"."appointment_reminder_jobs" to "service_role";

grant REFERENCES on table "public"."appointment_reminder_jobs" to "service_role";

grant SELECT on table "public"."appointment_reminder_jobs" to "service_role";

grant TRIGGER on table "public"."appointment_reminder_jobs" to "service_role";

grant TRUNCATE on table "public"."appointment_reminder_jobs" to "service_role";

grant UPDATE on table "public"."appointment_reminder_jobs" to "service_role";

grant DELETE on table "public"."audit_logs" to "service_role";

grant INSERT on table "public"."audit_logs" to "service_role";

grant REFERENCES on table "public"."audit_logs" to "service_role";

grant SELECT on table "public"."audit_logs" to "service_role";

grant TRIGGER on table "public"."audit_logs" to "service_role";

grant TRUNCATE on table "public"."audit_logs" to "service_role";

grant UPDATE on table "public"."audit_logs" to "service_role";

grant DELETE on table "public"."care_assistant_conversations" to "service_role";

grant INSERT on table "public"."care_assistant_conversations" to "service_role";

grant REFERENCES on table "public"."care_assistant_conversations" to "service_role";

grant SELECT on table "public"."care_assistant_conversations" to "service_role";

grant TRIGGER on table "public"."care_assistant_conversations" to "service_role";

grant TRUNCATE on table "public"."care_assistant_conversations" to "service_role";

grant UPDATE on table "public"."care_assistant_conversations" to "service_role";

grant DELETE on table "public"."chat_conversations" to "service_role";

grant INSERT on table "public"."chat_conversations" to "service_role";

grant REFERENCES on table "public"."chat_conversations" to "service_role";

grant SELECT on table "public"."chat_conversations" to "service_role";

grant TRIGGER on table "public"."chat_conversations" to "service_role";

grant TRUNCATE on table "public"."chat_conversations" to "service_role";

grant UPDATE on table "public"."chat_conversations" to "service_role";

grant DELETE on table "public"."chat_message_attachments" to "service_role";

grant INSERT on table "public"."chat_message_attachments" to "service_role";

grant REFERENCES on table "public"."chat_message_attachments" to "service_role";

grant SELECT on table "public"."chat_message_attachments" to "service_role";

grant TRIGGER on table "public"."chat_message_attachments" to "service_role";

grant TRUNCATE on table "public"."chat_message_attachments" to "service_role";

grant UPDATE on table "public"."chat_message_attachments" to "service_role";

grant DELETE on table "public"."chat_messages" to "service_role";

grant INSERT on table "public"."chat_messages" to "service_role";

grant REFERENCES on table "public"."chat_messages" to "service_role";

grant SELECT on table "public"."chat_messages" to "service_role";

grant TRIGGER on table "public"."chat_messages" to "service_role";

grant TRUNCATE on table "public"."chat_messages" to "service_role";

grant UPDATE on table "public"."chat_messages" to "service_role";

grant DELETE on table "public"."clinical_record_addenda" to "service_role";

grant INSERT on table "public"."clinical_record_addenda" to "service_role";

grant REFERENCES on table "public"."clinical_record_addenda" to "service_role";

grant SELECT on table "public"."clinical_record_addenda" to "service_role";

grant TRIGGER on table "public"."clinical_record_addenda" to "service_role";

grant TRUNCATE on table "public"."clinical_record_addenda" to "service_role";

grant UPDATE on table "public"."clinical_record_addenda" to "service_role";

grant DELETE on table "public"."clinical_record_quarantine" to "service_role";

grant INSERT on table "public"."clinical_record_quarantine" to "service_role";

grant REFERENCES on table "public"."clinical_record_quarantine" to "service_role";

grant SELECT on table "public"."clinical_record_quarantine" to "service_role";

grant TRIGGER on table "public"."clinical_record_quarantine" to "service_role";

grant TRUNCATE on table "public"."clinical_record_quarantine" to "service_role";

grant UPDATE on table "public"."clinical_record_quarantine" to "service_role";

grant DELETE on table "public"."consultation_attachments" to "service_role";

grant INSERT on table "public"."consultation_attachments" to "service_role";

grant REFERENCES on table "public"."consultation_attachments" to "service_role";

grant SELECT on table "public"."consultation_attachments" to "service_role";

grant TRIGGER on table "public"."consultation_attachments" to "service_role";

grant TRUNCATE on table "public"."consultation_attachments" to "service_role";

grant UPDATE on table "public"."consultation_attachments" to "service_role";

grant DELETE on table "public"."consultation_status_history" to "service_role";

grant INSERT on table "public"."consultation_status_history" to "service_role";

grant REFERENCES on table "public"."consultation_status_history" to "service_role";

grant SELECT on table "public"."consultation_status_history" to "service_role";

grant TRIGGER on table "public"."consultation_status_history" to "service_role";

grant TRUNCATE on table "public"."consultation_status_history" to "service_role";

grant UPDATE on table "public"."consultation_status_history" to "service_role";

grant DELETE on table "public"."consultations" to "service_role";

grant INSERT on table "public"."consultations" to "service_role";

grant REFERENCES on table "public"."consultations" to "service_role";

grant SELECT on table "public"."consultations" to "service_role";

grant TRIGGER on table "public"."consultations" to "service_role";

grant TRUNCATE on table "public"."consultations" to "service_role";

grant UPDATE on table "public"."consultations" to "service_role";

grant DELETE on table "public"."diagnoses" to "service_role";

grant INSERT on table "public"."diagnoses" to "service_role";

grant REFERENCES on table "public"."diagnoses" to "service_role";

grant SELECT on table "public"."diagnoses" to "service_role";

grant TRIGGER on table "public"."diagnoses" to "service_role";

grant TRUNCATE on table "public"."diagnoses" to "service_role";

grant UPDATE on table "public"."diagnoses" to "service_role";

grant DELETE on table "public"."doctor_hospital_employments" to "service_role";

grant INSERT on table "public"."doctor_hospital_employments" to "service_role";

grant REFERENCES on table "public"."doctor_hospital_employments" to "service_role";

grant SELECT on table "public"."doctor_hospital_employments" to "service_role";

grant TRIGGER on table "public"."doctor_hospital_employments" to "service_role";

grant TRUNCATE on table "public"."doctor_hospital_employments" to "service_role";

grant UPDATE on table "public"."doctor_hospital_employments" to "service_role";

grant DELETE on table "public"."doctor_patient_assignments" to "service_role";

grant INSERT on table "public"."doctor_patient_assignments" to "service_role";

grant REFERENCES on table "public"."doctor_patient_assignments" to "service_role";

grant SELECT on table "public"."doctor_patient_assignments" to "service_role";

grant TRIGGER on table "public"."doctor_patient_assignments" to "service_role";

grant TRUNCATE on table "public"."doctor_patient_assignments" to "service_role";

grant UPDATE on table "public"."doctor_patient_assignments" to "service_role";

grant DELETE on table "public"."doctor_schedules" to "service_role";

grant INSERT on table "public"."doctor_schedules" to "service_role";

grant REFERENCES on table "public"."doctor_schedules" to "service_role";

grant SELECT on table "public"."doctor_schedules" to "service_role";

grant TRIGGER on table "public"."doctor_schedules" to "service_role";

grant TRUNCATE on table "public"."doctor_schedules" to "service_role";

grant UPDATE on table "public"."doctor_schedules" to "service_role";

grant DELETE on table "public"."doctors" to "service_role";

grant INSERT on table "public"."doctors" to "service_role";

grant REFERENCES on table "public"."doctors" to "service_role";

grant SELECT on table "public"."doctors" to "service_role";

grant TRIGGER on table "public"."doctors" to "service_role";

grant TRUNCATE on table "public"."doctors" to "service_role";

grant UPDATE on table "public"."doctors" to "service_role";

grant DELETE on table "public"."document_processing_jobs" to "service_role";

grant INSERT on table "public"."document_processing_jobs" to "service_role";

grant REFERENCES on table "public"."document_processing_jobs" to "service_role";

grant SELECT on table "public"."document_processing_jobs" to "service_role";

grant TRIGGER on table "public"."document_processing_jobs" to "service_role";

grant TRUNCATE on table "public"."document_processing_jobs" to "service_role";

grant UPDATE on table "public"."document_processing_jobs" to "service_role";

grant DELETE on table "public"."emergency_access_events" to "service_role";

grant INSERT on table "public"."emergency_access_events" to "service_role";

grant REFERENCES on table "public"."emergency_access_events" to "service_role";

grant SELECT on table "public"."emergency_access_events" to "service_role";

grant TRIGGER on table "public"."emergency_access_events" to "service_role";

grant TRUNCATE on table "public"."emergency_access_events" to "service_role";

grant UPDATE on table "public"."emergency_access_events" to "service_role";

grant DELETE on table "public"."emergency_room_status" to "service_role";

grant INSERT on table "public"."emergency_room_status" to "service_role";

grant REFERENCES on table "public"."emergency_room_status" to "service_role";

grant SELECT on table "public"."emergency_room_status" to "service_role";

grant TRIGGER on table "public"."emergency_room_status" to "service_role";

grant TRUNCATE on table "public"."emergency_room_status" to "service_role";

grant UPDATE on table "public"."emergency_room_status" to "service_role";

grant DELETE on table "public"."guest_consultation_requests" to "service_role";

grant INSERT on table "public"."guest_consultation_requests" to "service_role";

grant REFERENCES on table "public"."guest_consultation_requests" to "service_role";

grant SELECT on table "public"."guest_consultation_requests" to "service_role";

grant TRIGGER on table "public"."guest_consultation_requests" to "service_role";

grant TRUNCATE on table "public"."guest_consultation_requests" to "service_role";

grant UPDATE on table "public"."guest_consultation_requests" to "service_role";

grant DELETE on table "public"."guest_request_status_history" to "service_role";

grant INSERT on table "public"."guest_request_status_history" to "service_role";

grant REFERENCES on table "public"."guest_request_status_history" to "service_role";

grant SELECT on table "public"."guest_request_status_history" to "service_role";

grant TRIGGER on table "public"."guest_request_status_history" to "service_role";

grant TRUNCATE on table "public"."guest_request_status_history" to "service_role";

grant UPDATE on table "public"."guest_request_status_history" to "service_role";

grant DELETE on table "public"."healthcare_service_categories" to "service_role";

grant INSERT on table "public"."healthcare_service_categories" to "service_role";

grant REFERENCES on table "public"."healthcare_service_categories" to "service_role";

grant SELECT on table "public"."healthcare_service_categories" to "service_role";

grant TRIGGER on table "public"."healthcare_service_categories" to "service_role";

grant TRUNCATE on table "public"."healthcare_service_categories" to "service_role";

grant UPDATE on table "public"."healthcare_service_categories" to "service_role";

grant DELETE on table "public"."hospital_announcements" to "service_role";

grant INSERT on table "public"."hospital_announcements" to "service_role";

grant REFERENCES on table "public"."hospital_announcements" to "service_role";

grant SELECT on table "public"."hospital_announcements" to "service_role";

grant TRIGGER on table "public"."hospital_announcements" to "service_role";

grant TRUNCATE on table "public"."hospital_announcements" to "service_role";

grant UPDATE on table "public"."hospital_announcements" to "service_role";

grant DELETE on table "public"."hospital_beds" to "service_role";

grant INSERT on table "public"."hospital_beds" to "service_role";

grant REFERENCES on table "public"."hospital_beds" to "service_role";

grant SELECT on table "public"."hospital_beds" to "service_role";

grant TRIGGER on table "public"."hospital_beds" to "service_role";

grant TRUNCATE on table "public"."hospital_beds" to "service_role";

grant UPDATE on table "public"."hospital_beds" to "service_role";

grant DELETE on table "public"."hospital_classifications" to "service_role";

grant INSERT on table "public"."hospital_classifications" to "service_role";

grant REFERENCES on table "public"."hospital_classifications" to "service_role";

grant SELECT on table "public"."hospital_classifications" to "service_role";

grant TRIGGER on table "public"."hospital_classifications" to "service_role";

grant TRUNCATE on table "public"."hospital_classifications" to "service_role";

grant UPDATE on table "public"."hospital_classifications" to "service_role";

grant DELETE on table "public"."hospital_departments" to "service_role";

grant INSERT on table "public"."hospital_departments" to "service_role";

grant REFERENCES on table "public"."hospital_departments" to "service_role";

grant SELECT on table "public"."hospital_departments" to "service_role";

grant TRIGGER on table "public"."hospital_departments" to "service_role";

grant TRUNCATE on table "public"."hospital_departments" to "service_role";

grant UPDATE on table "public"."hospital_departments" to "service_role";

grant DELETE on table "public"."hospital_facility_status" to "service_role";

grant INSERT on table "public"."hospital_facility_status" to "service_role";

grant REFERENCES on table "public"."hospital_facility_status" to "service_role";

grant SELECT on table "public"."hospital_facility_status" to "service_role";

grant TRIGGER on table "public"."hospital_facility_status" to "service_role";

grant TRUNCATE on table "public"."hospital_facility_status" to "service_role";

grant UPDATE on table "public"."hospital_facility_status" to "service_role";

grant DELETE on table "public"."hospital_rooms" to "service_role";

grant INSERT on table "public"."hospital_rooms" to "service_role";

grant REFERENCES on table "public"."hospital_rooms" to "service_role";

grant SELECT on table "public"."hospital_rooms" to "service_role";

grant TRIGGER on table "public"."hospital_rooms" to "service_role";

grant TRUNCATE on table "public"."hospital_rooms" to "service_role";

grant UPDATE on table "public"."hospital_rooms" to "service_role";

grant DELETE on table "public"."hospital_service_doctors" to "service_role";

grant INSERT on table "public"."hospital_service_doctors" to "service_role";

grant REFERENCES on table "public"."hospital_service_doctors" to "service_role";

grant SELECT on table "public"."hospital_service_doctors" to "service_role";

grant TRIGGER on table "public"."hospital_service_doctors" to "service_role";

grant TRUNCATE on table "public"."hospital_service_doctors" to "service_role";

grant UPDATE on table "public"."hospital_service_doctors" to "service_role";

grant DELETE on table "public"."hospital_services" to "service_role";

grant INSERT on table "public"."hospital_services" to "service_role";

grant REFERENCES on table "public"."hospital_services" to "service_role";

grant SELECT on table "public"."hospital_services" to "service_role";

grant TRIGGER on table "public"."hospital_services" to "service_role";

grant TRUNCATE on table "public"."hospital_services" to "service_role";

grant UPDATE on table "public"."hospital_services" to "service_role";

grant DELETE on table "public"."hospitals" to "service_role";

grant INSERT on table "public"."hospitals" to "service_role";

grant REFERENCES on table "public"."hospitals" to "service_role";

grant SELECT on table "public"."hospitals" to "service_role";

grant TRIGGER on table "public"."hospitals" to "service_role";

grant TRUNCATE on table "public"."hospitals" to "service_role";

grant UPDATE on table "public"."hospitals" to "service_role";

grant DELETE on table "public"."laboratory_requests" to "service_role";

grant INSERT on table "public"."laboratory_requests" to "service_role";

grant REFERENCES on table "public"."laboratory_requests" to "service_role";

grant SELECT on table "public"."laboratory_requests" to "service_role";

grant TRIGGER on table "public"."laboratory_requests" to "service_role";

grant TRUNCATE on table "public"."laboratory_requests" to "service_role";

grant UPDATE on table "public"."laboratory_requests" to "service_role";

grant DELETE on table "public"."laboratory_results" to "service_role";

grant INSERT on table "public"."laboratory_results" to "service_role";

grant REFERENCES on table "public"."laboratory_results" to "service_role";

grant SELECT on table "public"."laboratory_results" to "service_role";

grant TRIGGER on table "public"."laboratory_results" to "service_role";

grant TRUNCATE on table "public"."laboratory_results" to "service_role";

grant UPDATE on table "public"."laboratory_results" to "service_role";

grant DELETE on table "public"."maintenance_windows" to "service_role";

grant INSERT on table "public"."maintenance_windows" to "service_role";

grant REFERENCES on table "public"."maintenance_windows" to "service_role";

grant SELECT on table "public"."maintenance_windows" to "service_role";

grant TRIGGER on table "public"."maintenance_windows" to "service_role";

grant TRUNCATE on table "public"."maintenance_windows" to "service_role";

grant UPDATE on table "public"."maintenance_windows" to "service_role";

grant DELETE on table "public"."medical_documents" to "service_role";

grant INSERT on table "public"."medical_documents" to "service_role";

grant REFERENCES on table "public"."medical_documents" to "service_role";

grant SELECT on table "public"."medical_documents" to "service_role";

grant TRIGGER on table "public"."medical_documents" to "service_role";

grant TRUNCATE on table "public"."medical_documents" to "service_role";

grant UPDATE on table "public"."medical_documents" to "service_role";

grant DELETE on table "public"."medical_record_access_logs" to "service_role";

grant INSERT on table "public"."medical_record_access_logs" to "service_role";

grant REFERENCES on table "public"."medical_record_access_logs" to "service_role";

grant SELECT on table "public"."medical_record_access_logs" to "service_role";

grant TRIGGER on table "public"."medical_record_access_logs" to "service_role";

grant TRUNCATE on table "public"."medical_record_access_logs" to "service_role";

grant UPDATE on table "public"."medical_record_access_logs" to "service_role";

grant DELETE on table "public"."medical_records" to "service_role";

grant INSERT on table "public"."medical_records" to "service_role";

grant REFERENCES on table "public"."medical_records" to "service_role";

grant SELECT on table "public"."medical_records" to "service_role";

grant TRIGGER on table "public"."medical_records" to "service_role";

grant TRUNCATE on table "public"."medical_records" to "service_role";

grant UPDATE on table "public"."medical_records" to "service_role";

grant DELETE on table "public"."medication_summary_days" to "service_role";

grant INSERT on table "public"."medication_summary_days" to "service_role";

grant REFERENCES on table "public"."medication_summary_days" to "service_role";

grant SELECT on table "public"."medication_summary_days" to "service_role";

grant TRIGGER on table "public"."medication_summary_days" to "service_role";

grant TRUNCATE on table "public"."medication_summary_days" to "service_role";

grant UPDATE on table "public"."medication_summary_days" to "service_role";

grant DELETE on table "public"."notification_outbox" to "service_role";

grant INSERT on table "public"."notification_outbox" to "service_role";

grant REFERENCES on table "public"."notification_outbox" to "service_role";

grant SELECT on table "public"."notification_outbox" to "service_role";

grant TRIGGER on table "public"."notification_outbox" to "service_role";

grant TRUNCATE on table "public"."notification_outbox" to "service_role";

grant UPDATE on table "public"."notification_outbox" to "service_role";

grant DELETE on table "public"."notification_preferences" to "service_role";

grant INSERT on table "public"."notification_preferences" to "service_role";

grant REFERENCES on table "public"."notification_preferences" to "service_role";

grant SELECT on table "public"."notification_preferences" to "service_role";

grant TRIGGER on table "public"."notification_preferences" to "service_role";

grant TRUNCATE on table "public"."notification_preferences" to "service_role";

grant UPDATE on table "public"."notification_preferences" to "service_role";

grant DELETE on table "public"."notifications" to "service_role";

grant INSERT on table "public"."notifications" to "service_role";

grant REFERENCES on table "public"."notifications" to "service_role";

grant SELECT on table "public"."notifications" to "service_role";

grant TRIGGER on table "public"."notifications" to "service_role";

grant TRUNCATE on table "public"."notifications" to "service_role";

grant UPDATE on table "public"."notifications" to "service_role";

grant DELETE on table "public"."online_consultation_request_status_history" to "service_role";

grant INSERT on table "public"."online_consultation_request_status_history" to "service_role";

grant REFERENCES on table "public"."online_consultation_request_status_history" to "service_role";

grant SELECT on table "public"."online_consultation_request_status_history" to "service_role";

grant TRIGGER on table "public"."online_consultation_request_status_history" to "service_role";

grant TRUNCATE on table "public"."online_consultation_request_status_history" to "service_role";

grant UPDATE on table "public"."online_consultation_request_status_history" to "service_role";

grant DELETE on table "public"."online_consultation_requests" to "service_role";

grant INSERT on table "public"."online_consultation_requests" to "service_role";

grant REFERENCES on table "public"."online_consultation_requests" to "service_role";

grant SELECT on table "public"."online_consultation_requests" to "service_role";

grant TRIGGER on table "public"."online_consultation_requests" to "service_role";

grant TRUNCATE on table "public"."online_consultation_requests" to "service_role";

grant UPDATE on table "public"."online_consultation_requests" to "service_role";

grant DELETE on table "public"."patient_access_grants" to "service_role";

grant INSERT on table "public"."patient_access_grants" to "service_role";

grant REFERENCES on table "public"."patient_access_grants" to "service_role";

grant SELECT on table "public"."patient_access_grants" to "service_role";

grant TRIGGER on table "public"."patient_access_grants" to "service_role";

grant TRUNCATE on table "public"."patient_access_grants" to "service_role";

grant UPDATE on table "public"."patient_access_grants" to "service_role";

grant DELETE on table "public"."patient_access_record_selections" to "service_role";

grant INSERT on table "public"."patient_access_record_selections" to "service_role";

grant REFERENCES on table "public"."patient_access_record_selections" to "service_role";

grant SELECT on table "public"."patient_access_record_selections" to "service_role";

grant TRIGGER on table "public"."patient_access_record_selections" to "service_role";

grant TRUNCATE on table "public"."patient_access_record_selections" to "service_role";

grant UPDATE on table "public"."patient_access_record_selections" to "service_role";

grant DELETE on table "public"."patient_access_scopes" to "service_role";

grant INSERT on table "public"."patient_access_scopes" to "service_role";

grant REFERENCES on table "public"."patient_access_scopes" to "service_role";

grant SELECT on table "public"."patient_access_scopes" to "service_role";

grant TRIGGER on table "public"."patient_access_scopes" to "service_role";

grant TRUNCATE on table "public"."patient_access_scopes" to "service_role";

grant UPDATE on table "public"."patient_access_scopes" to "service_role";

grant DELETE on table "public"."patient_care_relationships" to "service_role";

grant INSERT on table "public"."patient_care_relationships" to "service_role";

grant REFERENCES on table "public"."patient_care_relationships" to "service_role";

grant SELECT on table "public"."patient_care_relationships" to "service_role";

grant TRIGGER on table "public"."patient_care_relationships" to "service_role";

grant TRUNCATE on table "public"."patient_care_relationships" to "service_role";

grant UPDATE on table "public"."patient_care_relationships" to "service_role";

grant DELETE on table "public"."patient_connection_requests" to "service_role";

grant INSERT on table "public"."patient_connection_requests" to "service_role";

grant REFERENCES on table "public"."patient_connection_requests" to "service_role";

grant SELECT on table "public"."patient_connection_requests" to "service_role";

grant TRIGGER on table "public"."patient_connection_requests" to "service_role";

grant TRUNCATE on table "public"."patient_connection_requests" to "service_role";

grant UPDATE on table "public"."patient_connection_requests" to "service_role";

grant DELETE on table "public"."patient_consents" to "service_role";

grant INSERT on table "public"."patient_consents" to "service_role";

grant REFERENCES on table "public"."patient_consents" to "service_role";

grant SELECT on table "public"."patient_consents" to "service_role";

grant TRIGGER on table "public"."patient_consents" to "service_role";

grant TRUNCATE on table "public"."patient_consents" to "service_role";

grant UPDATE on table "public"."patient_consents" to "service_role";

grant DELETE on table "public"."patient_hospital_identifiers" to "service_role";

grant INSERT on table "public"."patient_hospital_identifiers" to "service_role";

grant REFERENCES on table "public"."patient_hospital_identifiers" to "service_role";

grant SELECT on table "public"."patient_hospital_identifiers" to "service_role";

grant TRIGGER on table "public"."patient_hospital_identifiers" to "service_role";

grant TRUNCATE on table "public"."patient_hospital_identifiers" to "service_role";

grant UPDATE on table "public"."patient_hospital_identifiers" to "service_role";

grant DELETE on table "public"."patient_representatives" to "service_role";

grant INSERT on table "public"."patient_representatives" to "service_role";

grant REFERENCES on table "public"."patient_representatives" to "service_role";

grant SELECT on table "public"."patient_representatives" to "service_role";

grant TRIGGER on table "public"."patient_representatives" to "service_role";

grant TRUNCATE on table "public"."patient_representatives" to "service_role";

grant UPDATE on table "public"."patient_representatives" to "service_role";

grant DELETE on table "public"."patients" to "service_role";

grant INSERT on table "public"."patients" to "service_role";

grant REFERENCES on table "public"."patients" to "service_role";

grant SELECT on table "public"."patients" to "service_role";

grant TRIGGER on table "public"."patients" to "service_role";

grant TRUNCATE on table "public"."patients" to "service_role";

grant UPDATE on table "public"."patients" to "service_role";

grant DELETE on table "public"."prescription_orders" to "service_role";

grant INSERT on table "public"."prescription_orders" to "service_role";

grant REFERENCES on table "public"."prescription_orders" to "service_role";

grant SELECT on table "public"."prescription_orders" to "service_role";

grant TRIGGER on table "public"."prescription_orders" to "service_role";

grant TRUNCATE on table "public"."prescription_orders" to "service_role";

grant UPDATE on table "public"."prescription_orders" to "service_role";

grant DELETE on table "public"."prescriptions" to "service_role";

grant INSERT on table "public"."prescriptions" to "service_role";

grant REFERENCES on table "public"."prescriptions" to "service_role";

grant SELECT on table "public"."prescriptions" to "service_role";

grant TRIGGER on table "public"."prescriptions" to "service_role";

grant TRUNCATE on table "public"."prescriptions" to "service_role";

grant UPDATE on table "public"."prescriptions" to "service_role";

grant DELETE on table "public"."role_permissions" to "service_role";

grant INSERT on table "public"."role_permissions" to "service_role";

grant REFERENCES on table "public"."role_permissions" to "service_role";

grant SELECT on table "public"."role_permissions" to "service_role";

grant TRIGGER on table "public"."role_permissions" to "service_role";

grant TRUNCATE on table "public"."role_permissions" to "service_role";

grant UPDATE on table "public"."role_permissions" to "service_role";

grant DELETE on table "public"."roles" to "service_role";

grant INSERT on table "public"."roles" to "service_role";

grant REFERENCES on table "public"."roles" to "service_role";

grant SELECT on table "public"."roles" to "service_role";

grant TRIGGER on table "public"."roles" to "service_role";

grant TRUNCATE on table "public"."roles" to "service_role";

grant UPDATE on table "public"."roles" to "service_role";

grant DELETE on table "public"."security_logs" to "service_role";

grant INSERT on table "public"."security_logs" to "service_role";

grant REFERENCES on table "public"."security_logs" to "service_role";

grant SELECT on table "public"."security_logs" to "service_role";

grant TRIGGER on table "public"."security_logs" to "service_role";

grant TRUNCATE on table "public"."security_logs" to "service_role";

grant UPDATE on table "public"."security_logs" to "service_role";

grant DELETE on table "public"."system_settings" to "service_role";

grant INSERT on table "public"."system_settings" to "service_role";

grant REFERENCES on table "public"."system_settings" to "service_role";

grant SELECT on table "public"."system_settings" to "service_role";

grant TRIGGER on table "public"."system_settings" to "service_role";

grant TRUNCATE on table "public"."system_settings" to "service_role";

grant UPDATE on table "public"."system_settings" to "service_role";

grant DELETE on table "public"."treatment_plans" to "service_role";

grant INSERT on table "public"."treatment_plans" to "service_role";

grant REFERENCES on table "public"."treatment_plans" to "service_role";

grant SELECT on table "public"."treatment_plans" to "service_role";

grant TRIGGER on table "public"."treatment_plans" to "service_role";

grant TRUNCATE on table "public"."treatment_plans" to "service_role";

grant UPDATE on table "public"."treatment_plans" to "service_role";

grant DELETE on table "public"."users" to "service_role";

grant INSERT on table "public"."users" to "service_role";

grant REFERENCES on table "public"."users" to "service_role";

grant SELECT on table "public"."users" to "service_role";

grant TRIGGER on table "public"."users" to "service_role";

grant TRUNCATE on table "public"."users" to "service_role";

grant UPDATE on table "public"."users" to "service_role";

grant DELETE on table "public"."video_sessions" to "service_role";

grant INSERT on table "public"."video_sessions" to "service_role";

grant REFERENCES on table "public"."video_sessions" to "service_role";

grant SELECT on table "public"."video_sessions" to "service_role";

grant TRIGGER on table "public"."video_sessions" to "service_role";

grant TRUNCATE on table "public"."video_sessions" to "service_role";

grant UPDATE on table "public"."video_sessions" to "service_role";

revoke all on function "public"."activate_approved_guest"(target_request_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."activate_approved_guest"(target_request_id uuid) to "authenticated";

grant EXECUTE on function "public"."activate_approved_guest"(target_request_id uuid) to "service_role";

revoke all on function "private"."activate_relationship_access"(target_relationship_id uuid, target_consent_id uuid, target_doctor_id uuid, target_consultation_id uuid, target_selected_records jsonb) from public,anon,authenticated;

revoke all on function "private"."actor_has_category_access"(target_patient_id uuid, target_category text) from public,anon,authenticated;

revoke all on function "public"."add_clinical_record_addendum"(target_resource_type text, target_record_id uuid, addendum_text text, correction_reason text) from public,anon,authenticated;

grant EXECUTE on function "public"."add_clinical_record_addendum"(target_resource_type text, target_record_id uuid, addendum_text text, correction_reason text) to "authenticated";

grant EXECUTE on function "public"."add_clinical_record_addendum"(target_resource_type text, target_record_id uuid, addendum_text text, correction_reason text) to "service_role";

revoke all on function "private"."apply_authenticated_prescription_signature"() from public,anon,authenticated;

revoke all on function "public"."approve_patient_care_relationship"(target_relationship_id uuid, assigned_doctor_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."approve_patient_care_relationship"(target_relationship_id uuid, assigned_doctor_id uuid) to "authenticated";

grant EXECUTE on function "public"."approve_patient_care_relationship"(target_relationship_id uuid, assigned_doctor_id uuid) to "service_role";

revoke all on function "public"."assign_doctor_department"(target_user_id uuid, target_department_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."assign_doctor_department"(target_user_id uuid, target_department_id uuid) to "authenticated";

grant EXECUTE on function "public"."assign_doctor_department"(target_user_id uuid, target_department_id uuid) to "service_role";

revoke all on function "private"."audit_multi_hospital_change"() from public,anon,authenticated;

grant EXECUTE on function "private"."audit_multi_hospital_change"() to public;

revoke all on function "public"."available_doctor_slots"(target_doctor_id uuid, target_date date, target_type consultation_type) from public,anon,authenticated;

grant EXECUTE on function "public"."available_doctor_slots"(target_doctor_id uuid, target_date date, target_type consultation_type) to "authenticated";

grant EXECUTE on function "public"."available_doctor_slots"(target_doctor_id uuid, target_date date, target_type consultation_type) to "service_role";

grant EXECUTE on function "public"."available_doctor_slots"(target_doctor_id uuid, target_date date, target_type consultation_type) to "anon";

revoke all on function "public"."begin_emergency_patient_access"(target_patient_id uuid, target_hospital_id uuid, emergency_reason text, target_categories text[], duration_minutes integer) from public,anon,authenticated;

grant EXECUTE on function "public"."begin_emergency_patient_access"(target_patient_id uuid, target_hospital_id uuid, emergency_reason text, target_categories text[], duration_minutes integer) to "authenticated";

grant EXECUTE on function "public"."begin_emergency_patient_access"(target_patient_id uuid, target_hospital_id uuid, emergency_reason text, target_categories text[], duration_minutes integer) to "service_role";

revoke all on function "public"."book_consultation_v2"(booking_payload jsonb) from public,anon,authenticated;

grant EXECUTE on function "public"."book_consultation_v2"(booking_payload jsonb) to "authenticated";

grant EXECUTE on function "public"."book_consultation_v2"(booking_payload jsonb) to "service_role";

revoke all on function "public"."book_consultation"(booking_payload jsonb) from public,anon,authenticated;

grant EXECUTE on function "public"."book_consultation"(booking_payload jsonb) to "authenticated";

grant EXECUTE on function "public"."book_consultation"(booking_payload jsonb) to "service_role";

revoke all on function "public"."book_doctor_consultation"(target_patient_id uuid, target_appointment_date timestamp with time zone, target_type consultation_type, target_chief_complaint text) from public,anon,authenticated;

grant EXECUTE on function "public"."book_doctor_consultation"(target_patient_id uuid, target_appointment_date timestamp with time zone, target_type consultation_type, target_chief_complaint text) to "authenticated";

grant EXECUTE on function "public"."book_doctor_consultation"(target_patient_id uuid, target_appointment_date timestamp with time zone, target_type consultation_type, target_chief_complaint text) to "service_role";

revoke all on function "private"."can_access_clinical_record"(target_patient_id uuid, target_source_hospital_id uuid, target_category text, target_record_id uuid, target_action text) from public,anon,authenticated;

grant EXECUTE on function "private"."can_access_clinical_record"(target_patient_id uuid, target_source_hospital_id uuid, target_category text, target_record_id uuid, target_action text) to "authenticated";

grant EXECUTE on function "private"."can_access_clinical_record"(target_patient_id uuid, target_source_hospital_id uuid, target_category text, target_record_id uuid, target_action text) to "service_role";

revoke all on function "private"."can_access_consultation_storage"(object_name text) from public,anon,authenticated;

grant EXECUTE on function "private"."can_access_consultation_storage"(object_name text) to "authenticated";

revoke all on function "private"."can_access_conversation"(target_conversation_id uuid) from public,anon,authenticated;

grant EXECUTE on function "private"."can_access_conversation"(target_conversation_id uuid) to "authenticated";

grant EXECUTE on function "private"."can_access_conversation"(target_conversation_id uuid) to "service_role";

revoke all on function "private"."can_access_direct_chat_storage"(object_name text) from public,anon,authenticated;

grant EXECUTE on function "private"."can_access_direct_chat_storage"(object_name text) to "authenticated";

grant EXECUTE on function "private"."can_access_direct_chat_storage"(object_name text) to "service_role";

revoke all on function "private"."can_access_guest_request"(target_request_id uuid) from public,anon,authenticated;

grant EXECUTE on function "private"."can_access_guest_request"(target_request_id uuid) to "authenticated";

grant EXECUTE on function "private"."can_access_guest_request"(target_request_id uuid) to "service_role";

revoke all on function "private"."can_access_guest_storage"(object_name text) from public,anon,authenticated;

grant EXECUTE on function "private"."can_access_guest_storage"(object_name text) to "authenticated";

revoke all on function "private"."can_access_online_request"(target_request_id uuid) from public,anon,authenticated;

grant EXECUTE on function "private"."can_access_online_request"(target_request_id uuid) to "authenticated";

grant EXECUTE on function "private"."can_access_online_request"(target_request_id uuid) to "service_role";

revoke all on function "private"."can_access_patient_storage"(object_name text, object_bucket text, target_action text) from public,anon,authenticated;

grant EXECUTE on function "private"."can_access_patient_storage"(object_name text, object_bucket text, target_action text) to "authenticated";

grant EXECUTE on function "private"."can_access_patient_storage"(object_name text, object_bucket text, target_action text) to "service_role";

revoke all on function "private"."can_access_patient_storage"(object_name text) from public,anon,authenticated;

grant EXECUTE on function "private"."can_access_patient_storage"(object_name text) to "authenticated";

grant EXECUTE on function "private"."can_access_patient_storage"(object_name text) to "service_role";

revoke all on function "private"."can_access_patient"(target_patient_id uuid) from public,anon,authenticated;

grant EXECUTE on function "private"."can_access_patient"(target_patient_id uuid) to "authenticated";

grant EXECUTE on function "private"."can_access_patient"(target_patient_id uuid) to "service_role";

revoke all on function "private"."can_create_assigned_patient_document"(target_patient_id uuid, target_hospital_id uuid) from public,anon,authenticated;

grant EXECUTE on function "private"."can_create_assigned_patient_document"(target_patient_id uuid, target_hospital_id uuid) to "authenticated";

grant EXECUTE on function "private"."can_create_assigned_patient_document"(target_patient_id uuid, target_hospital_id uuid) to "service_role";

revoke all on function "private"."can_manage_hospital_storage"(object_name text) from public,anon,authenticated;

grant EXECUTE on function "private"."can_manage_hospital_storage"(object_name text) to "authenticated";

revoke all on function "private"."can_participate_conversation"(target_conversation_id uuid) from public,anon,authenticated;

grant EXECUTE on function "private"."can_participate_conversation"(target_conversation_id uuid) to "authenticated";

grant EXECUTE on function "private"."can_participate_conversation"(target_conversation_id uuid) to "service_role";

revoke all on function "private"."can_send_to_conversation"(target_conversation_id uuid) from public,anon,authenticated;

grant EXECUTE on function "private"."can_send_to_conversation"(target_conversation_id uuid) to "authenticated";

grant EXECUTE on function "private"."can_send_to_conversation"(target_conversation_id uuid) to "service_role";

revoke all on function "private"."can_upload_patient_storage"(object_name text, object_bucket text) from public,anon,authenticated;

grant EXECUTE on function "private"."can_upload_patient_storage"(object_name text, object_bucket text) to "authenticated";

grant EXECUTE on function "private"."can_upload_patient_storage"(object_name text, object_bucket text) to "service_role";

revoke all on function "private"."can_view_user"(target_user_id uuid) from public,anon,authenticated;

grant EXECUTE on function "private"."can_view_user"(target_user_id uuid) to "authenticated";

grant EXECUTE on function "private"."can_view_user"(target_user_id uuid) to "service_role";

revoke all on function "public"."cancel_consultation"(target_consultation_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."cancel_consultation"(target_consultation_id uuid) to "authenticated";

grant EXECUTE on function "public"."cancel_consultation"(target_consultation_id uuid) to "service_role";

revoke all on function "public"."cancel_online_consultation_request"(target_request_id uuid, cancellation_reason text) from public,anon,authenticated;

grant EXECUTE on function "public"."cancel_online_consultation_request"(target_request_id uuid, cancellation_reason text) to "authenticated";

grant EXECUTE on function "public"."cancel_online_consultation_request"(target_request_id uuid, cancellation_reason text) to "service_role";

revoke all on function "public"."claim_notification_outbox"(batch_size integer) from public,anon,authenticated;

grant EXECUTE on function "public"."claim_notification_outbox"(batch_size integer) to "service_role";

revoke all on function "public"."complete_notification_delivery"(target_outbox_id bigint, delivered boolean, provider_id text, error_message text) from public,anon,authenticated;

grant EXECUTE on function "public"."complete_notification_delivery"(target_outbox_id bigint, delivered boolean, provider_id text, error_message text) to "service_role";

revoke all on function "public"."confirm_medical_result"(target_result_id uuid, confirmed_findings text, interpretation text, create_record boolean) from public,anon,authenticated;

grant EXECUTE on function "public"."confirm_medical_result"(target_result_id uuid, confirmed_findings text, interpretation text, create_record boolean) to "authenticated";

grant EXECUTE on function "public"."confirm_medical_result"(target_result_id uuid, confirmed_findings text, interpretation text, create_record boolean) to "service_role";

revoke all on function "private"."current_doctor_id"() from public,anon,authenticated;

grant EXECUTE on function "private"."current_doctor_id"() to "authenticated";

grant EXECUTE on function "private"."current_doctor_id"() to "service_role";

revoke all on function "private"."current_hospital_id"() from public,anon,authenticated;

grant EXECUTE on function "private"."current_hospital_id"() to "authenticated";

grant EXECUTE on function "private"."current_hospital_id"() to "service_role";

revoke all on function "private"."current_patient_id"() from public,anon,authenticated;

grant EXECUTE on function "private"."current_patient_id"() to "authenticated";

grant EXECUTE on function "private"."current_patient_id"() to "service_role";

revoke all on function "public"."current_permissions"() from public,anon,authenticated;

grant EXECUTE on function "public"."current_permissions"() to "authenticated";

grant EXECUTE on function "public"."current_permissions"() to "service_role";

revoke all on function "private"."current_role"() from public,anon,authenticated;

grant EXECUTE on function "private"."current_role"() to "authenticated";

grant EXECUTE on function "private"."current_role"() to "service_role";

revoke all on function "private"."current_user_id"() from public,anon,authenticated;

grant EXECUTE on function "private"."current_user_id"() to "authenticated";

grant EXECUTE on function "private"."current_user_id"() to "service_role";

revoke all on function "public"."decide_patient_connection_request"(target_request_id uuid, approve_request boolean) from public,anon,authenticated;

grant EXECUTE on function "public"."decide_patient_connection_request"(target_request_id uuid, approve_request boolean) to "authenticated";

grant EXECUTE on function "public"."decide_patient_connection_request"(target_request_id uuid, approve_request boolean) to "service_role";

revoke all on function "public"."delete_own_medical_document"(target_document_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."delete_own_medical_document"(target_document_id uuid) to "authenticated";

grant EXECUTE on function "public"."delete_own_medical_document"(target_document_id uuid) to "service_role";

revoke all on function "private"."derive_emergency_capacity"() from public,anon,authenticated;

grant EXECUTE on function "private"."derive_emergency_capacity"() to public;

revoke all on function "public"."end_emergency_patient_access"(target_event_id uuid, review_note text) from public,anon,authenticated;

grant EXECUTE on function "public"."end_emergency_patient_access"(target_event_id uuid, review_note text) to "authenticated";

grant EXECUTE on function "public"."end_emergency_patient_access"(target_event_id uuid, review_note text) to "service_role";

revoke all on function "private"."end_replaced_doctor_patient_assignment"() from public,anon,authenticated;

revoke all on function "private"."enforce_clinical_provenance"() from public,anon,authenticated;

grant EXECUTE on function "private"."enforce_clinical_provenance"() to public;

revoke all on function "private"."enforce_consultation_assignment_provenance"() from public,anon,authenticated;

grant EXECUTE on function "private"."enforce_consultation_assignment_provenance"() to public;

revoke all on function "public"."enforce_consultation_change"() from public,anon,authenticated;

grant EXECUTE on function "public"."enforce_consultation_change"() to "service_role";

revoke all on function "public"."enforce_guest_request_change"() from public,anon,authenticated;

grant EXECUTE on function "public"."enforce_guest_request_change"() to "service_role";

revoke all on function "private"."enforce_reservation_lead_time"() from public,anon,authenticated;

revoke all on function "public"."enqueue_due_appointment_reminders"(batch_size integer, reminder_window interval) from public,anon,authenticated;

grant EXECUTE on function "public"."enqueue_due_appointment_reminders"(batch_size integer, reminder_window interval) to "service_role";

revoke all on function "public"."enqueue_due_medication_summaries"(batch_size integer) from public,anon,authenticated;

grant EXECUTE on function "public"."enqueue_due_medication_summaries"(batch_size integer) to "service_role";

revoke all on function "private"."enqueue_hospital_audience"(target_hospital_id uuid, target_title text, target_message text, target_type text, target_reference_id uuid, target_data jsonb) from public,anon,authenticated;

revoke all on function "private"."enqueue_notification"(target_user_id uuid, target_title text, target_message text, target_type text, target_reference_id uuid, target_data jsonb) from public,anon,authenticated;

revoke all on function "private"."enrich_connection_request_notification"() from public,anon,authenticated;

revoke all on function "public"."ensure_consultation_conversation"(target_consultation_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."ensure_consultation_conversation"(target_consultation_id uuid) to "authenticated";

grant EXECUTE on function "public"."ensure_consultation_conversation"(target_consultation_id uuid) to "service_role";

revoke all on function "public"."ensure_patient_conversation"(target_patient_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."ensure_patient_conversation"(target_patient_id uuid) to "authenticated";

grant EXECUTE on function "public"."ensure_patient_conversation"(target_patient_id uuid) to "service_role";

revoke all on function "public"."ensure_video_session"(target_consultation_id uuid, target_provider text) from public,anon,authenticated;

grant EXECUTE on function "public"."ensure_video_session"(target_consultation_id uuid, target_provider text) to "authenticated";

grant EXECUTE on function "public"."ensure_video_session"(target_consultation_id uuid, target_provider text) to "service_role";

revoke all on function "private"."finalize_online_outcome"() from public,anon,authenticated;

revoke all on function "public"."get_approved_video_room"(target_consultation_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."get_approved_video_room"(target_consultation_id uuid) to "authenticated";

grant EXECUTE on function "public"."get_approved_video_room"(target_consultation_id uuid) to "service_role";

revoke all on function "public"."get_authorized_medical_document_download"(target_document_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."get_authorized_medical_document_download"(target_document_id uuid) to "authenticated";

grant EXECUTE on function "public"."get_authorized_medical_document_download"(target_document_id uuid) to "service_role";

revoke all on function "public"."get_consultation_patient_context"(target_consultation_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."get_consultation_patient_context"(target_consultation_id uuid) to "authenticated";

grant EXECUTE on function "public"."get_consultation_patient_context"(target_consultation_id uuid) to "service_role";

revoke all on function "public"."get_guest_consultation_request_tracking"(target_reference text) from public,anon,authenticated;

grant EXECUTE on function "public"."get_guest_consultation_request_tracking"(target_reference text) to "authenticated";

grant EXECUTE on function "public"."get_guest_consultation_request_tracking"(target_reference text) to "service_role";

revoke all on function "public"."get_online_consultation_request_tracking"(target_reference text) from public,anon,authenticated;

grant EXECUTE on function "public"."get_online_consultation_request_tracking"(target_reference text) to "authenticated";

grant EXECUTE on function "public"."get_online_consultation_request_tracking"(target_reference text) to "service_role";

revoke all on function "public"."get_patient_medical_records"(target_patient_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."get_patient_medical_records"(target_patient_id uuid) to "authenticated";

grant EXECUTE on function "public"."get_patient_medical_records"(target_patient_id uuid) to "service_role";

revoke all on function "private"."guard_clinical_consultation"() from public,anon,authenticated;

revoke all on function "private"."guard_document_review"() from public,anon,authenticated;

revoke all on function "private"."guard_online_request_change"() from public,anon,authenticated;

revoke all on function "private"."guard_prescription_order_reference"() from public,anon,authenticated;

revoke all on function "private"."guard_source_document_record"() from public,anon,authenticated;

revoke all on function "public"."handle_new_auth_user"() from public,anon,authenticated;

grant EXECUTE on function "public"."handle_new_auth_user"() to "service_role";

revoke all on function "private"."has_active_doctor_employment"(target_doctor_id uuid, target_hospital_id uuid) from public,anon,authenticated;

grant EXECUTE on function "private"."has_active_doctor_employment"(target_doctor_id uuid, target_hospital_id uuid) to "authenticated";

grant EXECUTE on function "private"."has_active_doctor_employment"(target_doctor_id uuid, target_hospital_id uuid) to "service_role";

revoke all on function "private"."has_online_reviewer"(target_hospital uuid) from public,anon,authenticated;

revoke all on function "private"."has_permission"(target_permission text) from public,anon,authenticated;

grant EXECUTE on function "private"."has_permission"(target_permission text) to "authenticated";

revoke all on function "public"."hospital_analytics"() from public,anon,authenticated;

grant EXECUTE on function "public"."hospital_analytics"() to "authenticated";

grant EXECUTE on function "public"."hospital_analytics"() to "service_role";

revoke all on function "public"."invalidate_video_session_after_consultation_change"() from public,anon,authenticated;

grant EXECUTE on function "public"."invalidate_video_session_after_consultation_change"() to "service_role";

revoke all on function "private"."is_active_care_relationship"(target_relationship_id uuid, target_patient_id uuid, target_hospital_id uuid, target_doctor_id uuid) from public,anon,authenticated;

grant EXECUTE on function "private"."is_active_care_relationship"(target_relationship_id uuid, target_patient_id uuid, target_hospital_id uuid, target_doctor_id uuid) to "authenticated";

grant EXECUTE on function "private"."is_active_care_relationship"(target_relationship_id uuid, target_patient_id uuid, target_hospital_id uuid, target_doctor_id uuid) to "service_role";

revoke all on function "private"."is_consultation_participant"(target_consultation_id uuid) from public,anon,authenticated;

grant EXECUTE on function "private"."is_consultation_participant"(target_consultation_id uuid) to "authenticated";

revoke all on function "private"."is_doctor_slot_available"(target_doctor_id uuid, target_hospital_id uuid, target_type consultation_type, target_start timestamp with time zone, excluded_consultation_id uuid) from public,anon,authenticated;

grant EXECUTE on function "private"."is_doctor_slot_available"(target_doctor_id uuid, target_hospital_id uuid, target_type consultation_type, target_start timestamp with time zone, excluded_consultation_id uuid) to "authenticated";

revoke all on function "private"."is_hospital_admin_for"(target_hospital_id uuid) from public,anon,authenticated;

grant EXECUTE on function "private"."is_hospital_admin_for"(target_hospital_id uuid) to "authenticated";

grant EXECUTE on function "private"."is_hospital_admin_for"(target_hospital_id uuid) to "service_role";

revoke all on function "private"."is_storage_upload_owner"(object_name text) from public,anon,authenticated;

grant EXECUTE on function "private"."is_storage_upload_owner"(object_name text) to "authenticated";

grant EXECUTE on function "private"."is_storage_upload_owner"(object_name text) to "service_role";

revoke all on function "private"."is_super_admin"() from public,anon,authenticated;

grant EXECUTE on function "private"."is_super_admin"() to "authenticated";

grant EXECUTE on function "private"."is_super_admin"() to "service_role";

revoke all on function "public"."issue_prescription_order"(order_payload jsonb, idempotency_key text) from public,anon,authenticated;

grant EXECUTE on function "public"."issue_prescription_order"(order_payload jsonb, idempotency_key text) to "authenticated";

grant EXECUTE on function "public"."issue_prescription_order"(order_payload jsonb, idempotency_key text) to "service_role";

revoke all on function "public"."link_existing_patient"(target_patient_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."link_existing_patient"(target_patient_id uuid) to "authenticated";

grant EXECUTE on function "public"."link_existing_patient"(target_patient_id uuid) to "service_role";

revoke all on function "public"."link_guest_patient_account"(target_request_id uuid, target_user_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."link_guest_patient_account"(target_request_id uuid, target_user_id uuid) to "authenticated";

grant EXECUTE on function "public"."link_guest_patient_account"(target_request_id uuid, target_user_id uuid) to "service_role";

revoke all on function "public"."link_guest_patient_to_consultation"() from public,anon,authenticated;

grant EXECUTE on function "public"."link_guest_patient_to_consultation"() to "service_role";

revoke all on function "public"."list_available_consultation_slots"(target_doctor_id uuid, target_type consultation_type, horizon_days integer) from public,anon,authenticated;

grant EXECUTE on function "public"."list_available_consultation_slots"(target_doctor_id uuid, target_type consultation_type, horizon_days integer) to "authenticated";

grant EXECUTE on function "public"."list_available_consultation_slots"(target_doctor_id uuid, target_type consultation_type, horizon_days integer) to "service_role";

grant EXECUTE on function "public"."list_available_consultation_slots"(target_doctor_id uuid, target_type consultation_type, horizon_days integer) to "anon";

revoke all on function "public"."list_online_booking_hospitals"() from public,anon,authenticated;

grant EXECUTE on function "public"."list_online_booking_hospitals"() to "anon";

grant EXECUTE on function "public"."list_online_booking_hospitals"() to "authenticated";

grant EXECUTE on function "public"."list_online_booking_hospitals"() to "service_role";

revoke all on function "public"."list_patient_sharing_relationships"() from public,anon,authenticated;

grant EXECUTE on function "public"."list_patient_sharing_relationships"() to "authenticated";

grant EXECUTE on function "public"."list_patient_sharing_relationships"() to "service_role";

revoke all on function "private"."lock_consultation_reservation"() from public,anon,authenticated;

revoke all on function "private"."lock_doctor_schedule"(target_doctor uuid) from public,anon,authenticated;

revoke all on function "public"."log_audit_event"() from public,anon,authenticated;

grant EXECUTE on function "public"."log_audit_event"() to "service_role";

revoke all on function "public"."log_user_security_change"() from public,anon,authenticated;

grant EXECUTE on function "public"."log_user_security_change"() to "service_role";

revoke all on function "public"."mark_conversation_read"(target_conversation_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."mark_conversation_read"(target_conversation_id uuid) to "authenticated";

grant EXECUTE on function "public"."mark_conversation_read"(target_conversation_id uuid) to "service_role";

revoke all on function "private"."mark_guest_request_approved_for_consultation"() from public,anon,authenticated;

revoke all on function "public"."mark_notification_read"(target_notification_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."mark_notification_read"(target_notification_id uuid) to "authenticated";

grant EXECUTE on function "public"."mark_notification_read"(target_notification_id uuid) to "service_role";

revoke all on function "private"."medication_summary"(target_patient uuid, target_date date, target_order uuid) from public,anon,authenticated;

revoke all on function "private"."meets_reservation_lead_time"(target_start timestamp with time zone) from public,anon,authenticated;

revoke all on function "public"."nearby_hospitals"(user_latitude double precision, user_longitude double precision, radius_km double precision) from public,anon,authenticated;

grant EXECUTE on function "public"."nearby_hospitals"(user_latitude double precision, user_longitude double precision, radius_km double precision) to public;

grant EXECUTE on function "public"."nearby_hospitals"(user_latitude double precision, user_longitude double precision, radius_km double precision) to "anon";

grant EXECUTE on function "public"."nearby_hospitals"(user_latitude double precision, user_longitude double precision, radius_km double precision) to "authenticated";

grant EXECUTE on function "public"."nearby_hospitals"(user_latitude double precision, user_longitude double precision, radius_km double precision) to "service_role";

revoke all on function "private"."notification_action_path"(target_type text, target_data jsonb) from public,anon,authenticated;

revoke all on function "private"."notification_delivery_status"(notification_id uuid) from public,anon,authenticated;

revoke all on function "public"."notification_email_allowed"(target_notification uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."notification_email_allowed"(target_notification uuid) to "service_role";

revoke all on function "public"."notify_chat_message"() from public,anon,authenticated;

grant EXECUTE on function "public"."notify_chat_message"() to "service_role";

revoke all on function "public"."notify_consultation_status_change"() from public,anon,authenticated;

grant EXECUTE on function "public"."notify_consultation_status_change"() to "service_role";

revoke all on function "public"."notify_hospital_announcement"() from public,anon,authenticated;

grant EXECUTE on function "public"."notify_hospital_announcement"() to "service_role";

revoke all on function "public"."notify_hospital_status_alert"() from public,anon,authenticated;

grant EXECUTE on function "public"."notify_hospital_status_alert"() to "service_role";

revoke all on function "public"."notify_laboratory_result_ready"() from public,anon,authenticated;

grant EXECUTE on function "public"."notify_laboratory_result_ready"() to "service_role";

revoke all on function "public"."notify_patient_account_activation"() from public,anon,authenticated;

grant EXECUTE on function "public"."notify_patient_account_activation"() to "service_role";

revoke all on function "public"."notify_prescription_created"() from public,anon,authenticated;

grant EXECUTE on function "public"."notify_prescription_created"() to "service_role";

revoke all on function "public"."platform_analytics"() from public,anon,authenticated;

grant EXECUTE on function "public"."platform_analytics"() to "authenticated";

grant EXECUTE on function "public"."platform_analytics"() to "service_role";

revoke all on function "public"."protect_chat_message"() from public,anon,authenticated;

grant EXECUTE on function "public"."protect_chat_message"() to "service_role";

revoke all on function "public"."protect_hospital_approval_fields"() from public,anon,authenticated;

grant EXECUTE on function "public"."protect_hospital_approval_fields"() to "service_role";

revoke all on function "public"."protect_laboratory_confirmation"() from public,anon,authenticated;

grant EXECUTE on function "public"."protect_laboratory_confirmation"() to "service_role";

revoke all on function "private"."protect_reserved_schedule"() from public,anon,authenticated;

revoke all on function "public"."protect_user_privileges"() from public,anon,authenticated;

grant EXECUTE on function "public"."protect_user_privileges"() to "service_role";

revoke all on function "private"."queue_confirmed_consultation_email"() from public,anon,authenticated;

revoke all on function "public"."queue_notification_deliveries"() from public,anon,authenticated;

grant EXECUTE on function "public"."queue_notification_deliveries"() to "service_role";

revoke all on function "public"."queue_patient_email"(target_patient_id uuid, target_order_id uuid, message_kind text) from public,anon,authenticated;

grant EXECUTE on function "public"."queue_patient_email"(target_patient_id uuid, target_order_id uuid, message_kind text) to "authenticated";

grant EXECUTE on function "public"."queue_patient_email"(target_patient_id uuid, target_order_id uuid, message_kind text) to "service_role";

revoke all on function "private"."queue_prescription_order_notification"(target_order uuid) from public,anon,authenticated;

revoke all on function "public"."reassign_consultation_doctor"(target_consultation_id uuid, new_doctor_id uuid, reason text) from public,anon,authenticated;

grant EXECUTE on function "public"."reassign_consultation_doctor"(target_consultation_id uuid, new_doctor_id uuid, reason text) to "authenticated";

grant EXECUTE on function "public"."reassign_consultation_doctor"(target_consultation_id uuid, new_doctor_id uuid, reason text) to "service_role";

revoke all on function "public"."recommend_hospitals"(user_latitude double precision, user_longitude double precision, required_department text, required_services text[], required_specialization text, requires_emergency boolean, radius_km double precision, result_limit integer) from public,anon,authenticated;

grant EXECUTE on function "public"."recommend_hospitals"(user_latitude double precision, user_longitude double precision, required_department text, required_services text[], required_specialization text, requires_emergency boolean, radius_km double precision, result_limit integer) to "anon";

grant EXECUTE on function "public"."recommend_hospitals"(user_latitude double precision, user_longitude double precision, required_department text, required_services text[], required_specialization text, requires_emergency boolean, radius_km double precision, result_limit integer) to "authenticated";

grant EXECUTE on function "public"."recommend_hospitals"(user_latitude double precision, user_longitude double precision, required_department text, required_services text[], required_specialization text, requires_emergency boolean, radius_km double precision, result_limit integer) to "service_role";

revoke all on function "public"."record_clinical_access"(target_resource_type text, target_resource_id uuid, target_action text) from public,anon,authenticated;

grant EXECUTE on function "public"."record_clinical_access"(target_resource_type text, target_resource_id uuid, target_action text) to "authenticated";

grant EXECUTE on function "public"."record_clinical_access"(target_resource_type text, target_resource_id uuid, target_action text) to "service_role";

revoke all on function "public"."record_consultation_status_history"() from public,anon,authenticated;

grant EXECUTE on function "public"."record_consultation_status_history"() to "service_role";

revoke all on function "public"."record_guest_status_history"() from public,anon,authenticated;

grant EXECUTE on function "public"."record_guest_status_history"() to "service_role";

revoke all on function "private"."record_online_request_status"() from public,anon,authenticated;

grant EXECUTE on function "private"."record_online_request_status"() to public;

revoke all on function "public"."record_patient_checkup"(target_patient_id uuid, checkup_payload jsonb, recorded_at timestamp with time zone) from public,anon,authenticated;

grant EXECUTE on function "public"."record_patient_checkup"(target_patient_id uuid, checkup_payload jsonb, recorded_at timestamp with time zone) to "authenticated";

grant EXECUTE on function "public"."record_patient_checkup"(target_patient_id uuid, checkup_payload jsonb, recorded_at timestamp with time zone) to "service_role";

revoke all on function "public"."rename_own_medical_document"(target_document_id uuid, target_title text) from public,anon,authenticated;

grant EXECUTE on function "public"."rename_own_medical_document"(target_document_id uuid, target_title text) to "authenticated";

grant EXECUTE on function "public"."rename_own_medical_document"(target_document_id uuid, target_title text) to "service_role";

revoke all on function "public"."replace_hospital_service_doctors"(target_service_id uuid, target_doctor_ids uuid[], target_primary_doctor_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."replace_hospital_service_doctors"(target_service_id uuid, target_doctor_ids uuid[], target_primary_doctor_id uuid) to "authenticated";

grant EXECUTE on function "public"."replace_hospital_service_doctors"(target_service_id uuid, target_doctor_ids uuid[], target_primary_doctor_id uuid) to "service_role";

revoke all on function "public"."request_patient_care_relationship"(target_hospital_id uuid, target_doctor_id uuid, target_relationship_type text, target_purpose text, target_categories text[], requested_expiry timestamp with time zone) from public,anon,authenticated;

grant EXECUTE on function "public"."request_patient_care_relationship"(target_hospital_id uuid, target_doctor_id uuid, target_relationship_type text, target_purpose text, target_categories text[], requested_expiry timestamp with time zone) to "authenticated";

grant EXECUTE on function "public"."request_patient_care_relationship"(target_hospital_id uuid, target_doctor_id uuid, target_relationship_type text, target_purpose text, target_categories text[], requested_expiry timestamp with time zone) to "service_role";

revoke all on function "public"."reschedule_consultation"(target_consultation_id uuid, scheduled_for timestamp with time zone) from public,anon,authenticated;

grant EXECUTE on function "public"."reschedule_consultation"(target_consultation_id uuid, scheduled_for timestamp with time zone) to "authenticated";

grant EXECUTE on function "public"."reschedule_consultation"(target_consultation_id uuid, scheduled_for timestamp with time zone) to "service_role";

revoke all on function "public"."respond_online_consultation_request"(target_request_id uuid, response_action text, response_text text) from public,anon,authenticated;

grant EXECUTE on function "public"."respond_online_consultation_request"(target_request_id uuid, response_action text, response_text text) to "authenticated";

grant EXECUTE on function "public"."respond_online_consultation_request"(target_request_id uuid, response_action text, response_text text) to "service_role";

revoke all on function "public"."review_guest_consultation"(target_request_id uuid, decision text, target_doctor_id uuid, target_appointment_date timestamp with time zone, review_notes text) from public,anon,authenticated;

grant EXECUTE on function "public"."review_guest_consultation"(target_request_id uuid, decision text, target_doctor_id uuid, target_appointment_date timestamp with time zone, review_notes text) to "authenticated";

grant EXECUTE on function "public"."review_guest_consultation"(target_request_id uuid, decision text, target_doctor_id uuid, target_appointment_date timestamp with time zone, review_notes text) to "service_role";

revoke all on function "public"."review_hospital_application"(target_hospital_id uuid, decision verification_status, decision_note text) from public,anon,authenticated;

grant EXECUTE on function "public"."review_hospital_application"(target_hospital_id uuid, decision verification_status, decision_note text) to "authenticated";

grant EXECUTE on function "public"."review_hospital_application"(target_hospital_id uuid, decision verification_status, decision_note text) to "service_role";

revoke all on function "public"."review_online_consultation_request"(target_request_id uuid, decision text, target_doctor_id uuid, target_confirmed_schedule timestamp with time zone, target_channel text, review_notes text) from public,anon,authenticated;

grant EXECUTE on function "public"."review_online_consultation_request"(target_request_id uuid, decision text, target_doctor_id uuid, target_confirmed_schedule timestamp with time zone, target_channel text, review_notes text) to "authenticated";

grant EXECUTE on function "public"."review_online_consultation_request"(target_request_id uuid, decision text, target_doctor_id uuid, target_confirmed_schedule timestamp with time zone, target_channel text, review_notes text) to "service_role";

revoke all on function "public"."review_patient_document"(target_document_id uuid, decision text, review_notes text) from public,anon,authenticated;

grant EXECUTE on function "public"."review_patient_document"(target_document_id uuid, decision text, review_notes text) to "authenticated";

grant EXECUTE on function "public"."review_patient_document"(target_document_id uuid, decision text, review_notes text) to "service_role";

revoke all on function "private"."revoke_ended_assignment_access"() from public,anon,authenticated;

revoke all on function "public"."revoke_patient_access_grant"(target_grant_id uuid, reason text) from public,anon,authenticated;

grant EXECUTE on function "public"."revoke_patient_access_grant"(target_grant_id uuid, reason text) to "authenticated";

grant EXECUTE on function "public"."revoke_patient_access_grant"(target_grant_id uuid, reason text) to "service_role";

revoke all on function "private"."revoke_relationship_access"(target_relationship_id uuid, target_status text, target_reason text) from public,anon,authenticated;

revoke all on function "public"."save_hospital_service"(service_payload jsonb, target_doctor_ids uuid[], target_primary_doctor_id uuid) from public,anon,authenticated;

grant EXECUTE on function "public"."save_hospital_service"(service_payload jsonb, target_doctor_ids uuid[], target_primary_doctor_id uuid) to "authenticated";

grant EXECUTE on function "public"."save_hospital_service"(service_payload jsonb, target_doctor_ids uuid[], target_primary_doctor_id uuid) to "service_role";

revoke all on function "public"."search_existing_patients"(search_query text) from public,anon,authenticated;

grant EXECUTE on function "public"."search_existing_patients"(search_query text) to "authenticated";

grant EXECUTE on function "public"."search_existing_patients"(search_query text) to "service_role";

revoke all on function "private"."seed_demo_hospital_capabilities"() from public,anon,authenticated;

revoke all on function "public"."send_chat_message"(target_conversation_id uuid, message_body text, attachment_paths text[]) from public,anon,authenticated;

grant EXECUTE on function "public"."send_chat_message"(target_conversation_id uuid, message_body text, attachment_paths text[]) to "authenticated";

grant EXECUTE on function "public"."send_chat_message"(target_conversation_id uuid, message_body text, attachment_paths text[]) to "service_role";

revoke all on function "public"."set_guest_reference_number"() from public,anon,authenticated;

grant EXECUTE on function "public"."set_guest_reference_number"() to "service_role";

revoke all on function "private"."set_medical_document_ai_state"() from public,anon,authenticated;

grant EXECUTE on function "private"."set_medical_document_ai_state"() to public;

revoke all on function "private"."set_medical_document_provenance"() from public,anon,authenticated;

grant EXECUTE on function "private"."set_medical_document_provenance"() to public;

revoke all on function "private"."set_online_request_reference"() from public,anon,authenticated;

grant EXECUTE on function "private"."set_online_request_reference"() to public;

revoke all on function "public"."set_patient_number"() from public,anon,authenticated;

grant EXECUTE on function "public"."set_patient_number"() to "service_role";

revoke all on function "public"."set_system_setting_actor"() from public,anon,authenticated;

grant EXECUTE on function "public"."set_system_setting_actor"() to "service_role";

revoke all on function "public"."set_updated_at"() from public,anon,authenticated;

grant EXECUTE on function "public"."set_updated_at"() to public;

grant EXECUTE on function "public"."set_updated_at"() to "anon";

grant EXECUTE on function "public"."set_updated_at"() to "authenticated";

grant EXECUTE on function "public"."set_updated_at"() to "service_role";

revoke all on function "public"."standardize_guest_request_identity"() from public,anon,authenticated;

grant EXECUTE on function "public"."standardize_guest_request_identity"() to public;

grant EXECUTE on function "public"."standardize_guest_request_identity"() to "anon";

grant EXECUTE on function "public"."standardize_guest_request_identity"() to "authenticated";

grant EXECUTE on function "public"."standardize_guest_request_identity"() to "service_role";

revoke all on function "private"."storage_path_owner"(object_name text) from public,anon,authenticated;

grant EXECUTE on function "private"."storage_path_owner"(object_name text) to "authenticated";

grant EXECUTE on function "private"."storage_path_owner"(object_name text) to "service_role";

revoke all on function "public"."submit_guest_consultation_request"(request_payload jsonb, idempotency_key text) from public,anon,authenticated;

grant EXECUTE on function "public"."submit_guest_consultation_request"(request_payload jsonb, idempotency_key text) to "authenticated";

grant EXECUTE on function "public"."submit_guest_consultation_request"(request_payload jsonb, idempotency_key text) to "service_role";

revoke all on function "public"."submit_online_consultation_request"(request_payload jsonb) from public,anon,authenticated;

grant EXECUTE on function "public"."submit_online_consultation_request"(request_payload jsonb) to "authenticated";

grant EXECUTE on function "public"."submit_online_consultation_request"(request_payload jsonb) to "service_role";

revoke all on function "public"."sync_completed_consultation_clinical_records"() from public,anon,authenticated;

grant EXECUTE on function "public"."sync_completed_consultation_clinical_records"() to "service_role";

revoke all on function "private"."sync_consultation_care_access"() from public,anon,authenticated;

grant EXECUTE on function "private"."sync_consultation_care_access"() to public;

revoke all on function "public"."sync_doctor_profile_image"() from public,anon,authenticated;

grant EXECUTE on function "public"."sync_doctor_profile_image"() to "service_role";

revoke all on function "private"."sync_email_delivery_status"() from public,anon,authenticated;

revoke all on function "private"."sync_employment_termination"() from public,anon,authenticated;

grant EXECUTE on function "private"."sync_employment_termination"() to public;

revoke all on function "private"."sync_rescheduled_consultation"() from public,anon,authenticated;

revoke all on function "private"."sync_video_session_request_status"() from public,anon,authenticated;

grant EXECUTE on function "private"."sync_video_session_request_status"() to public;

revoke all on function "public"."transition_consultation"(target_consultation_id uuid, target_status consultation_status, transition_notes text, scheduled_for timestamp with time zone, clinical_payload jsonb) from public,anon,authenticated;

grant EXECUTE on function "public"."transition_consultation"(target_consultation_id uuid, target_status consultation_status, transition_notes text, scheduled_for timestamp with time zone, clinical_payload jsonb) to "authenticated";

grant EXECUTE on function "public"."transition_consultation"(target_consultation_id uuid, target_status consultation_status, transition_notes text, scheduled_for timestamp with time zone, clinical_payload jsonb) to "service_role";

revoke all on function "public"."transition_online_consultation_request"(target_request_id uuid, target_status text, transition_notes text) from public,anon,authenticated;

grant EXECUTE on function "public"."transition_online_consultation_request"(target_request_id uuid, target_status text, transition_notes text) to "authenticated";

grant EXECUTE on function "public"."transition_online_consultation_request"(target_request_id uuid, target_status text, transition_notes text) to "service_role";

revoke all on function "public"."update_emergency_capacity"(target_record_id uuid, total_capacity integer, occupied_capacity integer, closed_unstaffed_capacity integer, reserved_capacity integer, reported_patient_count integer, manual_status_override text, manual_override_reason text) from public,anon,authenticated;

grant EXECUTE on function "public"."update_emergency_capacity"(target_record_id uuid, total_capacity integer, occupied_capacity integer, closed_unstaffed_capacity integer, reserved_capacity integer, reported_patient_count integer, manual_status_override text, manual_override_reason text) to "authenticated";

grant EXECUTE on function "public"."update_emergency_capacity"(target_record_id uuid, total_capacity integer, occupied_capacity integer, closed_unstaffed_capacity integer, reserved_capacity integer, reported_patient_count integer, manual_status_override text, manual_override_reason text) to "service_role";

revoke all on function "public"."update_own_patient_profile"(patient_profile_update jsonb) from public,anon,authenticated;

grant EXECUTE on function "public"."update_own_patient_profile"(patient_profile_update jsonb) to "authenticated";

grant EXECUTE on function "public"."update_own_patient_profile"(patient_profile_update jsonb) to "service_role";

revoke all on function "private"."valid_record_category"(target_category text) from public,anon,authenticated;

grant EXECUTE on function "private"."valid_record_category"(target_category text) to "authenticated";

grant EXECUTE on function "private"."valid_record_category"(target_category text) to "service_role";

revoke all on function "public"."validate_clinical_relationships"() from public,anon,authenticated;

grant EXECUTE on function "public"."validate_clinical_relationships"() to "service_role";

revoke all on function "private"."validate_consultation_identity_source"() from public,anon,authenticated;

revoke all on function "public"."validate_consultation_relationships"() from public,anon,authenticated;

grant EXECUTE on function "public"."validate_consultation_relationships"() to "service_role";

revoke all on function "public"."validate_conversation_relationships"() from public,anon,authenticated;

grant EXECUTE on function "public"."validate_conversation_relationships"() to "service_role";

revoke all on function "public"."validate_doctor_user_relationship"() from public,anon,authenticated;

grant EXECUTE on function "public"."validate_doctor_user_relationship"() to "service_role";

revoke all on function "private"."validate_document_reference"() from public,anon,authenticated;

revoke all on function "public"."validate_guest_hospital_relationships"() from public,anon,authenticated;

grant EXECUTE on function "public"."validate_guest_hospital_relationships"() to "service_role";

revoke all on function "public"."validate_hospital_department_relationship"() from public,anon,authenticated;

grant EXECUTE on function "public"."validate_hospital_department_relationship"() to "service_role";

revoke all on function "public"."validate_prescription_relationships"() from public,anon,authenticated;

grant EXECUTE on function "public"."validate_prescription_relationships"() to "service_role";

revoke all on function "private"."validate_record_selections"(target_patient uuid, categories text[], selections jsonb) from public,anon,authenticated;

grant usage on schema public to anon,authenticated,service_role;

grant usage on schema private to authenticated,service_role;

grant usage,select on all sequences in schema public to authenticated,service_role;

create policy "notification_preferences_owner_manage" on "public"."notification_preferences" as PERMISSIVE for ALL to "authenticated" using (((user_id = ( SELECT auth.uid() AS uid)) AND (private.current_user_id() IS NOT NULL))) with check (((user_id = ( SELECT auth.uid() AS uid)) AND (private.current_user_id() IS NOT NULL)));

create policy "clinical_record_quarantine_no_client_access" on "public"."clinical_record_quarantine" as RESTRICTIVE for ALL to "authenticated" using (false) with check (false);

create policy "ai_configurations_super_manage" on "public"."ai_configurations" as PERMISSIVE for ALL to "authenticated" using (private.is_super_admin()) with check (private.is_super_admin());

create policy "cnph_direct_chat_attachments_delete" on "storage"."objects" as PERMISSIVE for DELETE to "authenticated" using (((bucket_id = 'consultation-attachments'::text) AND private.can_access_direct_chat_storage(name)));

create policy "cnph_hospital_images_admin_delete" on "storage"."objects" as PERMISSIVE for DELETE to "authenticated" using (((bucket_id = 'hospital-images'::text) AND (private."current_role"() = ANY (ARRAY['hospital_admin'::text, 'super_admin'::text]))));

create policy "cnph_profile_images_owner_delete" on "storage"."objects" as PERMISSIVE for DELETE to "authenticated" using (((bucket_id = 'profile-images'::text) AND private.storage_path_owner(name)));

create policy "cnph_admin_documents_scoped_delete" on "storage"."objects" as PERMISSIVE for DELETE to "authenticated" using (((bucket_id = ANY (ARRAY['doctor-documents'::text, 'hospital-accreditation-documents'::text])) AND private.can_manage_hospital_storage(name)));

create policy "cnph_patient_documents_uploader_delete" on "storage"."objects" as PERMISSIVE for DELETE to "authenticated" using (((bucket_id = ANY (ARRAY['laboratory-results'::text, 'scanned-medical-results'::text, 'medical-documents'::text, 'prescriptions'::text, 'consultation-attachments'::text])) AND private.is_storage_upload_owner(name)));

create policy "cnph_guest_documents_owner_delete" on "storage"."objects" as PERMISSIVE for DELETE to "authenticated" using (((bucket_id = ANY (ARRAY['valid-identification'::text, 'guest-consultation-documents'::text])) AND private.storage_path_owner(name)));

create policy "laboratory_requests_origin_delete" on "public"."laboratory_requests" as PERMISSIVE for DELETE to "authenticated" using (((doctor_id = private.current_doctor_id()) AND (status = ANY (ARRAY['requested'::text, 'scheduled'::text])) AND private.can_access_clinical_record(patient_id, hospital_id, 'laboratory_requests'::text, id, 'create'::text)));

create policy "doctor_schedules_delete" on "public"."doctor_schedules" as PERMISSIVE for DELETE to "authenticated" using (((doctor_id = private.current_doctor_id()) OR (EXISTS ( SELECT 1
   FROM doctors d
  WHERE ((d.id = doctor_schedules.doctor_id) AND private.is_hospital_admin_for(d.hospital_id))))));

create policy "announcements_admin_delete" on "public"."hospital_announcements" as PERMISSIVE for DELETE to "authenticated" using (((is_global AND private.is_super_admin()) OR ((hospital_id IS NOT NULL) AND private.is_hospital_admin_for(hospital_id))));

create policy "conversations_doctor_delete" on "public"."chat_conversations" as PERMISSIVE for DELETE to "authenticated" using ((doctor_id = private.current_doctor_id()));

create policy "document_jobs_doctor_delete" on "public"."document_processing_jobs" as PERMISSIVE for DELETE to "authenticated" using ((requested_by = private.current_doctor_id()));

create policy "Account owners delete assistant conversations" on "public"."care_assistant_conversations" as PERMISSIVE for DELETE to "authenticated" using ((user_id = private.current_user_id()));

create policy "doctors_admin_delete" on "public"."doctors" as PERMISSIVE for DELETE to "authenticated" using (private.is_hospital_admin_for(hospital_id));

create policy "emergency_status_admin_delete" on "public"."emergency_room_status" as PERMISSIVE for DELETE to "authenticated" using (private.is_hospital_admin_for(hospital_id));

create policy "beds_admin_delete" on "public"."hospital_beds" as PERMISSIVE for DELETE to "authenticated" using (private.is_hospital_admin_for(hospital_id));

create policy "departments_admin_delete" on "public"."hospital_departments" as PERMISSIVE for DELETE to "authenticated" using (private.is_hospital_admin_for(hospital_id));

create policy "facility_status_admin_delete" on "public"."hospital_facility_status" as PERMISSIVE for DELETE to "authenticated" using (private.is_hospital_admin_for(hospital_id));

create policy "rooms_admin_delete" on "public"."hospital_rooms" as PERMISSIVE for DELETE to "authenticated" using (private.is_hospital_admin_for(hospital_id));

create policy "service_doctors_admin_delete" on "public"."hospital_service_doctors" as PERMISSIVE for DELETE to "authenticated" using (private.is_hospital_admin_for(hospital_id));

create policy "services_admin_delete" on "public"."hospital_services" as PERMISSIVE for DELETE to "authenticated" using (private.is_hospital_admin_for(hospital_id));

create policy "service_categories_super_admin_delete" on "public"."healthcare_service_categories" as PERMISSIVE for DELETE to "authenticated" using (private.is_super_admin());

create policy "classifications_super_admin_delete" on "public"."hospital_classifications" as PERMISSIVE for DELETE to "authenticated" using (private.is_super_admin());

create policy "hospitals_super_admin_delete" on "public"."hospitals" as PERMISSIVE for DELETE to "authenticated" using (private.is_super_admin());

create policy "maintenance_windows_super_delete" on "public"."maintenance_windows" as PERMISSIVE for DELETE to "authenticated" using (private.is_super_admin());

create policy "role_permissions_super_delete" on "public"."role_permissions" as PERMISSIVE for DELETE to "authenticated" using (private.is_super_admin());

create policy "roles_super_admin_delete" on "public"."roles" as PERMISSIVE for DELETE to "authenticated" using (private.is_super_admin());

create policy "system_settings_super_delete" on "public"."system_settings" as PERMISSIVE for DELETE to "authenticated" using (private.is_super_admin());

create policy "assessment_recommendations_owner_insert" on "public"."ai_assessment_recommendations" as PERMISSIVE for INSERT to "authenticated" with check (((private.current_user_id() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM ai_assessments assessment
  WHERE ((assessment.id = ai_assessment_recommendations.assessment_id) AND (assessment.user_id = ( SELECT auth.uid() AS uid)))))));

create policy "ai_assessments_owner_insert" on "public"."ai_assessments" as PERMISSIVE for INSERT to "authenticated" with check (((user_id = ( SELECT auth.uid() AS uid)) AND (((private.current_user_id() IS NOT NULL) AND (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'is_anonymous'::text), 'false'::text) <> 'true'::text)) OR ((patient_id IS NULL) AND (guest_request_id IS NULL) AND (private.current_user_id() IS NULL) AND ((( SELECT auth.jwt() AS jwt) ->> 'is_anonymous'::text) = 'true'::text)))));

create policy "Account owners create assistant conversations" on "public"."care_assistant_conversations" as PERMISSIVE for INSERT to "authenticated" with check ((user_id = private.current_user_id()));

create policy "conversations_doctor_insert" on "public"."chat_conversations" as PERMISSIVE for INSERT to "authenticated" with check ((doctor_id = private.current_doctor_id()));

create policy "chat_attachments_sender_insert" on "public"."chat_message_attachments" as PERMISSIVE for INSERT to "authenticated" with check (((private.current_user_id() IS NOT NULL) AND (uploaded_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM chat_messages message
  WHERE ((message.id = chat_message_attachments.message_id) AND (message.sender_id = ( SELECT auth.uid() AS uid)))))));

create policy "messages_participant_insert" on "public"."chat_messages" as PERMISSIVE for INSERT to "authenticated" with check (((sender_id = ( SELECT auth.uid() AS uid)) AND private.can_send_to_conversation(conversation_id)));

create policy "clinical_addenda_authorized_insert" on "public"."clinical_record_addenda" as PERMISSIVE for INSERT to "authenticated" with check (((author_user_id = private.current_user_id()) AND (author_doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, originating_hospital_id, record_category, record_id, 'create'::text)));

create policy "consultation_attachments_scoped_insert" on "public"."consultation_attachments" as PERMISSIVE for INSERT to "authenticated" with check (((uploaded_by = private.current_user_id()) AND (((patient_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM consultations consultation
  WHERE ((consultation.id = consultation_attachments.consultation_id) AND private.can_access_clinical_record(consultation_attachments.patient_id, consultation.hospital_id, 'consultations'::text, consultation.id,
        CASE
            WHEN (consultation_attachments.patient_id = private.current_patient_id()) THEN 'view'::text
            ELSE 'create'::text
        END))))) OR ((guest_request_id IS NOT NULL) AND private.can_access_guest_request(guest_request_id)))));

create policy "diagnoses_scoped_insert" on "public"."diagnoses" as PERMISSIVE for INSERT to "authenticated" with check (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'diagnoses'::text, NULL::uuid, 'create'::text)));

create policy "doctor_schedules_insert" on "public"."doctor_schedules" as PERMISSIVE for INSERT to "authenticated" with check (((doctor_id = private.current_doctor_id()) OR (EXISTS ( SELECT 1
   FROM doctors d
  WHERE ((d.id = doctor_schedules.doctor_id) AND private.is_hospital_admin_for(d.hospital_id))))));

create policy "doctors_admin_insert" on "public"."doctors" as PERMISSIVE for INSERT to "authenticated" with check (private.is_hospital_admin_for(hospital_id));

create policy "document_jobs_doctor_insert" on "public"."document_processing_jobs" as PERMISSIVE for INSERT to "authenticated" with check ((requested_by = private.current_doctor_id()));

create policy "emergency_status_admin_insert" on "public"."emergency_room_status" as PERMISSIVE for INSERT to "authenticated" with check (private.is_hospital_admin_for(hospital_id));

create policy "guest_requests_owner_insert" on "public"."guest_consultation_requests" as PERMISSIVE for INSERT to "authenticated" with check (((submitted_by = ( SELECT auth.uid() AS uid)) AND (private.current_user_id() IS NOT NULL) AND (NULLIF((( SELECT auth.jwt() AS jwt) ->> 'email'::text), ''::text) IS NOT NULL)));

create policy "service_categories_super_admin_insert" on "public"."healthcare_service_categories" as PERMISSIVE for INSERT to "authenticated" with check (private.is_super_admin());

create policy "announcements_admin_insert" on "public"."hospital_announcements" as PERMISSIVE for INSERT to "authenticated" with check (((is_global AND private.is_super_admin()) OR ((hospital_id IS NOT NULL) AND private.is_hospital_admin_for(hospital_id))));

create policy "beds_admin_insert" on "public"."hospital_beds" as PERMISSIVE for INSERT to "authenticated" with check (private.is_hospital_admin_for(hospital_id));

create policy "classifications_super_admin_insert" on "public"."hospital_classifications" as PERMISSIVE for INSERT to "authenticated" with check (private.is_super_admin());

create policy "departments_admin_insert" on "public"."hospital_departments" as PERMISSIVE for INSERT to "authenticated" with check (private.is_hospital_admin_for(hospital_id));

create policy "facility_status_admin_insert" on "public"."hospital_facility_status" as PERMISSIVE for INSERT to "authenticated" with check (private.is_hospital_admin_for(hospital_id));

create policy "rooms_admin_insert" on "public"."hospital_rooms" as PERMISSIVE for INSERT to "authenticated" with check (private.is_hospital_admin_for(hospital_id));

create policy "service_doctors_admin_insert" on "public"."hospital_service_doctors" as PERMISSIVE for INSERT to "authenticated" with check (private.is_hospital_admin_for(hospital_id));

create policy "services_admin_insert" on "public"."hospital_services" as PERMISSIVE for INSERT to "authenticated" with check (private.is_hospital_admin_for(hospital_id));

create policy "hospitals_super_admin_insert" on "public"."hospitals" as PERMISSIVE for INSERT to "authenticated" with check (private.is_super_admin());

create policy "laboratory_requests_scoped_insert" on "public"."laboratory_requests" as PERMISSIVE for INSERT to "authenticated" with check (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'laboratory_requests'::text, NULL::uuid, 'create'::text)));

create policy "laboratory_results_scoped_insert" on "public"."laboratory_results" as PERMISSIVE for INSERT to "authenticated" with check (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'laboratory_results'::text, NULL::uuid, 'create'::text)));

create policy "maintenance_windows_super_insert" on "public"."maintenance_windows" as PERMISSIVE for INSERT to "authenticated" with check (private.is_super_admin());

create policy "medical_documents_scoped_insert" on "public"."medical_documents" as PERMISSIVE for INSERT to "authenticated" with check ((((patient_id = private.current_patient_id()) AND (uploaded_by = private.current_user_id()) AND (author_doctor_id IS NULL) AND (origin_type = 'patient_supplied'::text)) OR ((author_doctor_id = private.current_doctor_id()) AND (uploaded_by = private.current_user_id()) AND (hospital_id IS NOT NULL) AND (private.can_access_clinical_record(patient_id, hospital_id, 'medical_documents'::text, NULL::uuid, 'create'::text) OR private.can_create_assigned_patient_document(patient_id, hospital_id)))));

create policy "medical_access_logs_authorized_insert" on "public"."medical_record_access_logs" as PERMISSIVE for INSERT to "authenticated" with check (((actor_user_id = private.current_user_id()) AND private.can_access_patient(patient_id)));

create policy "medical_records_scoped_insert" on "public"."medical_records" as PERMISSIVE for INSERT to "authenticated" with check (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'medical_records'::text, NULL::uuid, 'create'::text)));

create policy "cnph_admin_documents_scoped_insert" on "storage"."objects" as PERMISSIVE for INSERT to "authenticated" with check (((bucket_id = ANY (ARRAY['doctor-documents'::text, 'hospital-accreditation-documents'::text])) AND private.can_manage_hospital_storage(name)));

create policy "cnph_direct_chat_attachments_insert" on "storage"."objects" as PERMISSIVE for INSERT to "authenticated" with check (((bucket_id = 'consultation-attachments'::text) AND private.can_access_direct_chat_storage(name)));

create policy "cnph_guest_documents_owner_insert" on "storage"."objects" as PERMISSIVE for INSERT to "authenticated" with check (((bucket_id = ANY (ARRAY['valid-identification'::text, 'guest-consultation-documents'::text])) AND private.storage_path_owner(name)));

create policy "cnph_hospital_images_admin_insert" on "storage"."objects" as PERMISSIVE for INSERT to "authenticated" with check (((bucket_id = 'hospital-images'::text) AND (private."current_role"() = ANY (ARRAY['hospital_admin'::text, 'super_admin'::text]))));

create policy "cnph_patient_documents_scoped_insert" on "storage"."objects" as PERMISSIVE for INSERT to "authenticated" with check ((((bucket_id = 'consultation-attachments'::text) AND private.can_access_consultation_storage(name)) OR ((bucket_id = ANY (ARRAY['laboratory-results'::text, 'scanned-medical-results'::text, 'medical-documents'::text, 'prescriptions'::text])) AND private.can_upload_patient_storage(name, bucket_id))));

create policy "cnph_profile_images_owner_insert" on "storage"."objects" as PERMISSIVE for INSERT to "authenticated" with check (((bucket_id = 'profile-images'::text) AND private.storage_path_owner(name)));

create policy "patients_care_team_insert" on "public"."patients" as PERMISSIVE for INSERT to "authenticated" with check (((created_by_doctor = private.current_doctor_id()) OR ((profile_status = 'temporary'::text) AND (user_id IS NULL) AND private.is_hospital_admin_for(primary_hospital_id))));

create policy "prescriptions_scoped_insert" on "public"."prescriptions" as PERMISSIVE for INSERT to "authenticated" with check (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'prescriptions'::text, NULL::uuid, 'create'::text)));

create policy "role_permissions_super_insert" on "public"."role_permissions" as PERMISSIVE for INSERT to "authenticated" with check (private.is_super_admin());

create policy "roles_super_admin_insert" on "public"."roles" as PERMISSIVE for INSERT to "authenticated" with check (private.is_super_admin());

create policy "system_settings_super_insert" on "public"."system_settings" as PERMISSIVE for INSERT to "authenticated" with check (private.is_super_admin());

create policy "treatment_plans_scoped_insert" on "public"."treatment_plans" as PERMISSIVE for INSERT to "authenticated" with check (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'treatment_plans'::text, NULL::uuid, 'create'::text)));

create policy "video_sessions_doctor_insert" on "public"."video_sessions" as PERMISSIVE for INSERT to "authenticated" with check (((created_by = ( SELECT auth.uid() AS uid)) AND (EXISTS ( SELECT 1
   FROM consultations c
  WHERE ((c.id = video_sessions.consultation_id) AND (c.doctor_id = private.current_doctor_id()))))));

create policy "doctors_authenticated_read" on "public"."doctors" as PERMISSIVE for SELECT to "authenticated" using ((((availability_status <> 'unavailable'::availability_status) AND (EXISTS ( SELECT 1
   FROM hospitals h
  WHERE ((h.id = doctors.hospital_id) AND (h.verification_status = 'verified'::verification_status))))) OR (user_id = private.current_user_id()) OR private.is_hospital_admin_for(hospital_id)));

create policy "departments_authenticated_read" on "public"."hospital_departments" as PERMISSIVE for SELECT to "authenticated" using ((((availability_status <> 'unavailable'::availability_status) AND (EXISTS ( SELECT 1
   FROM hospitals h
  WHERE ((h.id = hospital_departments.hospital_id) AND (h.verification_status = 'verified'::verification_status) AND (h.operating_status = ANY (ARRAY['open'::hospital_operating_status, 'limited'::hospital_operating_status])))))) OR private.is_hospital_admin_for(hospital_id)));

create policy "services_authenticated_read" on "public"."hospital_services" as PERMISSIVE for SELECT to "authenticated" using ((((availability_status <> 'unavailable'::availability_status) AND (EXISTS ( SELECT 1
   FROM hospitals h
  WHERE ((h.id = hospital_services.hospital_id) AND (h.verification_status = 'verified'::verification_status) AND (h.operating_status = ANY (ARRAY['open'::hospital_operating_status, 'limited'::hospital_operating_status])))))) OR private.is_hospital_admin_for(hospital_id)));

create policy "consultation_attachments_scoped_read" on "public"."consultation_attachments" as PERMISSIVE for SELECT to "authenticated" using ((((patient_id IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM consultations consultation
  WHERE ((consultation.id = consultation_attachments.consultation_id) AND private.can_access_clinical_record(consultation_attachments.patient_id, consultation.hospital_id, 'consultations'::text, consultation.id, 'view'::text))))) OR ((guest_request_id IS NOT NULL) AND private.can_access_guest_request(guest_request_id))));

create policy "ai_assessments_owner_read" on "public"."ai_assessments" as PERMISSIVE for SELECT to "authenticated" using ((((private.current_user_id() IS NOT NULL) AND (COALESCE((( SELECT auth.jwt() AS jwt) ->> 'is_anonymous'::text), 'false'::text) <> 'true'::text) AND ((user_id = ( SELECT auth.uid() AS uid)) OR ((patient_id IS NOT NULL) AND private.can_access_patient(patient_id)) OR ((guest_request_id IS NOT NULL) AND private.can_access_guest_request(guest_request_id)))) OR ((user_id = ( SELECT auth.uid() AS uid)) AND (patient_id IS NULL) AND (guest_request_id IS NULL) AND (private.current_user_id() IS NULL) AND ((( SELECT auth.jwt() AS jwt) ->> 'is_anonymous'::text) = 'true'::text))));

create policy "doctors_anon_directory_read" on "public"."doctors" as PERMISSIVE for SELECT to "anon" using (((availability_status <> 'unavailable'::availability_status) AND (EXISTS ( SELECT 1
   FROM hospitals h
  WHERE ((h.id = doctors.hospital_id) AND (h.verification_status = 'verified'::verification_status))))));

create policy "departments_anon_directory_read" on "public"."hospital_departments" as PERMISSIVE for SELECT to "anon" using (((availability_status <> 'unavailable'::availability_status) AND (EXISTS ( SELECT 1
   FROM hospitals h
  WHERE ((h.id = hospital_departments.hospital_id) AND (h.verification_status = 'verified'::verification_status) AND (h.operating_status = ANY (ARRAY['open'::hospital_operating_status, 'limited'::hospital_operating_status])))))));

create policy "services_anon_directory_read" on "public"."hospital_services" as PERMISSIVE for SELECT to "anon" using (((availability_status <> 'unavailable'::availability_status) AND (EXISTS ( SELECT 1
   FROM hospitals h
  WHERE ((h.id = hospital_services.hospital_id) AND (h.verification_status = 'verified'::verification_status) AND (h.operating_status = ANY (ARRAY['open'::hospital_operating_status, 'limited'::hospital_operating_status])))))));

create policy "cnph_direct_chat_attachments_read" on "storage"."objects" as PERMISSIVE for SELECT to "authenticated" using (((bucket_id = 'consultation-attachments'::text) AND private.can_access_direct_chat_storage(name)));

create policy "cnph_profile_images_owner_read" on "storage"."objects" as PERMISSIVE for SELECT to "authenticated" using (((bucket_id = 'profile-images'::text) AND private.storage_path_owner(name)));

create policy "cnph_admin_documents_scoped_read" on "storage"."objects" as PERMISSIVE for SELECT to "authenticated" using (((bucket_id = ANY (ARRAY['doctor-documents'::text, 'hospital-accreditation-documents'::text])) AND private.can_manage_hospital_storage(name)));

create policy "cnph_patient_documents_scoped_read" on "storage"."objects" as PERMISSIVE for SELECT to "authenticated" using (((bucket_id = ANY (ARRAY['laboratory-results'::text, 'scanned-medical-results'::text, 'medical-documents'::text, 'prescriptions'::text, 'consultation-attachments'::text])) AND private.can_access_patient_storage(name, bucket_id, 'view'::text)));

create policy "cnph_guest_documents_authorized_read" on "storage"."objects" as PERMISSIVE for SELECT to "authenticated" using (((bucket_id = ANY (ARRAY['valid-identification'::text, 'guest-consultation-documents'::text])) AND private.can_access_guest_storage(name)));

create policy "doctor_employments_authorized_read" on "public"."doctor_hospital_employments" as PERMISSIVE for SELECT to "authenticated" using (((doctor_id = private.current_doctor_id()) OR private.is_hospital_admin_for(hospital_id)));

create policy "emergency_status_authenticated_read" on "public"."emergency_room_status" as PERMISSIVE for SELECT to "authenticated" using (((EXISTS ( SELECT 1
   FROM hospitals h
  WHERE ((h.id = emergency_room_status.hospital_id) AND (h.verification_status = 'verified'::verification_status)))) OR private.is_hospital_admin_for(hospital_id)));

create policy "beds_authenticated_read" on "public"."hospital_beds" as PERMISSIVE for SELECT to "authenticated" using (((EXISTS ( SELECT 1
   FROM hospitals h
  WHERE ((h.id = hospital_beds.hospital_id) AND (h.verification_status = 'verified'::verification_status)))) OR private.is_hospital_admin_for(hospital_id)));

create policy "facility_status_authenticated_read" on "public"."hospital_facility_status" as PERMISSIVE for SELECT to "authenticated" using (((EXISTS ( SELECT 1
   FROM hospitals h
  WHERE ((h.id = hospital_facility_status.hospital_id) AND (h.verification_status = 'verified'::verification_status)))) OR private.is_hospital_admin_for(hospital_id)));

create policy "rooms_authenticated_read" on "public"."hospital_rooms" as PERMISSIVE for SELECT to "authenticated" using (((EXISTS ( SELECT 1
   FROM hospitals h
  WHERE ((h.id = hospital_rooms.hospital_id) AND (h.verification_status = 'verified'::verification_status)))) OR private.is_hospital_admin_for(hospital_id)));

create policy "patients_scoped_read" on "public"."patients" as PERMISSIVE for SELECT to "authenticated" using (((id = private.current_patient_id()) OR private.can_access_patient(id)));

create policy "maintenance_windows_authenticated_read" on "public"."maintenance_windows" as PERMISSIVE for SELECT to "authenticated" using (((is_active AND ((now() >= starts_at) AND (now() <= ends_at))) OR private.is_super_admin()));

create policy "consultations_participant_read" on "public"."consultations" as PERMISSIVE for SELECT to "authenticated" using (((patient_id = private.current_patient_id()) OR ((doctor_id = private.current_doctor_id()) AND private.has_active_doctor_employment(doctor_id, hospital_id)) OR ((guest_request_id IS NOT NULL) AND private.can_access_guest_request(guest_request_id)) OR private.is_hospital_admin_for(hospital_id) OR ((patient_id IS NOT NULL) AND private.can_access_clinical_record(patient_id, hospital_id, 'consultations'::text, id, 'view'::text))));

create policy "assignments_scoped_read" on "public"."doctor_patient_assignments" as PERMISSIVE for SELECT to "authenticated" using (((patient_id = private.current_patient_id()) OR (doctor_id = private.current_doctor_id()) OR ((hospital_id IS NOT NULL) AND private.is_hospital_admin_for(hospital_id))));

create policy "emergency_access_participant_read" on "public"."emergency_access_events" as PERMISSIVE for SELECT to "authenticated" using (((patient_id = private.current_patient_id()) OR (doctor_id = private.current_doctor_id()) OR private.is_hospital_admin_for(hospital_id)));

create policy "care_relationships_authorized_read" on "public"."patient_care_relationships" as PERMISSIVE for SELECT to "authenticated" using (((patient_id = private.current_patient_id()) OR (doctor_id = private.current_doctor_id()) OR private.is_hospital_admin_for(hospital_id)));

create policy "patient_connection_requests_participant_read" on "public"."patient_connection_requests" as PERMISSIVE for SELECT to "authenticated" using (((patient_id = private.current_patient_id()) OR (doctor_id = private.current_doctor_id()) OR private.is_hospital_admin_for(hospital_id)));

create policy "patient_consents_authorized_read" on "public"."patient_consents" as PERMISSIVE for SELECT to "authenticated" using (((patient_id = private.current_patient_id()) OR (EXISTS ( SELECT 1
   FROM patient_access_grants grant_row
  WHERE ((grant_row.consent_id = patient_consents.id) AND (grant_row.receiving_doctor_id = private.current_doctor_id()) AND (grant_row.status = 'active'::text) AND (grant_row.expires_at > now()) AND (grant_row.revoked_at IS NULL))))));

create policy "access_grants_participant_read" on "public"."patient_access_grants" as PERMISSIVE for SELECT to "authenticated" using (((patient_id = private.current_patient_id()) OR (receiving_doctor_id = private.current_doctor_id())));

create policy "patient_representatives_participant_read" on "public"."patient_representatives" as PERMISSIVE for SELECT to "authenticated" using (((patient_id = private.current_patient_id()) OR (representative_user_id = private.current_user_id())));

create policy "prescription_order_reads" on "public"."prescription_orders" as PERMISSIVE for SELECT to "authenticated" using (((patient_id = private.current_patient_id()) OR private.can_access_clinical_record(patient_id, hospital_id, 'prescriptions'::text, id, 'view'::text) OR ((doctor_id = private.current_doctor_id()) AND private.can_create_assigned_patient_document(patient_id, hospital_id))));

create policy "patient_identifiers_authorized_read" on "public"."patient_hospital_identifiers" as PERMISSIVE for SELECT to "authenticated" using (((patient_id = private.current_patient_id()) OR private.can_access_patient(patient_id) OR private.is_hospital_admin_for(hospital_id)));

create policy "medical_access_logs_authorized_read" on "public"."medical_record_access_logs" as PERMISSIVE for SELECT to "authenticated" using (((patient_id = private.current_patient_id()) OR private.can_access_patient(patient_id) OR private.is_super_admin() OR (EXISTS ( SELECT 1
   FROM patients patient
  WHERE ((patient.id = medical_record_access_logs.patient_id) AND private.is_hospital_admin_for(patient.primary_hospital_id))))));

create policy "assessment_recommendations_owner_read" on "public"."ai_assessment_recommendations" as PERMISSIVE for SELECT to "authenticated" using (((private.current_user_id() IS NOT NULL) AND (EXISTS ( SELECT 1
   FROM ai_assessments assessment
  WHERE ((assessment.id = ai_assessment_recommendations.assessment_id) AND ((assessment.user_id = ( SELECT auth.uid() AS uid)) OR ((assessment.patient_id IS NOT NULL) AND private.can_access_patient(assessment.patient_id)) OR ((assessment.guest_request_id IS NOT NULL) AND private.can_access_guest_request(assessment.guest_request_id))))))));

create policy "announcements_public_read" on "public"."hospital_announcements" as PERMISSIVE for SELECT to "anon","authenticated" using (((published_at <= now()) AND ((expires_at IS NULL) OR (expires_at > now()))));

create policy "document_jobs_care_team_read" on "public"."document_processing_jobs" as PERMISSIVE for SELECT to "authenticated" using (((requested_by = private.current_doctor_id()) OR (EXISTS ( SELECT 1
   FROM laboratory_results r
  WHERE ((r.id = document_processing_jobs.laboratory_result_id) AND private.can_access_patient(r.patient_id)))) OR (EXISTS ( SELECT 1
   FROM medical_documents d
  WHERE ((d.id = document_processing_jobs.medical_document_id) AND private.can_access_patient(d.patient_id))))));

create policy "notifications_owner_read" on "public"."notifications" as PERMISSIVE for SELECT to "authenticated" using (((user_id = ( SELECT auth.uid() AS uid)) AND (private.current_user_id() IS NOT NULL) AND COALESCE(( SELECT preference.in_app_enabled
   FROM notification_preferences preference
  WHERE (preference.user_id = ( SELECT auth.uid() AS uid))), true)));

create policy "hospitals_anon_directory_read" on "public"."hospitals" as PERMISSIVE for SELECT to "anon" using (((verification_status = 'verified'::verification_status) AND (operating_status = ANY (ARRAY['open'::hospital_operating_status, 'limited'::hospital_operating_status]))));

create policy "Hospital directory images are publicly readable" on "storage"."objects" as PERMISSIVE for SELECT to public using ((bucket_id = 'hospital-images'::text));

create policy "Profile images are publicly readable" on "storage"."objects" as PERMISSIVE for SELECT to public using ((bucket_id = 'profile-images'::text));

create policy "service_doctors_anon_directory_read" on "public"."hospital_service_doctors" as PERMISSIVE for SELECT to "anon" using ((EXISTS ( SELECT 1
   FROM ((hospital_services service
     JOIN hospitals hospital ON ((hospital.id = service.hospital_id)))
     JOIN doctors doctor ON ((doctor.id = hospital_service_doctors.doctor_id)))
  WHERE ((service.id = hospital_service_doctors.service_id) AND (service.availability_status <> 'unavailable'::availability_status) AND (doctor.availability_status <> 'unavailable'::availability_status) AND (hospital.verification_status = 'verified'::verification_status) AND (hospital.operating_status = ANY (ARRAY['open'::hospital_operating_status, 'limited'::hospital_operating_status]))))));

create policy "chat_attachments_participant_read" on "public"."chat_message_attachments" as PERMISSIVE for SELECT to "authenticated" using ((EXISTS ( SELECT 1
   FROM chat_messages m
  WHERE ((m.id = chat_message_attachments.message_id) AND private.can_participate_conversation(m.conversation_id)))));

create policy "emergency_status_anon_directory_read" on "public"."emergency_room_status" as PERMISSIVE for SELECT to "anon" using ((EXISTS ( SELECT 1
   FROM hospitals h
  WHERE ((h.id = emergency_room_status.hospital_id) AND (h.verification_status = 'verified'::verification_status)))));

create policy "beds_anon_directory_read" on "public"."hospital_beds" as PERMISSIVE for SELECT to "anon" using ((EXISTS ( SELECT 1
   FROM hospitals h
  WHERE ((h.id = hospital_beds.hospital_id) AND (h.verification_status = 'verified'::verification_status)))));

create policy "facility_status_anon_directory_read" on "public"."hospital_facility_status" as PERMISSIVE for SELECT to "anon" using ((EXISTS ( SELECT 1
   FROM hospitals h
  WHERE ((h.id = hospital_facility_status.hospital_id) AND (h.verification_status = 'verified'::verification_status)))));

create policy "rooms_anon_directory_read" on "public"."hospital_rooms" as PERMISSIVE for SELECT to "anon" using ((EXISTS ( SELECT 1
   FROM hospitals h
  WHERE ((h.id = hospital_rooms.hospital_id) AND (h.verification_status = 'verified'::verification_status)))));

create policy "access_selections_participant_read" on "public"."patient_access_record_selections" as PERMISSIVE for SELECT to "authenticated" using ((EXISTS ( SELECT 1
   FROM patient_access_grants grant_row
  WHERE ((grant_row.id = patient_access_record_selections.grant_id) AND ((grant_row.patient_id = private.current_patient_id()) OR (grant_row.receiving_doctor_id = private.current_doctor_id()))))));

create policy "access_scopes_participant_read" on "public"."patient_access_scopes" as PERMISSIVE for SELECT to "authenticated" using ((EXISTS ( SELECT 1
   FROM patient_access_grants grant_row
  WHERE ((grant_row.id = patient_access_scopes.grant_id) AND ((grant_row.patient_id = private.current_patient_id()) OR (grant_row.receiving_doctor_id = private.current_doctor_id()))))));

create policy "maintenance_windows_anon_read" on "public"."maintenance_windows" as PERMISSIVE for SELECT to "anon" using ((is_active AND ((now() >= starts_at) AND (now() <= ends_at))));

create policy "doctor_schedules_authenticated_read" on "public"."doctor_schedules" as PERMISSIVE for SELECT to "authenticated" using ((is_active OR (doctor_id = private.current_doctor_id())));

create policy "service_categories_authenticated_read" on "public"."healthcare_service_categories" as PERMISSIVE for SELECT to "authenticated" using ((is_active OR private.is_super_admin()));

create policy "system_settings_authenticated_read" on "public"."system_settings" as PERMISSIVE for SELECT to "authenticated" using ((is_public OR private.is_super_admin()));

create policy "medication_summary_owner_reads" on "public"."medication_summary_days" as PERMISSIVE for SELECT to "authenticated" using ((patient_id = private.current_patient_id()));

create policy "service_doctors_authenticated_read" on "public"."hospital_service_doctors" as PERMISSIVE for SELECT to "authenticated" using ((private.is_hospital_admin_for(hospital_id) OR (EXISTS ( SELECT 1
   FROM ((hospital_services service
     JOIN hospitals hospital ON ((hospital.id = service.hospital_id)))
     JOIN doctors doctor ON ((doctor.id = hospital_service_doctors.doctor_id)))
  WHERE ((service.id = hospital_service_doctors.service_id) AND (service.availability_status <> 'unavailable'::availability_status) AND (doctor.availability_status <> 'unavailable'::availability_status) AND (hospital.verification_status = 'verified'::verification_status) AND (hospital.operating_status = ANY (ARRAY['open'::hospital_operating_status, 'limited'::hospital_operating_status])))))));

create policy "hospitals_authenticated_read" on "public"."hospitals" as PERMISSIVE for SELECT to "authenticated" using ((private.is_super_admin() OR ((verification_status = 'verified'::verification_status) AND (operating_status = ANY (ARRAY['open'::hospital_operating_status, 'limited'::hospital_operating_status]))) OR private.is_hospital_admin_for(id)));

create policy "audit_logs_admin_read" on "public"."audit_logs" as PERMISSIVE for SELECT to "authenticated" using ((private.is_super_admin() OR private.is_hospital_admin_for(hospital_id)));

create policy "Account owners read assistant conversations" on "public"."care_assistant_conversations" as PERMISSIVE for SELECT to "authenticated" using ((user_id = private.current_user_id()));

create policy "doctor_schedules_anon_directory_read" on "public"."doctor_schedules" as PERMISSIVE for SELECT to "anon" using (is_active);

create policy "service_categories_anon_read" on "public"."healthcare_service_categories" as PERMISSIVE for SELECT to "anon" using (is_active);

create policy "system_settings_anon_public_read" on "public"."system_settings" as PERMISSIVE for SELECT to "anon" using (is_public);

create policy "diagnoses_scoped_read" on "public"."diagnoses" as PERMISSIVE for SELECT to "authenticated" using (private.can_access_clinical_record(patient_id, hospital_id, 'diagnoses'::text, id, 'view'::text));

create policy "laboratory_requests_scoped_read" on "public"."laboratory_requests" as PERMISSIVE for SELECT to "authenticated" using (private.can_access_clinical_record(patient_id, hospital_id, 'laboratory_requests'::text, id, 'view'::text));

create policy "laboratory_results_scoped_read" on "public"."laboratory_results" as PERMISSIVE for SELECT to "authenticated" using (private.can_access_clinical_record(patient_id, hospital_id, 'laboratory_results'::text, id, 'view'::text));

create policy "medical_documents_scoped_read" on "public"."medical_documents" as PERMISSIVE for SELECT to "authenticated" using (private.can_access_clinical_record(patient_id, hospital_id, 'medical_documents'::text, id, 'view'::text));

create policy "medical_records_scoped_read" on "public"."medical_records" as PERMISSIVE for SELECT to "authenticated" using (private.can_access_clinical_record(patient_id, hospital_id, 'medical_records'::text, id, 'view'::text));

create policy "prescriptions_scoped_read" on "public"."prescriptions" as PERMISSIVE for SELECT to "authenticated" using (private.can_access_clinical_record(patient_id, hospital_id, 'prescriptions'::text, id, 'view'::text));

create policy "treatment_plans_scoped_read" on "public"."treatment_plans" as PERMISSIVE for SELECT to "authenticated" using (private.can_access_clinical_record(patient_id, hospital_id, 'treatment_plans'::text, id, 'view'::text));

create policy "clinical_addenda_authorized_read" on "public"."clinical_record_addenda" as PERMISSIVE for SELECT to "authenticated" using (private.can_access_clinical_record(patient_id, originating_hospital_id, record_category, record_id, 'view'::text));

create policy "guest_requests_authorized_read" on "public"."guest_consultation_requests" as PERMISSIVE for SELECT to "authenticated" using (private.can_access_guest_request(id));

create policy "guest_status_history_read" on "public"."guest_request_status_history" as PERMISSIVE for SELECT to "authenticated" using (private.can_access_guest_request(request_id));

create policy "online_requests_authorized_read" on "public"."online_consultation_requests" as PERMISSIVE for SELECT to "authenticated" using (private.can_access_online_request(id));

create policy "online_request_history_authorized_read" on "public"."online_consultation_request_status_history" as PERMISSIVE for SELECT to "authenticated" using (private.can_access_online_request(request_id));

create policy "messages_participant_read" on "public"."chat_messages" as PERMISSIVE for SELECT to "authenticated" using (private.can_participate_conversation(conversation_id));

create policy "conversations_participant_read" on "public"."chat_conversations" as PERMISSIVE for SELECT to "authenticated" using (private.can_participate_conversation(id));

create policy "users_authorized_read" on "public"."users" as PERMISSIVE for SELECT to "authenticated" using (private.can_view_user(id));

create policy "consultation_status_history_read" on "public"."consultation_status_history" as PERMISSIVE for SELECT to "authenticated" using (private.is_consultation_participant(consultation_id));

create policy "video_sessions_participant_read" on "public"."video_sessions" as PERMISSIVE for SELECT to "authenticated" using (private.is_consultation_participant(consultation_id));

create policy "notification_outbox_super_admin_read" on "public"."notification_outbox" as PERMISSIVE for SELECT to "authenticated" using (private.is_super_admin());

create policy "security_logs_super_read" on "public"."security_logs" as PERMISSIVE for SELECT to "authenticated" using (private.is_super_admin());

create policy "classifications_public_read" on "public"."hospital_classifications" as PERMISSIVE for SELECT to "anon","authenticated" using (true);

create policy "role_permissions_authenticated_read" on "public"."role_permissions" as PERMISSIVE for SELECT to "authenticated" using (true);

create policy "roles_read" on "public"."roles" as PERMISSIVE for SELECT to "authenticated" using (true);

create policy "consultations_assigned_care_team_update" on "public"."consultations" as PERMISSIVE for UPDATE to "authenticated" using ((((doctor_id = private.current_doctor_id()) AND private.has_active_doctor_employment(doctor_id, hospital_id)) OR private.is_hospital_admin_for(hospital_id))) with check ((((doctor_id = private.current_doctor_id()) AND private.has_active_doctor_employment(doctor_id, hospital_id)) OR private.is_hospital_admin_for(hospital_id)));

create policy "guest_requests_reviewer_update" on "public"."guest_consultation_requests" as PERMISSIVE for UPDATE to "authenticated" using (((assigned_doctor_id = private.current_doctor_id()) OR private.is_hospital_admin_for(preferred_hospital_id))) with check (((assigned_doctor_id = private.current_doctor_id()) OR private.is_hospital_admin_for(preferred_hospital_id)));

create policy "users_authorized_update" on "public"."users" as PERMISSIVE for UPDATE to "authenticated" using (((auth_user_id = ( SELECT auth.uid() AS uid)) OR private.is_hospital_admin_for(hospital_id))) with check (((auth_user_id = ( SELECT auth.uid() AS uid)) OR private.is_hospital_admin_for(hospital_id)));

create policy "cnph_hospital_images_admin_update" on "storage"."objects" as PERMISSIVE for UPDATE to "authenticated" using (((bucket_id = 'hospital-images'::text) AND (private."current_role"() = ANY (ARRAY['hospital_admin'::text, 'super_admin'::text])))) with check (((bucket_id = 'hospital-images'::text) AND (private."current_role"() = ANY (ARRAY['hospital_admin'::text, 'super_admin'::text]))));

create policy "cnph_profile_images_owner_update" on "storage"."objects" as PERMISSIVE for UPDATE to "authenticated" using (((bucket_id = 'profile-images'::text) AND private.storage_path_owner(name))) with check (((bucket_id = 'profile-images'::text) AND private.storage_path_owner(name)));

create policy "cnph_admin_documents_scoped_update" on "storage"."objects" as PERMISSIVE for UPDATE to "authenticated" using (((bucket_id = ANY (ARRAY['doctor-documents'::text, 'hospital-accreditation-documents'::text])) AND private.can_manage_hospital_storage(name))) with check (((bucket_id = ANY (ARRAY['doctor-documents'::text, 'hospital-accreditation-documents'::text])) AND private.can_manage_hospital_storage(name)));

create policy "cnph_patient_documents_uploader_update" on "storage"."objects" as PERMISSIVE for UPDATE to "authenticated" using (((bucket_id = ANY (ARRAY['laboratory-results'::text, 'scanned-medical-results'::text, 'medical-documents'::text, 'prescriptions'::text, 'consultation-attachments'::text])) AND private.is_storage_upload_owner(name))) with check (((bucket_id = ANY (ARRAY['laboratory-results'::text, 'scanned-medical-results'::text, 'medical-documents'::text, 'prescriptions'::text, 'consultation-attachments'::text])) AND private.is_storage_upload_owner(name)));

create policy "diagnoses_origin_update" on "public"."diagnoses" as PERMISSIVE for UPDATE to "authenticated" using (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'diagnoses'::text, id, 'create'::text))) with check (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'diagnoses'::text, id, 'create'::text)));

create policy "laboratory_requests_origin_update" on "public"."laboratory_requests" as PERMISSIVE for UPDATE to "authenticated" using (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'laboratory_requests'::text, id, 'create'::text))) with check (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'laboratory_requests'::text, id, 'create'::text)));

create policy "laboratory_results_origin_update" on "public"."laboratory_results" as PERMISSIVE for UPDATE to "authenticated" using (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'laboratory_results'::text, id, 'create'::text))) with check (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'laboratory_results'::text, id, 'create'::text)));

create policy "medical_records_origin_update" on "public"."medical_records" as PERMISSIVE for UPDATE to "authenticated" using (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'medical_records'::text, id, 'create'::text))) with check (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'medical_records'::text, id, 'create'::text)));

create policy "prescriptions_origin_update" on "public"."prescriptions" as PERMISSIVE for UPDATE to "authenticated" using (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'prescriptions'::text, id, 'create'::text))) with check (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'prescriptions'::text, id, 'create'::text)));

create policy "treatment_plans_origin_update" on "public"."treatment_plans" as PERMISSIVE for UPDATE to "authenticated" using (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'treatment_plans'::text, id, 'create'::text))) with check (((doctor_id = private.current_doctor_id()) AND private.can_access_clinical_record(patient_id, hospital_id, 'treatment_plans'::text, id, 'create'::text)));

create policy "doctor_schedules_update" on "public"."doctor_schedules" as PERMISSIVE for UPDATE to "authenticated" using (((doctor_id = private.current_doctor_id()) OR (EXISTS ( SELECT 1
   FROM doctors d
  WHERE ((d.id = doctor_schedules.doctor_id) AND private.is_hospital_admin_for(d.hospital_id)))))) with check (((doctor_id = private.current_doctor_id()) OR (EXISTS ( SELECT 1
   FROM doctors d
  WHERE ((d.id = doctor_schedules.doctor_id) AND private.is_hospital_admin_for(d.hospital_id))))));

create policy "announcements_admin_update" on "public"."hospital_announcements" as PERMISSIVE for UPDATE to "authenticated" using (((is_global AND private.is_super_admin()) OR ((hospital_id IS NOT NULL) AND private.is_hospital_admin_for(hospital_id)))) with check (((is_global AND private.is_super_admin()) OR ((hospital_id IS NOT NULL) AND private.is_hospital_admin_for(hospital_id))));

create policy "notifications_owner_update" on "public"."notifications" as PERMISSIVE for UPDATE to "authenticated" using (((user_id = ( SELECT auth.uid() AS uid)) AND (private.current_user_id() IS NOT NULL))) with check (((user_id = ( SELECT auth.uid() AS uid)) AND (private.current_user_id() IS NOT NULL)));

create policy "conversations_doctor_update" on "public"."chat_conversations" as PERMISSIVE for UPDATE to "authenticated" using ((doctor_id = private.current_doctor_id())) with check ((doctor_id = private.current_doctor_id()));

create policy "video_sessions_doctor_update" on "public"."video_sessions" as PERMISSIVE for UPDATE to "authenticated" using ((EXISTS ( SELECT 1
   FROM consultations c
  WHERE ((c.id = video_sessions.consultation_id) AND (c.doctor_id = private.current_doctor_id()))))) with check ((EXISTS ( SELECT 1
   FROM consultations c
  WHERE ((c.id = video_sessions.consultation_id) AND (c.doctor_id = private.current_doctor_id())))));

create policy "hospitals_admin_update" on "public"."hospitals" as PERMISSIVE for UPDATE to "authenticated" using ((private.is_super_admin() OR private.is_hospital_admin_for(id))) with check ((private.is_super_admin() OR private.is_hospital_admin_for(id)));

create policy "document_jobs_doctor_update" on "public"."document_processing_jobs" as PERMISSIVE for UPDATE to "authenticated" using ((requested_by = private.current_doctor_id())) with check ((requested_by = private.current_doctor_id()));

create policy "Account owners update assistant conversations" on "public"."care_assistant_conversations" as PERMISSIVE for UPDATE to "authenticated" using ((user_id = private.current_user_id())) with check ((user_id = private.current_user_id()));

create policy "messages_receipt_update" on "public"."chat_messages" as PERMISSIVE for UPDATE to "authenticated" using (private.can_participate_conversation(conversation_id)) with check (private.can_participate_conversation(conversation_id));

create policy "doctors_admin_update" on "public"."doctors" as PERMISSIVE for UPDATE to "authenticated" using (private.is_hospital_admin_for(hospital_id)) with check (private.is_hospital_admin_for(hospital_id));

create policy "emergency_status_admin_update" on "public"."emergency_room_status" as PERMISSIVE for UPDATE to "authenticated" using (private.is_hospital_admin_for(hospital_id)) with check (private.is_hospital_admin_for(hospital_id));

create policy "beds_admin_update" on "public"."hospital_beds" as PERMISSIVE for UPDATE to "authenticated" using (private.is_hospital_admin_for(hospital_id)) with check (private.is_hospital_admin_for(hospital_id));

create policy "departments_admin_update" on "public"."hospital_departments" as PERMISSIVE for UPDATE to "authenticated" using (private.is_hospital_admin_for(hospital_id)) with check (private.is_hospital_admin_for(hospital_id));

create policy "facility_status_admin_update" on "public"."hospital_facility_status" as PERMISSIVE for UPDATE to "authenticated" using (private.is_hospital_admin_for(hospital_id)) with check (private.is_hospital_admin_for(hospital_id));

create policy "rooms_admin_update" on "public"."hospital_rooms" as PERMISSIVE for UPDATE to "authenticated" using (private.is_hospital_admin_for(hospital_id)) with check (private.is_hospital_admin_for(hospital_id));

create policy "service_doctors_admin_update" on "public"."hospital_service_doctors" as PERMISSIVE for UPDATE to "authenticated" using (private.is_hospital_admin_for(hospital_id)) with check (private.is_hospital_admin_for(hospital_id));

create policy "services_admin_update" on "public"."hospital_services" as PERMISSIVE for UPDATE to "authenticated" using (private.is_hospital_admin_for(hospital_id)) with check (private.is_hospital_admin_for(hospital_id));

create policy "service_categories_super_admin_update" on "public"."healthcare_service_categories" as PERMISSIVE for UPDATE to "authenticated" using (private.is_super_admin()) with check (private.is_super_admin());

create policy "classifications_super_admin_update" on "public"."hospital_classifications" as PERMISSIVE for UPDATE to "authenticated" using (private.is_super_admin()) with check (private.is_super_admin());

create policy "maintenance_windows_super_update" on "public"."maintenance_windows" as PERMISSIVE for UPDATE to "authenticated" using (private.is_super_admin()) with check (private.is_super_admin());

create policy "role_permissions_super_update" on "public"."role_permissions" as PERMISSIVE for UPDATE to "authenticated" using (private.is_super_admin()) with check (private.is_super_admin());

create policy "roles_super_admin_update" on "public"."roles" as PERMISSIVE for UPDATE to "authenticated" using (private.is_super_admin()) with check (private.is_super_admin());

create policy "system_settings_super_update" on "public"."system_settings" as PERMISSIVE for UPDATE to "authenticated" using (private.is_super_admin()) with check (private.is_super_admin());

CREATE TRIGGER on_auth_user_created AFTER INSERT ON auth.users FOR EACH ROW EXECUTE FUNCTION handle_new_auth_user();

CREATE TRIGGER aa_lock_consultation_reservation BEFORE INSERT OR UPDATE OF appointment_date ON public.consultations FOR EACH ROW EXECUTE FUNCTION private.lock_consultation_reservation();

CREATE TRIGGER audit_ai_assessments AFTER INSERT OR DELETE OR UPDATE ON public.ai_assessments FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_ai_configurations AFTER INSERT OR DELETE OR UPDATE ON public.ai_configurations FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_beds AFTER INSERT OR DELETE OR UPDATE ON public.hospital_beds FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_chat_conversations AFTER INSERT OR DELETE OR UPDATE ON public.chat_conversations FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_chat_messages AFTER INSERT OR DELETE OR UPDATE ON public.chat_messages FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_consultation_attachments AFTER INSERT OR DELETE OR UPDATE ON public.consultation_attachments FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_consultations AFTER INSERT OR DELETE OR UPDATE ON public.consultations FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_departments AFTER INSERT OR DELETE OR UPDATE ON public.hospital_departments FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_diagnoses AFTER INSERT OR DELETE OR UPDATE ON public.diagnoses FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_doctor_patient_assignments AFTER INSERT OR DELETE OR UPDATE ON public.doctor_patient_assignments FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_doctor_schedules AFTER INSERT OR DELETE OR UPDATE ON public.doctor_schedules FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_doctors AFTER INSERT OR DELETE OR UPDATE ON public.doctors FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_document_processing_jobs AFTER INSERT OR DELETE OR UPDATE ON public.document_processing_jobs FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_emergency_status AFTER INSERT OR DELETE OR UPDATE ON public.emergency_room_status FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_guest_requests AFTER INSERT OR DELETE OR UPDATE ON public.guest_consultation_requests FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_hospital_announcements AFTER INSERT OR DELETE OR UPDATE ON public.hospital_announcements FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_hospital_facility_status AFTER INSERT OR DELETE OR UPDATE ON public.hospital_facility_status FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_hospitals AFTER INSERT OR DELETE OR UPDATE ON public.hospitals FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_laboratory_requests AFTER INSERT OR DELETE OR UPDATE ON public.laboratory_requests FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_laboratory_results AFTER INSERT OR DELETE OR UPDATE ON public.laboratory_results FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_maintenance_windows AFTER INSERT OR DELETE OR UPDATE ON public.maintenance_windows FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_medical_documents AFTER INSERT OR DELETE OR UPDATE ON public.medical_documents FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_medical_records AFTER INSERT OR DELETE OR UPDATE ON public.medical_records FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_multi_hospital_change AFTER INSERT OR DELETE OR UPDATE ON public.clinical_record_addenda FOR EACH ROW EXECUTE FUNCTION private.audit_multi_hospital_change();

CREATE TRIGGER audit_multi_hospital_change AFTER INSERT OR DELETE OR UPDATE ON public.clinical_record_quarantine FOR EACH ROW EXECUTE FUNCTION private.audit_multi_hospital_change();

CREATE TRIGGER audit_multi_hospital_change AFTER INSERT OR DELETE OR UPDATE ON public.doctor_hospital_employments FOR EACH ROW EXECUTE FUNCTION private.audit_multi_hospital_change();

CREATE TRIGGER audit_multi_hospital_change AFTER INSERT OR DELETE OR UPDATE ON public.emergency_access_events FOR EACH ROW EXECUTE FUNCTION private.audit_multi_hospital_change();

CREATE TRIGGER audit_multi_hospital_change AFTER INSERT OR DELETE OR UPDATE ON public.online_consultation_requests FOR EACH ROW EXECUTE FUNCTION private.audit_multi_hospital_change();

CREATE TRIGGER audit_multi_hospital_change AFTER INSERT OR DELETE OR UPDATE ON public.patient_access_grants FOR EACH ROW EXECUTE FUNCTION private.audit_multi_hospital_change();

CREATE TRIGGER audit_multi_hospital_change AFTER INSERT OR DELETE OR UPDATE ON public.patient_access_record_selections FOR EACH ROW EXECUTE FUNCTION private.audit_multi_hospital_change();

CREATE TRIGGER audit_multi_hospital_change AFTER INSERT OR DELETE OR UPDATE ON public.patient_access_scopes FOR EACH ROW EXECUTE FUNCTION private.audit_multi_hospital_change();

CREATE TRIGGER audit_multi_hospital_change AFTER INSERT OR DELETE OR UPDATE ON public.patient_care_relationships FOR EACH ROW EXECUTE FUNCTION private.audit_multi_hospital_change();

CREATE TRIGGER audit_multi_hospital_change AFTER INSERT OR DELETE OR UPDATE ON public.patient_hospital_identifiers FOR EACH ROW EXECUTE FUNCTION private.audit_multi_hospital_change();

CREATE TRIGGER audit_multi_hospital_change AFTER INSERT OR DELETE OR UPDATE ON public.patient_representatives FOR EACH ROW EXECUTE FUNCTION private.audit_multi_hospital_change();

CREATE TRIGGER audit_notifications AFTER INSERT OR DELETE OR UPDATE ON public.notifications FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_patient_consents AFTER INSERT OR DELETE OR UPDATE ON public.patient_consents FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_patients AFTER INSERT OR DELETE OR UPDATE ON public.patients FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_prescriptions AFTER INSERT OR DELETE OR UPDATE ON public.prescriptions FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_role_permissions AFTER INSERT OR DELETE OR UPDATE ON public.role_permissions FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_rooms AFTER INSERT OR DELETE OR UPDATE ON public.hospital_rooms FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_service_categories AFTER INSERT OR DELETE OR UPDATE ON public.healthcare_service_categories FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_service_doctors AFTER INSERT OR DELETE OR UPDATE ON public.hospital_service_doctors FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_services AFTER INSERT OR DELETE OR UPDATE ON public.hospital_services FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_treatment_plans AFTER INSERT OR DELETE OR UPDATE ON public.treatment_plans FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_users AFTER INSERT OR DELETE OR UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER audit_video_sessions AFTER INSERT OR DELETE OR UPDATE ON public.video_sessions FOR EACH ROW EXECUTE FUNCTION log_audit_event();

CREATE TRIGGER derive_emergency_capacity_before_write BEFORE INSERT OR UPDATE ON public.emergency_room_status FOR EACH ROW EXECUTE FUNCTION private.derive_emergency_capacity();

CREATE TRIGGER end_replaced_assignment_before_write BEFORE INSERT OR UPDATE OF doctor_id, patient_id, assignment_status, ended_at ON public.doctor_patient_assignments FOR EACH ROW EXECUTE FUNCTION private.end_replaced_doctor_patient_assignment();

CREATE TRIGGER enforce_clinical_provenance_before_update BEFORE UPDATE ON public.diagnoses FOR EACH ROW EXECUTE FUNCTION private.enforce_clinical_provenance();

CREATE TRIGGER enforce_clinical_provenance_before_update BEFORE UPDATE ON public.laboratory_requests FOR EACH ROW EXECUTE FUNCTION private.enforce_clinical_provenance();

CREATE TRIGGER enforce_clinical_provenance_before_update BEFORE UPDATE ON public.laboratory_results FOR EACH ROW EXECUTE FUNCTION private.enforce_clinical_provenance();

CREATE TRIGGER enforce_clinical_provenance_before_update BEFORE UPDATE ON public.medical_documents FOR EACH ROW EXECUTE FUNCTION private.enforce_clinical_provenance();

CREATE TRIGGER enforce_clinical_provenance_before_update BEFORE UPDATE ON public.medical_records FOR EACH ROW EXECUTE FUNCTION private.enforce_clinical_provenance();

CREATE TRIGGER enforce_clinical_provenance_before_update BEFORE UPDATE ON public.prescriptions FOR EACH ROW EXECUTE FUNCTION private.enforce_clinical_provenance();

CREATE TRIGGER enforce_clinical_provenance_before_update BEFORE UPDATE ON public.treatment_plans FOR EACH ROW EXECUTE FUNCTION private.enforce_clinical_provenance();

CREATE TRIGGER enforce_consultation_assignment_provenance_before_update BEFORE UPDATE ON public.consultations FOR EACH ROW EXECUTE FUNCTION private.enforce_consultation_assignment_provenance();

CREATE TRIGGER enforce_consultation_change_before_write BEFORE UPDATE ON public.consultations FOR EACH ROW EXECUTE FUNCTION enforce_consultation_change();

CREATE TRIGGER enforce_guest_request_change_before_update BEFORE UPDATE ON public.guest_consultation_requests FOR EACH ROW EXECUTE FUNCTION enforce_guest_request_change();

CREATE TRIGGER enforce_reservation_lead_time BEFORE INSERT OR UPDATE OF appointment_date ON public.consultations FOR EACH ROW EXECUTE FUNCTION private.enforce_reservation_lead_time();

CREATE TRIGGER enforce_reservation_lead_time BEFORE INSERT OR UPDATE OF preferred_schedule ON public.guest_consultation_requests FOR EACH ROW EXECUTE FUNCTION private.enforce_reservation_lead_time();

CREATE TRIGGER enforce_reservation_lead_time BEFORE INSERT OR UPDATE OF preferred_schedule ON public.online_consultation_requests FOR EACH ROW EXECUTE FUNCTION private.enforce_reservation_lead_time();

CREATE TRIGGER enrich_connection_request_notification_before_write BEFORE INSERT OR UPDATE OF reference_id, notification_type, data ON public.notifications FOR EACH ROW EXECUTE FUNCTION private.enrich_connection_request_notification();

CREATE TRIGGER finalize_online_outcome AFTER UPDATE OF request_status ON public.online_consultation_requests FOR EACH ROW EXECUTE FUNCTION private.finalize_online_outcome();

CREATE TRIGGER guard_clinical_consultation BEFORE UPDATE OF status ON public.consultations FOR EACH ROW EXECUTE FUNCTION private.guard_clinical_consultation();

CREATE TRIGGER guard_document_review BEFORE UPDATE ON public.medical_documents FOR EACH ROW EXECUTE FUNCTION private.guard_document_review();

CREATE TRIGGER guard_online_request_change BEFORE UPDATE ON public.online_consultation_requests FOR EACH ROW EXECUTE FUNCTION private.guard_online_request_change();

CREATE TRIGGER guard_prescription_order_reference BEFORE INSERT OR UPDATE OF order_id ON public.prescriptions FOR EACH ROW EXECUTE FUNCTION private.guard_prescription_order_reference();

CREATE TRIGGER guard_source_document_record BEFORE INSERT ON public.medical_records FOR EACH ROW EXECUTE FUNCTION private.guard_source_document_record();

CREATE TRIGGER invalidate_video_session_after_consultation_change AFTER UPDATE OF appointment_date, status ON public.consultations FOR EACH ROW EXECUTE FUNCTION invalidate_video_session_after_consultation_change();

CREATE TRIGGER link_guest_patient_before_validation BEFORE INSERT ON public.consultations FOR EACH ROW EXECUTE FUNCTION link_guest_patient_to_consultation();

CREATE TRIGGER log_user_security_change_after_update AFTER UPDATE OF account_status, role_id ON public.users FOR EACH ROW EXECUTE FUNCTION log_user_security_change();

CREATE TRIGGER mark_guest_request_approved_before_consultation BEFORE INSERT ON public.consultations FOR EACH ROW EXECUTE FUNCTION private.mark_guest_request_approved_for_consultation();

CREATE TRIGGER notify_chat_message_after_insert AFTER INSERT ON public.chat_messages FOR EACH ROW EXECUTE FUNCTION notify_chat_message();

CREATE TRIGGER notify_consultation_status_after_write AFTER INSERT OR UPDATE OF status, appointment_date ON public.consultations FOR EACH ROW EXECUTE FUNCTION notify_consultation_status_change();

CREATE TRIGGER notify_emergency_status_after_update AFTER UPDATE OF status ON public.emergency_room_status FOR EACH ROW EXECUTE FUNCTION notify_hospital_status_alert();

CREATE TRIGGER notify_facility_status_after_update AFTER UPDATE OF status ON public.hospital_facility_status FOR EACH ROW EXECUTE FUNCTION notify_hospital_status_alert();

CREATE TRIGGER notify_hospital_announcement_after_write AFTER INSERT OR UPDATE OF title, message, published_at, expires_at ON public.hospital_announcements FOR EACH ROW EXECUTE FUNCTION notify_hospital_announcement();

CREATE TRIGGER notify_hospital_operating_status_after_update AFTER UPDATE OF operating_status ON public.hospitals FOR EACH ROW EXECUTE FUNCTION notify_hospital_status_alert();

CREATE TRIGGER notify_laboratory_result_ready_after_write AFTER INSERT OR UPDATE OF verification_status ON public.laboratory_results FOR EACH ROW EXECUTE FUNCTION notify_laboratory_result_ready();

CREATE TRIGGER notify_patient_account_activation_after_write AFTER INSERT OR UPDATE OF user_id, account_activation_status, profile_status ON public.patients FOR EACH ROW EXECUTE FUNCTION notify_patient_account_activation();

CREATE TRIGGER notify_prescription_after_insert AFTER INSERT ON public.prescriptions FOR EACH ROW EXECUTE FUNCTION notify_prescription_created();

CREATE TRIGGER prescriptions_authenticated_signature BEFORE INSERT ON public.prescriptions FOR EACH ROW EXECUTE FUNCTION private.apply_authenticated_prescription_signature();

CREATE TRIGGER protect_chat_message_before_update BEFORE UPDATE ON public.chat_messages FOR EACH ROW EXECUTE FUNCTION protect_chat_message();

CREATE TRIGGER protect_hospital_approval_fields_before_update BEFORE UPDATE ON public.hospitals FOR EACH ROW EXECUTE FUNCTION protect_hospital_approval_fields();

CREATE TRIGGER protect_laboratory_confirmation_before_write BEFORE INSERT OR UPDATE ON public.laboratory_results FOR EACH ROW EXECUTE FUNCTION protect_laboratory_confirmation();

CREATE TRIGGER protect_reserved_schedule BEFORE INSERT OR DELETE OR UPDATE ON public.doctor_schedules FOR EACH ROW EXECUTE FUNCTION private.protect_reserved_schedule();

CREATE TRIGGER protect_user_privileges_before_update BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION protect_user_privileges();

CREATE TRIGGER queue_confirmed_consultation_email_after_update AFTER UPDATE OF request_status, consultation_channel ON public.online_consultation_requests FOR EACH ROW EXECUTE FUNCTION private.queue_confirmed_consultation_email();

CREATE TRIGGER queue_notification_deliveries_after_insert AFTER INSERT ON public.notifications FOR EACH ROW EXECUTE FUNCTION queue_notification_deliveries();

CREATE TRIGGER record_consultation_status_after_write AFTER INSERT OR UPDATE ON public.consultations FOR EACH ROW EXECUTE FUNCTION record_consultation_status_history();

CREATE TRIGGER record_guest_status_after_write AFTER INSERT OR UPDATE ON public.guest_consultation_requests FOR EACH ROW EXECUTE FUNCTION record_guest_status_history();

CREATE TRIGGER record_online_request_status_after_write AFTER INSERT OR UPDATE OF request_status ON public.online_consultation_requests FOR EACH ROW EXECUTE FUNCTION private.record_online_request_status();

CREATE TRIGGER revoke_ended_assignment_access_after_update AFTER UPDATE OF assignment_status, ended_at ON public.doctor_patient_assignments FOR EACH ROW EXECUTE FUNCTION private.revoke_ended_assignment_access();

CREATE TRIGGER set_ai_configurations_updated_at BEFORE UPDATE ON public.ai_configurations FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_chat_conversations_updated_at BEFORE UPDATE ON public.chat_conversations FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_consultations_updated_at BEFORE UPDATE ON public.consultations FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_departments_updated_at BEFORE UPDATE ON public.hospital_departments FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_diagnoses_updated_at BEFORE UPDATE ON public.diagnoses FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_doctors_updated_at BEFORE UPDATE ON public.doctors FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_document_processing_jobs_updated_at BEFORE UPDATE ON public.document_processing_jobs FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_guest_reference BEFORE INSERT ON public.guest_consultation_requests FOR EACH ROW EXECUTE FUNCTION set_guest_reference_number();

CREATE TRIGGER set_guest_requests_updated_at BEFORE UPDATE ON public.guest_consultation_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_hospital_classifications_updated_at BEFORE UPDATE ON public.hospital_classifications FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_hospitals_updated_at BEFORE UPDATE ON public.hospitals FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_laboratory_requests_updated_at BEFORE UPDATE ON public.laboratory_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_laboratory_results_updated_at BEFORE UPDATE ON public.laboratory_results FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_maintenance_windows_updated_at BEFORE UPDATE ON public.maintenance_windows FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_medical_document_provenance_before_insert BEFORE INSERT ON public.medical_documents FOR EACH ROW EXECUTE FUNCTION private.set_medical_document_provenance();

CREATE TRIGGER set_medical_records_updated_at BEFORE UPDATE ON public.medical_records FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_multi_hospital_updated_at BEFORE UPDATE ON public.doctor_hospital_employments FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_multi_hospital_updated_at BEFORE UPDATE ON public.patient_access_grants FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_multi_hospital_updated_at BEFORE UPDATE ON public.patient_care_relationships FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_multi_hospital_updated_at BEFORE UPDATE ON public.patient_hospital_identifiers FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_multi_hospital_updated_at BEFORE UPDATE ON public.patient_representatives FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_notification_outbox_updated_at BEFORE UPDATE ON public.notification_outbox FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_notification_preferences_updated_at BEFORE UPDATE ON public.notification_preferences FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_online_request_reference_before_insert BEFORE INSERT ON public.online_consultation_requests FOR EACH ROW EXECUTE FUNCTION private.set_online_request_reference();

CREATE TRIGGER set_online_requests_updated_at BEFORE UPDATE ON public.online_consultation_requests FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_patient_consents_updated_at BEFORE UPDATE ON public.patient_consents FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_patient_number_before_insert BEFORE INSERT ON public.patients FOR EACH ROW EXECUTE FUNCTION set_patient_number();

CREATE TRIGGER set_patients_updated_at BEFORE UPDATE ON public.patients FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_prescriptions_updated_at BEFORE UPDATE ON public.prescriptions FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_role_permissions_updated_at BEFORE UPDATE ON public.role_permissions FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_service_categories_updated_at BEFORE UPDATE ON public.healthcare_service_categories FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_service_doctors_updated_at BEFORE UPDATE ON public.hospital_service_doctors FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_services_updated_at BEFORE UPDATE ON public.hospital_services FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_system_setting_actor_before_write BEFORE INSERT OR UPDATE ON public.system_settings FOR EACH ROW EXECUTE FUNCTION set_system_setting_actor();

CREATE TRIGGER set_treatment_plans_updated_at BEFORE UPDATE ON public.treatment_plans FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_users_updated_at BEFORE UPDATE ON public.users FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER set_video_sessions_updated_at BEFORE UPDATE ON public.video_sessions FOR EACH ROW EXECUTE FUNCTION set_updated_at();

CREATE TRIGGER standardize_guest_request_identity_before_write BEFORE INSERT OR UPDATE ON public.guest_consultation_requests FOR EACH ROW EXECUTE FUNCTION standardize_guest_request_identity();

CREATE TRIGGER sync_completed_consultation_clinical_records_after_write AFTER INSERT OR UPDATE OF status, patient_id, confirmed_diagnosis, treatment_plan ON public.consultations FOR EACH ROW EXECUTE FUNCTION sync_completed_consultation_clinical_records();

CREATE TRIGGER sync_consultation_care_access_after_write AFTER INSERT OR UPDATE OF status, doctor_id ON public.consultations FOR EACH ROW EXECUTE FUNCTION private.sync_consultation_care_access();

CREATE TRIGGER sync_doctor_profile_image AFTER UPDATE OF profile_image_url ON public.users FOR EACH ROW EXECUTE FUNCTION sync_doctor_profile_image();

CREATE TRIGGER sync_email_delivery_status AFTER INSERT OR UPDATE OF status ON public.notification_outbox FOR EACH ROW EXECUTE FUNCTION private.sync_email_delivery_status();

CREATE TRIGGER sync_employment_termination_after_update AFTER UPDATE OF employment_status, ends_at ON public.doctor_hospital_employments FOR EACH ROW EXECUTE FUNCTION private.sync_employment_termination();

CREATE TRIGGER sync_video_session_request_status_after_write AFTER INSERT OR UPDATE OF status ON public.video_sessions FOR EACH ROW EXECUTE FUNCTION private.sync_video_session_request_status();

CREATE TRIGGER validate_bed_department_before_write BEFORE INSERT OR UPDATE ON public.hospital_beds FOR EACH ROW EXECUTE FUNCTION validate_hospital_department_relationship();

CREATE TRIGGER validate_consultation_identity_source_before_write BEFORE INSERT OR UPDATE OF patient_id, guest_request_id ON public.consultations FOR EACH ROW EXECUTE FUNCTION private.validate_consultation_identity_source();

CREATE TRIGGER validate_consultation_relationships_before_write BEFORE INSERT OR UPDATE ON public.consultations FOR EACH ROW EXECUTE FUNCTION validate_consultation_relationships();

CREATE TRIGGER validate_conversation_relationships_before_write BEFORE INSERT OR UPDATE ON public.chat_conversations FOR EACH ROW EXECUTE FUNCTION validate_conversation_relationships();

CREATE TRIGGER validate_diagnosis_relationships BEFORE INSERT OR UPDATE ON public.diagnoses FOR EACH ROW EXECUTE FUNCTION validate_clinical_relationships();

CREATE TRIGGER validate_doctor_department_before_write BEFORE INSERT OR UPDATE ON public.doctors FOR EACH ROW EXECUTE FUNCTION validate_hospital_department_relationship();

CREATE TRIGGER validate_doctor_user_before_write BEFORE INSERT OR UPDATE ON public.doctors FOR EACH ROW EXECUTE FUNCTION validate_doctor_user_relationship();

CREATE TRIGGER validate_guest_hospital_relationships_before_write BEFORE INSERT OR UPDATE ON public.guest_consultation_requests FOR EACH ROW EXECUTE FUNCTION validate_guest_hospital_relationships();

CREATE TRIGGER validate_laboratory_request_relationships BEFORE INSERT OR UPDATE ON public.laboratory_requests FOR EACH ROW EXECUTE FUNCTION validate_clinical_relationships();

CREATE TRIGGER validate_laboratory_result_relationships BEFORE INSERT OR UPDATE ON public.laboratory_results FOR EACH ROW EXECUTE FUNCTION validate_clinical_relationships();

CREATE TRIGGER validate_medical_record_relationships BEFORE INSERT OR UPDATE ON public.medical_records FOR EACH ROW EXECUTE FUNCTION validate_clinical_relationships();

CREATE TRIGGER validate_prescription_relationships_before_write BEFORE INSERT OR UPDATE ON public.prescriptions FOR EACH ROW EXECUTE FUNCTION validate_prescription_relationships();

CREATE TRIGGER validate_service_department_before_write BEFORE INSERT OR UPDATE ON public.hospital_services FOR EACH ROW EXECUTE FUNCTION validate_hospital_department_relationship();

CREATE TRIGGER validate_treatment_plan_relationships BEFORE INSERT OR UPDATE ON public.treatment_plans FOR EACH ROW EXECUTE FUNCTION validate_clinical_relationships();

CREATE TRIGGER z_validate_document_reference BEFORE INSERT ON public.medical_documents FOR EACH ROW EXECUTE FUNCTION private.validate_document_reference();

CREATE TRIGGER zz_set_medical_document_ai_state_before_insert BEFORE INSERT ON public.medical_documents FOR EACH ROW EXECUTE FUNCTION private.set_medical_document_ai_state();

CREATE TRIGGER zz_sync_rescheduled_consultation AFTER UPDATE OF appointment_date ON public.consultations FOR EACH ROW EXECUTE FUNCTION private.sync_rescheduled_consultation();

set check_function_bodies = on;
