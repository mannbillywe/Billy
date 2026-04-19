-- GOAT Mode "v2" Flutter/dashboard release marker.
-- No DDL: the Downloads backend still writes into 20260423120000_goat_mode_v1
-- tables/columns; richer fields (unlockable_scopes, by_severity, metric
-- inputs_used / inputs_missing) live inside existing jsonb payloads.
select 1;
