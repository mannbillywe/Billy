-- Remove dead splits/split_participants tables (unused in app code).

drop policy if exists "Users can read own splits" on public.splits;
drop policy if exists "Users can insert own splits" on public.splits;
drop policy if exists "Users can update own splits" on public.splits;
drop policy if exists "Users can delete own splits" on public.splits;
drop policy if exists "Users can read participants of own splits" on public.split_participants;
drop policy if exists "Users can insert participants for own splits" on public.split_participants;

drop table if exists public.split_participants cascade;
drop table if exists public.splits cascade;
