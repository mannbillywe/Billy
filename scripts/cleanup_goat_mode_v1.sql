-- ============================================================================
-- CLEANUP: drop Goat Mode v1 objects (post-Apr-16 schema) to match the
-- code that main now points at (commit 3a7d27f / April 16 build).
--
-- What this does:
--   * Drops the 7 tables introduced by 20260423120000_goat_mode_v1.sql and
--     20260424090000_goat_mode_phase8_entitlement.sql (indexes, triggers,
--     RLS policies go with the table via CASCADE).
--   * Drops the helper function goat_mode_enabled_for(uuid).
--
-- What this deliberately does NOT touch:
--   * public.handle_new_user() — the hardened (ON CONFLICT) version from
--     20260417220000 is strictly safer than the Apr-16 version. Leaving it in
--     place avoids a latent race on signup.
--   * profiles.goat_mode column — that was added by the Apr-16-tree migration
--     20260422120000_profiles_goat_mode_flag.sql, still in main, still in code.
--   * Any auth.users rows. Use scripts/nuke_all_data.sql if you want a data wipe.
--
-- Safe to run multiple times (all drops are IF EXISTS).
-- Run from the Supabase SQL editor OR via `supabase db execute`.
-- ============================================================================

begin;

-- ---------------------------------------------------------------------------
-- Drop phase8 helper function first (nothing depends on it after tables go).
-- ---------------------------------------------------------------------------
drop function if exists public.goat_mode_enabled_for(uuid);

-- ---------------------------------------------------------------------------
-- Drop tables in dependency order (child first).
-- CASCADE removes associated policies, indexes, triggers, and FKs.
-- ---------------------------------------------------------------------------
drop table if exists public.goat_mode_recommendations cascade;
drop table if exists public.goat_mode_job_events     cascade;
drop table if exists public.goat_mode_snapshots      cascade;
drop table if exists public.goat_mode_jobs           cascade;

drop table if exists public.goat_obligations         cascade;
drop table if exists public.goat_goals               cascade;
drop table if exists public.goat_user_inputs         cascade;

commit;

-- ---------------------------------------------------------------------------
-- Verification — should return zero rows:
-- ---------------------------------------------------------------------------
select table_schema, table_name
from   information_schema.tables
where  table_schema = 'public'
  and  table_name in (
         'goat_mode_jobs',
         'goat_mode_snapshots',
         'goat_mode_job_events',
         'goat_mode_recommendations',
         'goat_user_inputs',
         'goat_goals',
         'goat_obligations'
       )
order  by table_name;

select n.nspname as schema, p.proname as function
from   pg_proc p
join   pg_namespace n on n.oid = p.pronamespace
where  n.nspname = 'public'
  and  p.proname = 'goat_mode_enabled_for';
