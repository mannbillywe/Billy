# Billy — Database Schema (Frontend-Relevant Tables)

All tables have RLS enabled and are user-scoped. The frontend accesses them via `Supabase.instance.client.from('table_name')`.

---

## Core Ledger

### `transactions` — The canonical financial event table

Every money movement in the system is a transaction. This is the primary table the frontend should read from for spend data, history, and aggregation.

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `user_id` | uuid | FK → profiles |
| `amount` | numeric(12,2) | Full amount (e.g., $100 dinner total) |
| `currency` | text | Default 'INR' |
| `date` | date | Transaction date |
| `type` | text | `expense`, `income`, `transfer`, `lend`, `borrow`, `settlement_out`, `settlement_in`, `refund`, `recurring` |
| `title` | text | Display name (vendor or description) |
| `description` | text | Optional detail |
| `category_id` | uuid | FK → categories |
| `category_source` | text | `manual`, `ai`, `rule`, `import`, `legacy` |
| `payment_method` | text | Optional |
| `source_type` | text | `scan`, `manual`, `statement`, `group_split`, `settlement`, `recurring`, `linked_account`, `system` |
| `source_document_id` | uuid | FK → documents (if from scan) |
| `source_import_id` | uuid | FK → statement_imports (if from import) |
| `effective_amount` | numeric(12,2) | User's actual share (e.g., $25 of $100 shared dinner) |
| `group_id` | uuid | FK → expense_groups |
| `group_expense_id` | uuid | FK → group_expenses |
| `lend_borrow_id` | uuid | FK → lend_borrow_entries |
| `settlement_id` | uuid | FK → group_settlements |
| `status` | text | `draft`, `confirmed`, `pending`, `voided`, `disputed` |
| `is_recurring` | boolean | Default false |
| `recurring_series_id` | uuid | FK → recurring_series |
| `account_id` | uuid | FK → accounts |
| `counter_account_id` | uuid | FK → accounts (for transfers) |
| `notes` | text | User notes |
| `tags` | text[] | Flexible tag array |
| `extracted_data` | jsonb | OCR/import metadata |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

**Key queries for frontend:**
- Dashboard spend: `SUM(effective_amount) WHERE type='expense' AND status='confirmed'`
- Recent activity: `ORDER BY date DESC LIMIT 10`
- Filter by type, group, category, date range

---

## Source / Evidence

### `documents` — Scanned receipts and manual entries (source evidence)

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `user_id` | uuid | FK → profiles |
| `vendor_name` | text | |
| `amount` | numeric | Receipt total |
| `currency` | text | |
| `date` | text | ISO date string |
| `description` | text | Category/description |
| `category_id` | uuid | FK → categories |
| `category_source` | text | |
| `status` | text | `draft`, `saved`, `deleted` |
| `extracted_data` | jsonb | OCR extraction payload |
| `created_at` | timestamptz | |
| `updated_at` | timestamptz | |

### `invoices` — OCR-extracted invoice headers

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `user_id` | uuid | |
| `vendor_name` | text | |
| `invoice_number` | text | |
| `total_amount` | numeric | |
| `tax_amount` | numeric | |
| `status` | text | `uploading`, `processing`, `ready`, `failed` |
| `storage_path` | text | Supabase Storage path |

### `invoice_items` — Line items from OCR

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `invoice_id` | uuid | FK → invoices |
| `description` | text | |
| `quantity` | numeric | |
| `unit_price` | numeric | |
| `total` | numeric | |
| `included` | boolean | Whether user included this item |

---

## Social / Groups

### `expense_groups` — Shared expense groups

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `name` | text | Group display name |
| `created_by` | uuid | FK → profiles |
| `created_at` | timestamptz | |

### `expense_group_members`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `group_id` | uuid | FK → expense_groups |
| `user_id` | uuid | FK → profiles |
| `display_name` | text | |
| `role` | text | `admin`, `member` |

### `group_expenses` — Shared expenses in groups

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `group_id` | uuid | FK → expense_groups |
| `paid_by_user_id` | uuid | Who paid |
| `title` | text | |
| `amount` | numeric | Total |
| `expense_date` | date | |
| `document_id` | uuid | FK → documents |
| `transaction_id` | uuid | FK → transactions |

### `group_expense_participants` — Per-user shares

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `expense_id` | uuid | FK → group_expenses |
| `user_id` | uuid | FK → profiles |
| `share_amount` | numeric | This person's share |

### `group_settlements` — Payment settlements

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `group_id` | uuid | FK → expense_groups |
| `paid_by` | uuid | FK → profiles |
| `paid_to` | uuid | FK → profiles |
| `amount` | numeric | |
| `status` | text | `pending`, `confirmed`, `rejected` |
| `confirmed_at` | timestamptz | |
| `transaction_id` | uuid | FK → transactions |

### `lend_borrow_entries` — IOUs between users

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `user_id` | uuid | Owner |
| `counterparty_name` | text | |
| `counterparty_user_id` | uuid | FK → profiles (if connected) |
| `amount` | numeric | |
| `type` | text | `lent` or `borrowed` |
| `settled` | boolean | |
| `document_id` | uuid | FK → documents |
| `transaction_id` | uuid | FK → transactions |

### `user_connections` — Confirmed friendships

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `user_a` | uuid | FK → profiles |
| `user_b` | uuid | FK → profiles |
| `created_at` | timestamptz | |

### `contact_invitations` — Pending friend invitations

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `from_user_id` | uuid | |
| `to_email` | text | |
| `status` | text | `pending`, `accepted`, `declined` |

---

## Activity & Trust

