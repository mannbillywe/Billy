# Billy — Complete Product Blueprint

**Version:** 1.0  
**Date:** 2026-04-11  
**Status:** Execution-ready architecture plan

---

## SECTION 1 — EXECUTIVE PRODUCT DIRECTION

### What the app is today

Billy is a Flutter financial app built on Supabase with Riverpod state management. It captures invoices and receipts via camera/gallery, extracts data through a server-side Gemini OCR pipeline, stores structured documents, and supports optional group expense splits and lend/borrow IOUs from the same scan flow. It has a dashboard with spend charts, an analytics screen with AI-powered insights, a friends/groups tab, and a settings/export area. The app has a solid auth system, usage limits, category resolution, batch scanning, and a working social layer (contacts, invitations, connections).

### What it should become

Billy should become a **unified personal finance system** where every financial event — whether scanned, typed, imported from a statement, or received from a linked account — flows into a single canonical ledger. That ledger powers personal spending views, shared expense tracking, lend/borrow records, budgets, recurring bill monitoring, and eventually net worth calculations. The user should never have to wonder "where did I record that?" because every source traces to one transaction model, and every transaction can branch into group splits, IOUs, budget allocations, or recurring pattern detection.

### The main transformation required

The app must shift from a **source-first architecture** (where documents are the primary entity and group expenses / lend-borrow are side effects of a scan) to a **transaction-first architecture** (where a canonical financial transaction is the primary entity, and documents/scans/imports are source evidence attached to transactions). This inversion is the single most important structural change.

### Guiding product principle

**One source, one review, many structured outputs — all traced to one canonical transaction.**

Every piece of financial data enters through one of several capture methods, gets classified once, and fans out into the right ledger entries, relationships, and planning constructs. The user sees a unified timeline. The system maintains full traceability from any output back to its source.

---

## SECTION 2 — CURRENT SYSTEM INVENTORY

### Screens / Routes

| Screen | Location | Tab/Route | Status |
|--------|----------|-----------|--------|
| `LoginScreen` | `lib/features/auth/screens/` | Auth gate | Active |
| `LayoutShell` | `lib/app/layout_shell.dart` | Tab container | Active |
| `DashboardScreen` | `lib/features/dashboard/screens/` | Tab 0 (Home) | Active |
| `AnalyticsScreen` | `lib/features/analytics/screens/` | Tab 1 (Analytics) | Active |
| `SplitScreen` | `lib/features/lend_borrow/screens/` | Tab 2 (Friends) | Active |
| `SettingsScreen` | `lib/features/settings/screens/` | Tab 3 (Settings) | Active |
| `ScanScreen` | `lib/features/scanner/screens/` | FAB → Push | Active |
| `DocumentsHistoryScreen` | `lib/features/documents/screens/` | Push from many | Active |
| `DocumentDetailScreen` | `lib/features/documents/screens/` | Push | Active |
| `DocumentEditScreen` | `lib/features/documents/screens/` | Push from detail | Active |
| `DocumentAiReviewScreen` | `lib/features/analytics/screens/` | Push from detail | Active |
| `GroupExpensesScreen` | `lib/features/groups/screens/` | Push from Split/scan | Active |
| `ExportScreen` | `lib/features/export/screens/` | Push from dashboard/settings | Active |
| `ExportHistoryScreen` | `lib/features/export/screens/` | Push from settings | Active |
| `ProfileScreen` | `lib/features/profile/screens/` | Push from settings | Active |
| `GoatModePlaceholderScreen` | `lib/features/goat/` | Push (being removed) | Deprecating |

### Core Flows

1. **Scan → OCR → Review → Save** — Camera/gallery/file → `InvoiceOcrPipeline` → Gemini Edge Function → `ScanReviewPanel` → write to `invoices`, `invoice_items`, `documents`, optionally `group_expenses` + `group_expense_participants`, optionally `lend_borrow_entries`
2. **Manual expense entry** — `AddExpenseSheet` bottom sheet → `documents` insert (no OCR)
3. **Group expense (standalone)** — From `SplitScreen` or `GroupExpensesScreen` → `create_group_expense` RPC
4. **Lend/borrow (standalone)** — From `SplitScreen` → `lend_borrow_entries` insert
5. **Settlement** — From `GroupExpensesScreen` → `group_settlements` insert
6. **Export** — Date range selection → PDF/CSV generation → share
7. **AI analytics** — `AnalyticsInsightsService` → Edge Function → cached snapshots

### Tables / Data Models (Post-GOAT-removal)

| Table | Purpose | Key Relationships |
|-------|---------|-------------------|
| `profiles` | User accounts | FK → `auth.users` |
| `categories` | Expense categories (user + global) | FK → `profiles` |
| `documents` | Primary financial records | FK → `profiles`, `categories` |
| `invoices` | OCR-extracted invoice headers | FK → `profiles` |
| `invoice_items` | Line items from OCR | FK → `invoices` |
| `invoice_ocr_logs` | OCR processing logs | FK → `invoices` |
| `invoice_processing_events` | Pipeline event tracking | FK → `invoices` |
| `lend_borrow_entries` | IOUs/loans between users | FK → `profiles`, optional `documents`, `expense_groups` |
| `splits` / `split_participants` | Legacy split table | **Dead code** — unused in providers |
| `contact_invitations` | Pending friend invitations | FK → `profiles` |
| `user_connections` | Confirmed friendships | FK → `profiles` (pair) |
| `expense_groups` | Groups for shared expenses | FK → `profiles` (creator) |
| `expense_group_members` | Group membership | FK → `expense_groups`, `profiles` |
| `group_expenses` | Shared expenses in groups | FK → `expense_groups`, optional `documents` |
| `group_expense_participants` | Per-user shares | FK → `group_expenses` |
| `group_settlements` | Payment settlements | FK → `expense_groups`, `profiles` |
| `connected_apps` | External app connections (future) | FK → `profiles` |
| `export_history` | Export audit trail | FK → `profiles` |
| `analytics_insight_snapshots` | Cached AI insights | FK → `profiles` |
| `user_usage_limits` | OCR/refresh quotas | FK → `profiles` |
| `app_api_keys` | Shared API keys (server only) | — |

### Providers / Services

| Provider | Manages | Active |
|----------|---------|--------|
| `documentsProvider` | `documents` CRUD | Yes |
| `profileProvider` | Current user profile | Yes |
| `expenseGroupsNotifierProvider` | `expense_groups` + members | Yes |
| `groupExpensesProvider` (family) | Group expenses per group | Yes |
| `groupSettlementsProvider` (family) | Settlements per group | Yes |
| `lendBorrowProvider` | `lend_borrow_entries` CRUD | Yes |
| `connectionsNotifierProvider` | User connections | Yes |
| `invitationsNotifierProvider` | Contact invitations | Yes |
| `usageLimitsProvider` | OCR/refresh limits | Yes |
| `weekSpendBasisProvider` | Dashboard preference | Yes |
| `authStateProvider` | Auth stream | Yes |
| `analyticsInsightsProvider` | Cached AI insights | Yes |
| `splitsProvider` | Legacy splits | **Dead** |

| Service | Responsibility | Active |
|---------|---------------|--------|
| `SupabaseService` | All Postgrest/Storage/RPC calls | Yes (some dead methods) |
| `InvoiceOcrPipeline` | Upload → process → poll → extract | Yes |
| `AnalyticsInsightsService` | AI insights via Edge Function | Yes |
| `PdfGenerator` / `CsvGenerator` | Export file creation | Yes |

### Current Strengths

1. **Scan pipeline is production-quality** — multi-image batch, PDF support, background prefetch during crop, proper polling
2. **Review panel is already rich** — line-item toggling, group assignment, lend/borrow per-line, counterparty picker from contacts
3. **Social layer works** — invitations, connections, expense groups, member management
4. **Group expense RPC is solid** — server-side with share validation, document linking
5. **Category system has AI + manual + rule sources**
6. **Usage limits are properly server-guarded** (security definer RPCs)
7. **RLS is comprehensive** — user-scoped on all tables

### Current Structural Limitations

