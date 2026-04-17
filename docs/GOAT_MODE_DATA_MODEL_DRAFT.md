# Goat Mode — Data Model Draft (Phase 0)

> Companion to `GOAT_MODE_ANALYTICS_ARCHITECTURE.md`.
> **No migrations are created in this phase.** This document defines the
> proposed tables, columns, indexes, RLS intent, producers, consumers, and
> rationale, so an actual migration can be generated and reviewed in Phase 1.
>
> V1 rule: dedicated data only. Every table below is user-scoped and lives
> behind RLS `auth.uid() = user_id`.

---

## 1. Why these tables

Goat Mode needs to persist four classes of state:

1. **Operational job state** (something was requested / is running / finished).
2. **Computed analytical snapshots** (what the run produced).
3. **Audit + observability** (events during a run).
4. **User-provided inputs** that operational tables don't reliably capture
   (income, targets, goals, obligations, preferences).

The existing schema already captures *operational finance data* (transactions,
budgets, recurring, lend/borrow, statements, accounts, etc.), so Goat Mode
should **compose over it**, not duplicate it. The existing
`analytics_insight_snapshots` is keyed on `(user_id, range_preset)` and only
covers a single rolling analytics payload; Goat Mode snapshots are
multi-scope, carry forecasts/anomalies/risks, and need a different lifecycle.

**Decisions against the initial candidate set from the task brief:**

| Candidate | Decision | Why |
| --- | --- | --- |
| `goat_mode_jobs` | **Keep** | Need job lifecycle separate from the snapshot so retries and errors are first-class. |
| `goat_mode_analytics` | **Keep, renamed `goat_mode_snapshots`** | Snapshot fits our vocabulary (`analytics_insight_snapshots` precedent) and scopes are part of the payload, not the row name. |
| `goat_mode_job_events` | **Keep** | Audit trail + debugging (model versions, fold metrics, validation failures, AI rejections). |
| `goat_mode_data_coverage` | **Merge into snapshot** | Coverage is a deterministic sub-field of every snapshot; a separate table adds write-amplification with no query benefit. |
| `goat_mode_user_inputs` | **Keep, renamed `goat_user_inputs`** | Clean, short name; single source of truth for declared income/targets/household/planning horizon. |
| `goat_mode_recommendations` | **Keep as `goat_mode_recommendations`** | Must survive across snapshots (dismiss/snooze cool-down) and be pageable independently of snapshots. |
| Goals | **New `goat_goals`** (separate from `goat_user_inputs`) | Goals are 1-to-many with lifecycle (active/paused/complete) and will plausibly have `goal_contributions` later. Keeping inputs and goals separate prevents a wide JSON scratchpad. |
| Obligations | **New `goat_obligations`** | Same reasoning as goals: 1-to-many, with status. |

Not adding in v1:

- `goat_mode_forecasts` — forecasts are part of the snapshot JSON. Splitting
  them earns us nothing because we never query them independently in v1. If
  we start scoring backtests, a `goat_mode_backtests` table comes later.
- `goat_mode_models` / `goat_mode_model_versions` — model metadata lives in
  code constants + `goat_mode_job_events.payload`. Revisit at L3 if we have
  per-user trained models.

---

## 2. Existing tables Goat Mode reads

Read-only (operational). No schema changes required from Goat Mode:

- `transactions`, `accounts`, `budgets`, `budget_periods`,
  `recurring_series`, `recurring_occurrences`, `recurring_suggestions`,
  `lend_borrow_entries`, `group_expenses`, `group_expense_participants`,
  `group_settlements`, `statement_imports`, `statement_import_rows`,
  `documents`, `invoices`, `merchant_canonical`, `categories`,
  `activity_events`, `ai_suggestions`.
- `profiles` (reads `goat_mode`, `preferred_currency`, `trust_score`).
- `user_usage_limits` (for refresh quotas, reusing the existing counter).

Goat Mode should **write** only to its own tables. The sole permitted writes
to existing tables are:

- `ai_suggestions` — new rows of `suggestion_type in
  ('anomaly_alert','budget_warning','recurring_detect','duplicate_warning')`.
  This is an existing contract and keeps the user's unified inbox consistent.
- `activity_events` — one `event_type` entry per completed job for audit.
  Allowed list already covers it (`analytics_*`/admin types may need adding later).

---

## 3. New tables (v1)

Naming: lowercase, `goat_` prefix, snake_case. Every table has `id uuid pk
default gen_random_uuid()`, `user_id uuid not null references profiles(id) on
delete cascade`, `created_at timestamptz default now()`, and `updated_at
timestamptz default now()` where mutable.

