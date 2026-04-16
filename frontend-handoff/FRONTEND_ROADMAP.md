# Billy — Frontend Roadmap

What needs to be built or improved on the frontend, ordered by priority.

---

## Priority 1: Core Transaction Experience

### 1.1 Transaction Detail Screen Enhancement
**Location:** `lib/features/transactions/screens/transaction_detail_screen.dart`
**Status:** Exists but basic

**Needs:**
- Source card (link to document/scan image if `source_document_id` exists)
- Allocation section (show effective_amount vs total, group split details if group transaction)
- Edit history section (fetch `activity_events` WHERE `entity_type='transaction' AND entity_id=this.id`)
- Void button (soft delete via `status='voided'`)
- Link to related group expense, lend/borrow entry if applicable

### 1.2 Transaction History Screen
**Location:** Should replace/enhance `lib/features/documents/screens/documents_history_screen.dart`

**Needs:**
- Read from `transactions` table instead of `documents`
- Filter chips: All | Expenses | Income | Lend | Borrow | Settlements
- Date range filter
- Category filter
- Search by title/description
- Pagination (load more on scroll)
- Each item shows: icon (from type), title, effective_amount, date, type badge

### 1.3 Dashboard Transition to Transactions
**Location:** `lib/features/dashboard/screens/dashboard_screen.dart`

**Needs:**
- Recent activity should show transactions (not documents)
- Spend calculations should use `transactions.effective_amount` WHERE `type='expense' AND status='confirmed'`
- Keep existing budget and recurring sections (they already work)

---

## Priority 2: Activity Feed

### 2.1 Activity Screen Enhancement
**Location:** `lib/features/activity/screens/activity_screen.dart`

**Needs:**
- Fetch from `activity_events` table, paginated, ordered by `created_at DESC`
- Filter chips: All | Personal | Groups | Lend/Borrow | Settlements | Budget Alerts
- Each event item shows:
  - Icon based on `event_type` (see icon map below)
  - Summary text
  - Timestamp (relative: "2h ago", "Yesterday", etc.)
  - Group badge if `group_id` present
  - Amount if transaction-related
  - Tap to navigate to related entity
- AI insights card at top (reuse existing `AiInsightsPanel` from analytics)

**Event type → Icon mapping:**
| Event | Icon |
|-------|------|
| `transaction_created` | Icons.add_circle_outline |
| `transaction_updated` | Icons.edit_outlined |
| `transaction_voided` | Icons.cancel_outlined |
| `group_expense_created` | Icons.group_add_rounded |
| `settlement_created` | Icons.payment_rounded |
| `settlement_confirmed` | Icons.check_circle_outline |
| `settlement_rejected` | Icons.cancel_rounded |
| `dispute_opened` | Icons.warning_amber_rounded |
| `dispute_resolved` | Icons.handshake_rounded |
| `budget_exceeded` | Icons.trending_up_rounded |
| `recurring_due` | Icons.event_rounded |

### 2.2 Activity Feed Provider
**Location:** `lib/providers/activity_feed_provider.dart`

**Needs:**
- `AsyncNotifier` with pagination support
- Filter by event type, group, date range
- Fetch from `activity_events` ordered by `created_at DESC`
- Support cursor-based pagination (fetch next page from last seen `created_at`)

---

## Priority 3: Planning Features

### 3.1 Budget Detail Screen (NEW)
**Location:** `lib/features/planning/screens/budget_detail_screen.dart`

**What it shows:**
- Budget name, amount, period, category
- Circular progress indicator (spent / budget amount)
- Spending breakdown (if category budget: list transactions matching that category this period)
- Historical periods (last 3-6 months, bar chart or list showing spent per period)
- Edit / Delete actions

### 3.2 Recurring Detail Screen (NEW)
**Location:** `lib/features/planning/screens/recurring_detail_screen.dart`

**What it shows:**
- Series info: title, amount, cadence, next due date
- Occurrence history (list of past occurrences with status: confirmed/missed/skipped)
- Upcoming occurrences (next 3-6)
- Link to matched transaction for confirmed occurrences
- Edit / Pause / Delete actions

### 3.3 Plan Screen Enhancement
**Location:** `lib/features/planning/screens/plan_screen.dart`

**Needs:**
- Budget section: list of active budgets with progress bars, tap → BudgetDetailScreen
- Recurring section: list of active recurring series, tap → RecurringDetailScreen
- Monthly calendar view (future) showing upcoming bills on dates
- Empty states with CTAs to create first budget / recurring item

---

## Priority 4: Statement Import (NEW screens)

### 4.1 Statement Import Screen
**Location:** `lib/features/statements/screens/statement_import_screen.dart`

**Flow:**
1. File picker (CSV, PDF)
2. Upload to Supabase Storage
3. Create `statement_imports` row
4. Parse file (CSV client-side, PDF via Edge Function)
5. Show parsed row count, navigate to review

### 4.2 Statement Review Screen
**Location:** `lib/features/statements/screens/statement_review_screen.dart`

