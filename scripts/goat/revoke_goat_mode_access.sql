-- Revoke GOAT Mode access for one or more users by UUID.
-- Idempotent. Mirrors profiles.goat_mode=false via the sync trigger.
do $$
declare
  uids uuid[] := array[
    -- '3d8238ac-97bd-49e5-9ee7-1966447bae7c',
  ]::uuid[];
  uid uuid;
begin
  if array_length(uids, 1) is null then
    raise exception 'No UUIDs supplied. Edit the uids array at the top.';
  end if;
  foreach uid in array uids loop
    update public.goat_mode_access
       set enabled = false, updated_at = now(), notes = coalesce(notes, '') || ' | revoked ' || now()::text
     where user_id = uid;
  end loop;
end
$$;