### 3.1 `goat_mode_jobs`

**Purpose.** One row per Goat Mode compute request. Drives "pending / running /
done / failed" UI and exists even when the snapshot itself couldn't be
written. Also the handle the Flutter app polls.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `user_id` | uuid FK → profiles | RLS subject |
| `scope` | text | `overview|cashflow|budgets|recurring|debt|goals|full` |
| `trigger` | text | `manual|scheduled|post_event` (v1: `manual` only) |
| `status` | text | `queued|running|succeeded|partial|failed|cancelled` |
| `readiness_level` | text | `L1|L2|L3` computed at job start |
| `requested_at` | timestamptz | default now() |
| `started_at` | timestamptz nullable | |
| `finished_at` | timestamptz nullable | |
| `duration_ms` | integer nullable | convenience |
| `snapshot_id` | uuid nullable FK → `goat_mode_snapshots(id)` | set on success |
| `error_code` | text nullable | machine-readable |
| `error_message` | text nullable | user-facing short message |
| `input_fingerprint` | text | hash of (tx max(updated_at), budgets max(updated_at), recurring max(updated_at), ...) — the same pattern already used by `analytics_insight_snapshots` |
| `app_version` | text nullable | |
| `backend_version` | text nullable | |
| `model_versions` | jsonb nullable | e.g. `{ets: "statsmodels-0.14", overrun_risk: "v0.1-logit"}` |
| `notes` | text nullable | |
| `created_at`, `updated_at` | timestamptz | |

**Producer.** Backend (Cloud Run FastAPI) and local dev runner.
**Consumer.** Flutter (polls while `status in queued|running`).
**Indexes.** `(user_id, created_at desc)`, `(user_id, status)`, `(user_id, scope, created_at desc)`.
**RLS.** Select/insert/update restricted to `auth.uid() = user_id` when called via PostgREST; backend uses service role for writes from the compute worker.
**Realtime.** Not required v1 (Flutter can poll every 1–2 s while the bottom sheet is open). Revisit at L3.

### 3.2 `goat_mode_snapshots`

**Purpose.** The computed payload. Separate from the job so we can retain
historical snapshots for the last-N UI ("how did things change last week?")
and reuse a previous good snapshot while a new one is running.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `user_id` | uuid FK | |
| `scope` | text | same enum as `goat_mode_jobs.scope` |
| `readiness_level` | text | |
| `data_fingerprint` | text | identical scheme to `analytics_insight_snapshots.data_fingerprint` |
| `period_start` | date | analysis window |
| `period_end` | date | |
| `deterministic` | jsonb | full deterministic block (§3.1 in architecture doc) |
| `forecasts` | jsonb nullable | (p10/p50/p90 series, MAPE, model name) |
| `anomalies` | jsonb nullable | ranked list with explanations |
| `risks` | jsonb nullable | calibrated probabilities + reason codes |
| `missing_inputs` | jsonb nullable | ordered list of prompts |
| `coverage_score` | numeric(5,2) | 0–100 |
| `well_being_score` | numeric(5,2) nullable | 0–100 |
| `ai_layer` | jsonb nullable | structured narrative (§4 in architecture doc) |
| `ai_validated` | boolean default false | false if AI fell back to deterministic templates |
| `generated_at` | timestamptz | |
| `created_at`, `updated_at` | timestamptz | |

**Indexes.**
- `(user_id, scope, generated_at desc)` — primary read path ("latest full snapshot").
- **Unique** `(user_id, scope, data_fingerprint)` — idempotency: identical inputs produce one row. Upsert pattern mirrors `analytics_insight_snapshots`.
- Optional partial `(user_id) where scope = 'full'` for the default screen.
**Producer.** Backend writes.
**Consumer.** Flutter reads the latest `scope='full'` snapshot + optional per-scope rows when user drills in. Scope detail screens can also read `scope='full'` and extract their sub-block.
**RLS.** `auth.uid() = user_id`.
**Realtime.** Not required; Flutter pulls after the job reports `succeeded`.

### 3.3 `goat_mode_job_events`

**Purpose.** Observability / audit. Captures per-stage events during a run
and debug payloads too large to fit in `notes`.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `job_id` | uuid FK → `goat_mode_jobs(id) on delete cascade` | |
| `user_id` | uuid | denormalised for RLS |
| `stage` | text | `input_load|deterministic|forecast|anomaly|risk|recommendation|ai|persist` |
| `event_type` | text | `started|finished|warning|error|validation_failed|ai_rejected|fallback_used` |
| `severity` | text | `info|warn|error` |
| `message` | text | |
| `payload` | jsonb nullable | bounded (recommended max 64 kB in-app; larger dumps go to Sentry) |
| `created_at` | timestamptz | |

