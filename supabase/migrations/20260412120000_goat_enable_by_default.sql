-- GOAT Mode: turn on for everyone by default so Recurring/Forecast are usable without manual SQL.
-- Operators can set profiles.goat = false for accounts that should stay on classic Billy only.
alter table public.profiles alter column goat set default true;

update public.profiles
set goat = true
where goat is distinct from true;

comment on column public.profiles.goat is 'When true, user sees GOAT entry points and workspace. Default true; set false to hide.';
