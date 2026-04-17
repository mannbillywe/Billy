-- Make the auth → profiles bootstrap trigger idempotent and self-healing.
--
-- Why
-- ---
-- The previous `handle_new_user` did a bare `insert into profiles` and a bare
-- `insert into user_usage_limits`. If either row already existed (which is
-- possible after partial data wipes, restored backups, or manual fix-ups),
-- the trigger raised a unique-violation and the signup failed silently
-- downstream — leaving the new auth user without a profile row. The client
-- then fell back to "whatever profileProvider last cached" for that install,
-- which is the "all profiles look the same" bug the user hit.
--
-- What this migration does
-- ------------------------
-- 1. Re-creates `handle_new_user` with `ON CONFLICT DO NOTHING` on both inserts.
-- 2. Back-fills missing profiles / usage rows for any auth.users that don't
--    have them (safety net for existing installs).
-- 3. Re-asserts the trigger so a fresh install always has it wired.

create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, display_name, avatar_url)
  values (
    new.id,
    coalesce(
      new.raw_user_meta_data->>'full_name',
      new.raw_user_meta_data->>'name',
      split_part(new.email, '@', 1)
    ),
    new.raw_user_meta_data->>'avatar_url'
  )
  on conflict (id) do nothing;

  insert into public.user_usage_limits (user_id)
  values (new.id)
  on conflict (user_id) do nothing;

  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- Back-fill: every existing auth user must have a matching profile row.
insert into public.profiles (id, display_name, avatar_url)
select
  u.id,
  coalesce(
    u.raw_user_meta_data->>'full_name',
    u.raw_user_meta_data->>'name',
    split_part(u.email, '@', 1)
  ),
  u.raw_user_meta_data->>'avatar_url'
from auth.users u
where not exists (select 1 from public.profiles p where p.id = u.id)
on conflict (id) do nothing;

insert into public.user_usage_limits (user_id)
select u.id
from auth.users u
where not exists (select 1 from public.user_usage_limits l where l.user_id = u.id)
on conflict (user_id) do nothing;
