-- Feature flag: GOAT Mode entry points only when profiles.goat_mode is true.
-- New signups default to false; enable per user in SQL or Table Editor:
--   update public.profiles set goat_mode = true where id = '<user_uuid>';

alter table public.profiles
  add column if not exists goat_mode boolean not null default false;

comment on column public.profiles.goat_mode is
  'When true, the Billy app shows GOAT Mode. Default false; set true to grant access.';