**Flow:**
1. List parsed rows from `statement_import_rows`
2. Each row shows: date, description, amount, debit/credit, suggested category
3. Actions per row: Accept (creates transaction), Skip, Mark as duplicate
4. Bulk actions: Accept all, Skip all duplicates
5. Summary at top: X accepted, Y skipped, Z remaining
6. Finish button → update `statement_imports.status = 'completed'`

---

## Priority 5: Social & Trust Enhancements

### 5.1 Settlement Confirmation Flow
**Location:** `lib/features/settlements/screens/settlement_confirm_screen.dart`

**Enhancement:**
- Show settlement details: who paid, how much, which group
- Confirm button → update `group_settlements.status = 'confirmed'`, create transaction
- Reject button → update status, show reason text field, log activity event
- Pending settlements should show yellow badge in People tab
- Confirmed settlements show green check

### 5.2 Group Activity Feed
**Location:** Inside `lib/features/groups/screens/group_expenses_screen.dart`

**Add:**
- Activity section showing `activity_events` filtered by `group_id`
- Settlement confirmation badges on settlement items
- Dispute button on each group expense
- Net balance summary card at top

### 5.3 Dispute Flow
**Location:** `lib/features/disputes/screens/dispute_screen.dart`

**Flow:**
1. Open dispute on group expense / settlement / lend-borrow
2. Enter reason + optional proposed amount
3. Submit → create `disputes` row + activity event
4. View dispute status, resolution notes
5. Resolve → update status, log activity event

### 5.4 People Screen Enhancement
**Location:** `lib/features/lend_borrow/screens/split_screen.dart`

**Needs:**
- Rename to PeopleScreen
- Add cross-group net balance summary card ("You owe Alice ₹500 total", "Bob owes you ₹200 total")
- Show pending settlements awaiting your confirmation
- Better separation of Groups vs Lend/Borrow sections

---

## Priority 6: Polish & Navigation

### 6.1 Enhanced Manual Entry
**Location:** `lib/features/dashboard/widgets/add_expense_sheet.dart`

**Needs:**
- Create `transactions` row directly (not just documents)
- Add optional group assignment
- Add optional lend/borrow toggle
- Category picker

### 6.2 Scan Review Enhancement
**Location:** `lib/features/scanner/widgets/scan_review_panel.dart`

**Needs (from Product Blueprint Section 6):**
- Money Intent step: Personal | Shared | Lend | Borrow | Mixed Bill
- Result Preview: summary card showing all transactions that will be created
- Progressive disclosure: default is personal (one tap save), group/lend are toggles

### 6.3 Export Enhancement
**Location:** `lib/features/export/`

**Needs:**
- Read from `transactions` instead of `documents`
- Filter by transaction type, group, category
- Export file shows `effective_amount` (user's share, not receipt total)

---

## Existing Providers Reference

| Provider | File | What it manages |
|----------|------|-----------------|
| `transactionsProvider` | `lib/providers/transactions_provider.dart` | Transaction CRUD |
| `documentsProvider` | `lib/providers/documents_provider.dart` | Document/source CRUD |
| `budgetsProvider` | `lib/providers/budgets_provider.dart` | Budget CRUD |
| `recurringSeriesProvider` | `lib/providers/recurring_provider.dart` | Recurring series CRUD |
| `lendBorrowProvider` | `lib/providers/lend_borrow_provider.dart` | IOUs |
| `profileProvider` | `lib/providers/profile_provider.dart` | User profile |
| `expenseGroupsNotifierProvider` | `lib/providers/groups_provider.dart` | Groups + members |
| `groupExpensesProvider` | `lib/providers/group_expenses_provider.dart` | Per-group expenses |
| `groupSettlementsProvider` | `lib/providers/group_settlements_provider.dart` | Per-group settlements |
| `connectionsNotifierProvider` | `lib/providers/social_provider.dart` | User connections |
| `invitationsNotifierProvider` | `lib/providers/social_provider.dart` | Contact invitations |
| `usageLimitsProvider` | `lib/providers/usage_limits_provider.dart` | OCR quotas |
| `activityFeedProvider` | `lib/providers/activity_feed_provider.dart` | Activity events |
| `dashboardSummaryProvider` | `lib/providers/dashboard_summary_provider.dart` | Dashboard aggregates |

## Existing Services Reference

| Service | File | What it does |
|---------|------|-------------|
| `TransactionService` | `lib/services/transaction_service.dart` | Transaction CRUD, dashboard aggregation |
| `SupabaseService` | `lib/services/supabase_service.dart` | Large data layer for all Postgrest/Storage |
| `AllocationService` | `lib/services/allocation_service.dart` | Compute group shares, lend buckets |
| `ActivityLogger` | `lib/services/activity_logger.dart` | Log activity_events to Supabase |
| `InvoiceOcrPipeline` | `lib/features/invoices/services/invoice_ocr_pipeline.dart` | OCR pipeline |
| `AnalyticsInsightsService` | `lib/features/analytics/services/analytics_insights_service.dart` | AI insights |
| `PdfGenerator` | `lib/features/export/services/pdf_generator.dart` | Export PDF |
| `CsvGenerator` | `lib/features/export/services/csv_generator.dart` | Export CSV |
