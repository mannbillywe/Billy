-- GOAT-only Gemini: optional second key for analytics-insights when the client sends gemini_scope=goat
-- and profiles.goat is true. Edge resolution: GOAT_GEMINI_API_KEY secret → row below → fallback to main gemini chain.
--
-- Example (run in SQL Editor with appropriate privileges):
-- insert into public.app_api_keys (provider, api_key, is_active)
-- values ('goat_gemini', 'YOUR_GOOGLE_AI_STUDIO_KEY', true)
-- on conflict (provider) do update set api_key = excluded.api_key, is_active = true, updated_at = now();

comment on table public.app_api_keys is
  'Shared keys for Edge Functions: provider gemini (default OCR + analytics), goat_gemini (GOAT workspace AI only).';