### `activity_events` — Chronological audit trail

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `user_id` | uuid | Event owner |
| `event_type` | text | See list below |
| `actor_user_id` | uuid | Who performed the action |
| `target_user_id` | uuid | Who was affected |
| `group_id` | uuid | FK → expense_groups |
| `transaction_id` | uuid | FK → transactions |
| `entity_type` | text | `transaction`, `group_expense`, `settlement`, etc. |
| `entity_id` | uuid | Generic FK |
| `summary` | text | Human-readable description |
| `details` | jsonb | Structured metadata |
| `previous_state` | jsonb | Pre-edit snapshot (for history) |
| `visibility` | text | `private`, `group`, `public` |
| `created_at` | timestamptz | |

**Event types:** `transaction_created`, `transaction_updated`, `transaction_voided`, `transaction_disputed`, `group_expense_created`, `group_expense_updated`, `group_expense_deleted`, `settlement_created`, `settlement_confirmed`, `settlement_rejected`, `lend_created`, `borrow_created`, `lend_settled`, `borrow_settled`, `group_member_added`, `group_member_removed`, `budget_created`, `budget_exceeded`, `recurring_detected`, `recurring_due`, `dispute_opened`, `dispute_resolved`, `document_scanned`, `statement_imported`

### `disputes` — Contest shared charges

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `user_id` | uuid | Who opened the dispute |
| `entity_type` | text | `group_expense`, `settlement`, `lend_borrow` |
| `entity_id` | uuid | |
| `group_id` | uuid | |
| `transaction_id` | uuid | |
| `reason` | text | |
| `proposed_amount` | numeric | |
| `status` | text | `open`, `acknowledged`, `resolved`, `withdrawn` |
| `resolved_by` | uuid | |
| `resolution_notes` | text | |

---

## Planning

### `budgets` — Spending limits by category or total

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `user_id` | uuid | |
| `name` | text | |
| `category_id` | uuid | FK → categories (null = total budget) |
| `amount` | numeric(12,2) | Budget limit |
| `period` | text | `weekly`, `monthly`, `yearly` |
| `currency` | text | Default 'INR' |
| `rollover_enabled` | boolean | |
| `is_active` | boolean | |
| `start_date` | date | |
| `end_date` | date | null = ongoing |

### `budget_periods` — Track actuals per budget per period

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `budget_id` | uuid | FK → budgets |
| `user_id` | uuid | |
| `period_start` | date | |
| `period_end` | date | |
| `spent` | numeric(12,2) | |
| `rollover_amount` | numeric(12,2) | |

### `recurring_series` — Known recurring charges

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `user_id` | uuid | |
| `title` | text | e.g., "Netflix" |
| `amount` | numeric(12,2) | |
| `currency` | text | |
| `category_id` | uuid | |
| `cadence` | text | `daily`, `weekly`, `biweekly`, `monthly`, `quarterly`, `yearly` |
| `anchor_date` | date | First occurrence |
| `next_due` | date | |
| `detection_source` | text | `manual`, `pattern`, `statement` |
| `is_active` | boolean | |
| `auto_confirm` | boolean | |
| `remind_days_before` | integer | Default 1 |

### `recurring_occurrences` — Individual instances

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `series_id` | uuid | FK → recurring_series |
| `user_id` | uuid | |
| `due_date` | date | |
| `actual_amount` | numeric(12,2) | |
| `transaction_id` | uuid | FK → transactions |
| `status` | text | `upcoming`, `confirmed`, `missed`, `skipped` |

### `statement_imports` — Bank statement uploads

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `user_id` | uuid | |
| `file_path` | text | Storage path |
| `file_name` | text | |
| `status` | text | `uploaded`, `processing`, `review`, `completed`, `failed` |
| `row_count` | integer | |
| `imported_count` | integer | |

### `statement_import_rows` — Individual parsed rows

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `import_id` | uuid | FK → statement_imports |
| `row_index` | integer | |
| `parsed_date` | date | |
| `cleaned_description` | text | |
| `parsed_amount` | numeric(12,2) | |
| `debit_or_credit` | text | `debit`, `credit` |
| `review_status` | text | `pending`, `accepted`, `ignored`, `duplicate`, `needs_review` |
| `created_transaction_id` | uuid | FK → transactions |

---

## User & Config

### `profiles`

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK, matches auth.users |
| `display_name` | text | |
| `email` | text | |
| `preferred_currency` | text | Default 'INR' |
| `avatar_url` | text | |

### `categories` — Expense categories

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `user_id` | uuid | null = global |
| `name` | text | |
| `icon` | text | |
| `color` | text | Hex color |
| `is_default` | boolean | |

### `user_usage_limits` — OCR/refresh quotas

| Column | Type | Notes |
|--------|------|-------|
| `user_id` | uuid | PK |
| `ocr_scans_used` | integer | |
| `ocr_scans_limit` | integer | |
| `insight_refreshes_used` | integer | |
| `insight_refreshes_limit` | integer | |

### `accounts` — Financial accounts (future: net worth)

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `user_id` | uuid | |
| `name` | text | |
| `type` | text | `checking`, `savings`, `credit_card`, `cash`, `investment`, `loan`, `other` |
| `institution` | text | |
| `current_balance` | numeric(14,2) | |
| `is_asset` | boolean | false for credit cards, loans |
| `is_active` | boolean | |

### `ai_suggestions` — AI-powered suggestions inbox

| Column | Type | Notes |
|--------|------|-------|
| `id` | uuid | PK |
| `user_id` | uuid | |
| `suggestion_type` | text | `category`, `merchant_normalize`, `recurring_detect`, `duplicate_warning`, etc. |
| `title` | text | |
| `description` | text | |
| `confidence` | numeric(3,2) | 0-1 |
| `suggested_action` | jsonb | |
| `status` | text | `pending`, `accepted`, `dismissed`, `snoozed`, `expired` |
