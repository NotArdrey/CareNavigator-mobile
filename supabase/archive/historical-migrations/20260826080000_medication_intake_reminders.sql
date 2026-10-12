-- Migration: Add medication intake reminders support to notification_preferences

alter table public.notification_preferences
  add column if not exists medication_reminders boolean not null default true;

comment on column public.notification_preferences.medication_reminders is
  'Whether the user receives daily medication intake reminders aligned with their active prescription frequencies.';