**Indexes.** `(job_id, created_at)`, `(user_id, severity, created_at desc) where severity in ('warn','error')`.
**Producer.** Backend.
**Consumer.** Internal dashboard / dev tool; the Flutter app only surfaces an opaque count when `severity='error'`.
**RLS.** `auth.uid() = user_id`. Service role bypasses for ops queries.

### 3.4 `goat_user_inputs`

**Purpose.** Single source of truth for user-declared numbers Goat Mode needs
that are not reliably present in operational tables. One row per user.

| Column | Type | Notes |
| --- | --- | --- |
| `user_id` | uuid PK FK → profiles | one row per user |
| `monthly_income` | numeric(12,2) nullable | declared net income |
| `income_cadence` | text nullable | `weekly|biweekly|monthly|other` |
| `salary_day_of_month` | smallint nullable | `1..31` or null |
| `income_source_account_id` | uuid nullable FK → accounts | primary payroll account |
| `emergency_fund_target_months` | numeric(4,2) nullable default 3 | |
| `emergency_fund_account_id` | uuid nullable FK → accounts | if separate from savings |
| `household_size` | smallint nullable | |
| `dependents_count` | smallint nullable | |
| `planning_horizon_days` | smallint not null default 30 | clamped `7..180` |
| `risk_tolerance` | text nullable check in `('conservative','balanced','aggressive')` | |
| `notification_level` | text not null default 'normal' check in `('minimal','normal','detailed')` | |
| `tone_preference` | text not null default 'calm' check in `('calm','direct','coaching')` | |
| `liquidity_floor` | numeric(12,2) nullable | threshold for liquidity warnings |
| `currency_override` | text nullable | defaults to `profiles.preferred_currency` |
| `inputs_last_completed_at` | timestamptz nullable | |
| `created_at`, `updated_at` | timestamptz | |

**Producer.** Flutter setup flow; Goat Mode reads.
**RLS.** `auth.uid() = user_id`.
**Indexes.** PK only; single-row per user.

### 3.5 `goat_goals`

**Purpose.** User-declared goals (save for X by date Y).

| Column | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `user_id` | uuid FK | |
| `name` | text not null | |
| `target_amount` | numeric(12,2) not null check > 0 | |
| `target_date` | date nullable | |
| `current_amount` | numeric(12,2) not null default 0 | |
| `monthly_commitment` | numeric(12,2) nullable | user's promised contribution |
| `linked_account_id` | uuid nullable FK → accounts | |
| `priority` | smallint not null default 3 check between 1..5 | |
| `status` | text not null default 'active' check in `('active','paused','completed','abandoned')` | |
| `notes` | text nullable | |
| `created_at`, `updated_at` | timestamptz | |

**Producer.** Flutter setup. **Consumer.** Goat Mode `goals` scope.
**Indexes.** `(user_id, status, priority)`. **RLS.** `auth.uid() = user_id`.

Future: `goat_goal_contributions` when we start explicit contribution logging
(post-v1).

### 3.6 `goat_obligations`

**Purpose.** User-declared recurring financial obligations not fully captured
by `recurring_series` (e.g. credit card minimum payments, EMIs, rent if not
tracked as a recurring transaction).

| Column | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `user_id` | uuid FK | |
| `name` | text not null | |
| `type` | text not null check in `('emi','credit_card_min','rent','insurance','loan','other')` | |
| `monthly_amount` | numeric(12,2) not null | |
| `due_day_of_month` | smallint nullable | |
| `cadence` | text not null default 'monthly' check in `('weekly','biweekly','monthly','quarterly','yearly')` | |
| `linked_recurring_series_id` | uuid nullable FK → recurring_series | if it's also a modelled series |
| `is_active` | boolean not null default true | |
| `notes` | text nullable | |
| `created_at`, `updated_at` | timestamptz | |

**Producer.** Flutter setup. **Consumer.** `debt` scope (debt-to-income,
missed-payment risk).
**Indexes.** `(user_id, is_active)`. **RLS.** `auth.uid() = user_id`.

### 3.7 `goat_mode_recommendations`

**Purpose.** Persist recommendations with their own lifecycle (dismiss /
snooze / resolve) independent of snapshots. Survives re-computes as long as
the underlying fingerprint hasn't changed.

