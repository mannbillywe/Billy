-- GOAT Mode gate: power-user premium shell (app reads this flag; toggle in SQL or Table Editor).
alter table public.profiles
  add column if not exists goat boolean not null default false;

comment on column public.profiles.goat is 'When true, user may open GOAT Mode premium shell in the app.';
