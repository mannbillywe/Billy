-- GOAT Mode: default **off** for new profiles. Enable per user in Table Editor or:
--   update public.profiles set goat = true where id = '<user_uuid>';
-- Does not mass-update existing rows (operators may have set goat already).
alter table public.profiles alter column goat set default false;

comment on column public.profiles.goat is 'When true, user may open GOAT Mode. Default false for new signups; set true manually per account.';