| Column | Type | Notes |
| --- | --- | --- |
| `id` | uuid PK | |
| `user_id` | uuid FK | |
| `snapshot_id` | uuid FK → `goat_mode_snapshots(id) on delete set null` | may outlive the snapshot |
| `kind` | text not null | enum: `budget_overrun`, `anomaly_review`, `liquidity_warning`, `goal_shortfall`, `missed_payment_risk`, `recurring_drift`, `duplicate_cluster`, `missing_input`, `uncategorized_cleanup`, `recovery_iou` (extensible via CHECK) |
| `severity` | text not null check in `('info','watch','warn','critical')` | |
| `priority` | numeric(5,3) not null | sort key |
| `confidence` | numeric(4,3) not null check between 0..1 | |
| `title` | text not null | |
| `body` | text not null | short user-facing sentence |
| `why_shown` | text nullable | drawn from `pillars[].observation+inference` |
| `rec_fingerprint` | text not null | dedupe key |
| `entity_type` | text nullable | e.g. `budget`, `goal`, `obligation`, `transaction` |
| `entity_id` | uuid nullable | |
| `inputs_snapshot` | jsonb not null | the fields driving the rec (verbatim) |
| `cta` | jsonb nullable | `{type, label, target}` |
| `status` | text not null default 'open' check in `('open','dismissed','snoozed','resolved','expired')` | |
| `snoozed_until` | timestamptz nullable | |
| `expires_at` | timestamptz nullable | default +7 d |
| `generated_at` | timestamptz not null default now() | |
| `updated_at` | timestamptz not null default now() | |

**Indexes.**
- `(user_id, status, priority desc) where status in ('open','snoozed')` — default screen read path.
- **Unique** `(user_id, rec_fingerprint) where status = 'open'` — dedupe live recs.
- `(user_id, kind, generated_at desc)`.

**Producer.** Backend (deterministic rec engine + AI phrasing).
**Consumer.** Flutter default screen + recommendation detail.
**RLS.** `auth.uid() = user_id`.

---

## 4. Index strategy (summary)

Follows Supabase Postgres best practices (selective, partial indexes for
"open"/"active" filters; avoid indexing every FK by default):

- Primary keys everywhere.
- Every `user_id` on a user-scoped table gets a covering composite index that
  matches the dominant read path (e.g. `(user_id, scope, generated_at desc)`).
- Partial indexes for the "hot" subsets (`where status = 'open'`, `where
  is_active = true`).
- Unique constraints wherever idempotency is needed
  (`snapshots.data_fingerprint`, `recommendations.rec_fingerprint`).
- No btree on large JSONB columns in v1; add GIN later only if we query into
  them.

---

## 5. RLS posture

Every new table:

```sql
alter table <t> enable row level security;
create policy "<t>_select" on <t> for select using  (auth.uid() = user_id);
create policy "<t>_insert" on <t> for insert with check (auth.uid() = user_id);
create policy "<t>_update" on <t> for update using  (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "<t>_delete" on <t> for delete using  (auth.uid() = user_id);
```

Backend writes (Cloud Run service) use the Supabase **service role key**
injected via env and therefore bypass RLS. The Flutter app only ever sees the
anon+JWT session and is thus fully constrained by the policies. The Edge
Function trigger stays user-context (forwards `Authorization`), matching the
pattern in `supabase/functions/analytics-insights/index.ts`.

---

## 6. Realtime vs polling

- v1: poll. Flutter polls `goat_mode_jobs` every 1–2 s while a modal/sheet is
  shown, then fetches the latest snapshot on `status='succeeded'`. This is
  consistent with `AnalyticsInsightsNotifier`'s pattern today.
- v2 consideration: enable Supabase Realtime on `goat_mode_jobs` so the app
  updates the progress pill without polling. Out of scope for v1.

---

## 7. Migration shape (to be generated in Phase 1)

A single new migration `supabase/migrations/<timestamp>_goat_mode_v1.sql` is
sufficient. The migration must:

1. Create the 7 tables above (in dependency order: `goat_user_inputs`,
   `goat_goals`, `goat_obligations`, `goat_mode_snapshots`, `goat_mode_jobs`,
   `goat_mode_job_events`, `goat_mode_recommendations`).
2. Add all indexes / uniques / checks.
3. Enable RLS and create the 4 policies per table.
4. Create the two triggers reusing `set_invoice_updated_at()` (already present
   in the repo) for mutable tables' `updated_at`.
5. **Not** modify existing tables. Any add-on to `ai_suggestions` or
   `activity_events` (for extra event_type values) goes into a separate
   migration reviewed alongside the Flutter rollout.

Seed data for local testing is placed in `supabase/seed.sql` and three scripts
under `scripts/goat/` (sparse / medium / rich) — see
`GOAT_MODE_LOCAL_FIRST_PLAN.md`.
