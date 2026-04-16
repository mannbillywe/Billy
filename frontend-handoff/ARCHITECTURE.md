# Billy — Architecture & Conventions

## Project Structure

```
lib/
├── main.dart                          # Entry point: Supabase init, Sentry, ProviderScope
├── app/
│   ├── app.dart                       # BillyApp root widget, auth gate, MaterialApp
│   ├── layout_shell.dart              # Main scaffold: tabs, header, bottom nav, FAB
│   └── widgets/
│       ├── billy_bottom_nav.dart      # Custom bottom nav with center FAB
│       └── billy_header.dart          # App header with logo + settings icon
├── config/
│   ├── supabase_config.dart           # Supabase URL + anon key (from --dart-define)
│   └── gemini_config.dart             # Gemini model name (API runs in Edge Function)
├── core/
│   ├── theme/billy_theme.dart         # Color palette, text styles, ThemeData
│   ├── logging/billy_logger.dart      # Debug logger
│   ├── formatting/app_currency.dart   # Currency formatting helpers
│   └── utils/                         # Shared utilities
├── providers/                         # Shared Riverpod providers (cross-feature)
│   ├── transactions_provider.dart
│   ├── documents_provider.dart
│   ├── budgets_provider.dart
│   ├── recurring_provider.dart
│   ├── lend_borrow_provider.dart
│   ├── profile_provider.dart
│   ├── groups_provider.dart
│   ├── social_provider.dart
│   └── ...more
├── services/                          # Shared services (Supabase calls, business logic)
│   ├── supabase_service.dart          # Large data layer for Postgrest/Storage/RPC
│   ├── transaction_service.dart       # Transaction CRUD + dashboard aggregation
│   ├── allocation_service.dart        # Compute group shares, lend buckets from line items
│   └── activity_logger.dart           # Log activity_events to Supabase
└── features/                          # Feature-first modules
    ├── auth/
    ├── dashboard/
    ├── activity/
    ├── analytics/
    ├── scanner/
    ├── documents/
    ├── transactions/
    ├── lend_borrow/
    ├── groups/
    ├── settlements/
    ├── planning/
    ├── disputes/
    ├── export/
    ├── profile/
    ├── settings/
    └── suggestions/
```

## Feature Folder Convention

Each feature follows this structure:

```
lib/features/<feature>/
├── screens/          # Full-page widgets (one per route)
│   └── <feature>_screen.dart
├── widgets/          # Reusable UI components for this feature
│   └── <widget_name>.dart
├── models/           # Data classes / DTOs (optional)
│   └── <model_name>.dart
├── services/         # Feature-specific business logic (optional)
│   └── <service_name>.dart
├── providers/        # Feature-specific Riverpod providers (optional)
│   └── <provider_name>.dart
└── utils/            # Feature-specific helpers (optional)
    └── <util_name>.dart
```

## State Management: Riverpod

- The app uses `flutter_riverpod` with `ProviderScope` at root
- Widgets extend `ConsumerWidget` or `ConsumerStatefulWidget`
- Providers are `AsyncNotifierProvider` for async data (Supabase fetches)
- Use `ref.watch(provider)` in `build()` for reactive UI
- Use `ref.read(provider.notifier).method()` for actions

### Provider Pattern Example

```dart
class TransactionsNotifier extends AsyncNotifier<List<Map<String, dynamic>>> {
  @override
  Future<List<Map<String, dynamic>>> build() async {
    return TransactionService.fetchTransactions();
  }

  Future<void> refresh() async {
    state = const AsyncValue.loading();
    state = await AsyncValue.guard(() => TransactionService.fetchTransactions());
  }
}

final transactionsProvider =
    AsyncNotifierProvider<TransactionsNotifier, List<Map<String, dynamic>>>(
  TransactionsNotifier.new,
);
```

### Using Providers in Widgets

```dart
class MyScreen extends ConsumerWidget {
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(transactionsProvider);
    return dataAsync.when(
      data: (items) => ListView(...),
      loading: () => CircularProgressIndicator(),
      error: (e, st) => Text('Error: $e'),
    );
  }
}
```

## Navigation

- **No go_router** — the app uses Navigator 1.0 with `MaterialPageRoute`
- Tab switching is managed by `LayoutShell` with an `_activeTab` int
- Push routes use `Navigator.of(context).push(MaterialPageRoute(...))`
- The bottom nav has 5 positions: Home (0), Activity (1), People (2), Plan (3), Insights (4)
- The center FAB opens the scan screen
- Settings is pushed from the header icon, not a tab

### Navigation Pattern

```dart
// Push a new screen
Navigator.of(context).push(
  MaterialPageRoute<void>(builder: (_) => const SomeScreen()),
);

// Pop back
Navigator.of(context).maybePop();
```

## Tab Structure (current)

| Index | Label     | Screen              | Icon                         |
|-------|-----------|---------------------|------------------------------|
| 0     | Home      | DashboardScreen     | Icons.home_rounded           |
| 1     | Activity  | ActivityScreen      | Icons.timeline_rounded       |
| 2     | People    | SplitScreen         | Icons.people_rounded         |
| 3     | Plan      | PlanScreen          | Icons.calendar_month_rounded |
| 4     | Insights  | AnalyticsScreen     | Icons.insights_rounded       |
| FAB   | (Scan)    | ScanScreen          | Icons.camera_alt_rounded     |

## Supabase Access Pattern

- All database calls go through static service methods (e.g., `TransactionService.fetchTransactions()`)
- Services use `Supabase.instance.client` directly
- User ID: `Supabase.instance.client.auth.currentUser?.id`
- Data is returned as `List<Map<String, dynamic>>` (no typed models for most tables)
- RLS ensures users only see their own data

```dart
class SomeService {
  static SupabaseClient get _client => Supabase.instance.client;
  static String? get _uid => _client.auth.currentUser?.id;

  static Future<List<Map<String, dynamic>>> fetchItems() async {
    final uid = _uid;
    if (uid == null) return [];
    final res = await _client
        .from('some_table')
        .select()
        .eq('user_id', uid)
        .order('created_at', ascending: false);
    return List<Map<String, dynamic>>.from(res);
  }
}
```

## Dependencies (pubspec.yaml)

| Package | Purpose |
|---------|---------|
| `flutter_riverpod` | State management |
| `supabase_flutter` | Backend (auth, database, storage) |
| `sentry_flutter` | Error tracking (optional) |
| `google_sign_in` | Google OAuth |
| `sign_in_with_apple` | Apple OAuth |
| `image_picker` | Camera/gallery |
| `file_picker` | File selection |
| `fl_chart` | Charts (dashboard) |
| `intl` | Date/number formatting |
| `pdf` / `printing` | PDF export |
| `csv` | CSV export |
| `share_plus` | Share files |
| `pdfrx` | PDF viewing |
| `flutter_dropzone` | Web file drop zone |
| `cached_network_image` | Image caching |

## Key Conventions

1. **Colors:** Always use `BillyTheme.<color>` — never raw hex
2. **Spacing:** Standard padding is 20px horizontal, 8-16px between sections
3. **Cards:** White background, 24px border radius, no elevation (theme default)
4. **Bottom sheets:** `showModalBottomSheet` with 24px top radius, white background
5. **Loading states:** Use `AsyncValue.when()` for data/loading/error
6. **Currency:** Read `profile['preferred_currency']` and pass as `currencyCode`
7. **Dates:** Use `intl` package's `DateFormat` for display formatting
