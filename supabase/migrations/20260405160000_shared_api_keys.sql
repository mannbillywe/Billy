-- Shared API keys table: a single Gemini key used by all accounts.
-- Replaces per-user profiles.gemini_api_key approach.

create table public.app_api_keys (
  id uuid primary key default uuid_generate_v4(),
  provider text not null unique,  -- e.g. 'gemini'
  api_key text not null,
  is_active boolean not null default true,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

alter table public.app_api_keys enable row level security;

-- All authenticated users can read active keys (Edge Functions use service role,
-- but this policy lets the Flutter app check key existence if needed).
create policy "Authenticated users can read active keys"
  on public.app_api_keys for select
  using (auth.role() = 'authenticated' and is_active = true);

-- Helper function: get the active API key for a provider.
-- Used by Edge Functions to resolve a single shared key.
create or replace function public.get_api_key(p_provider text)
returns text as $$
declare
  key text;
begin
  select api_key into key
  from public.app_api_keys
  where provider = p_provider and is_active = true
  limit 1;
  return key;
end;
$$ language plpgsql security definer;
