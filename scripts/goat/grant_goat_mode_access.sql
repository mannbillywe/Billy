-- ============================================================================
-- Grant GOAT Mode access to one or more users by UUID.
--
-- HOW TO USE
--   1. Paste auth UUIDs into the `uids` array below (comma-separated).
--   2. Open Supabase Dashboard → SQL Editor → paste this file → Run.
--   3. Script is idempotent: re-running with the same UUIDs does nothing.
--
-- WHAT IT DOES
--   * Upserts into public.goat_mode_access (the admin ledger).
--   * A trigger on that table mirrors `enabled` into public.profiles.goat_mode,
--     which is what the Flutter app already uses to show/hide the GOAT button.
--
-- REQUIREMENTS
--   * Migration supabase/migrations/20260423120000_goat_mode_v1.sql must be
--     applied (creates goat_mode_access + the profile sync trigger).
--   * Each UUID must exist in public.profiles (i.e. the user has signed up).
-- ============================================================================

do $$
declare
  -- ──────────────────── EDIT THIS BLOCK ─────────────────────
  uids uuid[] := array[
    -- '3d8238ac-97bd-49e5-9ee7-1966447bae7c',
    -- '00000000-0000-0000-0000-000000000000',
  ]::uuid[];
  grant_notes text := 'beta access granted by admin';
  grant_source text := 'admin_sql'; -- one of: admin_sql|admin_ui|beta_invite|self_signup|migration|other
  -- ──────────────────────────────────────────────────────────
  uid uuid;
  missing uuid[] := array[]::uuid[];
  granted int := 0;
begin
  if array_length(uids, 1) is null then
    raise exception 'No UUIDs supplied. Edit the uids array at the top of this script.';
  end if;

  foreach uid in array uids loop
    if not exists (select 1 from public.profiles where id = uid) then
      missing := missing || uid;
      continue;
    end if;

    insert into public.goat_mode_access (user_id, enabled, enabled_at, source, notes)
    values (uid, true, now(), grant_source, grant_notes)
    on conflict (user_id) do update
      set enabled    = true,
          enabled_at = now(),
          source     = excluded.source,
          notes      = excluded.notes,
          updated_at = now();

    granted := granted + 1;
  end loop;

  raise notice 'granted goat_mode access to % user(s)', granted;

  if array_length(missing, 1) is not null then
    raise warning 'skipped % unknown UUID(s) (no matching public.profiles row): %',
      array_length(missing, 1), missing;
  end if;
end
$$;

-- Verify
select p.id, p.display_name, p.goat_mode,
       a.enabled as access_enabled, a.enabled_at, a.source, a.notes
  from public.profiles p
  left join public.goat_mode_access a on a.user_id = p.id
 where p.goat_mode = true
 order by a.enabled_at desc nulls last;
