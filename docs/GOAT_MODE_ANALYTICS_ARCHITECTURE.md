# Goat Mode — Analytics Architecture (Phase 0)

> **Status:** Architecture + analytics contract only. No backend endpoints, Edge
> Functions, Cloud Run deployment, Flutter UI, or final migrations are produced
> in this phase. See `GOAT_MODE_LOCAL_FIRST_PLAN.md` for build order and
> `GOAT_MODE_DATA_MODEL_DRAFT.md` for the proposed schema.
>
> **V1 scope rule (dedicated data only):** Goat Mode v1 uses **only**
> Billy-owned / user-owned data. No market / weather / news / macro APIs. External
> context may appear only as **future-extension notes**.
>
> **Principle:** Always return
>
> 1.  the best analytics possible from currently available data,
> 2.  the next inputs/uploads/setup values that would improve it,
> 3.  recommendations grounded in the completed analysis — and only where safe.

---

## 1. Repo Audit

### 1.1 Stack and runtime (confirmed from repo)

| Area | Finding |
| --- | --- |
| App | Flutter + Riverpod + Supabase, imperative `Navigator`/`MaterialPageRoute`; no `go_router` wiring. |
| Entry | `lib/main.dart` → `BillyApp` → `LayoutShell` (5 tabs: Home, Activity, People, Plan, Insights). |
| Theme | `lib/core/theme/billy_theme.dart` (`BillyTheme.scaffoldBg`, `emerald*`, `gray*`, `blue*`). |
| Services | `lib/services/supabase_service.dart` is the **one** Supabase façade (CRUD, RPCs, dashboard rollups, usage limits, signed URLs). Also `transaction_service.dart`, `allocation_service.dart`, `activity_logger.dart`. |
| Providers | `lib/providers/*` and `lib/features/*/providers/*` — all Riverpod (e.g. `analytics_insights_provider.dart`, `transactions_provider.dart`, `recurring_provider.dart`, `budgets_provider.dart`, `recurring_suggestions_provider.dart`, `suggestions_provider.dart`, `lend_borrow_provider.dart`, `profile_provider.dart`). |
| Existing AI-analytics | Edge Function `supabase/functions/analytics-insights/index.ts` already computes a rich deterministic payload (overview, categories, vendors, debt, groups, documents, invoice_pipeline, behavior_features, engagement, quality) and optionally calls Gemini (Money Coach + JAI Insight). Persisted to `analytics_insight_snapshots(user_id,range_preset)` with `data_fingerprint`, `deterministic`, `ai_layer`. |
| Backend | `backend/` has a minimal FastAPI skeleton (`app/main.py` health + requirements include `pandas`, `numpy`, `scikit-learn`, `statsmodels`, `prophet`, `google-genai`, `supabase`). Dockerfile targets Cloud Run. This is the right home for Goat Mode compute. |
| Edge Functions | `supabase/functions/` contains `process-invoice`, `statement-classify`, `analytics-insights`, shared `cors.ts` and `resolve_gemini_key.ts`. |
| Migrations | `supabase/migrations/` includes the canonical `20260420130000_consolidated_ledger_architecture.sql` (transactions, activity_events, disputes, budgets, budget_periods, recurring_series, recurring_occurrences, statement_imports, accounts), `20260421120000_money_os_enhancements.sql` (statement_import_rows, merchant_canonical, ai_suggestions, recurring_suggestions, analytics fingerprint), `20260405150000_user_usage_limits.sql`, `20260404100000_analytics_insight_snapshots.sql`, `20260422120000_profiles_goat_mode_flag.sql` (`profiles.goat_mode boolean`). Note: a prior full GOAT schema was **dropped** in the consolidated migration — v1 must not re-introduce the old "goat_*" tables. |
| Local scripts | `scripts/seed_manng_data.sql`, `scripts/clear_user_data.sql`, `scripts/fix_created_at_to_bill_date.sql`, PowerShell deploy scripts for Edge Functions and Vercel. Useful foundation for Goat seed fixtures. |
| Snapshot logic (already present) | `fetchAnalyticsInsightSnapshot(rangePreset)` via `SupabaseService`; `AnalyticsInsightsNotifier.refreshInsights(...)` pattern. Goat Mode should reuse this idiom (cached snapshot first, manual refresh triggers compute). |
| Goat placeholder | `lib/features/goat/goat_mode_placeholder_screen.dart` (hero + "35% complete" + feature grid). Entry exists behind `profiles.goat_mode = true`. |
| Existing setup/onboarding surfaces that can be reused | `lib/features/profile/`, `lib/features/settings/`. No dedicated onboarding flow — Goat Mode can ship its own minimal "Setup & Missing Inputs" flow that writes to a new `goat_user_inputs` table. |
| Design system anchors | `BillyTheme` + conventions already used in `goat_mode_placeholder_screen.dart`: hero gradient `#059669 → #10B981 → #34D399`, status pill `#FEF3C7`/`#F59E0B`, 20–28 px rounded cards, `w700`/`w800` headings. Goat Mode UI should inherit these tokens unchanged. |

### 1.2 Operational data already available for Goat Mode v1

All user-scoped (RLS on `auth.uid() = user_id`):

- `transactions` (canonical ledger; `type in expense|income|transfer|lend|borrow|settlement_*|refund|recurring`, `status`, `account_id`, `category_id`, `source_type`, `source_document_id`, `is_recurring`, `recurring_series_id`).
- `accounts` (`type in checking|savings|credit_card|cash|investment|loan|other`, `current_balance`, `is_asset`, `is_active`).
- `budgets` + `budget_periods` (`period in weekly|monthly|yearly`, `spent`, `rollover_amount`).
- `recurring_series` + `recurring_occurrences` (cadence, `next_due`, `status`).
- `recurring_suggestions` (pending detected patterns).
- `lend_borrow_entries` (with `status`, `due_date`, `counterparty_*`).
- `statement_imports` + `statement_import_rows` (parsed rows, duplicates, matches).
- `documents`, `invoices`, `invoice_items` (OCR pipeline signal).
- `group_expenses`, `group_expense_participants`, `group_settlements`, `expense_group_members`.
- `categories`, `merchant_canonical`.
- `ai_suggestions` (unified inbox for suggestion_type, incl. `anomaly_alert`, `budget_warning`, `recurring_detect`, `duplicate_warning`).
- `activity_events` (audit stream).
- `analytics_insight_snapshots` (deterministic/ai_layer cache).
- `user_usage_limits` (monthly refresh counters).
- `profiles.goat_mode` (feature flag), `profiles.preferred_currency`, `profiles.trust_score`.

