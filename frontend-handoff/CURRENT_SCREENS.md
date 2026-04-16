# Billy — Current Screens & Navigation Map

## App Shell

### `BillyApp` (`lib/app/app.dart`)
- Root `ConsumerWidget` wrapping `MaterialApp`
- Watches `authStateProvider` — shows `LoginScreen` when logged out, `LayoutShell` when authenticated
- Listens for auth state changes to auto-redirect on logout

### `LayoutShell` (`lib/app/layout_shell.dart`)
- Main scaffold with `BillyHeader` + tab content + `BillyBottomNav`
- Manages `_activeTab` state (0-4)
- Provides callbacks to child screens: `onOpenScan`, `onExportData`, `onCreateBill`, `onOpenAllDocuments`, `onOpenDocumentDetail`
- FAB opens scan flow, "Add expense" bottom sheet offers scan or manual entry

### `BillyHeader` (`lib/app/widgets/billy_header.dart`)
- Logo + settings gear icon
- Settings icon pushes `SettingsScreen`

### `BillyBottomNav` (`lib/app/widgets/billy_bottom_nav.dart`)
- 5-position nav: Home, Activity, [FAB/People], Plan, Insights
- Center FAB (emerald circle) triggers scan
- "People" label sits below FAB as a tap target for tab index 2

---

## Tab Screens

### Tab 0: Dashboard (`lib/features/dashboard/screens/dashboard_screen.dart`)
**Status:** Active, fully built
**What it does:**
- Shows spend summary (SpendHero widget) with this week vs last week
- Quick actions (scan, manual entry, export, view all docs)
- OCR usage pill
- Budget status cards (if budgets exist)
- Upcoming recurring bills card (if recurring items exist)
- Money flow chart + insights card (category breakdown)
- Recent activity list (last 5 documents)

**Key widgets:** `SpendHero`, `QuickActions`, `OcrUsageCard`, `BudgetStatusCard`, `UpcomingBillsCard`, `MoneyFlowChart`, `InsightsCard`, `RecentActivity`

**Data sources:** `documentsProvider`, `lendBorrowProvider`, `profileProvider`, `budgetsProvider`, `recurringSeriesProvider`, `usageLimitsProvider`

### Tab 1: Activity (`lib/features/activity/screens/activity_screen.dart`)
**Status:** Active, needs enhancement
**What it does:** Chronological feed of activity events

### Tab 2: People / Split (`lib/features/lend_borrow/screens/split_screen.dart`)
**Status:** Active
**What it does:** Friends tab with groups, lend/borrow entries, connections

### Tab 3: Plan (`lib/features/planning/screens/plan_screen.dart`)
**Status:** Active, needs more features
**What it does:** Budget overview + recurring bills
**Key widgets:** `BudgetCreateSheet`, `RecurringCreateSheet`

### Tab 4: Insights / Analytics (`lib/features/analytics/screens/analytics_screen.dart`)
**Status:** Active
**What it does:** AI-powered analytics with trend charts, patterns, category insights
**Key widgets:** `TrendChart`, `PatternsList`, `AiInsightsCard`, `AiInsightsPanel`

---

## Push Screens (from tabs or other screens)

### Scanner Flow
| Screen | Path | Pushed from |
|--------|------|-------------|
| `ScanScreen` | `lib/features/scanner/screens/scan_screen.dart` | FAB, Quick Actions |

**Sub-widgets:** `ScanIdle`, `ScanProcessing`, `ScanError`, `ScanReviewPanel`, `ScanAdjustPreview`

### Document Screens
| Screen | Path | Pushed from |
|--------|------|-------------|
| `DocumentsHistoryScreen` | `lib/features/documents/screens/documents_history_screen.dart` | Dashboard "View all", Quick Actions |
| `DocumentDetailScreen` | `lib/features/documents/screens/document_detail_screen.dart` | History list, Recent Activity items |
| `DocumentEditScreen` | `lib/features/documents/screens/document_edit_screen.dart` | Document detail |
| `DocumentAiReviewScreen` | `lib/features/analytics/screens/document_ai_review_screen.dart` | Document detail |

### Transaction Screens
| Screen | Path | Pushed from |
|--------|------|-------------|
| `TransactionDetailScreen` | `lib/features/transactions/screens/transaction_detail_screen.dart` | Dashboard recent items |

### Group & Social Screens
| Screen | Path | Pushed from |
|--------|------|-------------|
| `GroupExpensesScreen` | `lib/features/groups/screens/group_expenses_screen.dart` | People tab, scan review |
| `SettlementConfirmScreen` | `lib/features/settlements/screens/settlement_confirm_screen.dart` | Group expenses |
| `DisputeScreen` | `lib/features/disputes/screens/dispute_screen.dart` | Group expenses |

### Export Screens
| Screen | Path | Pushed from |
|--------|------|-------------|
| `ExportScreen` | `lib/features/export/screens/export_screen.dart` | Dashboard, Settings |
| `ExportHistoryScreen` | `lib/features/export/screens/export_history_screen.dart` | Settings |

### Other Screens
| Screen | Path | Pushed from |
|--------|------|-------------|
| `LoginScreen` | `lib/features/auth/screens/login_screen.dart` | Auth gate |
| `SettingsScreen` | `lib/features/settings/screens/settings_screen.dart` | Header icon |
| `ProfileScreen` | `lib/features/profile/screens/profile_screen.dart` | Settings |
| `SuggestionsScreen` | `lib/features/suggestions/screens/suggestions_screen.dart` | Various |

---

## Bottom Sheets

| Sheet | Location | Triggered by |
|-------|----------|-------------|
| `AddExpenseSheet` | `lib/features/dashboard/widgets/add_expense_sheet.dart` | "Manual entry" option in add flow |
| `BudgetCreateSheet` | `lib/features/planning/widgets/budget_create_sheet.dart` | Plan tab |
| `RecurringCreateSheet` | `lib/features/planning/widgets/recurring_create_sheet.dart` | Plan tab |
| Add options sheet | Inline in `LayoutShell` | FAB or "Add expense" action |

---

## Screen Status & What Needs Work

| Screen | Status | Needs |
|--------|--------|-------|
| DashboardScreen | Working | Migrate to read from `transactions` instead of `documents` |
| ActivityScreen | Basic | Needs full activity feed with filters, event types, pagination |
| SplitScreen | Working | Rename to PeopleScreen, add cross-group net balance summary |
| PlanScreen | Basic | Needs budget detail, recurring detail, monthly calendar view |
| AnalyticsScreen | Working | Consider merging insights into Activity or Dashboard |
| ScanScreen + Review | Working | Add Money Intent step + Result Preview (see PRODUCT_BLUEPRINT.md Section 6) |
| DocumentsHistoryScreen | Working | Will evolve into TransactionHistoryScreen |
| TransactionDetailScreen | Exists | Needs source card, allocations section, edit history |
| GroupExpensesScreen | Working | Add settlement confirmation badges, dispute button, group activity feed |
| SettingsScreen | Working | Move to push route (already done), add more preference options |
| StatementImportScreen | NOT BUILT | Upload + parse CSV/PDF statements |
| StatementReviewScreen | NOT BUILT | Review parsed rows, confirm/skip, create transactions |
| BudgetDetailScreen | NOT BUILT | Single budget: progress, history, category breakdown |
| RecurringDetailScreen | NOT BUILT | Single recurring series: history, upcoming, edit |
