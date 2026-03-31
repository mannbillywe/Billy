-- Add per-user Gemini API key to profiles
-- Users without a key will use the app's default key
-- Run in Supabase SQL Editor

alter table public.profiles
  add column if not exists gemini_api_key text;

comment on column public.profiles.gemini_api_key is 'User-specific Google Gemini API key. If null, app uses default key.';
