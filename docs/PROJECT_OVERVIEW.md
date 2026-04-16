# Billy — Project overview

This document describes how the **Billy** repository is organized, what technologies it uses, how the Flutter app boots and navigates, and how **Supabase** (and related services) connect to the client.

---

## What Billy is

**Billy** is a Flutter financial app for managing **invoices, receipts, and expenses**. Users capture documents (camera/gallery), data can be extracted with **Google Gemini** (via server-side processing), and records live in **Supabase** (Postgres, Auth, Storage, RPCs). The UI includes dashboard, activity feed, group/split flows, planning, analytics, export, and settings.

---

## Tech stack (from `pubspec.yaml`)

| Area | Packages / services |
|------|----------------------|
| **UI** | Flutter (Material), custom theme in `lib/core/theme/billy_theme.dart` |
| **Backend** | [Supabase](https://supabase.com/) — `supabase_flutter` |
| **State** | [Riverpod](https://riverpod.dev/) — `flutter_riverpod`, `riverpod_annotation` |
| **Routing** | **Imperative** `Navigator` + `MaterialPageRoute` (see below). `go_router` is listed in `pubspec.yaml` but **not wired** in `lib/` yet. |
| **Auth** | Supabase Auth; `google_sign_in`, `sign_in_with_apple` |
| **AI / OCR** | Gemini used from **Supabase Edge Functions** (e.g. `process-invoice`); client references model name in `lib/config/gemini_config.dart` |
| **Charts / export** | `fl_chart`, `pdf`, `printing`, `csv` |
| **Media / files** | `image_picker`, `file_picker`, `image`, `pdfrx`, etc. |
| **Observability** | `sentry_flutter` (optional DSN via `--dart-define=SENTRY_DSN=...`) |

---

## Repository layout (high level)

```
billy_con/
├── lib/                      # Flutter application source
│   ├── main.dart             # Entry: WidgetsBinding, Supabase.init, Riverpod, Sentry
│   ├── app/                  # App shell: MaterialApp, layout, header, bottom nav
│   ├── config/               # Supabase URL/key resolution, Gemini model name
│   ├── core/                 # Theme, logging, shared utils
│   ├── features/             # Feature-first modules (screens, widgets, services)
│   ├── providers/            # Cross-feature Riverpod notifiers/providers
│   └── services/             # SupabaseService, transactions, allocation, activity log, etc.
├── supabase/
│   ├── migrations/           # SQL schema + RLS (apply in order)
│   ├── functions/            # Edge Functions (invoice processing, analytics, statements)
│   ├── scripts/              # Maintenance SQL
│   └── README.md             # Bucket names and migration hints
├── config/                   # Optional dart-define JSON (e.g. prod keys) — not committed secrets
├── assets/                   # Branding images
├── docs/                     # Product / engineering docs
└── pubspec.yaml
```

**Convention (from `.cursor/rules` and `AGENTS.md`):** new UI and domain logic live under `lib/features/<feature>/`. Shared networking and Supabase access tend to live in `lib/services/` and `lib/providers/`.

---

## How the app is built and starts

1. **`main.dart`**
   - Calls `WidgetsFlutterBinding.ensureInitialized()`.
   - Wraps startup in optional **`SentryFlutter.init`** when `SENTRY_DSN` is non-empty (compile-time `String.fromEnvironment`).
   - Calls **`Supabase.initialize`** with URL and anon key from `SupabaseConfig` (`lib/config/supabase_config.dart`). On **web**, a custom HTTP client avoids Safari issues with `FetchClient` keepalive.
   - Runs **`runApp(const ProviderScope(child: BillyApp()))`**.

2. **`BillyApp`** (`lib/app/app.dart`)
   - **`ConsumerWidget`** watching `authStateProvider`.
   - If session user is non-null → **`LayoutShell`** (main app). If null → **`LoginScreen`**. Loading shows a spinner; errors fall back to login.
   - Listens to auth changes: on logout, **`pushAndRemoveUntil`** the login route using a root **`navigatorKey`**.

There is **no** `GoRouter` configuration in the current tree; navigation is **stack-based** inside a single `MaterialApp`.

---

## Navigation and “pages”

### Main shell (tabs)

**`LayoutShell`** (`lib/app/layout_shell.dart`) is the home after sign-in:

- **Header:** `BillyHeader` (settings gear opens **Settings** via `Navigator.push`).
- **Body:** One of five tabs, selected by `_activeTab` and **`BillyBottomNav`**:
  | Index | Tab label | Screen widget |
  |------|-----------|----------------|
  | 0 | Home | `DashboardScreen` |
  | 1 | Activity | `ActivityScreen` |
  | 2 | People | `SplitScreen` (lend/borrow / social surfaces) |
  | 3 | Plan | `PlanScreen` |
  | 4 | Insights | `AnalyticsScreen` |
- **Center FAB:** opens scan flow (`ScanScreen` inside a pushed `Scaffold` with app bar), or “add expense” sheets from the dashboard path.

On **`initState`**, the shell refreshes **invitations**, **connections**, and **expense groups** via Riverpod notifiers (`social_provider`, `groups_provider`).

### Pushed routes (examples)

The shell and dashboard use **`Navigator.of(context).push(MaterialPageRoute(...))`** for full screens and **`showModalBottomSheet`** for sheets. Typical destinations include:

- **Scan:** `ScanScreen` (and related scanner UI under `lib/features/scanner/`).
- **Documents:** `DocumentsHistoryScreen`, `DocumentDetailScreen(documentId: ...)`.
- **Export:** `ExportScreen` (with documents prepared for export).
- **Settings:** `SettingsScreen`.

Other **feature screens** exist for deep flows (opened from settings, analytics, groups, etc.): e.g. `DocumentEditScreen`, `ExportHistoryScreen`, `GroupExpensesScreen`, `TransactionDetailScreen`, `StatementReviewScreen`, `DisputeScreen`, `ProfileScreen`, `SuggestionsScreen`, `DocumentAiReviewScreen`, `SettlementConfirmScreen`, `ScanIntentScreen`, and placeholder `GoatModePlaceholderScreen`.

**Rule of thumb:** tab bodies = primary “app sections”; everything else = **pushed** or **modal** on top of that stack.

---

## State management

- **Global / cross-screen state:** **Riverpod** — `ProviderScope` in `main.dart`, `ConsumerWidget` / `ConsumerStatefulWidget` in shell and many screens.
- **Providers** live mainly in `lib/providers/` (documents, transactions, groups, budgets, activity feed, etc.) and sometimes under a feature (e.g. `lib/features/auth/providers/auth_provider.dart`).
- **Auth stream:** `authStateProvider` maps `Supabase.instance.client.auth.onAuthStateChange` to `User?`.

---

## Supabase: what it is here and how the app connects

### What Supabase provides for Billy

- **Authentication** — email/OAuth providers configured in the Supabase project; the client uses the session JWT for API calls.
- **PostgreSQL** — tables such as `documents`, `invoices`, `invoice_items`, `profiles`, `categories`, `lend_borrow_entries`, `splits`, `expense_groups`, `group_expenses`, `group_settlements`, `export_history`, `analytics_insight_snapshots`, `connected_apps`, etc. (evolve over time; source of truth is `supabase/migrations/`).
- **Row Level Security (RLS)** — policies in migrations restrict rows to the owning user (and group/social rules where applicable).
- **Storage** — buckets such as **`invoice-files`** for OCR uploads (see `SupabaseService.signedUrlForInvoiceFile` and `deleteInvoiceForUser`).
- **RPCs** — e.g. `create_group_expense`, `increment_ocr_scan`, `maybe_reset_usage`, contact invitation helpers (`SupabaseService`).
- **Edge Functions** — under `supabase/functions/` (e.g. **`process-invoice`**, **`analytics-insights`**, **`statement-classify`**), typically called over HTTP from the app or from other backends (depending on feature).

### Client connection flow

1. **Configuration** — `lib/config/supabase_config.dart` resolves:
   - **`SUPABASE_URL`** and **`SUPABASE_ANON_KEY`** from **`--dart-define`** / **`--dart-define-from-file`** when set.
   - Otherwise, in **debug** or **web**, it can use **embedded fallbacks** so local runs work without a JSON file. **Release mobile builds** should supply defines (see comments in that file) so the app does not depend on embedded defaults.

2. **Initialization** — `Supabase.initialize(url: ..., anonKey: ...)` in `main.dart`.

3. **Usage** — Most database and storage calls go through **`Supabase.instance.client`** directly or via **`SupabaseService`** (`lib/services/supabase_service.dart`), which centralizes:
   - document CRUD and category resolution,
   - invoice OCR sync/review,
   - lend/borrow, splits, groups, settlements,
   - profile and social APIs,
   - usage limits / OCR counters,
   - dashboard aggregations (today/week spend, recent docs, etc.).

### Migrations and ops

- SQL migrations live in **`supabase/migrations/`** — apply in **timestamp order** on your Supabase project (Dashboard SQL editor or CLI).
- **`supabase/README.md`** documents legacy bucket names (`receipts`, `exports`, `splits`); the codebase also uses **`invoice-files`** for the invoice pipeline — align buckets and RLS with your deployed project.

### Gemini and keys

- **`lib/config/gemini_config.dart`** documents that **API calls for extraction run in Edge Functions** (not with a raw client key in the Flutter app for production flows).
- User or shared API key patterns may appear in migrations (e.g. `user_gemini_api_key`, `shared_api_keys`) — see migrations and function code under `supabase/functions/_shared/`.

---

## Other important paths

| Path | Role |
|------|------|
| `lib/services/transaction_service.dart` | Transaction ledger operations |
| `lib/services/allocation_service.dart` | Allocation / split logic |
| `lib/services/activity_logger.dart` | Activity events |
| `lib/features/invoices/services/invoice_ocr_pipeline.dart` | Client-side orchestration of invoice OCR + storage |
| `lib/core/logging/billy_logger.dart` | Logging helper |
| `AGENTS.md` | How to think about “frontend vs backend vs AI” agents for this repo |
| `frontend-handoff/` | Screen and UX handoff notes (parallel to code) |

---

## Quick reference: `lib/` folders

| Folder | Contents |
|--------|-----------|
| `lib/app/` | `BillyApp`, `LayoutShell`, `billy_header`, `billy_bottom_nav` |
| `lib/config/` | `supabase_config`, `gemini_config` |
| `lib/core/` | `theme`, `logging`, `formatting`, `utils` |
| `lib/features/<name>/` | Per-feature `screens/`, `widgets/`, `services/`, `models/`, `providers/` |
| `lib/providers/` | App-wide Riverpod state |
| `lib/services/` | Supabase and domain services |

---

## Summary

- **Built with** Flutter + Riverpod + Supabase + optional Sentry; Gemini-backed flows are integrated via **Supabase Edge Functions** and related tables/storage.
- **Structure** is **feature-first** under `lib/features/`, with shared **providers** and **services**.
- **Pages** are mostly **`LayoutShell` tabs** plus **Navigator-pushed** screens and **modal bottom sheets**.
- **Supabase** is initialized once in **`main.dart`** from **`SupabaseConfig`**; data access is concentrated in **`SupabaseService`** and table/RLS definitions in **`supabase/migrations/`**.

For product intent and roadmap, see `docs/PRODUCT_BLUEPRINT.md` and `PROJECT_PLAN.md` (if present) in the repo root.
