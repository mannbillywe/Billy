# Billy — Full Production-Readiness Guide

> **Purpose:** A living checklist that takes Billy from "strong MVP" to "App Store / TestFlight-ready production app."
> Every item includes *what* to do, *why* it matters, *how* to implement it, and *where* in the codebase it applies.

---

## Table of Contents

- [Part A — Security](#part-a--security)
  - [A1. Secrets and Configuration](#a1-secrets-and-configuration)
  - [A2. Row-Level Security (RLS) Audit](#a2-row-level-security-rls-audit)
  - [A3. Edge Function Security](#a3-edge-function-security)
  - [A4. Auth Hardening](#a4-auth-hardening)
  - [A5. Input Validation](#a5-input-validation)
  - [A6. CORS Whitelist](#a6-cors-whitelist)
  - [A7. Shared API Keys Table Exposure](#a7-shared-api-keys-table-exposure)
  - [A8. Storage Bucket Policies](#a8-storage-bucket-policies)
- [Part B — Scalability](#part-b--scalability)
  - [B1. N+1 Query Patterns](#b1-n1-query-patterns)
  - [B2. SupabaseService — The God Object](#b2-supabaseservice--the-god-object)
  - [B3. Typed Models Instead of Map](#b3-typed-models-instead-of-map)
  - [B4. Caching and State Management](#b4-caching-and-state-management)
  - [B5. Database Indexing](#b5-database-indexing)
  - [B6. Edge Function Performance](#b6-edge-function-performance)
  - [B7. Pagination](#b7-pagination)
- [Part C — Architecture](#part-c--architecture)
  - [C1. Feature-First Provider Restructure](#c1-feature-first-provider-restructure)
  - [C2. Navigation — Pick One System](#c2-navigation--pick-one-system)
  - [C3. Error Handling Strategy](#c3-error-handling-strategy)
  - [C4. Offline and Connectivity](#c4-offline-and-connectivity)
  - [C5. Money Handling — double vs Decimal](#c5-money-handling--double-vs-decimal)
  - [C6. Export Hardening](#c6-export-hardening)
- [Part D — Testing](#part-d--testing)
  - [D1. Current Test Coverage](#d1-current-test-coverage)
  - [D2. What To Test (Priority Order)](#d2-what-to-test-priority-order)
  - [D3. Making Tests Runnable in CI](#d3-making-tests-runnable-in-ci)
  - [D4. Edge Function Tests](#d4-edge-function-tests)
- [Part E — Observability and Ops](#part-e--observability-and-ops)
  - [E1. Crash Reporting](#e1-crash-reporting)
  - [E2. Analytics / Product Metrics](#e2-analytics--product-metrics)
  - [E3. Performance Monitoring](#e3-performance-monitoring)
  - [E4. Database Maintenance](#e4-database-maintenance)
  - [E5. CI/CD Pipeline](#e5-cicd-pipeline)
- [Part F — UX and Polish](#part-f--ux-and-polish)
  - [F1. Loading, Error, and Empty States](#f1-loading-error-and-empty-states)
  - [F2. Dead Features and Placeholders](#f2-dead-features-and-placeholders)
  - [F3. Accessibility](#f3-accessibility)
  - [F4. Internationalization](#f4-internationalization)
- [Part G — App Store and Distribution](#part-g--app-store-and-distribution)
  - [G1. iOS App Store Checklist](#g1-ios-app-store-checklist)
  - [G2. Android Play Store Checklist](#g2-android-play-store-checklist)
  - [G3. Web (Vercel) Production Checklist](#g3-web-vercel-production-checklist)
  - [G4. TestFlight / Alpha Testing Checklist](#g4-testflight--alpha-testing-checklist)
- [Part H — Priority Matrix](#part-h--priority-matrix)

---

## Part A — Security

### A1. Secrets and Configuration

**Current state:** `lib/config/supabase_config.dart` hardcodes the Supabase project URL and anon key as plain Dart string constants committed to git.

```dart
// CURRENT (lib/config/supabase_config.dart)
class SupabaseConfig {
  static const String url = 'https://wpzopkigbbldcfpxuvcm.supabase.co';
  static const String anonKey = 'eyJhbGciOiJIUzI1NiIs...';
}
```

**Why it matters:**
- You cannot distinguish staging from production without a code change and rebuild.
- If someone ever pastes a service-role key or other real secret into this pattern, it is leaked **forever** in git history (even after removal, it persists in old commits).
- `.env` exists and is `.gitignored`, but nothing in the Flutter code actually reads it at runtime.
- App Store reviewers and security scanners flag hardcoded credentials.

**What to do:**

1. **Use `--dart-define` or `--dart-define-from-file` for per-environment config:**

```dart
// FIXED (lib/config/supabase_config.dart)
class SupabaseConfig {
  static const String url = String.fromEnvironment('SUPABASE_URL');
  static const String anonKey = String.fromEnvironment('SUPABASE_ANON_KEY');
}
```

2. **Create per-environment JSON files (gitignored):**

```
config/
  dev.json      ← local development
  staging.json  ← staging/preview
  prod.json     ← production
```

Each file:
```json
{
  "SUPABASE_URL": "https://your-project.supabase.co",
  "SUPABASE_ANON_KEY": "eyJ...",
  "ENV": "dev"
}
```

3. **Update build commands:**

```bash
# Development
flutter run --dart-define-from-file=config/dev.json

# Production build
flutter build ios --dart-define-from-file=config/prod.json
flutter build appbundle --dart-define-from-file=config/prod.json
flutter build web --dart-define-from-file=config/prod.json
```

4. **Update `.gitignore`:**

```gitignore
# Environment configs (contain project-specific values)
config/dev.json
config/staging.json
config/prod.json

# Native signing
*.jks
*.keystore
key.properties
google-services.json
GoogleService-Info.plist
```

5. **Create `config/example.json` (committed) as a template:**

```json
{
  "SUPABASE_URL": "https://YOUR_PROJECT.supabase.co",
  "SUPABASE_ANON_KEY": "YOUR_ANON_KEY",
  "ENV": "dev"
}
```

6. **Scrub git history** if the repo will ever be public:

```bash
# Using BFG Repo-Cleaner
bfg --replace-text passwords.txt
git reflog expire --expire=now --all && git gc --prune=now --aggressive
```

7. **CI/CD reads secrets from GitHub Secrets / Vercel environment variables**, never from the repository.

8. **Update `deploy-vercel.ps1`** to pass `--dart-define-from-file` during the web build.

---

### A2. Row-Level Security (RLS) Audit

**Current state:** RLS is enabled on every table with user-scoped policies. There are 13 migration files defining policies across ~20 tables.

**Specific issues found:**

| Table / Policy | Issue | Severity |
|---|---|---|
| `documents` | Uses `FOR ALL USING (auth.uid() = user_id)` with no `WITH CHECK` clause. A tampered client could attempt to set `user_id` to another user on INSERT. | **High** |
| `lend_borrow_entries` | Original catch-all policy may still exist alongside the newer per-operation policies from the contacts migration. Need to verify the old one was dropped, not just shadowed. | **Medium** |
| `profiles` | No INSERT policy. Handled by `handle_new_user` trigger (security definer), which is correct. But if any client path ever tries `profiles.insert`, it silently fails with no clear error. | **Low** |
| `invoice_items` | The `invoice_items_all_own` policy uses a subquery against `invoices` for every row operation. For large item sets this creates a performance cliff. | **Medium** |
| `expense_group_members` (original) | Self-referencing RLS caused infinite recursion on Postgres 15+. Fixed in migration `20260402140000`, but must verify it is deployed. | **High** |
| `user_usage_limits` | Comment says "service-only" but the UPDATE policy allows the row owner to modify their own limits/counters. A user could reset their OCR scan count. | **High** |
| `app_api_keys` | SELECT policy allows **any authenticated user** to read the full `api_key` column. This exposes shared Gemini API keys to every user. | **Critical** |
| `analytics_insight_snapshots` | Uses `FOR ALL` with `auth.uid() = user_id` — add explicit per-operation policies with `WITH CHECK`. | **Low** |

**Action items:**

1. **Run the full policy audit query on your Supabase project:**

```sql
SELECT schemaname, tablename, policyname, cmd, qual, with_check
FROM pg_policies
ORDER BY tablename, cmd;
```

Paste the output into a spreadsheet and verify every row.

2. **Add explicit `WITH CHECK` on every INSERT/UPDATE policy.** Example fix for `documents`:

```sql
-- Drop the catch-all
DROP POLICY IF EXISTS "documents_all_own" ON public.documents;

-- Replace with per-operation policies
CREATE POLICY "documents_select_own"
  ON public.documents FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

CREATE POLICY "documents_insert_own"
  ON public.documents FOR INSERT
  TO authenticated
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "documents_update_own"
  ON public.documents FOR UPDATE
  TO authenticated
  USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

CREATE POLICY "documents_delete_own"
  ON public.documents FOR DELETE
  TO authenticated
  USING (auth.uid() = user_id);
```

3. **Fix `user_usage_limits`** — remove the user UPDATE policy; only service-role / security-definer functions should modify limits:

```sql
DROP POLICY IF EXISTS "usage_limits_update_own" ON public.user_usage_limits;

-- If users need to read their limits:
CREATE POLICY "usage_limits_select_own"
  ON public.user_usage_limits FOR SELECT
  TO authenticated
  USING (auth.uid() = user_id);

-- All mutations go through security-definer functions only
```

4. **Fix `app_api_keys`** — remove the SELECT policy for authenticated users; only Edge Functions (via service role) should read keys:

```sql
DROP POLICY IF EXISTS "app_api_keys_select_active" ON public.app_api_keys;

-- No RLS policy for authenticated — only service_role can read
-- Edge Functions already use service role client
```

5. **Write a migration test** — a `.sql` script that connects as a test user and verifies it cannot read/write another user's data:

```sql
-- Run as user A, try to read user B's documents
SET request.jwt.claims = '{"sub": "user-a-uuid", "role": "authenticated"}';
SELECT count(*) FROM documents WHERE user_id = 'user-b-uuid';
-- Should return 0
```

6. **Verify the `expense_group_members` recursion fix** is deployed:

```sql
SELECT proname, prosrc
FROM pg_proc
WHERE proname = 'user_is_expense_group_member';
-- Should exist and use a direct query, not the recursive policy
```

---

### A3. Edge Function Security

**Files:** `supabase/functions/process-invoice/index.ts`, `supabase/functions/analytics-insights/index.ts`

**What's good:**
- Requires `Authorization` header and validates JWT via `getUser()`
- `file_path` must start with `{user.id}/`
- Invoice ownership verified before processing
- Gemini API key resolved server-side, not from client

**Issues to fix:**

1. **Rate-limit `forceReprocess`:** Each force-reprocess call costs Gemini tokens. A malicious user could spam this endpoint. Add per-user rate limiting:

```typescript
// In process-invoice/index.ts
const RATE_LIMIT_WINDOW_MS = 60 * 60 * 1000; // 1 hour
const MAX_REPROCESS_PER_WINDOW = 10;

// Check against invoice_processing_events count in the last hour
const { count } = await serviceClient
  .from('invoice_processing_events')
  .select('*', { count: 'exact', head: true })
  .eq('user_id', user.id)
  .gte('created_at', new Date(Date.now() - RATE_LIMIT_WINDOW_MS).toISOString());

if ((count ?? 0) >= MAX_REPROCESS_PER_WINDOW) {
  return jsonResponse({ success: false, error: { code: 'RATE_LIMITED', message: 'Too many reprocess requests' } }, req, 429);
}
```

2. **Gemini API key validation:** Users can set any string in `profiles.gemini_api_key`. If they set a stolen key, your system makes calls with it. At minimum, validate the key format before use:

```typescript
function isValidGeminiKey(key: string): boolean {
  return /^AIza[0-9A-Za-z_-]{35}$/.test(key);
}
```

3. **Remove partial key logging in production:** Logging `keyPrefix` (first 8 chars of API key) could be considered partial key exposure in compliance contexts:

```typescript
// Replace:
console.log(`Using Gemini key: ${keyPrefix}...`);
// With:
console.log(`Gemini key resolved: source=${keySource}`);
```

4. **Add explicit Content-Length check** to reject oversized payloads early:

```typescript
const contentLength = parseInt(req.headers.get('content-length') ?? '0');
if (contentLength > 1_048_576) { // 1 MB
  return jsonResponse({ success: false, error: { code: 'PAYLOAD_TOO_LARGE', message: 'Request body too large' } }, req, 413);
}
```

5. **Add a timeout on the Gemini fetch call:**

```typescript
const controller = new AbortController();
const timeoutId = setTimeout(() => controller.abort(), 60_000); // 60s

try {
  const result = await model.generateContent({
    contents: [/* ... */],
    signal: controller.signal,
  });
} finally {
  clearTimeout(timeoutId);
}
```

6. **Service role fallback risk:** If `SUPABASE_SERVICE_ROLE_KEY` is unset, the code falls back to the anon key for the service client. This silently degrades security. Fail hard instead:

```typescript
const serviceRoleKey = Deno.env.get('SUPABASE_SERVICE_ROLE_KEY');
if (!serviceRoleKey) {
  return jsonResponse({ success: false, error: { code: 'CONFIG_ERROR', message: 'Server misconfiguration' } }, req, 500);
}
```

---

### A4. Auth Hardening

1. **Email confirmation:** Ensure it is enabled in Supabase Dashboard → Auth → Settings → Email. Without it, `signUp` creates fully active accounts with unverified emails.

2. **Password policy:** Supabase default minimum is 6 characters. For a financial app, raise to 8+ characters via the Dashboard. Consider adding:
   - Minimum 1 uppercase letter
   - Minimum 1 number
   - Password breach checking (via HaveIBeenPwned API in a trigger or Edge Function)

3. **Google OAuth redirect URIs:** Verify these are set in Google Cloud Console:
   - `https://wpzopkigbbldcfpxuvcm.supabase.co/auth/v1/callback` (Supabase)
   - `http://localhost:3000` (local dev)
   - `https://your-production-domain.com` (production)
   - Any Vercel preview domains

4. **Apple Sign-In:** You have `sign_in_with_apple` in pubspec — ensure the App ID, Service ID, and key are configured in Apple Developer portal and Supabase Dashboard.

5. **Session management:**
   - On web: verify `persistSession: true` and that tokens are stored safely. Consider `sessionStorage` instead of `localStorage` for shared/public computers.
   - Add a "Sign out all devices" button on the profile screen for financial data safety.
   - Implement session timeout: auto-sign-out after 30 minutes of inactivity for web.

6. **Deep link handling:** Configure universal links (iOS) and app links (Android) so that auth callbacks route correctly on mobile:
   - iOS: `apple-app-site-association` file
   - Android: `assetlinks.json` file
   - Flutter: `supabase_flutter` deep link config in `main.dart`

---

### A5. Input Validation

**Client-side (Flutter):**

| Field | Current | Fix |
|---|---|---|
| Vendor name | `vendor.isEmpty` check only | Add `maxLength: 500` to `TextField` |
| Notes / description | No length check | Add `maxLength: 2000` to `TextField` |
| Counterparty name | No length check | Add `maxLength: 200` to `TextField` |
| Amount fields | `amount <= 0` check | Also check `amount <= 9999999999.99` (matches `decimal(12,2)`) |
| All text inputs | No sanitization | Strip leading/trailing whitespace with `.trim()` before save |

**Server-side (Postgres):**

Add column constraints in a new migration:

```sql
-- Text length constraints
ALTER TABLE public.documents
  ADD CONSTRAINT documents_vendor_name_length CHECK (length(vendor_name) <= 500),
  ADD CONSTRAINT documents_description_length CHECK (length(description) <= 2000);

ALTER TABLE public.lend_borrow_entries
  ADD CONSTRAINT lbe_counterparty_name_length CHECK (length(counterparty_name) <= 200),
  ADD CONSTRAINT lbe_description_length CHECK (length(description) <= 2000);

ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_display_name_length CHECK (length(display_name) <= 200);

-- Amount range constraints (prevent absurd values)
ALTER TABLE public.documents
  ADD CONSTRAINT documents_amount_range CHECK (amount >= 0 AND amount <= 9999999999.99);

ALTER TABLE public.lend_borrow_entries
  ADD CONSTRAINT lbe_amount_range CHECK (amount > 0 AND amount <= 9999999999.99);
```

**Edge Function:**
- `invoice_id` and `file_path` are validated as non-empty strings — good.
- `raw_text` is truncated to 12,000 chars — reasonable.
- Add explicit type checks on all parsed Gemini output fields before database writes.

---

### A6. CORS Whitelist

**Current state:** Edge Functions reflect any `Origin` header:

```typescript
// CURRENT — reflects any origin
const allowOrigin =
  origin && (origin.startsWith("http://") || origin.startsWith("https://"))
    ? origin
    : "*";
```

**Fix:** Whitelist known domains:

```typescript
const ALLOWED_ORIGINS = new Set([
  'https://billy.yourdomain.com',        // production
  'https://billy-preview.vercel.app',     // Vercel preview
  'http://localhost:3000',                // local dev (web)
  'http://localhost:54321',               // local Supabase
]);

function corsHeadersFor(req: Request): Record<string, string> {
  const origin = req.headers.get('Origin') ?? '';
  const allowOrigin = ALLOWED_ORIGINS.has(origin) ? origin : '';

  if (!allowOrigin) {
    return {}; // No CORS headers = browser blocks the request
  }

  return {
    'Access-Control-Allow-Origin': allowOrigin,
    'Access-Control-Allow-Methods': 'POST, OPTIONS',
    'Access-Control-Allow-Headers': 'authorization, x-client-info, apikey, content-type',
    'Access-Control-Max-Age': '86400',
    'Vary': 'Origin',
  };
}
```

Apply this fix to **both** `process-invoice/index.ts` and `analytics-insights/index.ts`.

---

### A7. Shared API Keys Table Exposure

**Critical finding:** Migration `20260405160000_shared_api_keys.sql` creates a SELECT policy that lets **any authenticated user** read the full `api_key` value from `app_api_keys`.

```sql
-- CURRENT (DANGEROUS)
CREATE POLICY "app_api_keys_select_active"
  ON public.app_api_keys FOR SELECT
  TO authenticated
  USING (is_active = true);
```

This means any logged-in user can run:
```sql
SELECT api_key FROM app_api_keys WHERE provider = 'gemini';
```

**Fix:** Remove this policy entirely. Only service-role (used by Edge Functions) should access this table:

```sql
-- New migration: fix_app_api_keys_rls.sql
DROP POLICY IF EXISTS "app_api_keys_select_active" ON public.app_api_keys;

-- No policies for authenticated role.
-- Edge Functions use serviceClient (service_role) which bypasses RLS.
```

If you need the client to know whether a shared key *exists* (without seeing it), create an RPC:

```sql
CREATE OR REPLACE FUNCTION public.has_shared_api_key(p_provider text)
RETURNS boolean
LANGUAGE sql
SECURITY DEFINER
STABLE
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.app_api_keys
    WHERE provider = p_provider AND is_active = true
  );
$$;

GRANT EXECUTE ON FUNCTION public.has_shared_api_key TO authenticated;
```

---

### A8. Storage Bucket Policies

**Current state:** The `invoice-files` bucket is private with MIME allowlists.

**Verify these storage policies exist** (they may not be in migration files — check via Supabase Dashboard → Storage → Policies):

```sql
-- Users can only upload to their own folder
CREATE POLICY "users_upload_own_files"
  ON storage.objects FOR INSERT
  TO authenticated
  WITH CHECK (
    bucket_id = 'invoice-files'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Users can only read their own files
CREATE POLICY "users_read_own_files"
  ON storage.objects FOR SELECT
  TO authenticated
  USING (
    bucket_id = 'invoice-files'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );

-- Users can only delete their own files
CREATE POLICY "users_delete_own_files"
  ON storage.objects FOR DELETE
  TO authenticated
  USING (
    bucket_id = 'invoice-files'
    AND (storage.foldername(name))[1] = auth.uid()::text
  );
```

Without these, any authenticated user could overwrite another user's invoice files.

---

## Part B — Scalability

### B1. N+1 Query Patterns

**Pattern 1 — `ConnectionsNotifier.build()` in `social_provider.dart`:**

```dart
// CURRENT — N+1: one HTTP call per connection
for (final r in rows) {
  final other = r['user_low'] == uid ? r['user_high'] : r['user_low'];
  final p = await SupabaseService.fetchProfileById(other);
  // ...
}
```

With 20 connections = 20 sequential HTTP round-trips. At 50+, this takes several seconds.

**Fix:** Single query with `inFilter`:

```dart
final otherIds = rows.map((r) {
  return r['user_low'] == uid ? r['user_high'] : r['user_low'];
}).toList();

final profiles = await Supabase.instance.client
    .from('profiles')
    .select('id, display_name, avatar_url')
    .inFilter('id', otherIds);

final profileMap = {for (final p in profiles) p['id'] as String: p};

// Now look up from profileMap instead of fetching one by one
```

**Pattern 2 — `dailySpendForWeek()` in `supabase_service.dart`:**

Makes 7 sequential Supabase calls, one per day.

**Fix:** Single query for the 7-day range, bucket client-side:

```dart
static Future<Map<String, double>> dailySpendForWeek(DateTime weekStart) async {
  final weekEnd = weekStart.add(const Duration(days: 7));
  final rows = await _client.from('documents')
      .select('date, amount')
      .eq('user_id', _uid)
      .gte('date', weekStart.toIso8601String().substring(0, 10))
      .lt('date', weekEnd.toIso8601String().substring(0, 10));

  final result = <String, double>{};
  for (final row in rows) {
    final date = row['date'] as String;
    result[date] = (result[date] ?? 0) + ((row['amount'] as num?)?.toDouble() ?? 0);
  }
  return result;
}
```

**Other N+1 locations to check:**
- Any `for` loop that calls `SupabaseService.fetchX()` per iteration
- Group expenses loading members individually
- Any place that loads a list, then loads related data item-by-item

---

### B2. SupabaseService — The God Object

**Current state:** `lib/services/supabase_service.dart` has **49 public static methods** covering documents, exports, invoices, lend/borrow, splits, profile, social, groups, usage limits, and dashboard aggregates.

**Problems:**
- Cannot mock for tests (static methods are not overridable)
- Cannot swap implementations (e.g., add offline cache layer)
- Every import pulls in the entire 49-method surface area
- No separation of concerns — a change to group logic risks breaking document logic

**Recommended refactor — Repository pattern:**

```
lib/
  data/
    repositories/
      document_repository.dart           # abstract interface
      supabase_document_repository.dart   # Supabase implementation
      group_repository.dart
      supabase_group_repository.dart
      social_repository.dart
      supabase_social_repository.dart
      lend_borrow_repository.dart
      supabase_lend_borrow_repository.dart
      profile_repository.dart
      supabase_profile_repository.dart
      invoice_repository.dart
      supabase_invoice_repository.dart
```

**Example implementation:**

```dart
// lib/data/repositories/document_repository.dart
abstract class DocumentRepository {
  Future<List<Document>> fetchAll();
  Future<Document> fetchById(String id);
  Future<void> insert(Document doc);
  Future<void> update(Document doc);
  Future<void> delete(String id);
  Future<Map<String, double>> dailySpendForRange(DateTime start, DateTime end);
}
```

```dart
// lib/data/repositories/supabase_document_repository.dart
class SupabaseDocumentRepository implements DocumentRepository {
  final SupabaseClient _client;

  SupabaseDocumentRepository(this._client);

  @override
  Future<List<Document>> fetchAll() async {
    final rows = await _client.from('documents')
        .select()
        .eq('user_id', _client.auth.currentUser!.id)
        .order('date', ascending: false);
    return rows.map(Document.fromJson).toList();
  }

  // ... other methods
}
```

**Riverpod provider:**

```dart
final documentRepositoryProvider = Provider<DocumentRepository>((ref) {
  return SupabaseDocumentRepository(Supabase.instance.client);
});

// Notifier depends on abstraction
class DocumentsNotifier extends AsyncNotifier<List<Document>> {
  @override
  Future<List<Document>> build() async {
    final repo = ref.watch(documentRepositoryProvider);
    return repo.fetchAll();
  }
}
```

**Migration strategy:** Don't rewrite everything at once. Start with the most-tested feature (documents), then migrate one repository at a time. Keep `SupabaseService` methods that haven't been migrated yet — gradually empty it.

---

### B3. Typed Models Instead of Map

**Current state:** Almost every provider and service deals in `Map<String, dynamic>`. Only a few models exist (`ExtractedReceipt`, `ExportDocument`, `DocumentCategorySource`).

**Problems:**
- No compile-time safety: `d['vendor_Name']` (typo) silently returns `null`
- No IDE autocompletion
- Every widget must cast and null-check: `(d['amount'] as num?)?.toDouble() ?? 0`
- Refactoring column names requires grep-and-pray

**Create model classes for every table:**

```dart
// lib/features/documents/models/document.dart
class Document {
  final String id;
  final String userId;
  final String vendorName;
  final double amount;
  final double taxAmount;
  final DateTime date;
  final String type; // 'invoice' | 'receipt' | 'expense'
  final String? description;
  final String? category;
  final String? categorySource;
  final String status;
  final String? imageUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  const Document({
    required this.id,
    required this.userId,
    required this.vendorName,
    required this.amount,
    required this.taxAmount,
    required this.date,
    required this.type,
    this.description,
    this.category,
    this.categorySource,
    required this.status,
    this.imageUrl,
    required this.createdAt,
    required this.updatedAt,
  });

  factory Document.fromJson(Map<String, dynamic> json) => Document(
    id: json['id'] as String,
    userId: json['user_id'] as String,
    vendorName: json['vendor_name'] as String? ?? '',
    amount: (json['amount'] as num?)?.toDouble() ?? 0,
    taxAmount: (json['tax_amount'] as num?)?.toDouble() ?? 0,
    date: DateTime.parse(json['date'] as String),
    type: json['type'] as String? ?? 'expense',
    description: json['description'] as String?,
    category: json['category'] as String?,
    categorySource: json['category_source'] as String?,
    status: json['status'] as String? ?? 'manual',
    imageUrl: json['image_url'] as String?,
    createdAt: DateTime.parse(json['created_at'] as String),
    updatedAt: DateTime.parse(json['updated_at'] as String),
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'user_id': userId,
    'vendor_name': vendorName,
    'amount': amount,
    'tax_amount': taxAmount,
    'date': date.toIso8601String().substring(0, 10),
    'type': type,
    'description': description,
    'category': category,
    'category_source': categorySource,
    'status': status,
    'image_url': imageUrl,
  };
}
```

**Priority order for model creation:**

1. `Document` (used everywhere — dashboard, analytics, export, history)
2. `LendBorrowEntry` (money logic — must be correct)
3. `ExpenseGroup` + `ExpenseGroupMember`
4. `GroupExpense` + `GroupExpenseParticipant`
5. `Profile`
6. `Invoice` + `InvoiceItem`
7. `GroupSettlement`
8. `ContactInvitation` + `UserConnection`

---

### B4. Caching and State Management

**Current behavior:**
- `documentsProvider` fetches all documents on `build()`. Every tab switch that depends on it triggers a re-read when invalidated.
- `dailySpendProvider`, `weekSpendProvider`, `recentDocsProvider` each watch `documentsProvider` — a single invalidation cascades into 4+ network calls.
- `profileProvider` is a plain `FutureProvider` that refetches from scratch when invalidated.

**Improvements:**

1. **Add `ref.keepAlive()` to stable providers:**

```dart
final profileProvider = FutureProvider<Map<String, dynamic>>((ref) async {
  ref.keepAlive(); // Don't discard when no listeners
  return SupabaseService.fetchProfile();
});
```

2. **Derive dashboard stats from loaded documents client-side** instead of making separate Supabase calls:

```dart
// Instead of separate dailySpendProvider that calls Supabase
final weeklySpendProvider = Provider<Map<String, double>>((ref) {
  final docs = ref.watch(documentsProvider).valueOrNull ?? [];
  final now = DateTime.now();
  final weekStart = now.subtract(Duration(days: now.weekday - 1));

  final result = <String, double>{};
  for (final doc in docs) {
    final date = doc['date'] as String;
    if (DateTime.parse(date).isAfter(weekStart)) {
      result[date] = (result[date] ?? 0) + ((doc['amount'] as num?)?.toDouble() ?? 0);
    }
  }
  return result;
});
```

3. **Add pagination from day one** (see B7).

4. **Implement optimistic updates:**

```dart
Future<void> addDocument(Document doc) async {
  // Immediately update local state
  state = AsyncData([doc, ...state.value ?? []]);

  try {
    await ref.read(documentRepositoryProvider).insert(doc);
  } catch (e) {
    // Rollback on failure
    state = AsyncData([...state.value?.where((d) => d.id != doc.id) ?? []]);
    rethrow;
  }
}
```

5. **Consider Supabase Realtime subscriptions** for multi-device sync:

```dart
void _listenToChanges() {
  Supabase.instance.client
    .from('documents')
    .stream(primaryKey: ['id'])
    .eq('user_id', Supabase.instance.client.auth.currentUser!.id)
    .listen((data) {
      state = AsyncData(data.map(Document.fromJson).toList());
    });
}
```

---

### B5. Database Indexing

The schema has basic indexes. For production-scale queries, add:

```sql
-- Analytics: user + date range (the most common query pattern)
CREATE INDEX IF NOT EXISTS idx_documents_user_date
  ON public.documents (user_id, date DESC)
  INCLUDE (amount, type, category);

-- Group expenses by group + date
CREATE INDEX IF NOT EXISTS idx_group_expenses_group_date
  ON public.group_expenses (group_id, expense_date DESC);

-- Lend/borrow: OR queries need both columns indexed separately
CREATE INDEX IF NOT EXISTS idx_lend_borrow_counterparty_status
  ON public.lend_borrow_entries (counterparty_user_id, status);

-- Invoice processing: user + status for dashboard queries
CREATE INDEX IF NOT EXISTS idx_invoices_user_status
  ON public.invoices (user_id, status);

-- Contact invitations: recipient lookup
CREATE INDEX IF NOT EXISTS idx_invitations_recipient
  ON public.contact_invitations (recipient_user_id, status);

-- OCR logs: user + created_at for history
CREATE INDEX IF NOT EXISTS idx_ocr_logs_user_created
  ON public.invoice_ocr_logs (user_id, created_at DESC);
```

**Validation:** Run `EXPLAIN ANALYZE` on your most common queries from `SupabaseService` to confirm index usage:

```sql
EXPLAIN ANALYZE
SELECT * FROM documents
WHERE user_id = 'some-uuid'
  AND date >= '2026-01-01'
  AND date < '2026-02-01'
ORDER BY date DESC;
```

Look for `Index Scan` or `Index Only Scan` — if you see `Seq Scan`, an index is missing.

---

### B6. Edge Function Performance

1. **Cold starts:** Supabase Edge Functions (Deno) have cold starts of 200-500ms. For OCR this is fine (already async). If you add more functions:
   - Consider consolidating related functions
   - Set up a cron ping to keep critical functions warm

2. **Image size:** The function downloads the full image from Storage and sends it to Gemini as base64. For very large images (16 MB = ~22 MB base64), this is a lot of memory.
   - You already set `maxWidth: 1920, imageQuality: 85` for camera captures — good
   - **Extend this to file picker uploads too** (currently unconstrained)
   - Consider server-side image resizing before Gemini if the client doesn't resize

3. **Fetch timeout on Gemini call:** There is currently no timeout. Add:

```typescript
const controller = new AbortController();
const timeout = setTimeout(() => controller.abort(), 60_000);

try {
  const result = await model.generateContent(/* ... */);
} finally {
  clearTimeout(timeout);
}
```

4. **Background processing:** The use of `EdgeRuntime.waitUntil()` for async processing with 202 responses is excellent — keep this pattern.

---

### B7. Pagination

| Endpoint | Current | Recommended |
|---|---|---|
| `fetchDocuments` | All rows, no limit | Cursor pagination (keyset on `date DESC, id`) — load 50 at a time |
| `fetchLendBorrow` | All rows | Paginate; show "pending" first, "settled" on demand |
| `fetchContactInvitations` | All rows | Fine for now (unlikely to be >100) |
| `fetchExpenseGroups` | All rows + nested members | Fine until ~50 groups |
| `fetchGroupExpenses` | All rows per group | Paginate by `expense_date` |
| `invoice_ocr_logs` | All rows | Paginate; these grow fast with OCR usage |

**Example pagination implementation:**

```dart
// Repository
Future<List<Document>> fetchDocuments({
  int limit = 50,
  String? afterId,
  DateTime? afterDate,
}) async {
  var query = _client.from('documents')
      .select()
      .eq('user_id', _uid)
      .order('date', ascending: false)
      .order('id', ascending: false)
      .limit(limit);

  if (afterDate != null && afterId != null) {
    query = query.or('date.lt.${afterDate.toIso8601String()},and(date.eq.${afterDate.toIso8601String()},id.lt.$afterId)');
  }

  return (await query).map(Document.fromJson).toList();
}
```

```dart
// Notifier with infinite scroll
class DocumentsNotifier extends AsyncNotifier<List<Document>> {
  bool _hasMore = true;

  Future<void> loadMore() async {
    if (!_hasMore) return;
    final current = state.value ?? [];
    final lastDoc = current.isNotEmpty ? current.last : null;

    final newDocs = await ref.read(documentRepositoryProvider).fetchDocuments(
      limit: 50,
      afterId: lastDoc?.id,
      afterDate: lastDoc?.date,
    );

    _hasMore = newDocs.length == 50;
    state = AsyncData([...current, ...newDocs]);
  }
}
```

---

## Part C — Architecture

### C1. Feature-First Provider Restructure

**Current state:** Features live in `lib/features/` (good), but all providers live in `lib/providers/` — a flat bag of 9 files. This breaks the feature-first pattern.

**Recommended structure:**

```
lib/
  features/
    documents/
      models/document.dart
      repositories/document_repository.dart
      providers/documents_provider.dart
      screens/
      widgets/
    scanner/
      models/extracted_receipt.dart
      providers/scan_provider.dart
      screens/
      widgets/
    analytics/
      models/
      providers/analytics_insights_provider.dart
      services/analytics_insights_service.dart
      screens/
      widgets/
    social/
      providers/social_provider.dart
      providers/groups_provider.dart
      providers/group_expenses_provider.dart
      providers/group_settlements_provider.dart
      screens/
    lend_borrow/
      providers/lend_borrow_provider.dart
      providers/splits_provider.dart
      screens/
    export/
      models/
      services/
      screens/
    profile/
      providers/profile_provider.dart
      screens/
    auth/
      providers/auth_provider.dart
      screens/
  shared/
    repositories/  # cross-feature interfaces
    services/      # shared utilities
    widgets/       # reusable UI components
  core/
    logging/
    utils/
    formatting/
    theme/
  data/
    repositories/  # if you prefer centralized repos
```

Each feature is self-contained. Cross-feature dependencies go through `shared/` or the repository abstraction layer.

---

### C2. Navigation — Pick One System

**Current state:** `go_router: ^14.6.2` is in `pubspec.yaml` but is not used anywhere. The app uses `Navigator.push` / `MaterialPageRoute` everywhere and a tab index integer in `LayoutShell`.

**For production, pick one:**

**Option A — Adopt `go_router` (recommended for web deployment):**
- Deep linking works (`billy.app/analytics` lands on analytics tab)
- Web URL support (users can bookmark and share URLs)
- Declarative routing with type-safe parameters
- Better integration with browser back/forward buttons

```dart
final router = GoRouter(
  routes: [
    ShellRoute(
      builder: (context, state, child) => LayoutShell(child: child),
      routes: [
        GoRoute(path: '/', builder: (_, __) => const DashboardScreen()),
        GoRoute(path: '/analytics', builder: (_, __) => const AnalyticsScreen()),
        GoRoute(path: '/scan', builder: (_, __) => const ScanScreen()),
        GoRoute(path: '/split', builder: (_, __) => const SplitScreen()),
        GoRoute(path: '/settings', builder: (_, __) => const SettingsScreen()),
        GoRoute(
          path: '/document/:id',
          builder: (_, state) => DocumentDetailScreen(id: state.pathParameters['id']!),
        ),
      ],
    ),
    GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
  ],
  redirect: (context, state) {
    final isLoggedIn = Supabase.instance.client.auth.currentUser != null;
    if (!isLoggedIn && state.matchedLocation != '/login') return '/login';
    if (isLoggedIn && state.matchedLocation == '/login') return '/';
    return null;
  },
);
```

**Option B — Remove `go_router` from dependencies** to avoid confusion:

```bash
flutter pub remove go_router
```

If you deploy to web via Vercel, Option A is strongly recommended — currently all web users always land on the dashboard after auth, regardless of what URL they navigated to.

---

### C3. Error Handling Strategy

**Current state:** Most providers do `try/catch` and show `SnackBar`. Some providers set `AsyncValue.error`. No unified pattern.

**Recommended layered approach:**

**Layer 1 — Typed exceptions:**

```dart
// lib/core/errors/app_exceptions.dart
sealed class AppException implements Exception {
  final String message;
  final Object? cause;
  const AppException(this.message, [this.cause]);
}

class NetworkException extends AppException {
  const NetworkException([String message = 'Network error', Object? cause])
      : super(message, cause);
}

class AuthExpiredException extends AppException {
  const AuthExpiredException() : super('Session expired');
}

class NotFoundError extends AppException {
  const NotFoundError(String entity) : super('$entity not found');
}

class ValidationError extends AppException {
  final Map<String, String> fieldErrors;
  const ValidationError(this.fieldErrors) : super('Validation failed');
}

class RateLimitError extends AppException {
  const RateLimitError() : super('Too many requests');
}
```

**Layer 2 — Repository layer catches and maps Supabase errors:**

```dart
Future<List<Document>> fetchAll() async {
  try {
    final rows = await _client.from('documents').select()
        .eq('user_id', _client.auth.currentUser!.id);
    return rows.map(Document.fromJson).toList();
  } on AuthException catch (e) {
    throw AuthExpiredException();
  } on PostgrestException catch (e) {
    throw NetworkException('Database error', e);
  } catch (e) {
    throw NetworkException('Unexpected error', e);
  }
}
```

**Layer 3 — Provider/notifier catches and sets AsyncValue.error with typed error.**

**Layer 4 — Global error observer:**

```dart
class BillyProviderObserver extends ProviderObserver {
  @override
  void providerDidFail(
    ProviderBase provider,
    Object error,
    StackTrace stackTrace,
    ProviderContainer container,
  ) {
    CrashReporting.report(error, stackTrace, extra: {
      'provider': provider.name ?? provider.runtimeType.toString(),
    });
  }
}

// In main.dart
runApp(ProviderScope(
  observers: [BillyProviderObserver()],
  child: const BillyApp(),
));
```

**Layer 5 — Shared error UI widget:**

```dart
class ErrorBanner extends ConsumerWidget {
  final Object error;
  final VoidCallback? onRetry;

  const ErrorBanner({required this.error, this.onRetry});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final message = switch (error) {
      AuthExpiredException() => 'Session expired. Please sign in again.',
      NetworkException() => 'Network error. Check your connection.',
      RateLimitError() => 'Too many requests. Please wait.',
      _ => 'Something went wrong.',
    };

    return MaterialBanner(
      content: Text(message),
      actions: [
        if (onRetry != null)
          TextButton(onPressed: onRetry, child: const Text('Retry')),
        if (error is AuthExpiredException)
          TextButton(
            onPressed: () => Supabase.instance.client.auth.signOut(),
            child: const Text('Sign In'),
          ),
      ],
    );
  }
}
```

---

### C4. Offline and Connectivity

**Current state:** No offline handling. If the device loses connectivity, providers throw and the UI shows error states (at best) or silently fails (at worst). Manual expense entry is lost if the save call fails.

**Minimum viable implementation (do this first):**

1. **Add `connectivity_plus` package:**

```bash
flutter pub add connectivity_plus
```

2. **Create a connectivity provider:**

```dart
final connectivityProvider = StreamProvider<bool>((ref) {
  return Connectivity().onConnectivityChanged.map(
    (results) => results.any((r) => r != ConnectivityResult.none),
  );
});
```

3. **Show an offline banner:**

```dart
class OfflineBanner extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isOnline = ref.watch(connectivityProvider).valueOrNull ?? true;
    if (isOnline) return const SizedBox.shrink();

    return MaterialBanner(
      backgroundColor: Colors.orange.shade100,
      content: const Text('You are offline. Changes will sync when connected.'),
      actions: [const SizedBox.shrink()],
    );
  }
}
```

**Full implementation (later):**

4. **Queue mutations locally** using `shared_preferences` or `hive`:

```dart
class OfflineQueue {
  static Future<void> enqueue(Map<String, dynamic> mutation) async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList('offline_queue') ?? [];
    queue.add(jsonEncode(mutation));
    await prefs.setStringList('offline_queue', queue);
  }

  static Future<void> flush() async {
    final prefs = await SharedPreferences.getInstance();
    final queue = prefs.getStringList('offline_queue') ?? [];
    for (final item in queue) {
      final mutation = jsonDecode(item) as Map<String, dynamic>;
      await _executeMutation(mutation);
    }
    await prefs.setStringList('offline_queue', []);
  }
}
```

5. **Cache last-known data** so the dashboard renders instantly on cold start, then hydrate from network.

---

### C5. Money Handling — double vs Decimal

**Current state:** All money amounts are Dart `double`. This causes floating-point precision issues:

```dart
print(0.1 + 0.2); // 0.30000000000000004
```

Your share-splitting code uses `round2` to mitigate:
```dart
double round2(double x) => (x * 100).round() / 100;
```

**For production correctness, choose one approach:**

**Option A — Integer cents (simpler, recommended for Billy):**

```dart
// Store and transmit amounts as integer cents
// amount: 1299 = $12.99
// Only divide by 100 for display

class Money {
  final int cents;
  const Money(this.cents);

  factory Money.fromDouble(double amount) => Money((amount * 100).round());

  double toDouble() => cents / 100;

  String format(String currencySymbol) {
    final formatter = NumberFormat.currency(symbol: currencySymbol, decimalDigits: 2);
    return formatter.format(toDouble());
  }

  Money operator +(Money other) => Money(cents + other.cents);
  Money operator -(Money other) => Money(cents - other.cents);
}
```

**Option B — Use the `decimal` package:**

```bash
flutter pub add decimal
```

```dart
import 'package:decimal/decimal.dart';

final amount = Decimal.parse('12.99');
final tax = Decimal.parse('1.04');
final total = amount + tax; // Exact: 14.03
```

**Priority:** At minimum, audit `group_balance.dart` and `scan_review_panel.dart` where split math determines how much money people owe each other.

---

### C6. Export Hardening

**Issue 1 — Hardcoded currency:**

```dart
// CURRENT (lib/features/export/services/pdf_generator.dart)
final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');

// CURRENT (lib/features/export/services/csv_generator.dart)
final _currencyFormat = NumberFormat.currency(locale: 'en_IN', symbol: '₹');
```

But the user's `preferred_currency` can be USD, EUR, GBP, etc.

**Fix:** Pass currency from user profile:

```dart
class PdfGenerator {
  final NumberFormat _currencyFormat;

  PdfGenerator({required String currencyCode})
      : _currencyFormat = AppCurrency.formatterFor(currencyCode);

  // ... rest of the class
}
```

**Issue 2 — `export_history` table exists but exports don't write to it.** Either:
- Write to it (for audit trail) — useful for compliance
- Drop the table and migration (to avoid confusion)

---

## Part D — Testing

### D1. Current Test Coverage

**One file:** `test/widget_test.dart` — a smoke test that:
- Calls `Supabase.initialize` with **real** project URL and anon key
- Pumps `ProviderScope` + `BillyApp`
- Asserts one `MaterialApp` exists

**Problems:**
- Cannot run in CI without network access
- Tests nothing meaningful (no business logic, no UI behavior)
- Depends on real Supabase project being available

---

### D2. What To Test (Priority Order)

**Tier 1: Unit tests (pure Dart, no Flutter, no network) — DO THESE FIRST**

| What | Why | File |
|---|---|---|
| `group_balance.dart` — `expenseNetFromRows`, `applySettlements` | Money math correctness — if wrong, people are owed incorrect amounts | `lib/features/groups/group_balance.dart` |
| `lend_borrow_perspective.dart` — `effectiveTypeForViewer` | Role flip logic — must be correct for both parties | `lib/features/lend_borrow/lend_borrow_perspective.dart` |
| `DocumentDateRange.forFilter`, `filterDocuments` | Date filtering — easy to get off-by-one | `lib/core/utils/document_date_range.dart` |
| `AppCurrency.format`, `formatCompact` | Currency display edge cases (0, negative, large numbers, different currencies) | `lib/core/formatting/app_currency.dart` |
| Share splitting: `_sharesFromAgg` / `_equalShares` | Rounding must exactly match the target total | `lib/features/scanner/widgets/scan_review_panel.dart` |
| `ExtractedReceipt.fromJson`, `.fromInvoiceOcr` | Parsing robustness with malformed/partial JSON | `lib/features/scanner/models/extracted_receipt.dart` |
| `ExportDocument.documentsForExport` | Correct mapping from raw data to export format | `lib/features/export/models/export_document.dart` |
| `normalizeFromGeminiJson` (Edge Function) | The most critical parsing logic — test with 20+ real receipt JSONs | `supabase/functions/process-invoice/index.ts` |

**Example test file:**

```dart
// test/unit/group_balance_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:billy/features/groups/group_balance.dart';

void main() {
  group('expenseNetFromRows', () {
    test('single expense with two equal participants', () {
      final rows = [
        {
          'id': '1',
          'total_amount': 100.0,
          'paid_by': 'alice',
          'participants': [
            {'user_id': 'alice', 'share_amount': 50.0},
            {'user_id': 'bob', 'share_amount': 50.0},
          ],
        },
      ];
      final net = expenseNetFromRows(rows, 'alice');
      expect(net['bob'], equals(-50.0)); // bob owes alice 50
    });

    test('rounding with three-way split', () {
      final rows = [
        {
          'id': '1',
          'total_amount': 100.0,
          'paid_by': 'alice',
          'participants': [
            {'user_id': 'alice', 'share_amount': 33.34},
            {'user_id': 'bob', 'share_amount': 33.33},
            {'user_id': 'charlie', 'share_amount': 33.33},
          ],
        },
      ];
      final net = expenseNetFromRows(rows, 'alice');
      // Total shares = 100.00; alice paid 100, her share is 33.34
      // So alice is owed 66.66 total from bob + charlie
      expect(net.values.fold<double>(0, (a, b) => a + b), closeTo(-66.66, 0.01));
    });

    test('empty rows returns empty map', () {
      expect(expenseNetFromRows([], 'alice'), isEmpty);
    });
  });

  group('applySettlements', () {
    test('settlement reduces debt', () {
      final net = {'bob': -50.0}; // bob owes alice 50
      final settlements = [
        {'payer_id': 'bob', 'payee_id': 'alice', 'amount': 30.0},
      ];
      final result = applySettlements(net, settlements, 'alice');
      expect(result['bob'], closeTo(-20.0, 0.01)); // bob now owes 20
    });
  });
}
```

**Tier 2: Repository/provider tests (mocked Supabase)**

With the repository pattern from B2, these become trivial:

```dart
// test/providers/documents_provider_test.dart
class FakeDocumentRepository implements DocumentRepository {
  final List<Document> _docs;
  FakeDocumentRepository(this._docs);

  @override
  Future<List<Document>> fetchAll() async => _docs;
  // ... other methods return test data
}

void main() {
  test('DocumentsNotifier loads documents', () async {
    final container = ProviderContainer(overrides: [
      documentRepositoryProvider.overrideWithValue(
        FakeDocumentRepository([
          Document(id: '1', vendorName: 'Test', amount: 50, ...),
        ]),
      ),
    ]);

    final notifier = container.read(documentsProvider.notifier);
    await container.read(documentsProvider.future);

    expect(container.read(documentsProvider).value?.length, equals(1));
  });
}
```

**Tier 3: Widget tests**

| Screen | What to test |
|---|---|
| `LoginScreen` | Email validation, error states, loading indicator |
| `AddExpenseSheet` | Empty fields rejected, valid submission calls provider |
| `ScanReviewPanel` | Line item selection math, share splitting correctness |
| `DashboardScreen` | Displays correct totals from provider data |
| `ExportScreen` | Date range filter, format selection |

**Tier 4: Integration / E2E**

| Flow | Steps |
|---|---|
| Full scan flow | Pick image → processing → review → save → appears in dashboard |
| Export flow | Filter by date → generate PDF → verify no crash |
| Lend/borrow flow | Add entry → appears in list → settle → status changes |
| Group expense flow | Create group → add expense → splits calculated correctly |

Use `patrol` or `integration_test` with a dedicated test Supabase project.

---

### D3. Making Tests Runnable in CI

1. **Abstract Supabase initialization behind a provider** so tests can inject a mock:

```dart
// lib/core/di/supabase_provider.dart
final supabaseClientProvider = Provider<SupabaseClient>((ref) {
  return Supabase.instance.client;
});
```

In tests, override this provider with a mock.

2. **Never call real Supabase in unit/widget tests.** Use `mocktail` or just mock at the repository level.

3. **Fix `widget_test.dart`** to not require real Supabase:

```dart
void main() {
  testWidgets('App renders without crash', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          // Override all providers that touch Supabase
          supabaseClientProvider.overrideWithValue(MockSupabaseClient()),
        ],
        child: const BillyApp(),
      ),
    );
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
```

4. **Add a GitHub Actions workflow:**

```yaml
# .github/workflows/test.yml
name: Test & Analyze

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - uses: subosito/flutter-action@v2
        with:
          channel: stable

      - name: Install dependencies
        run: flutter pub get

      - name: Analyze
        run: flutter analyze --fatal-infos

      - name: Run tests
        run: flutter test --coverage

      - name: Check coverage
        run: |
          # Fail if coverage drops below threshold
          # (install lcov first for genhtml)
          sudo apt-get install -y lcov
          lcov --summary coverage/lcov.info
```

---

### D4. Edge Function Tests

The Edge Functions contain critical parsing logic (`normalizeFromGeminiJson`) that should be tested.

1. **Create a test file for the process-invoice function:**

```typescript
// supabase/functions/process-invoice/normalize.test.ts
import { assertEquals } from "https://deno.land/std/assert/mod.ts";
import { normalizeFromGeminiJson } from "./normalize.ts";

Deno.test("normalizeFromGeminiJson - complete receipt", () => {
  const input = {
    vendor_name: "Walmart",
    date: "2026-01-15",
    total_amount: 45.99,
    tax_amount: 3.99,
    items: [
      { description: "Groceries", quantity: 1, unit_price: 42.00 },
    ],
  };
  const result = normalizeFromGeminiJson(input);
  assertEquals(result.vendor_name, "Walmart");
  assertEquals(result.total_amount, 45.99);
});

Deno.test("normalizeFromGeminiJson - missing fields", () => {
  const input = { vendor_name: "Store" };
  const result = normalizeFromGeminiJson(input);
  assertEquals(result.vendor_name, "Store");
  assertEquals(result.total_amount, 0);
  assertEquals(result.items, []);
});

Deno.test("normalizeFromGeminiJson - malformed date", () => {
  const input = { vendor_name: "Store", date: "not-a-date" };
  const result = normalizeFromGeminiJson(input);
  assertEquals(result.date, null);
});
```

2. **Extract `normalizeFromGeminiJson` into its own module** so it can be imported independently for testing.

3. **Run with:**

```bash
deno test supabase/functions/process-invoice/
```

---

## Part E — Observability and Ops

### E1. Crash Reporting

**Current state:** `BillyLogger` prints to `dart:developer` console. In production:
- **Mobile:** Console output is invisible to you
- **Web:** Browser console is invisible to you
- You have zero visibility into production errors

**Add Sentry (recommended) or Firebase Crashlytics:**

```bash
flutter pub add sentry_flutter
```

```dart
// lib/main.dart
import 'package:sentry_flutter/sentry_flutter.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await SentryFlutter.init(
    (options) {
      options.dsn = const String.fromEnvironment('SENTRY_DSN');
      options.environment = const String.fromEnvironment('ENV', defaultValue: 'dev');
      options.tracesSampleRate = 0.2; // 20% of transactions for performance
      options.attachScreenshot = true;
      options.sendDefaultPii = false; // Don't send personal info
    },
    appRunner: () async {
      await Supabase.initialize(
        url: SupabaseConfig.url,
        anonKey: SupabaseConfig.anonKey,
      );

      runApp(
        ProviderScope(
          observers: [BillyProviderObserver()],
          child: const BillyApp(),
        ),
      );
    },
  );
}
```

**Wire `BillyLogger.error` to also send to Sentry:**

```dart
class BillyLogger {
  static void error(String message, [Object? error, StackTrace? stackTrace]) {
    developer.log(message, error: error, stackTrace: stackTrace);
    if (error != null) {
      Sentry.captureException(error, stackTrace: stackTrace);
    }
  }
}
```

---

### E2. Analytics / Product Metrics

You're building a financial app but currently have no way to know:
- How many users scan invoices per day
- Average scan success rate
- Most-used features
- Funnel: sign up → first scan → first export

**Add PostHog (open source, generous free tier) or Mixpanel:**

```bash
flutter pub add posthog_flutter
```

**Key events to track:**

| Event | Properties |
|---|---|
| `scan_started` | `source: camera/gallery` |
| `scan_completed` | `duration_ms, item_count` |
| `scan_failed` | `error_code, error_message` |
| `expense_added_manual` | `amount_range, category` |
| `expense_added_ocr` | `amount_range, confidence` |
| `export_generated` | `format: pdf/csv, doc_count, date_range` |
| `group_created` | `member_count` |
| `settlement_recorded` | `amount_range` |
| `lend_borrow_created` | `type: lend/borrow` |
| `feature_used` | `feature: analytics/export/social/groups` |
| `auth_signed_up` | `method: email/google/apple` |
| `auth_signed_in` | `method: email/google/apple` |

**Track funnels:**
- Onboarding: sign_up → first_scan → first_save → first_export
- Weekly engagement: sessions, scans, manual entries

---

### E3. Performance Monitoring

1. **Supabase Dashboard:** Set up alerts for:
   - Query latency > 500ms
   - Edge Function errors
   - Auth failures
   - Storage bandwidth spikes

2. **Flutter Performance:**

```dart
// In debug mode
MaterialApp(
  showPerformanceOverlay: kDebugMode,
  // ...
)
```

For production, Sentry Performance or Firebase Performance SDK track:
- Screen load times
- Slow frames (jank)
- Network request latency
- App startup time

3. **Custom performance tracking:**

```dart
class PerformanceTracker {
  static Future<T> track<T>(String operation, Future<T> Function() fn) async {
    final stopwatch = Stopwatch()..start();
    try {
      return await fn();
    } finally {
      stopwatch.stop();
      if (stopwatch.elapsedMilliseconds > 1000) {
        BillyLogger.warning('Slow operation: $operation took ${stopwatch.elapsedMilliseconds}ms');
      }
      // Send to analytics
    }
  }
}

// Usage
final docs = await PerformanceTracker.track(
  'fetchDocuments',
  () => repo.fetchAll(),
);
```

---

### E4. Database Maintenance

1. **Backups:**
   - Supabase Pro plan has daily point-in-time recovery (PITR)
   - **Verify backups are enabled** in Dashboard → Settings → Database
   - **Test a restore** at least once before launch
   - Consider additional off-site backups for compliance

2. **Vacuuming:**
   - Postgres auto-vacuums, but high-churn tables need tuned settings:

```sql
-- For tables with frequent inserts/deletes
ALTER TABLE invoice_ocr_logs SET (
  autovacuum_vacuum_scale_factor = 0.05,
  autovacuum_analyze_scale_factor = 0.05
);

ALTER TABLE invoice_processing_events SET (
  autovacuum_vacuum_scale_factor = 0.05,
  autovacuum_analyze_scale_factor = 0.05
);
```

3. **Log retention:**
   - `invoice_ocr_logs` stores full Gemini request/response payloads as JSONB
   - Over time this table will grow very large
   - Add a retention policy:

```sql
-- Run monthly via pg_cron or a scheduled Edge Function
DELETE FROM invoice_ocr_logs
WHERE created_at < NOW() - INTERVAL '90 days';

-- Or partition by month for efficient dropping
```

4. **Monitor table sizes:**

```sql
SELECT
  schemaname,
  tablename,
  pg_size_pretty(pg_total_relation_size(schemaname||'.'||tablename)) AS total_size,
  pg_size_pretty(pg_relation_size(schemaname||'.'||tablename)) AS table_size,
  pg_size_pretty(pg_indexes_size(schemaname||'.'||tablename)) AS index_size
FROM pg_tables
WHERE schemaname = 'public'
ORDER BY pg_total_relation_size(schemaname||'.'||tablename) DESC;
```

---

### E5. CI/CD Pipeline

**Recommended full pipeline:**

```
Push to feature branch →
  1. flutter analyze (linting / static analysis)
  2. flutter test --coverage (unit + widget tests)
  3. Build web / APK (verify compilation)
  4. Run Deno tests for Edge Functions

Merge to main →
  5. Build production web → deploy to Vercel
  6. Run supabase db push (apply new migrations)
  7. Deploy Edge Functions (supabase functions deploy)
  8. Run smoke E2E tests against staging

Release tag (v1.0.0, v1.1.0, etc.) →
  9. Build signed APK/AAB + iOS archive
  10. Upload to Play Store / TestFlight
  11. Tag the Supabase migration state
```

**GitHub Actions workflow:**

```yaml
# .github/workflows/ci.yml
name: CI

on:
  push:
    branches: [main]
  pull_request:
    branches: [main]

jobs:
  analyze-and-test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter analyze --fatal-infos
      - run: flutter test --coverage
      - name: Upload coverage
        uses: codecov/codecov-action@v4
        with:
          file: coverage/lcov.info

  build-web:
    needs: analyze-and-test
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter build web --dart-define-from-file=config/ci.json
      - uses: actions/upload-artifact@v4
        with:
          name: web-build
          path: build/web

  build-android:
    needs: analyze-and-test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/')
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-java@v4
        with:
          distribution: temurin
          java-version: 17
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter build appbundle --dart-define-from-file=config/prod.json
      - uses: actions/upload-artifact@v4
        with:
          name: android-build
          path: build/app/outputs/bundle/release/

  build-ios:
    needs: analyze-and-test
    runs-on: macos-latest
    if: github.ref == 'refs/heads/main' || startsWith(github.ref, 'refs/tags/')
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with:
          channel: stable
      - run: flutter pub get
      - run: flutter build ios --no-codesign --dart-define-from-file=config/prod.json

  deploy-edge-functions:
    needs: analyze-and-test
    runs-on: ubuntu-latest
    if: github.ref == 'refs/heads/main'
    steps:
      - uses: actions/checkout@v4
      - uses: supabase/setup-cli@v1
      - run: supabase functions deploy process-invoice --project-ref ${{ secrets.SUPABASE_PROJECT_REF }}
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
      - run: supabase functions deploy analytics-insights --project-ref ${{ secrets.SUPABASE_PROJECT_REF }}
        env:
          SUPABASE_ACCESS_TOKEN: ${{ secrets.SUPABASE_ACCESS_TOKEN }}
```

---

## Part F — UX and Polish

### F1. Loading, Error, and Empty States

**Current state:** Many screens only handle the `data` case and skip proper loading/error:
- Dashboard silently shows `0` while providers are loading — should show skeleton loaders
- Analytics shows "No data in range" but no distinction between "loading" and "actually empty"

**Pattern — Always handle all three `AsyncValue` states:**

```dart
Widget build(BuildContext context, WidgetRef ref) {
  final documents = ref.watch(documentsProvider);

  return documents.when(
    loading: () => const DocumentsSkeleton(), // Shimmer / skeleton
    error: (error, stack) => ErrorBanner(
      error: error,
      onRetry: () => ref.invalidate(documentsProvider),
    ),
    data: (docs) => docs.isEmpty
        ? const EmptyState(
            icon: Icons.receipt_long,
            title: 'No documents yet',
            subtitle: 'Scan an invoice or add an expense to get started',
          )
        : DocumentsList(documents: docs),
  );
}
```

**Create reusable skeleton widgets:**

```dart
class DocumentsSkeleton extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      itemCount: 5,
      itemBuilder: (_, __) => Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Container(width: 48, height: 48, decoration: BoxDecoration(
              color: Colors.grey.shade200,
              borderRadius: BorderRadius.circular(8),
            )),
            const SizedBox(width: 12),
            Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(height: 14, width: 120, color: Colors.grey.shade200),
                const SizedBox(height: 8),
                Container(height: 12, width: 80, color: Colors.grey.shade200),
              ],
            )),
          ],
        ),
      ),
    );
  }
}
```

---

### F2. Dead Features and Placeholders

These create user confusion and maintenance debt. Either implement or remove before production:

| Item | Current State | Action |
|---|---|---|
| "Customize" button in header | Visual only, no handler | Remove or implement |
| "Link Bank" quick action | Shows SnackBar "coming soon" | Remove from v1 or label explicitly |
| Analytics notification/settings icons | Empty `onPressed` | Remove or wire up |
| Profile → Notifications | Empty handler | Remove or add real screen |
| Profile → Privacy | Empty handler | Remove or add real screen |
| `splits` table + `splits_provider.dart` | Table exists, provider exists, not shown in UI | Remove or build the UI |
| `connected_apps` table + service methods | Table exists, methods exist, not in UI | Remove or build |
| `go_router` dependency | In pubspec, not used | Remove or adopt (see C2) |
| `export_history` table | Exists, exports don't write to it | Use it or drop it |

**For App Store review:** Apple specifically rejects apps with placeholder/non-functional buttons. Clean these up before submission.

---

### F3. Accessibility

For App Store compliance and good UX:

1. **Add `Semantics` labels to custom widgets:**

```dart
// FAB
Semantics(
  label: 'Add new expense',
  button: true,
  child: FloatingActionButton(/* ... */),
)

// Quick action tiles
Semantics(
  label: 'Scan receipt',
  button: true,
  child: QuickActionTile(/* ... */),
)

// Chart elements
Semantics(
  label: 'Weekly spending chart showing $total total',
  child: MoneyFlowChart(/* ... */),
)
```

2. **Add `excludeFromSemantics` on decorative elements:**

```dart
Image.asset(
  'assets/branding/billy_logo.png',
  semanticsLabel: null, // Decorative
  excludeFromSemantics: true,
)
```

3. **Fix color contrast:** `BillyTheme.gray400` (#9CA3AF) on white background fails WCAG AA for small text. Darken to at least #6B7280 for body text.

4. **Ensure minimum tap targets:** All interactive elements should be at least 48x48 pixels (Material Design minimum).

5. **Test with screen reader:** Run the app with TalkBack (Android) and VoiceOver (iOS) to identify missing labels.

---

### F4. Internationalization

**Current state:** Hardcoded English strings everywhere.

**For v1 (alpha testing):** This is acceptable if your audience is English-only.

**For production scaling:**

1. **Add the `intl` localization setup:**

```yaml
# pubspec.yaml
dependencies:
  flutter_localizations:
    sdk: flutter

flutter:
  generate: true
```

```yaml
# l10n.yaml
arb-dir: lib/l10n
template-arb-file: app_en.arb
output-localization-file: app_localizations.dart
```

2. **Create ARB files:**

```json
// lib/l10n/app_en.arb
{
  "@@locale": "en",
  "dashboardTitle": "Dashboard",
  "addExpense": "Add Expense",
  "scanReceipt": "Scan Receipt",
  "totalSpend": "Total Spend",
  "noDocuments": "No documents yet",
  "amount": "Amount",
  "vendor": "Vendor",
  "amountFormat": "{currency}{amount}",
  "@amountFormat": {
    "placeholders": {
      "currency": {"type": "String"},
      "amount": {"type": "String"}
    }
  }
}
```

3. **Fix date formats** to use device locale:

```dart
// CURRENT — always English month names
DateFormat('dd MMM').format(date);

// FIXED — respects device locale
DateFormat('dd MMM', Localizations.localeOf(context).languageCode).format(date);
```

---

## Part G — App Store and Distribution

### G1. iOS App Store Checklist

| Item | Status | Notes |
|---|---|---|
| **Apple Developer Account** | Required | $99/year enrollment |
| **App ID / Bundle ID** | Set in Xcode | Currently `com.billy.billy` — verify this is registered in Apple Developer portal |
| **App Icons** | Required | 1024x1024 App Store icon + all sizes. Check `ios/Runner/Assets.xcassets/AppIcon.appiconset/` |
| **Launch Screen** | Required | Configured in `ios/Runner/Assets.xcassets/LaunchImage.imageset/` |
| **Signing Certificate** | Required | Distribution certificate + provisioning profile |
| **Privacy Policy URL** | Required by Apple | Must be a live URL, referenced in App Store Connect |
| **Terms of Service URL** | Recommended | For financial apps, often required |
| **App Privacy Nutrition Labels** | Required | Declare all data collected (email, financial data, usage analytics) |
| **Export Compliance** | Required | If using standard HTTPS encryption only, declare ECCN exemption |
| **Sign In with Apple** | Required | You have `sign_in_with_apple` in pubspec — ensure it works |
| **Camera Permission String** | Required | `NSCameraUsageDescription` in `Info.plist` |
| **Photo Library Permission** | Required | `NSPhotoLibraryUsageDescription` in `Info.plist` |
| **App Review Information** | Required | Provide demo credentials for the review team |
| **No Placeholder Content** | Required | Apple rejects apps with non-functional buttons (see F2) |
| **Universal Links** | Recommended | For deep linking / auth callbacks |
| **Minimum iOS Version** | Check | Currently targets whatever Flutter default is — consider iOS 15+ |

**Build and archive commands:**

```bash
# Build the iOS archive
flutter build ipa --dart-define-from-file=config/prod.json

# Or for manual signing
flutter build ios --dart-define-from-file=config/prod.json
# Then archive in Xcode → Product → Archive
```

---

### G2. Android Play Store Checklist

| Item | Status | Notes |
|---|---|---|
| **Google Play Developer Account** | Required | $25 one-time fee |
| **App Signing Key** | Required | Currently using debug signing for release builds — **must fix** |
| **Package Name** | Set | `com.billy.billy` in `android/app/build.gradle.kts` |
| **App Icons** | Required | Adaptive icons in `android/app/src/main/res/` |
| **Feature Graphic** | Required | 1024x500 for Play Store listing |
| **Privacy Policy URL** | Required | Must be a live URL |
| **Content Rating** | Required | Complete the questionnaire in Play Console |
| **Target API Level** | Required | Google requires targeting recent API levels |
| **64-bit Support** | Required | Flutter provides this by default with `appbundle` |
| **ProGuard / R8** | Recommended | Shrink and obfuscate release builds |

**Fix release signing (critical):**

Currently in `android/app/build.gradle.kts`:
```kotlin
// CURRENT — uses debug signing for release (NOT production-ready)
buildTypes {
    release {
        signingConfig = signingConfigs.getByName("debug")
    }
}
```

**Fix:**

1. **Generate a release keystore:**

```bash
keytool -genkey -v -keystore billy-release.jks -keyalg RSA -keysize 2048 -validity 10000 -alias billy
```

2. **Create `android/key.properties` (gitignored):**

```properties
storePassword=your_store_password
keyPassword=your_key_password
keyAlias=billy
storeFile=../billy-release.jks
```

3. **Update `android/app/build.gradle.kts`:**

```kotlin
val keystoreProperties = Properties()
val keystoreFile = rootProject.file("key.properties")
if (keystoreFile.exists()) {
    keystoreProperties.load(FileInputStream(keystoreFile))
}

android {
    signingConfigs {
        create("release") {
            keyAlias = keystoreProperties["keyAlias"] as String?
            keyPassword = keystoreProperties["keyPassword"] as String?
            storeFile = keystoreProperties["storeFile"]?.let { file(it as String) }
            storePassword = keystoreProperties["storePassword"] as String?
        }
    }
    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
        }
    }
}
```

4. **Add to `.gitignore`:**

```gitignore
*.jks
*.keystore
key.properties
```

5. **Back up the keystore** securely — if you lose it, you can never update the app on the Play Store.

**Build command:**

```bash
flutter build appbundle --dart-define-from-file=config/prod.json
# Output: build/app/outputs/bundle/release/app-release.aab
```

---

### G3. Web (Vercel) Production Checklist

| Item | Status | Notes |
|---|---|---|
| **Custom Domain** | Pending | Configure in Vercel → Domains |
| **HTTPS** | Automatic | Vercel provides SSL certificates |
| **CSP Headers** | Missing | Add Content-Security-Policy headers |
| **Cache Headers** | Configured | `vercel.json` has cache headers for index.html |
| **SPA Routing** | Configured | `vercel.json` has SPA rewrites |
| **Environment Variables** | Configure | Set in Vercel → Settings → Environment Variables |
| **Error Pages** | Missing | Add custom 404 page |
| **Favicon** | Check | Ensure `web/favicon.png` is set |
| **Meta Tags** | Check | `web/index.html` — add Open Graph and description tags |
| **PWA Manifest** | Check | `web/manifest.json` — verify app name, icons, theme color |

**Add Content-Security-Policy header to `vercel.json`:**

```json
{
  "headers": [
    {
      "source": "/(.*)",
      "headers": [
        {
          "key": "Content-Security-Policy",
          "value": "default-src 'self'; script-src 'self' 'unsafe-inline' 'unsafe-eval'; style-src 'self' 'unsafe-inline'; img-src 'self' data: https://*.supabase.co; connect-src 'self' https://*.supabase.co wss://*.supabase.co; font-src 'self';"
        },
        {
          "key": "X-Frame-Options",
          "value": "DENY"
        },
        {
          "key": "X-Content-Type-Options",
          "value": "nosniff"
        },
        {
          "key": "Referrer-Policy",
          "value": "strict-origin-when-cross-origin"
        }
      ]
    }
  ]
}
```

**Update `deploy-vercel.ps1`** to use `--dart-define-from-file`:

```powershell
flutter build web --release --dart-define-from-file=config/prod.json --pwa-strategy=none
```

---

### G4. TestFlight / Alpha Testing Checklist

**For Versal (Vercel) Alpha Testing (Web):**

1. **Set up a staging environment:**
   - Create a separate Supabase project for staging (or use branch databases)
   - Create `config/staging.json` with staging credentials
   - Deploy staging to a Vercel preview branch

2. **Create test accounts** with seeded data:
   - Account with 0 documents (empty state testing)
   - Account with 100+ documents (performance testing)
   - Account with groups, connections, settlements (social feature testing)

3. **Test checklist for alpha testers:**

   - [ ] Sign up with email
   - [ ] Sign up with Google
   - [ ] Sign up with Apple
   - [ ] Add manual expense
   - [ ] Scan receipt with camera
   - [ ] Scan receipt from gallery
   - [ ] Review and edit OCR results
   - [ ] View dashboard with data
   - [ ] View analytics
   - [ ] Export to PDF
   - [ ] Export to CSV
   - [ ] Create expense group
   - [ ] Add group expense
   - [ ] Record settlement
   - [ ] Create lend/borrow entry
   - [ ] Settle lend/borrow
   - [ ] Send contact invitation
   - [ ] Accept contact invitation
   - [ ] Edit profile
   - [ ] Change preferred currency
   - [ ] Sign out
   - [ ] Sign back in (session persistence)
   - [ ] Test offline behavior (airplane mode)
   - [ ] Test slow network (throttle in DevTools)

**For TestFlight (iOS):**

1. **Archive the app** in Xcode and upload to App Store Connect
2. **Add internal testers** (up to 100) — immediate access
3. **Add external testers** (up to 10,000) — requires brief Apple review
4. **Set up TestFlight "What to Test" notes** for each build
5. **Enable crash reporting** so you can see TestFlight crash logs

**For Android Alpha Testing:**

1. **Upload AAB to Google Play Console** → Testing → Internal testing
2. **Add tester email addresses** to the internal testing track
3. **Share the opt-in link** with testers

---

## Part H — Priority Matrix

| Priority | Item | Effort | Impact | Section |
|---|---|---|---|---|
| **P0** (do first) | Move secrets out of source code | Small | Security | A1 |
| **P0** | Fix `app_api_keys` RLS — remove authenticated SELECT | Small | Security | A7 |
| **P0** | Fix `user_usage_limits` RLS — remove user UPDATE | Small | Security | A2 |
| **P0** | RLS audit (verify all policies, add `WITH CHECK`) | Small | Security | A2 |
| **P0** | Whitelist CORS origins in Edge Functions | Small | Security | A6 |
| **P0** | Fix Android release signing (not debug) | Small | Distribution | G2 |
| **P0** | Add crash reporting (Sentry) | Small | Observability | E1 |
| **P1** | Fix N+1 queries (connections, daily spend) | Small | Performance | B1 |
| **P1** | Unit tests for money math and balance logic | Medium | Correctness | D2 |
| **P1** | Typed models instead of `Map<String, dynamic>` | Medium | Maintainability | B3 |
| **P1** | Remove dead features/placeholders | Small | UX / App Store | F2 |
| **P1** | Fix currency in export generators | Small | Correctness | C6 |
| **P1** | Service role fallback — fail hard if missing | Small | Security | A3 |
| **P1** | Add loading/error/empty states to all screens | Medium | UX | F1 |
| **P2** | Repository pattern (replace SupabaseService static) | Medium | Testability | B2 |
| **P2** | CI pipeline (analyze + test + build) | Medium | Quality | E5 |
| **P2** | Derive dashboard stats from loaded docs | Medium | Performance | B4 |
| **P2** | Adopt or remove `go_router` | Small | Code hygiene | C2 |
| **P2** | Pagination for documents | Medium | Scalability | B7 |
| **P2** | Input validation (client + server constraints) | Medium | Security | A5 |
| **P2** | Database indexing for common queries | Small | Performance | B5 |
| **P2** | Error handling strategy (typed exceptions) | Medium | Reliability | C3 |
| **P2** | Storage bucket policy verification | Small | Security | A8 |
| **P3** | Offline support / queue | Large | UX | C4 |
| **P3** | Product analytics (PostHog / Mixpanel) | Medium | Growth | E2 |
| **P3** | Localization structure | Medium | Market reach | F4 |
| **P3** | Accessibility improvements | Medium | Compliance | F3 |
| **P3** | Money handling (integer cents / decimal) | Medium | Correctness | C5 |
| **P3** | Edge Function tests (Deno) | Medium | Reliability | D4 |
| **P3** | Database maintenance (vacuuming, log retention) | Small | Ops | E4 |

---

## Quick-Start: The 5 Highest-Leverage Changes

If you only have 2-3 days before alpha launch, do these five things:

1. **Secrets out of code** (A1) — 1 hour. Switch to `--dart-define-from-file`, gitignore the config files, update build scripts.

2. **Fix critical RLS issues** (A2, A7) — 2 hours. Drop the `app_api_keys` SELECT policy, fix `user_usage_limits` UPDATE policy, add `WITH CHECK` to all INSERT/UPDATE policies.

3. **Add crash reporting** (E1) — 1 hour. `flutter pub add sentry_flutter`, wrap `main()`, wire `BillyLogger.error`.

4. **Fix N+1 queries** (B1) — 2 hours. Replace the loop-based profile fetching with `inFilter`, collapse `dailySpendForWeek` to one query.

5. **Unit tests on money logic** (D2) — 4 hours. Test `group_balance.dart`, `lend_borrow_perspective.dart`, share splitting math, and `ExtractedReceipt.fromJson`.

6. **Fix Android release signing** (G2) — 1 hour. Generate keystore, configure `build.gradle.kts`, back up the keystore securely.

These six items, totaling roughly 11 hours of focused work, would get Billy meaningfully closer to production confidence.

---

## Appendix: Complete File Inventory

For reference, here is the complete list of all 67 Dart source files and 13 migrations in the project:

### Dart Files (lib/)

```
lib/main.dart
lib/app/app.dart
lib/app/layout_shell.dart
lib/app/widgets/billy_header.dart
lib/app/widgets/billy_bottom_nav.dart
lib/config/supabase_config.dart
lib/config/gemini_config.dart
lib/core/logging/billy_logger.dart
lib/core/utils/analytics_fingerprint.dart
lib/core/utils/document_date_range.dart
lib/core/formatting/app_currency.dart
lib/core/theme/billy_theme.dart
lib/services/supabase_service.dart
lib/providers/documents_provider.dart
lib/providers/usage_limits_provider.dart
lib/providers/splits_provider.dart
lib/providers/lend_borrow_provider.dart
lib/providers/group_settlements_provider.dart
lib/providers/group_expenses_provider.dart
lib/providers/social_provider.dart
lib/providers/groups_provider.dart
lib/providers/profile_provider.dart
lib/features/auth/screens/login_screen.dart
lib/features/auth/providers/auth_provider.dart
lib/features/documents/models/document_list_models.dart
lib/features/documents/models/document_category_source.dart
lib/features/documents/screens/document_detail_screen.dart
lib/features/documents/screens/document_edit_screen.dart
lib/features/documents/screens/documents_history_screen.dart
lib/features/documents/utils/document_json.dart
lib/features/scanner/models/extracted_receipt.dart
lib/features/scanner/screens/scan_screen.dart
lib/features/scanner/widgets/scan_idle.dart
lib/features/scanner/widgets/scan_review_panel.dart
lib/features/scanner/widgets/scan_processing.dart
lib/features/scanner/widgets/scan_adjust_preview.dart
lib/features/scanner/widgets/scan_error.dart
lib/features/scanner/utils/scan_raster_adjust.dart
lib/features/dashboard/screens/dashboard_screen.dart
lib/features/dashboard/widgets/ocr_banner.dart
lib/features/dashboard/widgets/add_expense_sheet.dart
lib/features/dashboard/widgets/recent_activity.dart
lib/features/dashboard/widgets/quick_actions.dart
lib/features/dashboard/widgets/insights_card.dart
lib/features/dashboard/widgets/money_flow_chart.dart
lib/features/dashboard/widgets/spend_hero.dart
lib/features/export/models/export_document.dart
lib/features/export/services/pdf_generator.dart
lib/features/export/services/csv_generator.dart
lib/features/export/screens/export_screen.dart
lib/features/export/screens/export_history_screen.dart
lib/features/settings/screens/settings_screen.dart
lib/features/analytics/models/analytics_insights_models.dart
lib/features/analytics/services/analytics_insights_service.dart
lib/features/analytics/providers/analytics_insights_provider.dart
lib/features/analytics/screens/analytics_screen.dart
lib/features/analytics/screens/document_ai_review_screen.dart
lib/features/analytics/widgets/ai_insights_panel.dart
lib/features/analytics/widgets/ai_insights_card.dart
lib/features/analytics/widgets/trend_chart.dart
lib/features/analytics/widgets/patterns_list.dart
lib/features/profile/screens/profile_screen.dart
lib/features/invoices/services/invoice_ocr_pipeline.dart
lib/features/lend_borrow/screens/split_screen.dart
lib/features/lend_borrow/lend_borrow_perspective.dart
lib/features/groups/group_balance.dart
lib/features/groups/screens/group_expenses_screen.dart
```

### Supabase Migrations

```
supabase/migrations/20240318000000_initial_schema.sql
supabase/migrations/20240318000001_rls_policies.sql
supabase/migrations/20240318000002_user_gemini_api_key.sql
supabase/migrations/20240401000000_contacts_groups_shared_lend.sql
supabase/migrations/20240402000000_group_expenses.sql
supabase/migrations/20240403000000_group_settlements.sql
supabase/migrations/20260401120000_invoice_ocr_pipeline.sql
supabase/migrations/20260402140000_fix_expense_group_members_rls_recursion.sql
supabase/migrations/20260403120000_documents_status_backfill.sql
supabase/migrations/20260404100000_analytics_insight_snapshots.sql
supabase/migrations/20260405120000_documents_category_source.sql
supabase/migrations/20260405150000_user_usage_limits.sql
supabase/migrations/20260405160000_shared_api_keys.sql
```

### Edge Functions

```
supabase/functions/process-invoice/index.ts
supabase/functions/analytics-insights/index.ts
```

---

*Last updated: April 5, 2026*
*Billy version: 1.0.0+1*
