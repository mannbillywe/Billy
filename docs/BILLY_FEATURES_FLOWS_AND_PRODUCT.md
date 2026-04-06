# Billy — Complete product, feature & flow reference

**Purpose:** Single exhaustive inventory of the Billy app: every major flow, screen, provider, service, database object, and Edge Function behavior as implemented in this repo. For high-level roadmap see [`PROJECT_PLAN.md`](../PROJECT_PLAN.md). For agent routing see [`AGENTS.md`](../AGENTS.md). **Schema truth** is always `supabase/migrations/`; this doc summarizes it.

**Maintenance:** When you add a route, table, RPC, or user-visible behavior, update the matching subsection here.

---

## Table of contents

1. [Product summary](#1-product-summary)  
2. [Technology stack](#2-technology-stack)  
3. [Bootstrap & configuration](#3-bootstrap--configuration)  
4. [Navigation & shell](#4-navigation--shell)  
5. [Screens & routes (complete list)](#5-screens--routes-complete-list)  
6. [Core domain: documents](#6-core-domain-documents)  
7. [Scan & OCR pipeline (full state machine)](#7-scan--ocr-pipeline-full-state-machine)  
8. [Review panel: save paths & side effects](#8-review-panel-save-paths--side-effects)  
9. [Dashboard: widgets & spend math](#9-dashboard-widgets--spend-math)  
10. [Analytics: Overview + AI Insights](#10-analytics-overview--ai-insights)  
11. [Document AI review (single-doc)](#11-document-ai-review-single-doc)  
12. [Friends tab: people, groups, lend/borrow](#12-friends-tab-people-groups-lendborrow)  
13. [Group expenses & settlements](#13-group-expenses--settlements)  
14. [Settings, profile, export](#14-settings-profile-export)  
15. [Authentication](#15-authentication)  
16. [Riverpod providers](#16-riverpod-providers)  
17. [SupabaseService API surface](#17-supabaseservice-api-surface)  
18. [Database tables & relationships](#18-database-tables--relationships)  
19. [RPCs & SQL functions (client-invoked)](#19-rpcs--sql-functions-client-invoked)  
20. [Edge Functions](#20-edge-functions)  
21. [Storage](#21-storage)  
22. [Usage limits](#22-usage-limits)  
23. [Hosted web proxies (Vercel)](#23-hosted-web-proxies-vercel)  
24. [Supporting scripts & optional SQL](#24-supporting-scripts--optional-sql)  
25. [Related docs](#25-related-docs)  

---

## 1. Product summary

Billy is a **cross-platform Flutter** app for personal (and small-group) money tracking:

- **Auth** via Supabase (email/password, password reset, Google OAuth, Apple OAuth).
- **Expenses** stored primarily in **`documents`** (invoice vs receipt type, vendor, amount, tax, date, category, `extracted_data` JSON, status including **draft**).
- **Invoice OCR** uses a parallel **`invoices`** + **`invoice_items`** pipeline: files in **`invoice-files`** storage, processing by Edge Function **`process-invoice`** with **Gemini** (`gemini-2.5-flash-lite` in code).
- **Dashboard** aggregates **non-draft** spend (with week logic that can attribute old bill dates to “this week” using **`created_at`** when appropriate).
- **Analytics** combines client-side charts with optional **AI insights** (Edge **`analytics-insights`**, cached in **`analytics_insight_snapshots`**).
- **Social:** email **invitations**, **connections**, **expense groups**, **group expenses** (RPC), **settlements**, and **lend/borrow** entries (optionally linked to contacts, groups, and documents).
- **Export:** PDF (printing/share) and CSV (share), with **`export_history`** logging.
- **Limits:** monthly **OCR scan** and **refresh** counters per user (`user_usage_limits` + RPCs).

---

## 2. Technology stack

| Area | Implementation |
|------|----------------|
| UI | Flutter, Material, `BillyTheme` (`lib/core/theme/billy_theme.dart`) |
| State | **Riverpod** — `ProviderScope` in `main.dart` |
| Backend | Supabase: Postgres, Auth, Storage, Edge Functions |
| Local logging | `BillyLogger` (`lib/core/logging/billy_logger.dart`) |
| Errors (optional) | `SentryFlutter` when `SENTRY_DSN` is non-empty (`String.fromEnvironment`) |
| Currency display | `AppCurrency` + `profiles.preferred_currency` (no FX conversion) |
| OCR AI | Google Gemini via Edge Functions (shared key table or env secret) |
| Web HTTP | `fetch_client` + custom `_NoKeepaliveFetchClient` for Safari (`main.dart`) |

**Config files:** `lib/config/supabase_config.dart`, `lib/config/gemini_config.dart`. Secrets: `.env` / compile-time — never commit keys.

---

## 3. Bootstrap & configuration

**`lib/main.dart`**

1. `WidgetsFlutterBinding.ensureInitialized()`.
2. Optionally `SentryFlutter.init` → runs `bootstrap` as `appRunner`.
3. `bootstrap`: `Supabase.initialize(url, anonKey)`; on **web** passes custom `httpClient` to avoid Safari `keepalive` issues on small POST bodies.
4. `runApp(ProviderScope(child: BillyApp()))`.
5. On init failure, shows a minimal `MaterialApp` with error text.

**`lib/app/app.dart`**

- `MaterialApp` → `theme: BillyTheme.lightTheme`, home from `authStateProvider`:
  - **loading:** centered progress (emerald).
  - **error:** `LoginScreen` (fail-safe).
  - **data:** `user != null` → `LayoutShell`, else `LoginScreen`.

---

## 4. Navigation & shell

**`lib/app/layout_shell.dart`**

- **Header:** `BillyHeader` (logo asset `assets/branding/billy_logo.png`, fallback “B” tile).
- **Body:** `AnimatedSwitcher` + `FadeTransition` between tab contents.
- **Bottom:** `BillyBottomNav` — indices:
  - `0` **Home** → `DashboardScreen` with callbacks for scan, export, add expense, document list, document detail.
  - `1` **Analytics** → `AnalyticsScreen`.
  - `2` **Friends** → `SplitScreen`.
  - `3` **Settings** → `SettingsScreen`.
- **FAB (center):** calls `_openScan` → `Navigator.push` → `Scaffold` + `AppBar` “Scan invoice” + `ScanScreen` body.
- **`initState` post-frame:** `invitationsNotifierProvider`, `connectionsNotifierProvider`, `expenseGroupsNotifierProvider` **refresh** (social data warm-up).

**Pushed routes (non-tab) from shell**

| From | Screen | Notes |
|------|--------|------|
| Home / FAB | `ScanScreen` | Full OCR flow |
| Home | `DocumentsHistoryScreen` | Paged list |
| Home | `DocumentDetailScreen(documentId)` | |
| Home / Settings | `ExportScreen(documents: …)` | Built via `documentsForExport` |
| Settings | `ProfileScreen` | |
| Settings | `ExportHistoryScreen` | |
| Settings | `ExportScreen` | Same as above |

---

## 5. Screens & routes (complete list)

Paths under `lib/features/` unless noted.

| Screen | File | Role |
|--------|------|------|
| Login | `auth/screens/login_screen.dart` | Sign in, sign up, forgot password, OAuth |
| Dashboard | `dashboard/screens/dashboard_screen.dart` | Spend hero, charts, insights, recent, quick actions |
| Analytics | `analytics/screens/analytics_screen.dart` | Date presets, Overview vs AI Insights segments |
| Document AI review | `analytics/screens/document_ai_review_screen.dart` | Per-document AI via Edge (`document_id`) |
| Split / Friends | `lend_borrow/screens/split_screen.dart` | Invites, groups, open group ledger, lend/borrow |
| Group expenses | `groups/screens/group_expenses_screen.dart` | Group ledger, add expense, settlements (pushed from Split) |
| Scan | `scanner/screens/scan_screen.dart` | Pick → adjust → process → review |
| Documents history | `documents/screens/documents_history_screen.dart` | Search, filters, sort, infinite scroll (50/page) |
| Document detail | `documents/screens/document_detail_screen.dart` | View, delete, open scan, re-OCR, replace file, edit, AI review |
| Document edit | `documents/screens/document_edit_screen.dart` | Editable fields for a document |
| Export | `export/screens/export_screen.dart` | Date range, PDF/CSV, share |
| Export history | `export/screens/export_history_screen.dart` | Past exports from DB |
| Settings | `settings/screens/settings_screen.dart` | Currency, links to profile/export/history |
| Profile | `profile/screens/profile_screen.dart` | Account info, sign out, export shortcut |

**Widgets** (not routes) of note: `AddExpenseSheet`, `SpendHero`, `MoneyFlowChart`, `InsightsCard`, `RecentActivity`, `QuickActions`, `OcrBanner`, `ScanIdle`, `ScanAdjustPreview`, `ScanProcessing`, `ScanError`, `ScanReviewPanel`, analytics chart widgets, `AiInsightsPanel`, etc.

---

## 6. Core domain: documents

### 6.1 Table `documents` (conceptual)

From initial schema + migrations: `user_id`, `type` (`invoice`|`receipt`), `vendor_name`, `amount`, `currency`, `tax_amount`, `date`, `category_id`, **`category_source`** (`manual`|`ai`|`rule`|`legacy`), `description`, `payment_method`, **`status`** (e.g. `saved`, **`draft`**), `image_url`, **`extracted_data`** (jsonb), timestamps.

### 6.2 Client access

- **List:** `documentsProvider` → `SupabaseService.fetchDocuments()` (full list for most UI); **history** uses **`fetchDocumentsPaged(limit: 50, offset)`** when not restricted.
- **Insert / update / delete:** `DocumentsNotifier` → `SupabaseService.insertDocument` / `updateDocument` / `deleteDocument`.
- **Category column missing:** inserts/updates strip `category_source` if Postgrest `PGRST204` indicates column absent (older DBs).

### 6.3 `extracted_data` conventions (OCR / review)

Populated by `ScanReviewPanel` and sync logic. Important keys include:

- `invoice_id` — links to **`invoices`** row (OCR pipeline).
- `line_selection` — per line: `included`, `assigned_user_id`, optional lend fields.
- `allocation_total` — total attributed to selected lines / header.
- `intent_group_expense`, `group_id` — user chose group split on save.
- `intent_lend_borrow`, `lend_type`, `lend_counterparty` — lend/borrow intent.
- `extraction_confidence` — drives **Needs review** filter.
- `user_flagged_mismatch` — also drives **Needs review**.
- `scan_draft` — set on **Save as draft**.

### 6.4 Export mapping

`documentsForExport` (`export/models/export_document.dart`): **excludes** `status == draft`; maps `description` first segment to **category** label for CSV/PDF.

### 6.5 Document history filters & sort

`documents/models/document_list_models.dart`:

- **Filters:** All, Receipts, Invoices, Manual (no `invoice_id` in extracted_data), OCR, Needs review, Drafts, Group-linked (`intent_group_expense` + `group_id`), Lend/borrow linked (`intent_lend_borrow`).
- **Sort:** Newest / oldest by `date`, highest / lowest amount.
- **Search:** Vendor name substring (case-insensitive).
- **Restrict mode:** `restrictToDocumentIds` set → uses in-memory/doc provider subset, **no server paging**.

---

## 7. Scan & OCR pipeline (full state machine)

### 7.1 `ScanScreen` states (`ScanState` enum)

| State | UI | Entry |
|-------|-----|--------|
| `idle` | `ScanIdle` | Initial; after discard |
| `previewAdjust` | `ScanAdjustPreview` | Raster image from camera/gallery/file (not PDF) |
| `processing` | `ScanProcessing` | OCR running |
| `success` | `ScanReviewPanel` | Extraction ready |
| `error` | `ScanError` | User can retry (discard) or pop |

### 7.2 Entry points (`ScanIdle`)

- **Camera** — `ImagePicker.pickImage`, max width 1920, quality 85, source `camera`.
- **Photo library** — single image, same compression.
- **Multiple photos** — `pickMultiImage` (not on web → falls back to file picker multi).
- **Upload PDF/image** — `FilePicker` single file; reads bytes (or stream on web multi).
- **Multiple files** — `FilePicker` multi; web may use `readStream` when `bytes` null.

**Limits**

- Batch queue max **`12`** files (`_maxBatch`).
- File size max **16 MB** in `InvoiceOcrPipeline`.

**MIME detection** — by extension: jpeg, png, webp, gif, pdf → else default image/jpeg.

### 7.3 Adjust preview & background prefetch

- For **adjustable raster** MIME (`scan_raster_adjust.dart`), after pick the app shows **`ScanAdjustPreview`**.
- **Post-frame** it starts **`_prefetchDuringAdjust`**: calls `_ocrUploadAndProcess` with **`countTowardOcrLimit: true`** once.
- If user **continues** with **same bytes** as prefetch seed: waits for prefetch job; uses cached receipt/invoice id **without second OCR charge**; if prefetch failed, **retries OCR** with **`countTowardOcrLimit: false`** (no double charge).
- If user **changes** image (rotate/crop): cancels prefetch, **deletes** partial prefetch invoice via `deleteInvoiceForUser`, runs **new** OCR with limit increment.

### 7.4 OCR limit increment

`_ocrUploadAndProcess` when `countTowardOcrLimit` is true:

1. `SupabaseService.incrementOcrScan()` → RPC (throws if over limit).
2. `ref.invalidate(usageLimitsProvider)`.

`ScanIdle` does **not** disable camera/upload when over quota; the user hits the error when OCR starts. `SupabaseService.canPerformOcrScan()` exists for UI that chooses to pre-check.

### 7.5 `InvoiceOcrPipeline.uploadAndProcess`

1. Preconditions: non-empty bytes, signed-in user.
2. Generate **`invoiceId`** (UUID v4).
3. Storage path: `{uid}/{yyyy}/{mm}/{invoiceId}/{sanitizedFileName}` in bucket **`invoice-files`**.
4. `storage.uploadBinary` with `contentType`, `upsert: true`.
5. Insert **`invoices`** row: `status: uploaded`, `file_path`, `file_name`, `mime_type`, `source` (`camera`|`gallery`|`file`).
6. Invoke Edge **`process-invoice`** with `{ invoice_id, file_path }` (and `force_reprocess` when reprocessing).
7. If response **202** or `pending: true`: **`_waitForInvoiceOcr`** polls `invoices.status` until `completed` or `failed` (timeout ~180s, step 750ms).
8. If synchronous success: parse `invoice` + `items` maps → `ExtractedReceipt.fromInvoiceOcr`.
9. Else load from DB via `_receiptFromDb`.

**Reprocess / replace** (document detail):

- `reprocessExistingInvoice` — `force_reprocess: true`, same file path.
- `replaceInvoiceFileAndReprocess` — `uploadBinary` upsert at path, then reprocess.

### 7.6 Hosted web invoke

If `kIsWeb` and host not localhost → POST **`${Uri.base.origin}/api/process-invoice`** with JSON body + `Authorization: Bearer <accessToken>` + `apikey: <anon>` (mirrors `analytics-insights` proxy pattern).

### 7.7 Discard

`_performDiscard`: cancel prefetch; delete prefetch invoice if any; if success state, **`deleteInvoiceForUser`** (removes storage object + `invoices` row, cascades items/events); reset UI state.

### 7.8 Batch queue

After successful save, `_onSaveDone`: if batch queue has next item, increments index and **`_runPipelineDirect`** for next file (each file = separate OCR, separate limit increments as coded).

---

## 8. Review panel: save paths & side effects

**File:** `scanner/widgets/scan_review_panel.dart`

### 8.1 Editable fields

Vendor, date, invoice number, category, notes; per **line**: on/off, assignee (group mode), lend counterparty names/linked users per line when applicable.

### 8.2 Validation highlights

- **Save:** `allocation_total` / line sum must be > 0 (or fall back to header total/subtotal).
- **Group:** must pick group; members loaded from `expenseGroupsNotifierProvider`; either assign **single member** when no lines, or each **included line** must have assignee.
- **Lend/borrow:** counterparty rules — empty lines need default name or per-line names.

### 8.3 Full save sequence (`_save`)

1. Resolve **category_id** from hints: `resolveBestCategoryIdFromHints` (exact name on user/default categories, then substring match).
2. Build **`extractedPayload`** via `_extractedPayload` (line_selection, allocation, intents, invoice_id).
3. If **`invoiceId` != null**: rebuild **`invoice_items`** rows for included lines; **`syncInvoiceAfterReview`** → deletes old items, inserts new, updates **`invoices`** header including optional **`expense_category`**, sets `status: confirmed`, `review_required: false`.
4. **`addDocument`** with amount = **line allocation** when lines exist else header total; `category_source: ai`; `extracted_data` = payload.
5. If **group intent**: aggregate shares by assignee → **`createGroupExpense`** RPC with `p_document_id` when migration present; invalidate `groupExpensesProvider(groupId)`, `expenseGroupsNotifierProvider`.
6. If **lend intent**: **`_persistLendBorrowForSave`** — one or more **`lend_borrow_entries`** bucketed by (name, linked user); includes **`document_id`** when column exists.
7. Snackbar success → **`onDone`** (pop scan route or next batch item).

### 8.4 Save as draft (`_saveAsDraft`)

- Inserts **`documents`** with `status: draft`, `extracted_data` includes `scan_draft: true`.
- **Does not** sync invoice header/items, **does not** create group expense or lend/borrow rows.

---

## 9. Dashboard: widgets & spend math

**File:** `dashboard/screens/dashboard_screen.dart`

**Data sources:** `documentsProvider`, `lendBorrowProvider`, `profileProvider`.

**Behaviors**

- **Loading:** linear progress while documents loading and value null.
- **Recent list:** up to 10 non-draft docs by `date` desc; UI shows 5 as `RecentActivity` with optional **`DocumentBackdateHint`** label.
- **Insights card / category split:** uses **non-draft** docs only; category key = first segment of `description` (same pattern as Analytics overview).
- **Quick actions:** Create bill (sheet), All documents, Export.
- **OcrBanner:** manual entry callback.

**`DashboardSpendMath`** (`dashboard/utils/dashboard_spend_math.dart`)

- **This week document spend:** ISO week Mon–Sun, **non-draft**; attributes each doc to a day using **`documents.date`** if it falls in current week and not after today, else **`created_at`** day if in week (so scans with old bill dates still show in “this week”).
- **Last calendar week**, **daily series**, **lend/borrow** weekly helpers, **pending** collect/pay totals — all used by **`SpendHero`** and charts.

---

## 10. Analytics: Overview + AI Insights

**File:** `analytics/screens/analytics_screen.dart`

### 10.1 Date filter UI

Presets **`1W`**, **`1M`**, **`3M`** — aligned with `DocumentDateRange.forFilter` and Edge `windowForPreset`.

### 10.2 Overview segment

- Filters docs with `DocumentDateRange.filterDocuments` (excludes drafts; includes doc if **either** `date` **or** `created_at` day falls in range — see `documentInDateRange`).
- Computes total spend, category map (description first segment), top category %, 7-day bar data via `lastSevenDaySpending`, average spend.
- Charts: `fl_chart` bar/line as implemented in file.

### 10.3 AI Insights segment

**`AiInsightsPanel`** (`analytics/widgets/ai_insights_panel.dart`):

- **`rangePreset`** must match Overview filter (`1W`|`1M`|`3M`).
- **Date basis toggle:** `InsightsDateBasis.billDate` vs `uploadWindow` — maps to API `bill_date` / `upload_window`; cached snapshot must match basis or UI treats as empty.
- **Load:** `loadCachedSnapshot` reads **`analytics_insight_snapshots`** (no Gemini).
- **Refresh:** `refreshInsights` → **`incrementRefreshCount`** first; then `AnalyticsInsightsService.refreshRange`.
- **Stale indicator:** `analyticsInsightsDocumentsStale` compares fingerprint to current docs + preset + basis.
- **Refresh lock:** when `usageLimitsProvider` shows `refresh_used >= refresh_limit`, button disabled.
- **Tabs:** Money Coach vs JAI (when dual AI payload present).
- **Drill-down:** `_openDocuments` → `DocumentsHistoryScreen(restrictToDocumentIds: …)`.

**`AnalyticsInsightsService`**

- **Mobile/desktop/local web:** `client.functions.invoke('analytics-insights', body: …)`.
- **Hosted web:** POST `/api/analytics-insights` same-origin with bearer + apikey.
- **Dual agent default:** when `ai_agents == 'both'`, sequential invocations: `money_coach` then `jai_insight`; merges in server/client per implementation.

**`analyticsInsightsProvider`**

- On refresh failure, restores previous snapshot and returns error string for Snackbar.

---

## 11. Document AI review (single-doc)

**`analytics/screens/document_ai_review_screen.dart`**

- Loads document via `fetchDocumentById`.
- **Run AI review:** `incrementRefreshCount` + `AnalyticsInsightsService.reviewDocument(documentId: …)` → same Edge function with `{ document_id, include_ai }`.
- Shows “facts” tiles from row; renders returned **`ai_layer`**.
- Respects refresh limit UI (disabled when locked).

---

## 12. Friends tab: people, groups, lend/borrow

**`lend_borrow/screens/split_screen.dart`** — scrollable column:

1. **Invite row** — email field + **Invite** → `invite_contact_by_email` RPC via `invitationsNotifierProvider`.
2. **Incoming invitations** — accept / reject.
3. **Outgoing invitations** — cancel (updates status).
4. **Groups** — list; **Create** dialog → `createExpenseGroup` + optional member picker (connections); **Add members** per group; **tap group** → `GroupExpensesScreen`.
5. **Lend/borrow section** — error banner + retry if load fails.
6. **Summary cards** — **To collect** vs **To pay back** (pending only); toggles filter list (`collect` → viewer-effective type `lent`; `pay` → `borrowed`).
7. **Search** — filters displayed entries by counterparty display name.
8. **List** — `_EntryRow` with settle action.
9. **Add transaction** sheet — type lent/borrowed, optional linked contact, optional group, amount, notes → `lendBorrowProvider.addEntry`.

**Perspective helpers:** `lend_borrow/lend_borrow_perspective.dart` — `effectiveTypeForViewer`, `otherPartyDisplayName` for shared rows.

---

## 13. Group expenses & settlements

**`groups/screens/group_expenses_screen.dart`** (opened from Split):

- Fetches expenses via `groupExpensesProvider` / `SupabaseService.fetchGroupExpenses`.
- **Add expense:** title, amount, payer, date, split shares across members → **`create_group_expense`** RPC (validates membership, share sum = amount).
- **Delete expense** (owner) — `deleteGroupExpense`.
- **Settlements** — list `fetchGroupSettlements`; **record payment** `insertGroupSettlement` (current user is payer); delete own settlement `deleteGroupSettlement`.

**RPC `create_group_expense`** (`20240402000000_group_expenses.sql`): security definer; inserts `group_expenses` + `group_expense_participants`; optional **`p_document_id`** in client when migration adds it (links scan to group expense).

---

## 14. Settings, profile, export

**Settings**

- **Display currency** dropdown: USD, EUR, GBP, INR, JPY, CAD, AUD → `updateProfile(preferred_currency)`.
- Tiles: **Account** → Profile; **Export data** → `ExportScreen`; **Export history** → `ExportHistoryScreen`.

**Profile**

- Shows profile fields; **sign out**; may link export (grep `ExportScreen`).

**Export screen**

- Date range pickers; format **pdf** | **csv**.
- Filters `ExportDocument` list to range.
- PDF: `PdfGenerator.generateReport` → `Printing.sharePdf`.
- CSV: `CsvGenerator.generate` → `Share.shareXFiles`.
- On success: `insertExportHistory` with format + range.

**Export history**

- `fetchExportHistory` ordered by `created_at` desc.

---

## 15. Authentication

**`auth/screens/login_screen.dart`**

- **Modes:** `signIn`, `signUp`, `forgotPassword`.
- **Email/password:** `signInWithPassword`, `signUp` with metadata (`full_name`, optional `phone` in raw user meta).
- **Forgot:** `resetPasswordForEmail`.
- **OAuth:** `signInWithOAuth` for **Google** and **Apple** (platform-dependent UI).
- Validation: email format, password min 8 on sign-up, confirm password match.

**`auth/providers/auth_provider.dart`**

- `authStateProvider` — `StreamProvider` mapping `onAuthStateChange` to `session?.user`.

**DB:** trigger `on_auth_user_created` → inserts **`profiles`** for new auth user.

---

## 16. Riverpod providers

| Provider | File | Responsibility |
|----------|------|----------------|
| `authStateProvider` | `features/auth/providers/auth_provider.dart` | Auth session user |
| `documentsProvider` | `providers/documents_provider.dart` | Document list CRUD + `syncDocumentFromLinkedInvoice` |
| `profileProvider` | `providers/profile_provider.dart` | Current user profile row |
| `usageLimitsProvider` | `providers/usage_limits_provider.dart` | `maybe_reset_usage` RPC row |
| `lendBorrowProvider` | `providers/lend_borrow_provider.dart` | Lend/borrow list + mutations |
| `invitationsNotifierProvider` | `providers/social_provider.dart` | Invites CRUD / RPC |
| `connectionsNotifierProvider` | `providers/social_provider.dart` | Connections list |
| `expenseGroupsNotifierProvider` | `providers/groups_provider.dart` | Groups + members |
| `groupExpensesProvider` | `providers/group_expenses_provider.dart` | Param: `groupId` → expenses |
| `groupSettlementsProvider` | `providers/group_settlements_provider.dart` | Param: `groupId` → settlements |
| `splitsProvider` | `providers/splits_provider.dart` | Legacy splits table (fetch) |
| `analyticsInsightsProvider` | `features/analytics/providers/analytics_insights_provider.dart` | Cached AI analytics snapshot |

---

## 17. SupabaseService API surface

Grouped by domain (`lib/services/supabase_service.dart`):

- **Documents:** `fetchDocuments`, `fetchDocumentsPaged`, `insertDocument`, `updateDocument`, `deleteDocument`, `fetchDocumentById`, `syncDocumentFromLinkedInvoice`.
- **Categories:** `resolveCategoryIdByName`, `resolveBestCategoryIdFromHints`.
- **Export history:** `insertExportHistory`, `fetchExportHistory`.
- **Analytics snapshots:** `fetchAnalyticsInsightSnapshot`.
- **Invoice OCR:** `signedUrlForInvoiceFile`, `fetchInvoiceHeaderForUser`, `syncInvoiceAfterReview`, `deleteInvoiceForUser`.
- **Lend/borrow:** `fetchLendBorrow`, `insertLendBorrow`, `settleLendBorrow`, `deleteLendBorrow`.
- **Splits:** `fetchSplits`, `insertSplit`.
- **Profile:** `fetchProfile`, `updateProfile`, `fetchProfileById`, `fetchProfilesByIds`.
- **Social:** `syncInvitationRecipient`, `inviteContactByEmail`, `acceptContactInvitation`, `rejectContactInvitation`, `fetchContactInvitations`, `fetchUserConnections`, `cancelOutgoingInvitation`.
- **Groups:** `fetchExpenseGroups`, `fetchGroupExpenses`, `createGroupExpense`, `deleteGroupExpense`, `fetchGroupSettlements`, `insertGroupSettlement`, `deleteGroupSettlement`, `createExpenseGroup`, `addUserToExpenseGroup`.
- **Connected apps:** `fetchConnectedApps`.
- **Usage:** `fetchUsageLimits`, `incrementOcrScan`, `incrementRefreshCount`, `canPerformOcrScan`, `canPerformRefresh`.
- **Dashboard stats (server-side):** `todaySpend`, `weekSpend`, `recentDocuments`, `categoryBreakdown`, `dailySpendForWeek` (some UI uses local math instead).

**Defensive compatibility:** `category_source` and `lend_borrow.document_id` errors fall back to operations without those columns.

---

## 18. Database tables & relationships

**Core (initial schema + follow-ups)**

| Table | Purpose |
|-------|---------|
| `profiles` | `id` = auth user; `display_name`, `avatar_url`, `trust_score`, **`preferred_currency`**, timestamps |
| `categories` | User-scoped or default (`user_id` null); name, icon, color |
| `documents` | Main expense ledger; FK `category_id`; **`category_source`**; **`status`** |
| `lend_borrow_entries` | Lent/borrowed; optional `counterparty_user_id`, `group_id`, **`document_id`** |
| `splits` / `split_participants` | Simple bill splits (legacy UI surface) |
| `connected_apps` | Integration placeholders |
| `export_history` | PDF/CSV export log |

**Social & groups**

| Table | Purpose |
|-------|---------|
| `contact_invitations` | Email invite workflow |
| `user_connections` | Mutual connection (ordered pair uniqueness) |
| `expense_groups` | Group container |
| `expense_group_members` | Membership |
| `group_expenses` | Group expense header; optional **`document_id`** (migration) |
| `group_expense_participants` | Per-user share |
| `group_settlements` | Payer → payee payment toward group balance |

**Invoice OCR**

| Table | Purpose |
|-------|---------|
| `invoices` | File metadata + extracted header; **`expense_category`**; statuses: `uploaded`, `processing`, `completed`, `failed`, `reviewed`, `confirmed` |
| `invoice_items` | Line items; `assigned_user_id` for group assignment from review |
| `invoice_ocr_logs` | Debug/audit payloads |
| `invoice_processing_events` | Timeline steps |

**Analytics cache**

| Table | Purpose |
|-------|---------|
| `analytics_insight_snapshots` | One row per user per `range_preset` (`1W`|`1M`|`3M`); `data_fingerprint`, `deterministic`, `ai_layer`, date range, optional basis handling in app |

**Ops**

| Table | Purpose |
|-------|---------|
| `user_usage_limits` | OCR + refresh counters, period boundaries |
| `app_api_keys` / shared keys | Edge Functions read Gemini key (migration `20260405160000_shared_api_keys.sql`) |
| `user_gemini_api_key` | Per-user key (migration `20240318000002_user_gemini_api_key.sql`) — usage depends on Edge implementation |

---

## 19. RPCs & SQL functions (client-invoked)

| RPC / function | Used for |
|----------------|----------|
| `sync_invitation_recipient` | Link invite to user email on login |
| `invite_contact_by_email` | Send invitation |
| `accept_contact_invitation` | Accept → connection |
| `reject_contact_invitation` | Reject |
| `create_group_expense` | Atomic group expense + shares (+ optional document id) |
| `maybe_reset_usage` | Reset monthly counters if period elapsed |
| `increment_ocr_scan` | Count OCR; throws over limit |
| `increment_refresh_count` | Count AI insight refreshes / doc review |
| `increment_ocr_scan` / `increment_refresh_count` | See `20260405150000_user_usage_limits.sql` for full definitions |

---

## 20. Edge Functions

### 20.1 `process-invoice` (`supabase/functions/process-invoice/index.ts`)

- **Model:** `gemini-2.5-flash-lite`.
- **Auth:** User JWT; reads file from **Storage** path; writes **`invoices`** / **`invoice_items`** / logs / events.
- **Prompt:** Structured JSON invoice/receipt schema + **expense taxonomy** (Food & Dining, Groceries, …) for `expense_category` and per-line categories.
- **API key:** Shared `app_api_keys` row type `gemini` or secret **`GEMINI_API_KEY`**.
- **Client body:** `{ invoice_id, file_path, force_reprocess? }`.
- **Responses:** Sync `success` + payload, or **async** `202` / `pending` + client polling until terminal status.
- **CORS:** `_shared/cors.ts`.

### 20.2 `analytics-insights` (`supabase/functions/analytics-insights/index.ts`)

- **Purpose:** Deterministic aggregates over `documents`, lend/borrow, group expenses, invoices metadata; optional **Gemini** layers (Money Coach, JAI Insight); **previous-window** comparisons; writes **`analytics_insight_snapshots`**.
- **Client body examples:** `range_preset`, `include_ai`, `ai_agents`, `date_basis`; or **`document_id`** for single-doc review.
- **Alignment:** Date windows match `DocumentDateRange.forFilter` (documented in Edge comments).
- **CORS:** shared helper.

---

## 21. Storage

- **Bucket `invoice-files`** (private): path first segment = **`auth.uid()`**; allowed types: jpeg, png, webp, pdf; size limit per migration (e.g. 16MB).
- **RLS policies** on `storage.objects` for insert/select/update/delete own prefix.

---

## 22. Usage limits

- Table **`user_usage_limits`**: `ocr_scans_used/limit`, `refresh_used/limit`, `period_start`, `period_end` (monthly by default).
- **RLS:** user reads own row; update own counters (see migration).
- **Scan flow** increments OCR on each billable `uploadAndProcess` call (with exceptions for prefetch retry without second charge).
- **AI insights refresh**, **document detail re-OCR**, **replace scan**, **document AI review**, **analytics refresh** use **`increment_refresh_count`** where implemented in UI.

---

## 23. Hosted web proxies (Vercel)

When the app is deployed to a **non-localhost** web host:

- **`InvoiceOcrPipeline`** POSTs to **`/api/process-invoice`** (same origin) instead of `functions.invoke`.
- **`AnalyticsInsightsService`** POSTs to **`/api/analytics-insights`**.

Repo may contain Vercel API route implementations elsewhere (not duplicated here); behavior is documented in the Dart services above.

---

## 24. Supporting scripts & optional SQL

- `supabase/scripts/optional_documents_date_align_created_at.sql` — optional maintenance (align dates); not applied automatically.
- `docs/TAXHACKER_GAP_ANALYSIS.md` — product comparison / gap notes.
- `docs/PRODUCTION_READINESS.md` — deployment checklist.

---

## 25. Related docs

| Path | Content |
|------|---------|
| [`PROJECT_PLAN.md`](../PROJECT_PLAN.md) | Phases, target structure |
| [`AGENTS.md`](../AGENTS.md) | Agent roles |
| [`.cursor/rules/billy-conventions.mdc`](../.cursor/rules/billy-conventions.mdc) | Repo conventions |
| [`docs/TAXHACKER_GAP_ANALYSIS.md`](TAXHACKER_GAP_ANALYSIS.md) | Competitive / gap analysis |
| [`docs/PRODUCTION_READINESS.md`](PRODUCTION_READINESS.md) | Production checklist |

---

*This document is intended to be exhaustive for the current codebase; migrations remain authoritative for column types and policies. Update this file when behavior changes.*