### 1.3 What is **missing** from operational data (and therefore must come from user setup)

- Stable **income** cadence / salary day (incomes exist as `transactions(type='income')` but there is no declared schedule or expected net amount).
- **Emergency-fund target** (amount or months of expenses).
- **Debt obligations** not captured as recurring expenses (credit-card min payments, EMIs outside of recurring_series, balloon payments).
- **Household / dependents** context (meaningful for burden ratios).
- **Financial goals** (name, target amount, target date, priority, funding source account).
- **Manual assets/liabilities** for net-worth that are outside `accounts`.
- **Planning horizon** (user's preferred forecast window / comfort level).
- **Risk tolerance** and **notification preferences** (affect surfacing of forecasts/anomalies).

These are captured in a new `goat_user_inputs` table and in goal-first "Setup & Missing Inputs" prompts surfaced by Goat Mode itself (see UX).

---

## 2. Analytics Contract

### 2.1 Readiness levels (drives everything else)

| Level | What the user has | What Goat Mode can compute | What it must *not* compute reliably |
| --- | --- | --- | --- |
| **L1 — Operational only** | Transactions (scanned + manual), budgets, recurring detected, some lend/borrow, maybe one account. No declared income or targets. | Descriptive: spend summary, category split, top merchants, recurring burden proxy, debt-flow counts, data-coverage score, prior-period deltas, weekday/weekend, volatility, basic anomalies. | Savings rate (needs income), emergency-fund runway (needs fund balance + target), goal trajectory, budget overrun *risk* (needs budget), missed-payment risk for undeclared obligations. Forecast horizons capped at 30 d, ±wide intervals. |
| **L2 — +User setup (goat_user_inputs)** | L1 + declared monthly income, salary day, emergency-fund target, known recurring debts, household, goals, planning horizon. | Everything in L1 + savings rate, income-vs-expense, end-of-month liquidity forecast, emergency-fund runway, goal completion trajectory, debt-to-income ratio, recurring bill burden against income, budget-overrun probability, missed-payment risk. Recommendation coverage expands. | Net-worth trend (unless balances tracked), scenario planning beyond planning horizon. |
| **L3 — +Uploads/history** | L2 + statement imports over ≥3 months, richer account balance history, categorized lend/borrow history, goal contributions logged. | Everything in L2 + multi-step cashflow forecasting with confidence intervals, category-level overrun trajectories, recurring cadence detection with confidence, anomaly detection at the full transaction grain, calibrated risk scores (budget overrun, missed payment, liquidity stress), SHAP-style explanations. | Claims about external macro (inflation, markets, wages) are still forbidden in v1. |

Level is computed *per scope* (overview can be L2 while debt is L1). The system always returns the *best possible* result at the level it actually has and surfaces "to improve this, add X" nudges.

### 2.2 Scopes

The 7 scopes below compose into `scope = full`. Each scope produces a
deterministic block **and** a list of "missing-input prompts". The full scope
also produces the top-level Financial Well-Being Score and a narrative stitched
from the individual AI layers (see §4).

---

#### 2.2.1 Scope: `overview`

- **Purpose.** One-screen snapshot of the user's current financial state.
- **Questions it answers.** "Am I doing OK?", "Am I spending more than last month?", "Is my data complete enough to trust this?"
- **Source tables.** `transactions`, `accounts`, `budgets`+`budget_periods`, `recurring_series`+`recurring_occurrences`, `lend_borrow_entries`, `analytics_insight_snapshots` (fallback cache), `goat_user_inputs` (if L2).
- **Minimum required data.** ≥14 days of any non-draft `transactions`.
- **Richer in-app data.** ≥60 days of transactions, ≥1 budget, ≥1 recurring series, ≥1 asset account with balance, declared income (L2).
- **Deterministic outputs.** Total net-worth (if accounts); current-period spend, income, savings rate; prior-period delta; fixed-vs-variable split; recurring bill burden; liquidity (sum of asset accounts if present, else null); Financial Well-Being Score (see §3.1.9); data-coverage score; freshness timestamp; list of degraded features.
- **Confidence / completeness.** Each metric has `value`, `confidence in [low|medium|high]`, and `reason_codes`. Confidence is derived deterministically from data-coverage (see §3.1.9).
- **Degraded-mode behavior.** If income is missing, return `savings_rate = null` with a prompt "Add your monthly income in Setup to compute savings rate." The UI still shows total spend, delta, and top categories.
- **Missing-input prompts to surface next.** Income (amount, cadence, salary day); emergency-fund target; first goal; ≥1 asset account balance.
- **Safe recommendations.** "Your discretionary spend rose 18% vs last period; top driver: food delivery (+₹2,400)." — *only when* the underlying deltas are significant under the volatility model (see §3.1.13). No goal-setting advice at L1.

---

#### 2.2.2 Scope: `cashflow`

- **Purpose.** Understand cash movement, predict short-term cashflow, flag liquidity stress.
- **Questions.** "Will I run short before next payday?", "What's my net cashflow this month?", "Which weeks were unusually heavy?"
- **Source tables.** `transactions` (all types), `accounts` (balances for starting state), `recurring_series`/`recurring_occurrences` (known future outflows), `goat_user_inputs` (income schedule).
- **Minimum.** ≥30 days of transactions.
- **Richer.** ≥90 days, declared income, ≥1 asset account with balance, future recurring due dates.
- **Deterministic.** Daily net cashflow series, 7/30-day rolling means, current-month-to-date, weekday/weekend split, payday-cycle detection (if income present), volatility (std/IQR of daily net), spike days (MAD z > 3.5).
- **Statistical / ML.** Forecast next-30-day and (if L3) next-90-day net cashflow (see §3.2).
- **Confidence.** Confidence intervals returned (p10/p50/p90). Historical MAPE over walk-forward folds attached.
- **Degraded.** < 30 days of data → return only descriptive rolling stats; no forecast. Missing income → forecast uses only detected regular inflows and returns "income not declared" flag which widens CI by `+25 %`.
- **Missing-input prompts.** Income cadence; account starting balances; cadence-confirmation for detected recurring items that influence the forecast.
- **Safe recommendations.** "At current pace you land at ₹X on the 27th (p10: ₹Y). Delay the ₹Z subscription to avoid overdraft." — only when the p10 line crosses a configured liquidity floor.

---

#### 2.2.3 Scope: `budgets`

- **Purpose.** Measure budget adherence and warn about overrun before end of period.
- **Questions.** "Which budgets am I busting?", "At current pace will I overrun this month?", "Which category is drifting?"
- **Source tables.** `budgets`, `budget_periods`, `transactions` (expense), `categories`.
- **Minimum.** ≥1 active budget with ≥1 elapsed day in the current period.
- **Richer.** ≥2 completed prior periods per budget (enables overrun-risk model).
- **Deterministic.** Per budget: % elapsed of period, % spent, pace index (`spent / expected_spent_at_now`), projected-end spend (linear + trailing-median), rollover impact, days-to-exhaustion.
- **Statistical / ML.** Budget-overrun risk probability at period end (see §3.4.1). At L1, fall back to the deterministic "projected-end-spend" rule.
- **Confidence.** Returned per budget. Calibration curve (reliability diagram) maintained offline during model dev.
- **Degraded.** No budgets → scope returns `status: empty` with prompt "Create a budget to see adherence." No priors → projection only, no probability.
- **Missing-input prompts.** Create budget; ensure category_id on transactions (uses `uncategorized_count`).
- **Safe recommendations.** "At current pace 'Food' will finish at 132 % (risk 0.74). Cut the next 7 days by ₹650 to stay within."

---

#### 2.2.4 Scope: `recurring`

- **Purpose.** Surface the user's recurring-bill load, cadence drift, and detection.
- **Questions.** "What's my monthly fixed load?", "Did something unexpectedly change?", "What's coming up?"
- **Source tables.** `recurring_series`, `recurring_occurrences`, `transactions (is_recurring|recurring_series_id)`, `recurring_suggestions`, `merchant_canonical`.
- **Minimum.** ≥1 active series OR ≥3 months of transactions (so suggestions can be generated).
- **Richer.** ≥3 months + accepted canonical merchants.
- **Deterministic.** Monthly fixed load (sum of `amount` over active series resampled to monthly cadence), upcoming 30-day occurrence list, cadence drift (std of inter-occurrence days ÷ mean), amount drift (MAD of actual vs series amount).
- **Statistical / ML.** Recurring cadence detection from transactions (see §3.3 — suggestions produced here feed existing `recurring_suggestions` inbox). Change-point on amount per series.
- **Confidence.** Per-series confidence from cadence consistency and amount stability; overall "coverage of your monthly load that is recurring-modeled" percentage.
- **Degraded.** No series → produce suggestion list; no detected patterns at < 3 months → return `status: sparse`.
- **Missing-input prompts.** Confirm/reject detected suggestions; add known bills that never appear as transactions (e.g. quarterly insurance).
- **Safe recommendations.** "Netflix went from ₹499 to ₹649 on 2026-03-14 — raise the series amount?", "3 series have a due date in the next 7 days totalling ₹4,200."

---

#### 2.2.5 Scope: `debt`

- **Purpose.** Measure debt pressure (IOUs + any declared loans) and settlement hygiene.
- **Questions.** "Who owes whom?", "What's overdue?", "Am I over-extended by lending?", "How much of my income goes to debt?"
- **Source tables.** `lend_borrow_entries`, `group_settlements`, `transactions (type in lend|borrow|settlement_*)`, `goat_user_inputs` (declared recurring obligations).
- **Minimum.** Any of: ≥1 lend_borrow_entry, ≥1 settlement, or ≥1 declared obligation.
- **Richer.** Declared income + declared obligations + ≥60 days of settlement history.
- **Deterministic.** Pending/settled amounts (lent, borrowed), overdue counts, top counterparties, pending-to-settled ratio, recovery-efficiency score, debt-stress score (already computed by `analytics-insights`; Goat reuses the same formula).
- **Statistical / ML.** Missed-payment risk per declared obligation in the next 30 days (see §3.4.2). Overdue-likelihood for pending IOUs (feature: days since created, counterparty settle history).
- **Confidence.** Per-score and per-obligation.
- **Degraded.** No declared income → skip debt-to-income; no obligations → skip missed-payment risk.
- **Missing-input prompts.** Declare obligations; mark counterparties on IOUs; confirm group settlements.
- **Safe recommendations.** "3 IOUs with <contact> are overdue > 30 d (₹4,500). Send a reminder." "EMI risk 0.82 on 'Car loan' for due date Apr 23 — schedule ₹X by Apr 20."

---

#### 2.2.6 Scope: `goals`

- **Purpose.** Track progress toward user-declared goals.
- **Questions.** "Am I on track?", "When will I reach this goal at current pace?", "What do I need to set aside per month to hit it?"
- **Source tables.** `goat_user_inputs` (goals — defined in `GOAT_MODE_DATA_MODEL_DRAFT.md`), `transactions (type='income'|'expense'|'transfer')`, `accounts` (if a goal is linked to an account).
- **Minimum.** ≥1 goal defined.
- **Richer.** ≥1 goal with linked account + history of contributions.
- **Deterministic.** Progress %, current pace (₹/month from contribution history), pace-implied completion date, required monthly contribution to hit target date, shortfall amount if on-pace.
- **Statistical.** Completion-date uncertainty via bootstrap on contribution history (percentile band around pace).
- **Confidence.** Medium when ≥3 contributions; low otherwise.
- **Degraded.** No goals → scope is `empty` and prompts goal creation.
- **Missing-input prompts.** Target date; monthly contribution commitment; link to account.
- **Safe recommendations.** "At ₹3,000/mo you'll finish 7 months late; raise to ₹4,200/mo to hit target date."

---

#### 2.2.7 Scope: `full`

- **Purpose.** Compose all scopes into one snapshot + overall well-being score + prioritized narrative.
- **Output.** Union of all scope blocks, overall Financial Well-Being Score (§3.1.9), data-coverage score, an ordered list of "next best inputs to add", and (optionally) the stitched AI layer (§4). This is what the Flutter Goat Mode screen binds to by default.

---

## 3. Quant / Modeling Decisions

> **Rule.** Deterministic math first. Statistical/ML only where it beats a well-specified baseline on held-out data. AI writes narrative only (§4).

### 3.1 Deterministic analytics layer

All formulas below are computed server-side from the canonical `transactions`
table plus the user-scoped ancillaries. Unless noted, the period is
configurable (`preset in {7D, 30D, 90D, MTD, 1M, 3M, 6M, 12M}`).

Let:

- `E` = set of confirmed expense transactions in period.
- `I` = set of confirmed income transactions in period.
- `T` = `E ∪ I ∪ transfers`.
- `t.amt = coalesce(t.effective_amount, t.amount)`.
- `D` = number of elapsed days in period.

#### 3.1.1 Net worth

`net_worth = Σ acc.current_balance * (1 if acc.is_asset else −1)` over
`accounts.is_active=true`.

- Assumptions: balances are recent (flag `freshness_days = today − max(updated_at)`).
- Edge cases: no accounts → `null` with reason `no_accounts`. Only liability accounts → negative value surfaced with warning.
- Sparse/noisy: confidence = high if all balances updated ≤ 7 d, medium if ≤ 30 d, low otherwise.

#### 3.1.2 Income vs expense

`income = Σ I.amt`, `expense = Σ E.amt`, `net = income − expense`. Prior-period
deltas are computed on matched lengths (e.g. same day count).

- Edge: split transactions should count at `effective_amount` for the user; group-splits already backfill this via `transactions.effective_amount`.

#### 3.1.3 Savings rate

`savings_rate = (income − expense) / income` if `income > 0`.

- Gated at L2 (declared income optional but **recommended** because transactions
  may not capture every income source).
- If declared `monthly_income` is present and detected income < 80 % of it, add
  reason code `income_likely_undercaptured`; return both computed and
  declared-based rates so the UI can show a range.

#### 3.1.4 Budget utilization

Per budget for the current `budget_period`:

- `pct_elapsed = elapsed_days / period_days`.
- `pct_spent = spent / amount`.
- `pace_index = pct_spent / max(pct_elapsed, 1/period_days)`.
- `projected_end = spent + (amount_avg_daily_trailing_14 * days_remaining)`
  where `amount_avg_daily_trailing_14` uses trailing 14 d of in-period spend on
  that category with robust trimming (drop top/bottom 10 %).

#### 3.1.5 Fixed vs variable expense split

- **Fixed** = `transactions.is_recurring = true` ∪ confirmed occurrences of
  active `recurring_series`.
- **Variable** = everything else in `E`.
- `fixed_ratio = fixed / expense`.
- Edge: no recurring series → ratio is `null` with reason `recurring_unmodeled`.

#### 3.1.6 Recurring bill burden

`recurring_monthly_total = Σ series_amount_monthly_equivalent` over active
series, where `series_amount_monthly_equivalent` converts each cadence to a
monthly figure (`weekly × 4.345`, `biweekly × 2.1725`, `quarterly / 3`, etc.).

- If declared income present: `recurring_burden_ratio = recurring_monthly_total / monthly_income`.
- Edge: detected suggestions (pending) are *not* included but surfaced
  separately as `+X potential if confirmed`.

#### 3.1.7 Debt / lend-borrow burden

Reuses the formulas from `analytics-insights`:

- `debt_stress_score = min(100, 20 * borrowed_pending / max(expense, 1) + 12 * overdue_borrowed_count)`.
- `recovery_efficiency_score = settled / (pending + settled)`.
- Add (L2): `debt_to_income = declared_debt_monthly / monthly_income` and classify
  (`<0.2` healthy, `0.2–0.36` watch, `>0.36` stress; thresholds chosen to match
  common lending guidelines and are transparently configurable in
  `goat_user_inputs`).

#### 3.1.8 Emergency-fund runway

- `monthly_expense_baseline = median(last_6_months_expense)`. If <6 months, use mean of what exists with `baseline_confidence=low`.
- `runway_months = emergency_fund_balance / monthly_expense_baseline`.
- `runway_ratio = runway_months / target_months` (target from `goat_user_inputs`, default 3).
- Edge: no dedicated emergency account → use asset accounts sum minus explicit
  goal-linked balances, flagged `inferred_balance=true`.

#### 3.1.9 Data-coverage score + Financial Well-Being Score

**Data coverage score (0–100), transparent sum:**

| Component | Weight | Definition |
| --- | --- | --- |
| Tx density | 20 | `min(1, active_days/60) × 20` |
| Categorization | 15 | `1 − uncategorized_rate` × 15 |
| Account coverage | 15 | `min(1, asset_accounts/2) × 15` |
| Income declared | 10 | 10 if `monthly_income` present else 0 |
| Budgets defined | 10 | `min(1, budgets/3) × 10` |
| Recurring modeled | 10 | `recurring_coverage_ratio × 10` |
| Goals defined | 10 | `min(1, goals/1) × 10` |
| Statement imports | 5 | 5 if any import in last 90 d else 0 |
| Debt declared | 5 | 5 if any obligation declared else 0 |

**Financial Well-Being Score (0–100)** is a scorecard, not a model — grounded in
the CFPB Financial Well-Being Scale concept (security + freedom of choice) but
computed from Billy's data so it is explainable and reproducible. The scale is
transparently summed and returned with reason codes:

| Pillar | Metric | Scoring |
| --- | --- | --- |
| Liquidity (25) | Runway months | 0 months → 0, 3 → 20, 6 → 25 (linear interp). `null` → pillar withheld and FWB returned with `partial=true`. |
| Savings behaviour (20) | Savings rate (declared income or inferred) | `<0 → 0`, `0.1 → 10`, `0.2 → 15`, `0.3+ → 20`. |
| Debt health (20) | Debt-to-income or `debt_stress_score` | Linear from best→worst. |
| Budget adherence (15) | Average `pace_index` over last 3 periods | `1.0 → 12`, `0.9 → 15`, `>1.2 → 0`. |
| Recurring discipline (10) | `recurring_burden_ratio` quality + missed occurrences | Linear. |
| Data quality (10) | `data_coverage_score` normalised | `× 0.1`. |

The score is always returned with `reason_codes` (strongest positive, weakest
pillar) — never as a black-box number. Inspired by (not reproducing) the
CFPB scale's IRT-scored 0–100 output and the concept of pillar-wise
transparency.

#### 3.1.10 Trend deltas vs prior period

For each headline metric `m`: `delta = m_curr − m_prev`, `pct = delta / m_prev`.
Prior-period window is **matched-length** ending the day before the current
window starts. Significance is assessed against §3.1.13 (volatility); below
`|z| < 1` the delta is displayed as "~flat".

#### 3.1.11 Volatility / stability measures

- Daily-spend series `x_d`. Use **MAD** and IQR as primary (robust):
  - `MAD = median(|x_d − median(x_d)|)` with scale factor `1.4826`.
  - `cv_robust = MAD_scaled / median(x_d)`.
- Category volatility: same metric per category with `>= 10` observations to be valid; otherwise `null`.
- Why MAD: robust to outliers which dominate personal-finance transaction streams (see references in §7).

#### 3.1.12 Handling sparse / noisy / partial data

- Never return division by near-zero means; gate with min denominator 1 currency unit or 5 observations.
- Always return the numerator & denominator along with the ratio so the UI can recompute.
- Every metric ships `confidence`, `reason_codes[]`, `inputs_used[]`, `inputs_missing[]`.

#### 3.1.13 Significance thresholds

- `z_robust = (x − median) / (1.4826 × MAD)`.
- Daily spike flag if `z_robust ≥ 3.5` (common MAD outlier threshold).
- Trend "material" if `|delta_pct| ≥ 10%` AND `|z_robust(of delta)| ≥ 1`.

### 3.2 Forecasting layer

> **V1 rule.** Dedicated data only. The *only* exogenous features allowed are
> internal future-known signals: salary day (from `goat_user_inputs`), known
> recurring due dates from `recurring_occurrences`, budget-period boundaries,
> and a small calendar-feature set (day-of-week, is_weekend, is_month_end,
> days_to_month_end, days_to_next_salary). No market, weather, news, or macro.

Candidate methods were evaluated against v1 constraints
(short history, Python stack already in `backend/app/requirements.txt`):

| Method | Strength | Weakness in our setting | V1 decision |
| --- | --- | --- | --- |
| Seasonal-naïve + rolling median | Dead-simple baseline; works from day 7 | Ignores trend | **Required baseline** — always produced. |
| Holt-Winters / ETS (statsmodels) | Interpretable trend + weekly seasonality; light | Needs 2 full seasons ideally | **Preferred** for 30-day cashflow/ spend when ≥ 60 d history. |
| Prophet | Easy, robust to missing days, changepoints, holiday regressors | Heavy dependency, weaker on short series, slower | **Fallback** when ETS fails to fit or when ≥ 180 d history and the user has noisy changepoints. |
| ARIMA / SARIMAX (statsmodels) | Principled; SARIMAX can take exog | Requires tuning; can overfit short data | Used only for `end_of_month_liquidity` when needed (see below). |
| skforecast + LightGBM | Tree-based, handles nonlinearity and lag features, can ingest our calendar/exog features | Needs more history; heavier model to maintain | **Reserve for L3** (≥ 180 d history) or drop from v1 if carrying weight isn't justified by evaluation. |

**Chosen stack for v1:**

- Primary: **statsmodels ETS** (additive trend, weekly seasonality if `D ≥ 21`).
- Fallback: **Prophet** when `D ≥ 180` OR ETS fit fails (log-captured).
- Always: **seasonal-naïve baseline** for blending and sanity.
- L3 only: skforecast+LightGBM evaluation in a shadow run (not shown to users until it beats ETS on backtest).

#### 3.2.1 Targets

| Target | Grain | Candidates | Preferred | Fallback | Min history | Train/test | Metrics | CI |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| 7/30-day spend | Daily expense sum | ETS, Prophet, SN | ETS additive trend + weekly | SN | 21 d / 60 d for 30 d | Walk-forward, 3 folds, last 20 % held out each fold | MAPE, sMAPE, pinball@p10/p90 | ETS in-sample residual 10/90; Prophet's native CI |
| 90-day cashflow (L3) | Daily net (income − expense + known inflows − known scheduled outflows) | skforecast+LGBM, Prophet | Prophet (or LGBM if beats) | ETS on net | 180 d | Same | MAPE, pinball | Quantile regressor or conformal |
| End-of-month liquidity | `acc_balance_t0 + cum_net_forecast_t→EOM` | Derived from cashflow | Derived | Derived | 30 d | — | — | Propagated from cashflow |
| Category-budget overrun trajectory | `cum(category_spend) to period_end` | ETS (no season) + linear pace | ETS | Linear pace | 14 d | — | MAPE on prior periods | ETS residual band |
| Recurring bill load | Monthly sum of series expected | Deterministic sum of occurrences in window | — | — | N/A | — | — | None (rule-based) |
| Emergency-fund depletion horizon | `balance / max(0, expected_monthly_spend − expected_monthly_income)` | Derived | — | — | L2 | — | — | Propagates CI from spend forecast |
| Goal completion trajectory | Contribution pace × remaining | Bootstrap percentiles on pace | — | — | ≥3 contributions | — | — | 10/50/90 pct |

#### 3.2.2 Uncertainty presentation

- Always return `p10`, `p50`, `p90` (and `mean`).
- Widen CI by `+25 %` when declared income is missing and the target depends on it.
- UI shows a central line + shaded band; numeric "likely range" label beside it. Never display a single-number forecast without a band.

### 3.3 Anomaly layer

Goals: catch point anomalies (one unusually large transaction), contextual
anomalies (normal amount but wrong day/merchant), and collective anomalies (a
run of unusual spend).

| Type | Technique | Features | Threshold | Why |
| --- | --- | --- | --- | --- |
| Rule-based | Hard-coded | Duplicates (already in `analytics-insights`), expired budgets, recurring amount drift, overdue IOU | Fixed rules | Zero false alarms on well-defined checks |
| Robust-stat | MAD z-score | Per-category daily sum; per-merchant transaction amount | `|z_robust| ≥ 3.5` | Literature-supported robust default |
| IsolationForest | sklearn IsolationForest | Transaction features: `log_amount`, `hour`, `dow`, `category_freq_rank`, `merchant_freq_rank`, `days_since_last_same_merchant`, `vs_merchant_median_amount`, `vs_category_median_amount` | `score_samples` below 10th percentile *per user*, trained monthly | Scales well, mostly-unsupervised, handles heterogeneous features |
| LOF | — | — | — | **Not used in v1.** IsolationForest is sufficient; adding LOF doubles maintenance without evidence of lift on our feature set. |

**False-alarm controls:**

- Only rank top-N (default 5) anomalies per snapshot; suppress if the user has
  already dismissed the same `merchant + amount-bucket + category` combination
  via `ai_suggestions.status='dismissed'` in the last 60 d.
- Require ≥ 30 transactions before IsolationForest is eligible; otherwise
  fall back to MAD.
- Rank by a composite score:
  `rank = 0.5 × |z_robust| / 3.5 + 0.5 × (1 − iforest_pct)` bounded to [0,1].
- Each anomaly carries a human-readable `explanation` string templated from the
  dominant feature (e.g. "₹3,200 at Zomato — 4.2× your usual Zomato median").

### 3.4 Predictive / risk layer

Supervised tasks. Treated as opt-in per readiness:

#### 3.4.1 Budget-overrun risk (L3 preferred, L2 allowed)

- **Unit.** One `(user, budget, period)` row.
- **Label.** `1` if `final_spent > amount` at period end.
- **Features.** `pct_elapsed`, `pct_spent`, `pace_index`, `trailing_14d_daily`, `category_seasonality_index` (dow pattern), `prior_overrun_rate_for_budget`, `days_to_period_end`, `variance_of_daily_spend`.
- **Candidates.** Logistic regression (interpretable baseline), Gradient-Boosted Trees (`sklearn.HistGradientBoostingClassifier`).
- **Chosen.** Logistic regression with monotonic features + `CalibratedClassifierCV` (isotonic when `n ≥ 500` per the sklearn guide; sigmoid otherwise). Trees shadowed for eval.
- **Calibration.** Isotonic (preferred per sklearn docs when enough data) or sigmoid (Platt) when small. Evaluated on Brier score and log-loss; reliability diagrams stored per release.
- **Metrics.** AUROC, PR-AUC, Brier score, calibration slope/intercept, decision-threshold chosen to hit precision≥0.7 at recall-optimised point.
- **Explainability.** Logistic coefficients for the main model; `shap.TreeExplainer` on the shadow GBM to sanity-check feature importance pre-release. No SHAP served at runtime initially; reason codes use the top-k signed feature contributions from logistic.

#### 3.4.2 Missed-payment risk

- **Unit.** `(user, obligation, upcoming_due_date)`.
- **Label.** `1` if not paid by due_date + grace.
- **Features.** `history_hit_rate`, `days_until_due`, `balance_at_due_forecast_p10`, `recurring_burden_ratio`, `recent_overdue_count`, `cashflow_p10_at_due`.
- **Model.** Logistic regression with calibration; GBM in shadow.
- **Output.** Probability + reason codes ("low liquidity projected at due date", "history of 3 late payments").

#### 3.4.3 Emergency-fund breach risk

- **Unit.** `(user, month)`.
- **Label.** `1` if projected `runway_months` drops below target.
- **Feature set.** Derived from cashflow forecast's p10 path + monthly income/expense baselines.
- **Model.** Deterministic from cashflow forecast (no supervised model needed v1); probability = share of forecast samples breaching.

#### 3.4.4 Short-term liquidity stress

- Derived from cashflow forecast: probability `min_balance_in_horizon < liquidity_floor`. No separate model.

#### 3.4.5 Goal shortfall probability

- Bootstrap contribution pace distribution; P(pace ≤ required). Only when ≥ 6 contributions.

### 3.5 Explainability layer

- **Local explanations:** logistic coefficients × feature value → top-k reason codes (signed, normalized). Returned as a list of `{feature, direction: +|−, magnitude: 0..1, phrase: '...'}`.
- **Global explanations:** SHAP beeswarm / summary generated **offline** during model validation for dev/debugging only. Not served to users.
- **Allowed user-facing statements.**
  - Descriptive ("Your Food spend is 41 % of total.")
  - Predictive with band ("Likely ₹12k–15k in next 30 days.")
  - Correlational ("Overrun risk is high *because* current pace is 1.34× expected and there are 17 days left.")
- **Forbidden.** Any causal claim not supported by the model inputs. Any claim about external macro/market/news. Any personally identifying speculation. No "you're bad with money" tone — behaviour only, not character.
- **Debugging vs user-facing.** Debug dumps (coefficients, SHAP, fold metrics) go to `goat_mode_job_events` and Sentry; user sees only `reason_codes[]` with vetted phrasing.

---

## 4. Recommendation / AI Decisions

### 4.1 Where Gemini is allowed

- Narrative summaries over a **pre-computed** deterministic/statistical payload.
- Plain-language explanation of a single metric/forecast/anomaly/risk.
- "Next best input" prompts derived from `inputs_missing`.
- Coaching copy variants (tone tuning per user preference).
- Recommendation *phrasing* — not recommendation *selection* (see 4.3).

### 4.2 Where Gemini is NOT allowed

- Inventing any financial number, merchant, amount, percentage, date.
- Generating SQL, writing to any table, or deciding which scope ran.
- Making investment, tax, or legal recommendations.
- Causal claims (macroeconomic, behavioural diagnoses).
- Deriving a metric not present in the deterministic payload.

### 4.3 Recommendation engine (deterministic → AI phrasing)

Recommendations are **generated deterministically** by rules keyed to the
output of §3, then **phrased** by Gemini.

```
// Rule sketch (illustrative, not final code)
if budget.pace_index >= 1.25 and budget.days_to_period_end >= 7:
    rec = { kind: 'budget_overrun', budget_id, severity: f(pace_index) }
if anomaly.rank >= 0.7 and anomaly.amount >= 0.02 * monthly_expense:
    rec = { kind: 'anomaly_review', transaction_id, severity: ... }
if runway_months < 1.0 and emergency_fund_present:
    rec = { kind: 'liquidity_warning', severity: high }
if goal.pace < goal.required_pace * 0.8:
    rec = { kind: 'goal_shortfall', goal_id, required_delta }
```

Each rec carries:

- `kind` (enum of safe, vetted types — see `goat_mode_recommendations` in the data model).
- `severity ∈ {info, watch, warn, critical}`.
- `impact_score` (0..1) = normalized expected impact on FWB if acted upon.
- `effort_score` (0..1) = a priori from kind (e.g. "cancel subscription" = 0.1, "create a budget" = 0.3).
- `priority` = `severity_weight * impact_score * (1 − 0.3 × effort_score)`.
- `inputs_snapshot` = the fields that drove it (verbatim). AI *may not* contradict these.
- `expires_at` (7 d by default) and `fingerprint` to deduplicate (`kind + primary_entity_id + amount_bucket + period`).

### 4.4 Recommendation confidence

- `confidence = f(scope.data_coverage, underlying_model_confidence, historical_hit_rate_of_rule)`.
- Recommendations below `confidence < 0.4` are not surfaced at L1; they're queued as "insights to verify" and require user action to expose.

### 4.5 De-duplication and cool-down

- Fingerprint index ensures the same rec isn't re-surfaced unless the snapshot fingerprint changes *and* 7 d have passed since dismissal.
- Per-kind daily cap (default 2 of same kind) to prevent clutter.

### 4.6 Degradation by data quality

- **L1.** Phrasing is conservative ("Based on limited data, …"). Forecast-derived recs are hidden. Only descriptive recs (duplicates, uncategorized, try a budget).
- **L2.** Adds budget-risk and missed-payment recs.
- **L3.** Full set, including cashflow-derived liquidity warnings.

### 4.7 Structured AI I/O contract

**Prompt input (JSON only).**

```json
{
  "scope": "full",
  "readiness_level": "L2",
  "data_fingerprint": "...",
  "deterministic": { "...": "..." },
  "forecasts": { "...": "..." },
  "anomalies": [ ],
  "risks": [ ],
  "recommendations": [ /* deterministically generated */ ],
  "missing_inputs": [ "monthly_income", "emergency_fund_target" ],
  "currency": "INR",
  "user_tone_preference": "calm"
}
```

**Structured output (validated, reject otherwise).**

```json
{
  "narrative": "string, <= 2 sentences",
  "pillars": [
    { "label": "Liquidity", "observation": "...", "inference": "...", "confidence": "medium" }
  ],
  "recommendation_phrasings": [
    { "rec_id": "...", "title": "...", "body": "...", "why_shown": "..." }
  ],
  "missing_input_prompts": [
    { "field": "monthly_income", "title": "...", "body": "...", "cta": "Add income" }
  ],
  "coaching": [ { "tone": "calm", "text": "..." } ],
  "follow_up_questions": [ "..." ]
}
```

**Validation rules.**

- Every `rec_id` must exist in input `recommendations[]`.
- No numeric value may appear in `narrative`/`body` that is not present in input (regex-check on numbers; if a digit appears in output not in input → reject and fall back to deterministic templates).
- Output must be pure JSON (re-use the `{…}` extraction + `JSON.parse` pattern from `analytics-insights/index.ts`).
- On validation failure, the backend substitutes deterministic templates per recommendation kind.

### 4.8 Separation of observation / inference / recommendation

The AI layer must use the `pillars[]` shape to keep them distinct:

- `observation` — a data point quoted from input (no new numbers).
- `inference` — a statement about what that likely means ("this is a pace change, not a trend").
- `recommendation_phrasings[].body` — one concrete action tied to a deterministic rec.

---

## 5. UX / Display Decisions

### 5.1 Principles

1. **Summary-first.** The default Goat Mode screen fits on one phone viewport.
2. **Progressive disclosure.** Everything else lives behind a tap, with ≤ 3 nesting levels.
3. **Confidence is always visible.** No number renders without at least a chip or color dot.
4. **Missing data is a feature, not an error.** Empty states are productive prompts, not dead ends.
5. **No dumped dashboards.** Never show every metric at once.
6. **Inherit Billy tokens.** Use `BillyTheme` colors, 20–28 px cards, emerald gradient reserved for hero/FWB score, amber for warnings, red only for critical.

### 5.2 Default screen (always L-agnostic)

Top-to-bottom, using existing Billy card/hero tokens:

1. **Hero Well-Being card** — big FWB score 0–100, +/- vs prior period, freshness
   timestamp, single primary CTA ("Refresh") and a subtle "Why this score?" that
   opens the pillar breakdown.
2. **Data-completeness strip** — one-line "Coverage 62 % · 3 missing inputs" with
   an "Improve" button. Tap opens a sheet listing the top 3 missing-input
   prompts.
3. **Top 3 prioritized insights** — large card stack: title + one sentence +
   chip for (`severity`, `confidence`, `kind`). Tap opens detail.
4. **Scope chips row** — horizontal chip scroller (Cashflow, Budgets, Recurring,
   Debt, Goals). Tapping a chip opens that scope screen.
5. **"What would improve this?" card** — up to 3 missing inputs, each with a
   one-tap CTA to the setup flow.
6. **Footer** — last refreshed, data-fingerprint hash (dev), and an inline link
   to the full deterministic JSON for power users (hidden unless a dev flag is on).

**Not on the default screen:** forecast charts, anomaly list, per-budget pace
details, per-goal trajectory, full category distribution, SHAP-style
explanations, raw metrics grid, past snapshots.

### 5.3 Scope detail screens (one per scope)

- **Header.** Scope name, readiness-level pill (L1/L2/L3 minimal), freshness.
- **Hero metric.** Single most important number for that scope + confidence chip.
- **Chart region.** One chart max per scope on the first screen (e.g. cashflow
  band chart for `cashflow`; stacked budget bars for `budgets`).
- **Tabs.** 2–3 tabs: *Now*, *Forecast*, *History*.
- **Recommendation strip.** At most 2 per scope in-line; "See more" opens a
  bottom sheet list.
- **Missing-inputs block.** Contextual — e.g. `debt` scope prompts "Declare
  recurring obligations" when none are present.

### 5.4 Component rules

| Use | Component |
| --- | --- |
| State label (readiness, confidence) | Chip (pill, 24 px, single line) |
| Severity | Color dot + word (info/watch/warn/critical) |
| Small categorical filters | Chip-row (horizontal scroll) |
| Single big number | Hero card (20–28 px radius, 20 px padding, title + subtext) |
| Trend / delta | Inline sparkline + %; never a full axis |
| Full chart | Dedicated section; max 1 on default screen per scope |
| A recommendation | Card with title, one-sentence body, two CTAs (primary action, "why") |
| "Why this recommendation?" | Bottom sheet with observation → inference → recommendation panels |
| Anomaly list | Detail screen only, never the default |
| Forecast | Band chart (p10/p50/p90) + text "Likely between X–Y"; never a single-number forecast |

### 5.5 Confidence / freshness / missing data

- Confidence: chip (low/medium/high) + optional "?" that opens `reason_codes[]`.
- Freshness: "Updated 2 h ago" + warning chip if > 48 h.
- Missing data: inline dashed outline with a prompt instead of a zero value.

### 5.6 Moving from top-line to detail

1. Default screen → summary insights.
2. Tap an insight → bottom-sheet detail with observation / inference /
   recommendation.
3. Tap a scope chip → scope screen.
4. Tap a metric in scope → detail screen or chart view.
5. Tap "Why this score?" on the hero → pillar breakdown screen.

Maximum depth = 3 taps from default to any primitive (formula, raw
transactions, forecast band). If it exceeds 3, it's debug-only.

### 5.7 Recommendation UX

- Default screen shows **top 3**, ordered by priority.
- Each card exposes a "Why shown" secondary that opens a sheet with:
  - Observation (raw data from scope).
  - Inference (one sentence).
  - What to do (CTA).
  - Confidence + readiness level.
- Group recommendations into sections only on the dedicated "Recommendations"
  detail screen, by `severity`, then `kind`.
- Never stack > 2 same-kind recs on the default screen.
- If data coverage is too low to generate confident recs, the default screen
  shows a single "Teach Billy about your money" card routing to the setup flow
  instead of recs.

---

## 6. Open research — Methods and References Reviewed

Primary sources consulted during this phase (summarised, chosen direction
noted in-line):

- **Forecasting.** Statsmodels ETS docs and tutorial notebooks, Prophet paper +
  docs, skforecast recursive-LightGBM guide. *Chosen:* ETS primary,
  Prophet fallback, skforecast in shadow at L3. Sources described ETS as a
  strong interpretable baseline and Prophet as robust to changepoints/holidays
  but heavier.
- **Anomaly detection.** scikit-learn IsolationForest docs + examples,
  MAD-based outlier guide, time-series context note on point/contextual/
  collective anomalies. *Chosen:* rules + MAD + IsolationForest; LOF not
  justified at v1.
- **Calibration.** scikit-learn `CalibratedClassifierCV` docs, isotonic vs
  sigmoid comparison. *Chosen:* isotonic when `n ≥ 500` per-model; sigmoid
  (Platt) fallback. Evaluate with Brier and log-loss.
- **Explainability.** SHAP TreeExplainer docs + "gentle introduction" +
  financial-ML explainability writeups. *Chosen:* SHAP in dev/backtest only;
  at-runtime reason codes come from linear models.
- **UX / progressive disclosure.** Fintech dashboard best-practice writeups,
  progressive-disclosure patterns, UI-density discussion. *Chosen:*
  summary-first hero with ≤ 3 levels of depth, chips for state, bottom sheets
  for drill-in.
- **Financial well-being scoring.** CFPB Financial Well-Being Scale + technical
  report (IRT-scored 0–100). *Chosen:* **inspiration only** — Billy's FWB is a
  transparent pillar scorecard from its own data, not the CFPB survey.
- **Supabase local dev.** Supabase CLI docs (`supabase init / start / db reset /
  functions serve`). *Chosen:* Supabase CLI as the canonical local-first path.
- **Cloud Run local testing.** Functions Framework + `docker run -p` docs. *Chosen:*
  uvicorn-in-Docker for Billy's Python backend; functions-framework used only
  if/when we move to gen2-functions; Cloud Code emulator optional.

The detailed source URLs are embedded in the analysis where the decision was
made; concrete references are listed here for traceability and are not
intended to be the final citation set.

---

*(Remainder of the phase-0 deliverable continues in
`GOAT_MODE_LOCAL_FIRST_PLAN.md` and `GOAT_MODE_DATA_MODEL_DRAFT.md`.)*