1. **`documents` is the de facto ledger** — but it's really a source/evidence table, not a financial transaction table
2. **No canonical transaction model** — spend data lives in `documents.amount` with intent metadata buried in `extracted_data` JSON
3. **Side effects are implicit** — group expense and lend/borrow creation happens as procedural code in `ScanReviewPanel._save()` with no unifying transaction
4. **No activity feed** — users can't see what happened across groups/IOUs/settlements chronologically
5. **No edit/version history** — changes to documents or group expenses are overwrites with no audit trail
6. **No budget system**
7. **No recurring bill detection or management**
8. **No statement import pipeline** (GOAT version was removed)
9. **No dispute mechanism** for shared expenses
10. **Settlement is basic** — insert-only, no confirmation flow from payee
11. **Dashboard aggregates are computed client-side** from full document list (doesn't scale)

---

## SECTION 3 — CORE PRODUCT PROBLEMS

### Problem 1: Source-first vs. money-first architecture

The `documents` table is simultaneously: (a) a record of a scanned/entered source, (b) the primary financial amount record, and (c) the carrier for extracted OCR data. This triple duty means there's no clean way to represent a financial event that doesn't originate from a scan (like a manual bank statement line, a settlement, or a recurring charge). Everything is forced through the "document" lens.

**Impact:** Cannot cleanly add statement imports, manual transactions, or system-generated events (like recurring charges) without creating fake "documents."

### Problem 2: Fragmented save side effects

When a receipt is saved in `ScanReviewPanel._save()`, the code sequentially: (1) syncs invoice items, (2) inserts a document, (3) conditionally creates a group expense, (4) conditionally creates lend/borrow entries. These are four independent database writes with no transactional binding. If step 3 fails, step 2 already committed. There's no rollback, no unified record that ties them together, and the only link is `document_id` columns added after the fact.

**Impact:** Data integrity risk; no single place to see "this receipt created these financial events."

### Problem 3: Document-ledger vs. transaction-ledger confusion

The dashboard reads `documents` to compute spend totals. But `documents` includes drafts, includes amounts that may have been split differently via group expense shares, and includes lend/borrow amounts that are conceptually different from personal spend. The "amount" on a document is the receipt total, not necessarily what the user actually spent.

**Impact:** Dashboard spend figures can be misleading. A $100 shared dinner where the user's share is $25 shows as $100 on the personal dashboard.

### Problem 4: Hidden split/allocation logic

Line-item allocation, group share computation, and lend/borrow bucketing all happen in widget-level code (`ScanReviewPanel`). There's no reusable service, no shared allocation engine, and no way to re-allocate after initial save.

**Impact:** Can't edit allocations after save; can't apply same logic from statement import or manual entry; can't test allocation logic in isolation.

### Problem 5: Weak collaboration trust layer

Group expenses have no confirmation from participants. Settlements have no confirmation from payee. There's no dispute flow, no activity feed showing who did what, no edit history, and no way for a group member to contest a charge.

**Impact:** Users can't trust shared financial data; the app feels unsafe for real group money management.

### Problem 6: No unified activity model

Actions happen across `documents`, `group_expenses`, `group_settlements`, `lend_borrow_entries`, and `contact_invitations` — but there's no single chronological feed showing all financial activity. The dashboard `RecentActivity` widget shows recent documents only.

**Impact:** Users lose track of what happened; group members can't see a timeline of shared financial events.

### Problem 7: No planning layer

There are no budgets, no recurring bill tracking, and no subscription management. The app captures what happened but doesn't help the user plan what should happen.

**Impact:** The app is reactive-only; users need a separate tool for forward-looking finance management.

---

## SECTION 4 — TARGET PRODUCT ARCHITECTURE

### Layer 1: Capture

**Purpose:** Ingest financial data from any source into the system.

**Entities:**
- `sources` — the evidence/origin (scanned receipt, manual entry, statement row, linked account transaction)
- `invoices` + `invoice_items` — OCR-specific extraction (stays as-is, becomes a source type)

**User-facing surfaces:**
- Scan screen (camera/gallery/file) — exists
- Manual entry sheet — exists, needs enhancement
- Statement import screen — new
- Linked accounts screen — future

**Connections:** Every source creates one or more `transactions` in the Ledger layer. Source → Transaction is 1:many (one receipt can produce multiple transactions when split).

### Layer 2: Ledger

**Purpose:** The single source of truth for all financial events.

**Entities:**
- `transactions` — canonical financial events (the new core table)
- `transaction_allocations` — how a transaction distributes across purposes (personal, group share, lend, borrow)
- `transaction_tags` — flexible categorization beyond single category

**User-facing surfaces:**
- Transaction history/timeline — replaces document history as primary
- Transaction detail — shows amount, allocations, linked source, linked group/lend
- Dashboard — reads from transactions, not documents

**Connections:** Transactions link down to Sources (evidence) and up to Relationships (groups, IOUs) and Planning (budgets, recurring).

### Layer 3: Relationships

**Purpose:** Manage the social and financial connections between users.

**Entities:**
- `expense_groups`, `expense_group_members` — stays
- `group_expenses`, `group_expense_participants` — stays, links to transactions
- `group_settlements` — enhanced with confirmation states
- `lend_borrow_entries` — stays, links to transactions
- `activity_events` — new event log for all actions
- `disputes` — new, for contesting shared charges

**User-facing surfaces:**
- Friends/Groups tab — enhanced with activity feed
- Group detail — enhanced with settlement confirmation, disputes
- Balance summary — cross-group net balances

**Connections:** Relationships consume Ledger transactions and produce Activity events. Settlements create new Ledger transactions.

### Layer 4: Planning

**Purpose:** Forward-looking financial management.

**Entities:**
- `budgets` + `budget_periods` — category/total budgets with period tracking
- `recurring_series` + `recurring_occurrences` — bills and subscriptions
- `accounts` — bank/wallet/cash accounts (for net worth)

**User-facing surfaces:**
- Budgets screen — set and track spending limits
- Recurring/Subscriptions screen — manage known recurring charges
- Monthly overview — calendar view of upcoming charges
- Accounts & net worth — future

**Connections:** Planning reads from Ledger to compute actuals vs. targets. Recurring series auto-detect from transaction patterns.

---

## SECTION 5 — UNIFIED DATA MODEL

### Overview: What changes

| Current Table | Fate | Why |
|---------------|------|-----|
| `documents` | **Stays, demoted to source** | Becomes evidence/attachment, not the ledger |
| `invoices` | **Stays as-is** | OCR extraction data, linked to documents |
| `invoice_items` | **Stays as-is** | Line items from OCR |
| `lend_borrow_entries` | **Stays, enhanced** | Gets `transaction_id` FK |
| `group_expenses` | **Stays, enhanced** | Gets `transaction_id` FK |
| `group_settlements` | **Enhanced** | Adds confirmation state, `transaction_id` |
| `splits` / `split_participants` | **Drop** | Dead code, never used |
| All other tables | **Stay as-is** | — |

### New Table: `transactions`

**Purpose:** The canonical financial event record. Every money movement in the system — whether a personal expense, a group split share, a lend, a borrow, a settlement, a recurring charge, or a statement import line — is a transaction.

```sql
create table public.transactions (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,

  -- Core financial data
  amount numeric(12,2) not null,
  currency text not null default 'INR',
  date date not null,
  
  -- Classification
  type text not null check (type in (
    'expense',        -- personal or shared spending
    'income',         -- money received
    'transfer',       -- between own accounts
    'lend',           -- money lent out
    'borrow',         -- money borrowed
    'settlement_out', -- settlement payment made
    'settlement_in',  -- settlement payment received
    'refund',         -- money returned
    'recurring'       -- auto-generated from recurring series
  )),
  
  -- Descriptive
  title text not null,
  description text,
  category_id uuid references public.categories(id),
  category_source text check (category_source in ('manual','ai','rule','import','legacy')),
  payment_method text,
  
  -- Source tracing
  source_type text not null check (source_type in (
    'scan',           -- from OCR pipeline
    'manual',         -- typed by user
    'statement',      -- from statement import
    'group_split',    -- auto-created from group expense
    'settlement',     -- from settlement flow
    'recurring',      -- auto-generated from recurring series
    'linked_account', -- future: bank feed
    'system'          -- system-generated adjustments
  )),
  source_document_id uuid references public.documents(id) on delete set null,
  source_import_id uuid,  -- future: statement_imports FK
  
  -- Ownership in shared context
  effective_amount numeric(12,2), -- user's actual share (e.g., $25 of $100 dinner)
  group_id uuid references public.expense_groups(id) on delete set null,
  group_expense_id uuid references public.group_expenses(id) on delete set null,
  lend_borrow_id uuid references public.lend_borrow_entries(id) on delete set null,
  settlement_id uuid references public.group_settlements(id) on delete set null,
  
  -- State
  status text not null default 'confirmed' check (status in ('draft','confirmed','pending','voided','disputed')),
  is_recurring boolean not null default false,
  recurring_series_id uuid, -- future FK to recurring_series
  
  -- Metadata
  notes text,
  tags text[], -- flexible tag array
  extracted_data jsonb, -- preserved OCR/import metadata
  
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

-- Indexes
create index transactions_user_id_idx on public.transactions(user_id);
create index transactions_date_idx on public.transactions(user_id, date desc);
create index transactions_type_idx on public.transactions(user_id, type);
create index transactions_source_doc_idx on public.transactions(source_document_id) where source_document_id is not null;
create index transactions_group_idx on public.transactions(group_id) where group_id is not null;
create index transactions_category_idx on public.transactions(category_id) where category_id is not null;
create index transactions_status_idx on public.transactions(user_id, status);

-- RLS
alter table public.transactions enable row level security;
create policy "txn_select" on public.transactions for select using (auth.uid() = user_id);
create policy "txn_insert" on public.transactions for insert with check (auth.uid() = user_id);
create policy "txn_update" on public.transactions for update using (auth.uid() = user_id) with check (auth.uid() = user_id);
create policy "txn_delete" on public.transactions for delete using (auth.uid() = user_id);

-- Updated_at trigger
create trigger transactions_touch_updated_at
  before update on public.transactions
  for each row execute function set_invoice_updated_at(); -- reuse existing trigger function
```

**Why this table is needed:**
- Decouples financial events from their sources
- `effective_amount` solves the "I paid $100 but my share is $25" problem
- `type` enum cleanly separates spending, lending, settlements, income
- `source_type` + `source_document_id` preserves full traceability
- FKs to `group_expenses`, `lend_borrow_entries`, `group_settlements` make cross-referencing explicit
- `status` supports drafts, voided transactions, and dispute states
- Dashboard can now query `SELECT SUM(effective_amount) FROM transactions WHERE type = 'expense' AND status = 'confirmed'` for accurate personal spend

### New Table: `activity_events`

**Purpose:** Chronological audit trail of all actions across the system. Powers activity feeds, edit history, and trust layer.

```sql
create table public.activity_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  
  -- What happened
  event_type text not null check (event_type in (
    'transaction_created',
    'transaction_updated', 
    'transaction_voided',
    'transaction_disputed',
    'group_expense_created',
    'group_expense_updated',
    'group_expense_deleted',
    'settlement_created',
    'settlement_confirmed',
    'settlement_rejected',
    'lend_created',
    'borrow_created',
    'lend_settled',
    'borrow_settled',
    'group_member_added',
    'group_member_removed',
    'budget_created',
    'budget_exceeded',
    'recurring_detected',
    'recurring_due',
    'dispute_opened',
    'dispute_resolved',
    'document_scanned',
    'statement_imported'
  )),
  
  -- Context
  actor_user_id uuid not null references public.profiles(id),
  target_user_id uuid references public.profiles(id),
  group_id uuid references public.expense_groups(id),
  transaction_id uuid references public.transactions(id) on delete set null,
  entity_type text, -- 'transaction', 'group_expense', 'settlement', etc.
  entity_id uuid,   -- generic FK to the affected entity
  
  -- Payload
  summary text not null,            -- human-readable "Alice added $50 dinner at Pizzeria"
  details jsonb,                    -- structured diff / metadata
  previous_state jsonb,             -- for edit history: snapshot before change
  
  -- Visibility
  visibility text not null default 'private' check (visibility in ('private','group','public')),
  
  created_at timestamptz not null default now()
);

create index activity_events_user_idx on public.activity_events(user_id, created_at desc);
create index activity_events_group_idx on public.activity_events(group_id, created_at desc) where group_id is not null;
create index activity_events_entity_idx on public.activity_events(entity_type, entity_id);

alter table public.activity_events enable row level security;
create policy "ae_select_own" on public.activity_events for select 
  using (auth.uid() = user_id or auth.uid() = actor_user_id or auth.uid() = target_user_id);
create policy "ae_insert" on public.activity_events for insert with check (auth.uid() = actor_user_id);
```

**Why:** Without this, there's no way to show "what happened" in groups, no edit history, no audit trail for disputes.

### New Table: `disputes`

**Purpose:** Allows group members to contest charges or request corrections.

```sql
create table public.disputes (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  
  -- What is disputed
  entity_type text not null check (entity_type in ('group_expense', 'settlement', 'lend_borrow')),
  entity_id uuid not null,
  group_id uuid references public.expense_groups(id),
  transaction_id uuid references public.transactions(id),
  
  -- Dispute details
  reason text not null,
  proposed_amount numeric(12,2),
  proposed_resolution text,
  
  -- State
  status text not null default 'open' check (status in ('open', 'acknowledged', 'resolved', 'withdrawn')),
  resolved_by uuid references public.profiles(id),
  resolution_notes text,
  
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index disputes_user_idx on public.disputes(user_id);
create index disputes_group_idx on public.disputes(group_id) where group_id is not null;
create index disputes_entity_idx on public.disputes(entity_type, entity_id);

alter table public.disputes enable row level security;
create policy "disputes_select" on public.disputes for select 
  using (
    auth.uid() = user_id 
    or (group_id is not null and public.user_is_expense_group_member(group_id))
  );
create policy "disputes_insert" on public.disputes for insert with check (auth.uid() = user_id);
create policy "disputes_update" on public.disputes for update using (auth.uid() = user_id or auth.uid() = resolved_by);
```

### New Table: `budgets`

**Purpose:** Monthly/weekly spending limits by category or total.

```sql
create table public.budgets (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  
  name text not null,
  category_id uuid references public.categories(id), -- null = total budget
  amount numeric(12,2) not null check (amount > 0),
  period text not null default 'monthly' check (period in ('weekly', 'monthly', 'yearly')),
  currency text not null default 'INR',
  
  -- Rollover
  rollover_enabled boolean not null default false,
  
  -- State
  is_active boolean not null default true,
  start_date date not null default current_date,
  end_date date, -- null = ongoing
  
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index budgets_user_category_active 
  on public.budgets(user_id, category_id) 
  where is_active = true and category_id is not null;

alter table public.budgets enable row level security;
create policy "budgets_all" on public.budgets for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

**Why:** Without budgets, users can't set spending limits. The `category_id` FK lets users budget per category. The unique partial index ensures one active budget per category.

### New Table: `budget_periods`

**Purpose:** Track actual spend per budget per period for historical comparison.

```sql
create table public.budget_periods (
  id uuid primary key default gen_random_uuid(),
  budget_id uuid not null references public.budgets(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  
  period_start date not null,
  period_end date not null,
  spent numeric(12,2) not null default 0,
  rollover_amount numeric(12,2) not null default 0, -- carried from previous period
  
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index budget_periods_unique on public.budget_periods(budget_id, period_start);
create index budget_periods_user_idx on public.budget_periods(user_id, period_start desc);

alter table public.budget_periods enable row level security;
create policy "bp_all" on public.budget_periods for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

### New Table: `recurring_series`

**Purpose:** Track known recurring charges (subscriptions, bills, EMIs).

```sql
create table public.recurring_series (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  
  title text not null,
  amount numeric(12,2) not null check (amount > 0),
  currency text not null default 'INR',
  category_id uuid references public.categories(id),
  
  -- Schedule
  cadence text not null check (cadence in ('daily','weekly','biweekly','monthly','quarterly','yearly')),
  anchor_date date not null, -- first occurrence or reference date
  next_due date,
  
  -- Detection
  detection_source text not null default 'manual' check (detection_source in ('manual','pattern','statement')),
  vendor_pattern text, -- regex or fuzzy match for auto-detection
  
  -- State
  is_active boolean not null default true,
  auto_confirm boolean not null default false,
  
  -- Notification
  remind_days_before integer not null default 1,
  
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index recurring_series_user_idx on public.recurring_series(user_id);
create index recurring_series_next_due_idx on public.recurring_series(user_id, next_due) where is_active = true;

alter table public.recurring_series enable row level security;
create policy "rs_all" on public.recurring_series for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

### New Table: `recurring_occurrences`

**Purpose:** Individual instances of recurring charges, linked to transactions when matched.

```sql
create table public.recurring_occurrences (
  id uuid primary key default gen_random_uuid(),
  series_id uuid not null references public.recurring_series(id) on delete cascade,
  user_id uuid not null references public.profiles(id) on delete cascade,
  
  due_date date not null,
  actual_amount numeric(12,2),
  transaction_id uuid references public.transactions(id) on delete set null,
  
  status text not null default 'upcoming' check (status in ('upcoming','confirmed','missed','skipped')),
  
  created_at timestamptz not null default now()
);

create unique index recurring_occ_unique on public.recurring_occurrences(series_id, due_date);
create index recurring_occ_user_idx on public.recurring_occurrences(user_id, due_date);

alter table public.recurring_occurrences enable row level security;
create policy "ro_all" on public.recurring_occurrences for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

### New Table: `statement_imports`

**Purpose:** Track bank/card statement file imports.

```sql
create table public.statement_imports (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  
  file_path text not null,
  file_name text not null,
  mime_type text,
  source_type text not null default 'upload' check (source_type in ('upload','email','api')),
  
  -- Parsing metadata
  account_name text,
  account_type text, -- 'checking', 'credit_card', 'savings'
  institution_name text,
  statement_period_start date,
  statement_period_end date,
  
  -- Processing
  status text not null default 'uploaded' check (status in ('uploaded','processing','review','completed','failed')),
  row_count integer,
  imported_count integer default 0,
  skipped_count integer default 0,
  error_message text,
  
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index statement_imports_user_idx on public.statement_imports(user_id, created_at desc);

alter table public.statement_imports enable row level security;
create policy "si_all" on public.statement_imports for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

### New Table: `accounts` (Future: Net Worth)

**Purpose:** Represent financial accounts for balance tracking and net worth.

```sql
create table public.accounts (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles(id) on delete cascade,
  
  name text not null,
  type text not null check (type in ('checking','savings','credit_card','cash','investment','loan','other')),
  institution text,
  currency text not null default 'INR',
  
  current_balance numeric(14,2) not null default 0,
  is_asset boolean not null default true, -- false for credit cards, loans
  
  is_active boolean not null default true,
  is_linked boolean not null default false, -- future: bank feed
  
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create index accounts_user_idx on public.accounts(user_id);

alter table public.accounts enable row level security;
create policy "accounts_all" on public.accounts for all using (auth.uid() = user_id) with check (auth.uid() = user_id);
```

### Enhancement: `group_settlements` — Add confirmation

```sql
alter table public.group_settlements 
  add column if not exists status text not null default 'pending' 
    check (status in ('pending','confirmed','rejected')),
  add column if not exists confirmed_at timestamptz,
  add column if not exists transaction_id uuid references public.transactions(id);
```

**Why:** Settlements need payee confirmation to be trusted. Without this, anyone can mark a debt as settled.

### Enhancement: `lend_borrow_entries` — Add transaction FK

```sql
alter table public.lend_borrow_entries
  add column if not exists transaction_id uuid references public.transactions(id);
```

### Enhancement: `group_expenses` — Add transaction FK

```sql
alter table public.group_expenses
  add column if not exists transaction_id uuid references public.transactions(id);
```

### Complete relationship diagram

```
Sources (capture)              Ledger (core)                  Relationships
─────────────────              ─────────────                  ─────────────
documents ──────────┐
invoices/items ─────┤          transactions ◄──────────────── group_expenses
statement_imports ──┤   ┌────► (canonical)                    group_settlements
                    └───┘          │                          lend_borrow_entries
                         ┌────────┤                          disputes
                         ▼        ▼                          activity_events
                    budgets    recurring_series
                    budget_    recurring_
                    periods    occurrences                    Planning
                              accounts                       ────────
```

---

## SECTION 6 — SCAN / REVIEW / SAVE FLOW REDESIGN

### Current flow summary

1. User opens scan → captures/picks image(s)
2. Image uploaded to Storage, `invoices` row created, Edge Function called
3. Gemini extracts structured data → `invoice_items` populated
4. `ScanReviewPanel` shows: vendor, date, invoice number, category, notes, tax summary, line items with checkboxes
5. User optionally enables group expense → picks group → assigns members per line
6. User optionally enables lend/borrow → picks counterparty → sets type (lent/borrowed)
7. Save: syncs invoice items → inserts document → conditionally creates group expense → conditionally creates lend/borrow entries
8. Draft: inserts document with `status: 'draft'` only

### What is wrong with current flow

1. **No preview of financial outcomes** — user presses "Save" and trusts that the right things happen; there's no summary showing "This will create: 1 personal expense of ₹450, 1 group expense of ₹300 split between Alice (₹150) and Bob (₹150), 1 IOU of ₹200 from Charlie"
2. **No transaction creation** — the financial event is implicit in the document amount; there's no explicit transaction record
3. **Mixed bill handling is linear** — a receipt with both personal items and shared items has no clear UX for "these 3 lines are personal, these 2 lines are for the group, this 1 line is a lend"
4. **Group assignment is all-or-nothing per receipt** — either the whole receipt is a group expense or it isn't; can't have a mixed receipt
5. **No reimbursement path** — if someone paid for something that should be reimbursed by one person (not a group split), there's no clean way to express that
6. **Single counterparty model for lend** — per-line counterparties work but are awkward; the common case of "I paid for X and Y owes me" is over-engineered
7. **No validation summary** — amounts aren't cross-checked before save

### New step-by-step flow

#### Step 1: Capture (unchanged)
Camera/gallery/file → OCR pipeline → extraction complete

#### Step 2: Source review
Edit vendor, date, invoice number, category, notes. Toggle line items on/off. This is the "verify what was extracted" step.

**Key change:** Add a "Receipt total vs. selected total" validation bar showing discrepancy if any.

#### Step 3: Money intent selection (NEW)

After reviewing the source data, the user classifies **how this money should be recorded**:

**Default (simplest path): "Personal expense"**
- All selected items → one personal expense transaction
- Amount = selected total
- One tap to save

**Option B: "Shared expense"**
- Opens group picker + member assignment
- Selected items assigned to members (per-line or bulk)
- Creates: one group expense + per-participant transactions
- User's share becomes their personal transaction with `effective_amount`

**Option C: "I paid, someone owes me" (Lend)**
- Opens counterparty picker
- Amount = selected total or per-line split
- Creates: one lend transaction + one personal expense with `effective_amount` = 0 (or partial)

**Option D: "Someone paid for me" (Borrow)**
- Counterparty picker
- Creates: one borrow transaction

**Option E: "Mixed bill" (NEW)**
- Opens line-item allocation panel
- Each line (or line group) gets assigned an intent: personal / group / lend / borrow
- Supports: "lines 1-3 are personal, lines 4-5 go to the group, line 6 is a lend to Bob"
- Most complex path — hidden behind "Advanced" or shown when user toggles multiple intents

**UX principle:** Progressive disclosure. Default is personal expense (one tap). Group/lend/borrow are switches. Mixed bill is an explicit mode.

#### Step 4: Allocation detail (conditional)

Only appears for non-personal paths:

**Group path:**
- Group picker (dropdown of user's groups)
- Member assignment: bulk "split equally" button, or per-line assignment
- Share preview: shows each member's computed share

**Lend path:**
- Counterparty picker (contacts, invites, or custom name)
- Lent amount (auto-filled from selected total)
- Due date (optional)

**Mixed path:**
- For each line item, a small chip/tag showing intent (Personal / Group:name / Lend:name)
- Tap chip to change allocation
- Summary at bottom

#### Step 5: Result preview (NEW — critical)

Before save, show a clear summary card:

```
┌────────────────────────────────────────┐
│  Review before saving                  │
│                                        │
│  Source: Pizzeria Roma (Receipt #4521) │
│  Date: 2026-04-11                      │
│                                        │
│  Transactions that will be created:    │
│  ✦ Personal expense: ₹250             │
│    (3 line items: Pizza, Coke, Salad) │
│                                        │
│  ✦ Group expense (Roommates): ₹350    │
│    Alice: ₹175 · Bob: ₹175           │
│    (2 items: Groceries, Cleaning)     │
│                                        │
│  ✦ Lend to Charlie: ₹200             │
│    (1 item: Books)                    │
│                                        │
│  Your effective spend: ₹425           │
│  (₹250 personal + ₹175 your share)   │
│                                        │
│  [Save as draft]          [Confirm ✓] │
└────────────────────────────────────────┘
```

This preview is non-negotiable. It solves the trust problem and prevents mis-saves.

#### Step 6: Save execution

On confirm:

1. **Begin logical operation** (wrap in try/catch with cleanup on failure)
2. Sync `invoice_items` with included items (existing behavior)
3. Update `documents` row with source data + status (existing behavior, now `source` role)
4. **Create `transactions` rows:**
   - Personal expense transaction(s) with `effective_amount` = personal portion
   - Group-related transaction with `effective_amount` = user's share
   - Lend transaction(s)
   - Borrow transaction(s)
5. If group intent: call `create_group_expense` RPC with `transaction_id`
6. If lend intent: insert `lend_borrow_entries` with `transaction_id`
7. **Create `activity_events`** for each created entity
8. Invalidate all relevant providers

#### Data flow diagram (new)

```
[OCR Extraction]
       │
       ▼
[ScanReviewPanel: Source Review]
       │
       ▼
[Money Intent Selection] ─── personal ──→ [1 transaction]
       │                  ── group ────→ [1 transaction + group_expense + participants]
       │                  ── lend ─────→ [1 transaction + lend_borrow_entry]
       │                  ── mixed ────→ [N transactions + optional group + optional lend]
       ▼
[Result Preview]
       │
       ▼
[Save] → documents (source)
       → transactions (1..N)
       → group_expenses (0..1) + participants
       → lend_borrow_entries (0..N)
       → activity_events (1..N)
```

### How one receipt becomes multiple structured finance outputs

**Example:** User scans a ₹800 grocery receipt with 6 items:
- Items 1-2: Personal groceries (₹300)
- Items 3-4: Roommate group groceries (₹350)  
- Item 5: Book borrowed for friend (₹150)

**Money intent:** Mixed bill

**Allocation:**
- Lines 1-2 → Personal
- Lines 3-4 → Group: "Roommates" → split equally (₹175 each)
- Line 5 → Lend to "Raj"

**Resulting records:**
1. `documents` row: vendor "BigBasket", amount ₹800, source evidence
2. `transactions` #1: type=expense, amount=₹300, effective_amount=₹300, source_type=scan
3. `transactions` #2: type=expense, amount=₹350, effective_amount=₹175, source_type=group_split, group_expense_id=X
4. `transactions` #3: type=lend, amount=₹150, effective_amount=₹0, source_type=scan, lend_borrow_id=Y
5. `group_expenses` row: title="BigBasket", amount=₹350, shares=[{user: me, ₹175}, {user: roommate, ₹175}]
6. `lend_borrow_entries` row: counterparty="Raj", amount=₹150, type=lent
7. `activity_events`: 3 events logged

**User's dashboard sees:** ₹475 effective spend (₹300 personal + ₹175 group share)

---

## SECTION 7 — SCREEN / NAVIGATION REWORK

### Final tab structure

| Tab | Label | Purpose | Primary Screen |
|-----|-------|---------|---------------|
| 0 | **Home** | Dashboard with spend overview, recent transactions, quick actions | `DashboardScreen` (reworked) |
| 1 | **Activity** | Unified chronological feed of all financial events | `ActivityScreen` (new, replaces Analytics tab) |
| 2 | **People** | Friends, groups, balances, settlements | `PeopleScreen` (reworked from SplitScreen) |
| 3 | **Plan** | Budgets, recurring bills, monthly overview | `PlanScreen` (new) |
| FAB | **+** | Scan, manual entry, or import | `CaptureSheet` (enhanced) |

**Settings moves** to a profile icon in the header (push route), not a tab. Settings is rarely accessed and doesn't deserve a tab slot.

### What current screens become

| Current Screen | Becomes |
|----------------|---------|
| `DashboardScreen` | Stays as Tab 0, reworked to read from `transactions` |
| `AnalyticsScreen` | Merged into Activity tab + insights accessible from Home |
| `SplitScreen` | Becomes `PeopleScreen` with enhanced group/balance view |
| `SettingsScreen` | Push route from header profile icon |
| `ScanScreen` | Stays, review panel enhanced per Section 6 |
| `DocumentsHistoryScreen` | Becomes `TransactionHistoryScreen` (rename + refactor) |
| `DocumentDetailScreen` | Becomes `TransactionDetailScreen` with source/allocation views |
| `DocumentEditScreen` | Stays for source editing, but transaction editing is separate |
| `GroupExpensesScreen` | Stays, enhanced with settlement confirmation + dispute |
| `ExportScreen` | Stays, reads from `transactions` |
| `ProfileScreen` | Stays, accessible from header |
| `AddExpenseSheet` | Enhanced to create transactions directly |

### New screens needed

| Screen | Purpose | Tab/Route |
|--------|---------|-----------|
| `ActivityScreen` | Chronological feed of all events across the system | Tab 1 |
| `PlanScreen` | Budget overview + recurring bills + monthly calendar | Tab 3 |
| `TransactionDetailScreen` | Shows transaction + linked source + allocations + history | Push |
| `BudgetDetailScreen` | Single budget: progress, history, category breakdown | Push from Plan |
| `BudgetCreateSheet` | Create/edit a budget | Bottom sheet from Plan |
| `RecurringDetailScreen` | Single recurring series: history, upcoming, edit | Push from Plan |
| `RecurringCreateSheet` | Create/edit a recurring series | Bottom sheet from Plan |
| `StatementImportScreen` | Upload + review statement file | Push from FAB or Plan |
| `StatementReviewScreen` | Review parsed rows, confirm/skip, map to transactions | Push |
| `DisputeScreen` | View/manage disputes on a group expense | Push from group detail |
| `SettlementConfirmScreen` | Confirm/reject a settlement request | Push from people/activity |

### Screens that should merge or split

- **Analytics + Document History → Activity tab** — The analytics insights become a card at the top of the activity feed; filtered document history becomes filtered transaction history in the same screen
- **Settings (tab) → Settings (push)** — Free up tab slot for Plan
- **SplitScreen → PeopleScreen** — Same purpose, better name, enhanced with balance summary across all groups

---

## SECTION 8 — FEATURE-BY-FEATURE PRODUCT REWORK PLAN

### 8.1 Dashboard / Home

**Current state:** Shows spend hero (this week vs last week), money flow chart, recent activity (documents), quick actions (scan, manual, export), OCR banner.

**Target state:** Shows spend overview (from `transactions.effective_amount`), budget progress bars (top 3 active budgets), upcoming recurring bills (next 7 days), recent transactions (last 10), quick actions.

**Changes required:**
- Replace `DashboardSpendMath` (reads documents) with `TransactionSpendMath` (reads transactions)
- Add budget progress cards (horizontal scroll, show category name + % used + amount)
- Add "Upcoming bills" section (next recurring occurrences)
- `RecentActivity` widget reads `transactions` instead of `documents`
- Remove OCR banner (scan is always accessible via FAB)

**Data implications:** New `TransactionService.dashboardSummary()` aggregates from `transactions` table. Server-side SQL for performance: `SUM(effective_amount)` grouped by date range and type.

**UX implications:** Dashboard becomes genuinely useful for "how am I doing this month" instead of just "what did I scan."

### 8.2 Activity / History

**Current state:** `AnalyticsScreen` with AI insights, trend charts, category breakdown, filtered document list. No unified timeline.

**Target state:** Single chronological feed showing all financial events. Filterable by type (personal, group, lend/borrow, recurring), by date range, by group. AI insights card at top (collapsible). Search/filter bar.

**Changes required:**
- New `ActivityScreen` replacing analytics tab
- New `activityFeedProvider` that fetches from `activity_events` + `transactions` (joined)
- AI insights card from current `AiInsightsPanel` (reuse widget)
- Filter chips: All | Personal | Groups | Lend/Borrow | Settlements
- Each feed item shows: icon, title, amount, timestamp, group/person badge if applicable

**Data implications:** `activity_events` table drives the feed. For performance: paginated fetch with cursor-based pagination.

### 8.3 Scan and OCR

**Current state:** Working scan pipeline with multi-image batch, PDF support, crop/rotate preview.

**Target state:** Same capture pipeline, enhanced review panel per Section 6, result preview before save, transaction creation on save.

**Changes required:**
- Rework `ScanReviewPanel` to add Money Intent step
- Add Result Preview step
- Update `_save()` to create `transactions` + `activity_events`
- Extract allocation logic into `AllocationService` (testable, reusable)

**Data implications:** Save now writes to `transactions` in addition to existing tables.

### 8.4 Documents (Sources)

**Current state:** `DocumentsHistoryScreen` is the primary history view. `DocumentDetailScreen` shows full document with edit capability.

**Target state:** Documents become "Sources" — they're evidence attached to transactions. The primary history view is transaction-based. Document detail is accessible from transaction detail as "View source."

**Changes required:**
- `DocumentsHistoryScreen` → `TransactionHistoryScreen` (or accessible as a filter in Activity)
- `DocumentDetailScreen` → still useful for viewing source/OCR data, but linked from transaction detail
- Transaction detail shows: transaction info + linked source card + allocations + activity history

### 8.5 Groups

**Current state:** Group creation, member management, group expenses with per-line assignment, settlements (basic insert).

**Target state:** Same group management + settlement confirmation flow + dispute capability + group activity feed + cross-group balance summary.

**Changes required:**
- `GroupExpensesScreen`: add settlement confirmation UI (pending/confirmed/rejected badges)
- Add dispute button on each group expense
- Add group activity feed section (reads `activity_events` filtered by `group_id`)
- `PeopleScreen`: add "Net balances" card showing cross-group totals per friend

**Data implications:** `group_settlements.status` column + `disputes` table.

### 8.6 Lend / Borrow

**Current state:** Create from scan review or standalone. Basic list in Split tab. Settle action marks as settled.

**Target state:** Same creation paths + transaction-linked + part of unified activity feed + settlement creates matching transaction + dispute support.

**Changes required:**
- Settlement action creates `transactions` row (type: `settlement_out` / `settlement_in`)
- Activity events logged on create/settle
- Display in People tab with clear "You owe" / "Owed to you" sections

### 8.7 Settlements

**Current state:** Insert-only. Creator records settlement. No confirmation from payee.

**Target state:** Two-phase: creator proposes settlement → payee confirms/rejects → confirmed settlement creates transaction.

**Changes required:**
- `group_settlements.status`: pending → confirmed/rejected
- Settlement creation: status = 'pending', activity event sent to payee
- Payee sees pending settlement in their activity feed
- Confirm action: updates status, creates `transactions` row, logs activity event
- Reject action: updates status, logs activity event, optionally opens dispute

### 8.8 Budgets (NEW)

**Current state:** Does not exist.

**Target state:** Users can create budgets per category or overall. Monthly/weekly periods. Progress tracking against `transactions`. Alerts when approaching/exceeding limit.

**Implementation plan:**
1. `budgets` + `budget_periods` tables (see Section 5)
2. `BudgetService` — CRUD + compute actuals from transactions
3. `budgetsProvider` — Riverpod state
4. `PlanScreen` shows active budgets with progress bars
5. `BudgetDetailScreen` shows history, transactions matching budget category
6. Dashboard shows top 3 budget progress cards
7. Budget alerts in activity feed when exceeded

### 8.9 Recurring Bills / Subscriptions (NEW)

**Current state:** Does not exist (GOAT version was removed).

**Target state:** Users can manually add recurring bills, or the system detects patterns from transactions. Calendar view of upcoming charges. Reminders.

**Implementation plan:**
1. `recurring_series` + `recurring_occurrences` tables (see Section 5)
2. `RecurringService` — CRUD + pattern detection + occurrence generation
3. `recurringProvider` — Riverpod state
4. `PlanScreen` shows upcoming bills (next 30 days)
5. `RecurringDetailScreen` shows occurrence history
6. Pattern detection: after N similar transactions to same vendor at similar intervals, suggest creating recurring series

### 8.10 Statement Import (NEW)

**Current state:** Does not exist (GOAT version was removed).

**Target state:** Users can upload CSV/Excel/PDF bank statements. System parses rows, user reviews and confirms, rows become transactions.

**Implementation plan:**
1. `statement_imports` table (see Section 5)
2. Storage bucket `statement-files`
3. `StatementParseService` — parse CSV/Excel (client-side for simple formats, Edge Function for PDF)
4. `StatementImportScreen` — upload + parse
5. `StatementReviewScreen` — paginated row review, each row: confirm (creates transaction), skip, edit amount/category
6. Duplicate detection: match by date + amount + vendor against existing transactions
7. Auto-categorization: reuse `resolveBestCategoryIdFromHints` + transaction history patterns

### 8.11 Linked Accounts (FUTURE)

**Current state:** `connected_apps` table exists but is unused.

**Target state:** Future phase. Users can link bank accounts (via aggregator API) for automatic transaction import.

**No immediate work needed.** The `accounts` table and `transactions.source_type = 'linked_account'` prepare the schema.

### 8.12 Net Worth (FUTURE)

**Current state:** Does not exist.

**Target state:** Future phase. Users add accounts (bank, credit card, loan, investment) with balances. System computes total assets - liabilities.

**No immediate work needed.** The `accounts` table is defined but implementation waits for Phase 4.

### 8.13 Settings / Privacy / Trust

**Current state:** Currency preference, profile, export, export history. No privacy controls, no trust settings.

**Target state:** Settings screen (push route) with sections: Account, Privacy & Data, Export, About.

**New settings needed:**
- Default currency (exists)
- Default category for manual entries
- Default split method (equal / by-line)
- Notification preferences (settlement requests, budget alerts, recurring reminders)
- Data: export all data, delete account
- Privacy: who can see your display name in groups

### 8.14 Export

**Current state:** Date range → PDF/CSV from documents. Export history tracked.

**Target state:** Same flow but reads from `transactions` instead of `documents`. Additional options: export by type (personal only, group only, all), export by group, export with source attachments.

**Changes required:**
- `ExportDocument` model → `ExportTransaction` model
- `PdfGenerator` / `CsvGenerator` adapt to new model
- Filter options: transaction type, group, category, date range

---

## SECTION 9 — PROVIDER / SERVICE / BACKEND EVOLUTION

### Providers that stay as-is

| Provider | Why |
|----------|-----|
| `profileProvider` | User profile doesn't change |
| `authStateProvider` | Auth is auth |
| `usageLimitsProvider` | Usage tracking stays |
| `connectionsNotifierProvider` | Social layer stays |
| `invitationsNotifierProvider` | Social layer stays |
| `expenseGroupsNotifierProvider` | Groups stay |

### Providers that need modification

| Provider | Changes |
|----------|---------|
| `documentsProvider` | Demote to source-tracking; dashboard no longer reads from it for spend calculations |
| `groupExpensesProvider` | Add `transaction_id` awareness; settlement confirmation state |
| `groupSettlementsProvider` | Add status field awareness; confirmation/rejection flows |
| `lendBorrowProvider` | Add `transaction_id` awareness; settlement creates transaction |
| `weekSpendBasisProvider` | Adapt to read from transactions instead of documents |

### New providers required

| Provider | Responsibility |
|----------|---------------|
| `transactionsProvider` | CRUD for `transactions` table. Primary ledger state. AsyncNotifier with pagination, filtering, search. |
| `activityFeedProvider` | Fetch `activity_events` with pagination. Filter by type, group, date. |
| `budgetsProvider` | CRUD for `budgets`. Compute actuals from transactions. |
| `budgetPeriodsProvider` | Fetch/compute budget period progress. |
| `recurringSeriesProvider` | CRUD for `recurring_series`. Pattern detection state. |
| `recurringOccurrencesProvider` | Upcoming occurrences feed. |
| `disputesProvider` | CRUD for `disputes`. Per-group dispute list. |
| `statementImportsProvider` | Statement import tracking. |
| `dashboardSummaryProvider` | Aggregated dashboard data from transactions (spend, budget progress, upcoming recurring). |

### SupabaseService evolution

**New method groups to add:**

```
// Transactions
fetchTransactions(filters, pagination) → List<Map>
fetchTransactionById(id) → Map
insertTransaction(data) → String (id)
updateTransaction(id, data) → void
voidTransaction(id) → void
transactionDashboardSummary(dateRange) → Map (aggregates)

// Activity
fetchActivityEvents(filters, pagination) → List<Map>
insertActivityEvent(data) → void

// Budgets
fetchBudgets() → List<Map>
insertBudget(data) → String
updateBudget(id, data) → void
deleteBudget(id) → void
fetchBudgetPeriods(budgetId) → List<Map>
computeBudgetActuals(budgetId, periodStart, periodEnd) → double

// Recurring
fetchRecurringSeries() → List<Map>
insertRecurringSeries(data) → String
updateRecurringSeries(id, data) → void
deleteRecurringSeries(id) → void
fetchUpcomingOccurrences(days) → List<Map>
confirmOccurrence(occurrenceId, transactionId) → void

// Disputes
fetchDisputesForGroup(groupId) → List<Map>
insertDispute(data) → String
updateDisputeStatus(id, status, notes) → void

// Statement imports
insertStatementImport(data) → String
updateStatementImportStatus(id, status) → void
fetchStatementImports() → List<Map>

// Settlements (enhanced)
confirmSettlement(settlementId) → void
rejectSettlement(settlementId) → void
```

### New service: `AllocationService`

Extract allocation logic from `ScanReviewPanel` into a testable service:

```dart
class AllocationService {
  // Compute group shares from line-item assignments
  static List<Map<String, dynamic>> computeGroupShares(
    List<LineItem> items,
    List<bool> lineOn,
    List<String?> lineAssignee,
    double targetTotal,
  );

  // Compute lend/borrow buckets from line-item assignments
  static List<LendBucket> computeLendBuckets(
    List<LineItem> items,
    List<bool> lineOn,
    List<LendLineConfig> lineConfig,
    String defaultCounterparty,
  );

  // Compute effective amount for user from group expense
  static double computeEffectiveAmount(
    double totalAmount,
    List<Map<String, dynamic>> shares,
    String currentUserId,
  );

  // Compute transactions from mixed-bill allocation
  static List<TransactionDraft> computeMixedBillTransactions(
    MixedBillAllocation allocation,
  );
}
```

### New service: `TransactionService`

```dart
class TransactionService {
  // Create transaction(s) from scan review
  static Future<List<String>> createFromScanReview({
    required String documentId,
    required ExtractedReceipt receipt,
    required AllocationResult allocation,
  });

  // Create transaction from manual entry
  static Future<String> createManual({
    required double amount,
    required String title,
    required DateTime date,
    String? categoryId,
  });

  // Create transaction from statement row
  static Future<String> createFromStatementRow({
    required String importId,
    required Map<String, dynamic> row,
  });

  // Dashboard aggregation
  static Future<Map<String, dynamic>> dashboardSummary({
    required String userId,
    required DateRange range,
  });
}
```

### Event logging requirements

Every write operation should create an `activity_events` row. Implement as a helper:

```dart
class ActivityLogger {
  static Future<void> log({
    required String eventType,
    required String summary,
    String? targetUserId,
    String? groupId,
    String? transactionId,
    String? entityType,
    String? entityId,
    Map<String, dynamic>? details,
    Map<String, dynamic>? previousState,
    String visibility = 'private',
  });
}
```

Called from: `TransactionService`, settlement actions, dispute actions, group CRUD, lend/borrow CRUD.

---

## SECTION 10 — MIGRATION + BACKFILL STRATEGY

### Migration order

1. **Create `transactions` table** — no FKs to new tables yet, only existing FKs
2. **Create `activity_events` table**
3. **Create `disputes` table**
4. **Create `budgets` + `budget_periods` tables**
5. **Create `recurring_series` + `recurring_occurrences` tables**
6. **Create `statement_imports` table**
7. **Create `accounts` table**
8. **Alter `group_settlements`** — add `status`, `confirmed_at`, `transaction_id`
9. **Alter `lend_borrow_entries`** — add `transaction_id`
10. **Alter `group_expenses`** — add `transaction_id`
11. **Backfill `transactions` from `documents`**
12. **Backfill `transactions` from `group_expenses`**
13. **Backfill `transactions` from `lend_borrow_entries`**
14. **Drop `splits` + `split_participants`** (dead tables)

### Backfill strategy

**Phase 1: `documents` → `transactions`**

```sql
INSERT INTO transactions (user_id, amount, currency, date, type, title, description,
  category_id, category_source, source_type, source_document_id, effective_amount, status,
  extracted_data, created_at, updated_at)
SELECT 
  d.user_id,
  d.amount,
  coalesce(d.currency, 'INR'),
  d.date::date,
  'expense',
  d.vendor_name,
  d.description,
  d.category_id,
  d.category_source,
  CASE 
    WHEN d.extracted_data->>'invoice_id' IS NOT NULL THEN 'scan'
    ELSE 'manual'
  END,
  d.id,
  d.amount, -- effective_amount = full amount initially
  CASE d.status WHEN 'draft' THEN 'draft' ELSE 'confirmed' END,
  d.extracted_data,
  d.created_at,
  d.updated_at
FROM documents d
WHERE d.status != 'deleted';
```

**Phase 2: Link `group_expenses` to transactions**

```sql
UPDATE group_expenses ge
SET transaction_id = t.id
FROM transactions t
WHERE t.source_document_id = ge.document_id
  AND t.source_document_id IS NOT NULL;
```

For group expenses without document links, create new transactions:

```sql
INSERT INTO transactions (user_id, amount, currency, date, type, title,
  source_type, group_id, group_expense_id, effective_amount, status, created_at)
SELECT
  ge.paid_by_user_id,
  ge.amount,
  'INR',
  ge.expense_date,
  'expense',
  ge.title,
  'group_split',
  ge.group_id,
  ge.id,
  coalesce((SELECT gep.share_amount FROM group_expense_participants gep 
    WHERE gep.expense_id = ge.id AND gep.user_id = ge.paid_by_user_id), ge.amount),
  'confirmed',
  ge.created_at
FROM group_expenses ge
WHERE ge.transaction_id IS NULL;
```

**Phase 3: Link `lend_borrow_entries` to transactions**

```sql
UPDATE lend_borrow_entries lb
SET transaction_id = t.id
FROM transactions t
WHERE t.source_document_id = lb.document_id
  AND lb.document_id IS NOT NULL;
```

For entries without document links:

```sql
INSERT INTO transactions (user_id, amount, currency, date, type, title,
  source_type, lend_borrow_id, effective_amount, status, created_at)
SELECT
  lb.user_id,
  lb.amount,
  'INR',
  lb.created_at::date,
  CASE lb.type WHEN 'lent' THEN 'lend' ELSE 'borrow' END,
  lb.counterparty_name,
  'manual',
  lb.id,
  0, -- lend/borrow effective = 0 personal spend
  CASE WHEN lb.settled THEN 'confirmed' ELSE 'confirmed' END,
  lb.created_at
FROM lend_borrow_entries lb
WHERE lb.transaction_id IS NULL;
```

### Compatibility strategy

- **Phase 1 deploys:** `transactions` table created, backfilled. New Flutter code writes to both `documents` AND `transactions`. Old code continues reading `documents`.
- **Phase 2 deploys:** Dashboard and history screens switched to read from `transactions`. `documents` becomes read-only for new code (only written via scan pipeline for source evidence).
- **Phase 3 deploys:** All remaining reads migrated from `documents` to `transactions`.
- **Phase 4:** `documents` table kept as source evidence storage; amount/date/category columns become redundant (data lives in `transactions`), but retained for backward compatibility.

### What should not be broken

- Existing document history and detail views must work throughout migration
- Group expense shares and settlements must remain accurate
- Lend/borrow entries must remain visible
- Export must continue working (reads from `transactions` after cutover)
- OCR pipeline remains unchanged (writes to `invoices` → review panel creates `transactions`)

### Rollout safety

- Feature flag on `profiles` table or local config: `use_transactions_ledger` boolean
- When true: dashboard/history reads from `transactions`
- When false: falls back to `documents`
- Gradual rollout: enable for test accounts → percentage → all users

---

## SECTION 11 — TRUST, PERMISSIONS, AND USER SAFETY LAYER

### Edit history

Every update to a `transaction`, `group_expense`, or `lend_borrow_entry` creates an `activity_events` row with `previous_state` JSONB containing the pre-edit snapshot. This provides full audit trail without a separate versions table.

**Implementation:**
- Before any update, fetch current row
- Store as `previous_state` in the activity event
- New state is the live row after update

**User-facing:** Transaction detail screen shows "History" section with chronological changes. Each entry shows: who changed, when, what fields changed (diff computed client-side from `previous_state` and `details`).

### Soft delete vs hard delete

- **Transactions:** soft delete via `status = 'voided'`. Never hard-delete. Voided transactions show in activity feed as "Voided: [title]" with strikethrough.
- **Documents:** keep current behavior (hard delete removes source). Consider moving to soft delete (add `deleted_at` column) if source evidence preservation is needed.
- **Group expenses:** soft delete (set `voided` flag) with activity event. Participants see the change.
- **Lend/borrow:** soft delete (settle or void). Never lose the record.

### Activity feed

The `activity_events` table powers two views:

1. **Personal activity feed** (Activity tab): All events where `user_id` = me or `target_user_id` = me or I'm a member of `group_id`
2. **Group activity feed** (Group detail screen): All events where `group_id` = this group

**Event types and their display:**

| Event | Icon | Summary template |
|-------|------|-----------------|
| `transaction_created` | ✦ | "Added ₹500 expense at BigBazaar" |
| `transaction_updated` | ✎ | "Updated dinner expense: ₹450 → ₹500" |
| `transaction_voided` | ✕ | "Voided ₹200 grocery expense" |
| `group_expense_created` | 👥 | "Alice added ₹800 dinner (your share: ₹200)" |
| `settlement_created` | 💸 | "Bob sent ₹500 settlement (awaiting confirmation)" |
| `settlement_confirmed` | ✓ | "You confirmed ₹500 settlement from Bob" |
| `settlement_rejected` | ✕ | "Alice rejected settlement — reason: wrong amount" |
| `dispute_opened` | ⚠ | "Bob disputed ₹200 dinner charge" |
| `dispute_resolved` | ✓ | "Dispute on dinner charge resolved" |
| `budget_exceeded` | ! | "Food budget exceeded: ₹5,200 / ₹5,000" |
| `recurring_due` | 📅 | "Netflix subscription due tomorrow: ₹649" |

### Disputes

**Flow:**
1. Group member opens dispute on a group expense → `disputes` row created, `status = 'open'`
2. Activity event logged, visible to all group members
3. Expense creator sees dispute notification
4. Creator can: adjust the expense (update amount/shares) → dispute auto-resolves, or respond with notes
5. Disputed transactions show a yellow badge in all views
6. Resolution: creator or any group admin marks dispute as resolved with notes

### Settlement confirmation

**Flow:**
1. Payer creates settlement → `group_settlements` row, `status = 'pending'`
2. Activity event sent to payee
3. Payee sees pending settlement in activity feed and People tab
4. Payee confirms → `status = 'confirmed'`, `confirmed_at` set, transaction created, balances updated
5. Payee rejects → `status = 'rejected'`, activity event logged, payer notified

**UX:** Pending settlements show a yellow "Awaiting confirmation" badge. Confirmed show green check. Rejected show red X with link to reason.

### Permission clarity

- **Group expenses:** Only group members can see group data (existing RLS)
- **Settlements:** Only payer/payee pair within group context
- **Disputes:** Visible to all group members (transparency)
- **Lend/borrow:** Visible to both parties if linked by `counterparty_user_id`
- **Transactions:** Always private to the user (own `user_id`) except when shared via group expense

### Data trust screens

- **Transaction detail:** Shows source (scan image, manual entry, import), creation timestamp, last modified, edit history count
- **Group detail:** Shows member list, join date, total expenses, total settlements, any open disputes
- **Settlement detail:** Shows creation time, confirmation time, payer/payee display names, linked transaction

### Onboarding permission strategy

On first app open after update:
1. Brief explanation: "Billy now tracks all your money in one place"
2. Existing data has been migrated (show count: "X transactions from your documents")
3. New features available: Budgets, Recurring bills
4. No destructive permissions needed — all data stays

---

## SECTION 12 — PHASED IMPLEMENTATION ROADMAP

### Phase 1: Foundation (Weeks 1-4)

**Goal:** Introduce `transactions` table, backfill existing data, create new providers/services, update scan review flow.

**Deliverables:**
1. SQL migration: `transactions` table + indexes + RLS
2. SQL migration: `activity_events` table + indexes + RLS
3. Backfill migration: documents → transactions, link group_expenses + lend_borrow
4. SQL migration: drop `splits` + `split_participants`
5. `TransactionService` + `AllocationService` Dart implementations
6. `transactionsProvider` Riverpod provider
7. `ActivityLogger` helper
8. Reworked `ScanReviewPanel` with Money Intent + Result Preview
9. Updated `_save()` to create transactions
10. `AddExpenseSheet` → creates transaction + document

**Dependencies:** None — builds on existing schema.

**Ship first:** Migrations (#1-4), then services (#5-7), then UI (#8-10).

**Why this order:** The table must exist before code writes to it. Services must exist before UI calls them. Backfill must run before UI reads from transactions.

### Phase 2: Trust Layer (Weeks 5-7)

**Goal:** Settlement confirmation, disputes, edit history, activity feed.

**Deliverables:**
1. SQL migration: alter `group_settlements` (status, confirmed_at, transaction_id)
2. SQL migration: `disputes` table
3. Settlement confirmation flow (UI + backend)
4. Dispute creation + resolution flow
5. `ActivityScreen` (new Tab 1, replaces Analytics)
6. `activityFeedProvider`
7. Transaction detail screen with history section
8. Group activity feed in `GroupExpensesScreen`

**Dependencies:** Phase 1 (transactions + activity_events must exist).

**Why this order:** Trust features need the canonical ledger and activity logging from Phase 1.

### Phase 3: Planning Layer (Weeks 8-11)

**Goal:** Budgets, recurring bills, new Plan tab, dashboard enhancement.

**Deliverables:**
1. SQL migration: `budgets` + `budget_periods`
2. SQL migration: `recurring_series` + `recurring_occurrences`
3. `BudgetService` + `budgetsProvider`
4. `RecurringService` + `recurringSeriesProvider`
5. `PlanScreen` (new Tab 3)
6. `BudgetDetailScreen` + `BudgetCreateSheet`
7. `RecurringDetailScreen` + `RecurringCreateSheet`
8. Dashboard: budget progress cards + upcoming bills section
9. Recurring pattern detection from transactions

**Dependencies:** Phase 1 (transactions table must exist for budget actuals computation).

**Why this order:** Planning features read from the canonical ledger. They don't depend on trust layer (Phase 2) but need accurate transaction data (Phase 1).

### Phase 4: Import & Accounts (Weeks 12-16)

**Goal:** Statement import, accounts for net worth, linked accounts preparation.

**Deliverables:**
1. SQL migration: `statement_imports` + storage bucket
2. SQL migration: `accounts`
3. `StatementParseService` (CSV/Excel client-side parsing)
4. `StatementImportScreen` + `StatementReviewScreen`
5. Duplicate detection logic
6. `AccountsScreen` with manual balance entry
7. Net worth calculation view
8. Linked accounts infrastructure (API key management, connected_apps activation)

**Dependencies:** Phase 1 (transactions are the target of statement import).

### Phase 5: Polish & Growth (Weeks 17-20)

**Goal:** UX polish, performance optimization, navigation rework, comprehensive export.

**Deliverables:**
1. Navigation restructure: 4-tab layout (Home, Activity, People, Plan) + Settings as push
2. `TransactionHistoryScreen` replacing document history as primary
3. Dashboard performance: server-side aggregation queries
4. Enhanced export with transaction-based filtering
5. Search across transactions (full-text on title + description)
6. Notification system (budget alerts, settlement requests, recurring reminders)
7. Onboarding flow for new tab structure
8. Empty states for all new features
9. Error handling and edge case polish

**Dependencies:** All previous phases.

**Why last:** Polish requires all features to exist. Navigation rework should happen when all screens are built.

---

## SECTION 13 — DETAILED NEXT STEPS

### Immediate next 10 product decisions

1. **Confirm `transactions` table schema** — review column types, constraints, enum values with team
2. **Decide on `effective_amount` semantics** — is it always the user's out-of-pocket? Or the portion that counts as personal spend?
3. **Decide on mixed-bill UX** — should it be a separate mode or an extension of the current group/lend toggles?
4. **Decide on settlement confirmation** — is two-phase required for launch, or can it be added after?
5. **Decide on tab restructure timing** — should 4-tab layout ship in Phase 1 or Phase 5?
6. **Decide on feature flags** — use `profiles` column or local config for gradual rollout?
7. **Decide on activity feed scope** — group-only events, or all personal events too?
8. **Decide on budget period** — fixed calendar month, or rolling 30 days?
9. **Decide on recurring detection** — manual-only first, or ship with pattern detection?
10. **Decide on document table fate** — keep writing to both tables indefinitely, or sunset `documents` amount column?

### Immediate next 10 engineering tasks

1. Write SQL migration for `transactions` table with all indexes and RLS
2. Write SQL migration for `activity_events` table
3. Write backfill migration (documents → transactions)
4. Write backfill migration (group_expenses → transactions link)
5. Write backfill migration (lend_borrow → transactions link)
6. Implement `TransactionService` with CRUD methods in `SupabaseService`
7. Implement `transactionsProvider` Riverpod AsyncNotifier
8. Implement `AllocationService` extracted from `ScanReviewPanel`
9. Implement `ActivityLogger` utility
10. Write migration to drop `splits` + `split_participants` tables

### Immediate next 10 UX/design tasks

1. Design the Money Intent selection step for scan review (wireframe the 4 paths)
2. Design the Result Preview card (what information, layout, hierarchy)
3. Design the Transaction Detail screen (source card, allocations section, history section)
4. Design the Activity Feed item layout (icon, title, amount, timestamp, badges)
5. Design the Settlement Confirmation UX (pending badge, confirm/reject buttons, notification)
6. Design the Budget Progress card for dashboard (circular progress, amount, category color)
7. Design the Plan tab layout (budgets section, recurring section, monthly calendar)
8. Design the Dispute flow (open dispute sheet, resolution view)
9. Design the 4-tab bottom navigation layout
10. Design empty states for: Activity feed, Budgets, Recurring, Statement imports

### Immediate next 10 backend/data tasks

1. **SQL-migrate first:** `transactions` table — this unblocks everything
2. **SQL-migrate second:** `activity_events` table — needed by all write operations
3. **SQL-migrate third:** Backfill documents → transactions
4. **SQL-migrate fourth:** Alter `group_settlements` (add status + transaction_id)
5. **SQL-migrate fifth:** Alter `lend_borrow_entries` (add transaction_id)
6. **SQL-migrate sixth:** Alter `group_expenses` (add transaction_id)
7. **SQL-migrate seventh:** Backfill group_expenses + lend_borrow → transactions links
8. **SQL-migrate eighth:** Drop `splits` + `split_participants`
9. Write server-side dashboard aggregation function (`transaction_dashboard_summary` RPC)
10. Update `create_group_expense` RPC to accept and store `transaction_id`

### What should be prototyped first

1. Money Intent selection UI in scan review — this is the most complex new interaction
2. Result Preview card — validates that users understand what will be created
3. Transaction Detail screen — validates the new information architecture

### What should be SQL-migrated first

1. `transactions` — unblocks all new code
2. `activity_events` — needed for trust layer
3. Backfill — makes existing data available in new format
4. `group_settlements` alter — enables settlement confirmation

### What should be left for later

- Linked accounts (Phase 4+)
- Net worth calculations (Phase 4+)
- Recurring pattern auto-detection (Phase 3, but manual-first is fine)
- Statement import via email (future — upload-only first)
- Advanced analytics (AI insights are already working; enhance after migration)
- Push notifications (depends on FCM setup; activity feed is the in-app substitute)
- Multi-currency conversion (complexity explosion; handle after core is solid)

---

## SECTION 14 — FINAL RECOMMENDED PRODUCT PRINCIPLE

> **Every financial event is a transaction. Every transaction has a source. Every source is captured once, classified once, and allocated once. The system guarantees: scan it once, see it everywhere it matters — your personal ledger, your group splits, your IOUs, your budgets, your recurring patterns — all traced back to one truth.**

This principle means:
- **No duplicate data entry.** One scan, one save, many outputs.
- **No hidden side effects.** The user previews every financial outcome before confirming.
- **No trust gaps.** Every action is logged, every edit is tracked, every settlement is confirmed.
- **No orphaned money.** Every dollar flows through the canonical `transactions` table, making dashboard totals, budget tracking, and net worth calculations accurate by construction.
- **No architectural dead ends.** Statement imports, linked accounts, and future features all write to the same `transactions` table through the same allocation engine.

Build every feature, every screen, and every migration with this principle as the test: *"Does this flow through the canonical ledger? Can the user trace it back to its source? Can they see the preview before committing?"* If the answer to all three is yes, the feature belongs in Billy.
