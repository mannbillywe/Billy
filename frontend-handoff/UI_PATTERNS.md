# Billy — UI Patterns & Theme Reference

## Color Palette

All colors are defined in `lib/core/theme/billy_theme.dart`. **Never hardcode hex values** — always reference `BillyTheme.<name>`.

### Primary (Emerald)
| Name | Hex | Usage |
|------|-----|-------|
| `emerald700` | #047857 | Darkest primary (headers, emphasis) |
| `emerald600` | #059669 | **Main primary** — buttons, FAB, active nav, links |
| `emerald500` | #10B981 | Slightly lighter primary |
| `emerald400` | #34D399 | Light primary (progress bars, badges) |
| `emerald100` | #D1FAE5 | Very light tint (success backgrounds) |
| `emerald50` | #ECFDF5 | Lightest tint (icon backgrounds, subtle cards) |

### Neutrals (Gray)
| Name | Hex | Usage |
|------|-----|-------|
| `gray800` | #1F2937 | **Primary text** |
| `gray700` | #374151 | Secondary headings |
| `gray600` | #4B5563 | Body text (darker) |
| `gray500` | #6B7280 | **Secondary text**, labels |
| `gray400` | #9CA3AF | Inactive icons, placeholder text |
| `gray300` | #D1D5DB | Borders, dividers, handle bars |
| `gray200` | #E5E7EB | Light borders |
| `gray100` | #F3F4F6 | Card borders, light backgrounds |
| `gray50` | #F9FAFB | Very light backgrounds |

### Accents
| Name | Hex | Usage |
|------|-----|-------|
| `red400` | #F87171 | Light error/warning |
| `red500` | #EF4444 | **Error** state |
| `blue400` | #60A5FA | Info, manual entry icon |
| `yellow400` | #FACC15 | Warning |
| `green400` | #4ADE80 | Success (different from emerald) |

### Special
| Name | Hex | Usage |
|------|-----|-------|
| `scaffoldBg` | #F4F7F6 | **Page background** (slightly green-tinted gray) |

---

## Typography

Defined in `BillyTheme.lightTheme.textTheme`:

| Style | Size | Weight | Color | Usage |
|-------|------|--------|-------|-------|
| `headlineLarge` | 32 | w800 | gray800 | Hero numbers (spend amount) |
| `headlineMedium` | 24 | w700 | gray800 | Section titles |
| `titleLarge` | 20 | w700 | gray800 | Screen titles, card headers |
| `titleMedium` | 16 | w600 | gray800 | Subsection titles |
| `bodyLarge` | 16 | w500 | gray800 | Primary body text |
| `bodyMedium` | 14 | w500 | gray500 | Secondary body text |
| `labelLarge` | 12 | w600 | gray500 | Labels, captions |

All use `letterSpacing: -0.02` for headline/title styles.

### Common Inline Styles

```dart
// Section header
TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800)

// Card title
TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray800)

// Subtitle / description
TextStyle(fontSize: 13, color: BillyTheme.gray500)

// Small label
TextStyle(fontSize: 12, color: BillyTheme.gray500)

// Bottom sheet title
TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: BillyTheme.gray800)
```

---

## Component Patterns

### Cards

```dart
Container(
  padding: const EdgeInsets.all(20),
  decoration: BoxDecoration(
    color: Colors.white,
    borderRadius: BorderRadius.circular(24),
  ),
  child: Column(...),
)
```

Theme default card: white, 24px radius, no elevation.

### Icon Badges (e.g., in option tiles)

```dart
Container(
  width: 48,
  height: 48,
  decoration: BoxDecoration(
    color: BillyTheme.emerald50,     // Light tint background
    borderRadius: BorderRadius.circular(14),
  ),
  child: Icon(Icons.some_icon, size: 24, color: BillyTheme.emerald600),
)
```

### List Option Tiles (used in bottom sheets)

```dart
Material(
  color: Colors.white,
  borderRadius: BorderRadius.circular(14),
  child: InkWell(
    onTap: onTap,
    borderRadius: BorderRadius.circular(14),
    child: Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: BillyTheme.gray100),
      ),
      child: Row(
        children: [
          _iconBadge,
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700, color: BillyTheme.gray800)),
                const SizedBox(height: 2),
                Text(subtitle, style: TextStyle(fontSize: 12, color: BillyTheme.gray500)),
              ],
            ),
          ),
          Icon(Icons.chevron_right_rounded, color: BillyTheme.gray300),
        ],
      ),
    ),
  ),
)
```

### Bottom Sheets

```dart
showModalBottomSheet(
  context: context,
  backgroundColor: Colors.white,
  isScrollControlled: true,  // if content is tall
  shape: const RoundedRectangleBorder(
    borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
  ),
  builder: (ctx) => Padding(
    padding: const EdgeInsets.fromLTRB(24, 24, 24, 40),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Handle bar
        Center(
          child: Container(
            width: 40, height: 4,
            decoration: BoxDecoration(
              color: BillyTheme.gray300,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        const SizedBox(height: 20),
        // Title
        Text('Sheet Title', style: TextStyle(fontSize: 20, fontWeight: FontWeight.w800, color: BillyTheme.gray800)),
        const SizedBox(height: 4),
        // Subtitle
        Text('Description', style: TextStyle(fontSize: 13, color: BillyTheme.gray500)),
        const SizedBox(height: 20),
        // Content...
      ],
    ),
  ),
);
```

### Primary Button

```dart
ElevatedButton(
  onPressed: () {},
  child: Text('Confirm'),
)
// Theme: emerald600 bg, white text, 16px radius, 24h/14v padding
```

### Section Header with Action

```dart
Row(
  mainAxisAlignment: MainAxisAlignment.spaceBetween,
  children: [
    Text('Recent', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, color: BillyTheme.gray800)),
    TextButton(
      onPressed: onViewAll,
      child: const Text('View all'),
    ),
  ],
)
```

### Loading State

```dart
LinearProgressIndicator(
  minHeight: 3,
  color: BillyTheme.emerald600,
  backgroundColor: BillyTheme.gray100,
)
```

### Scrollable Screen Layout

```dart
SingleChildScrollView(
  key: const ValueKey('screen_name'),
  padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),  // 120 bottom for nav clearance
  child: Column(
    crossAxisAlignment: CrossAxisAlignment.start,
    children: [
      // Sections with SizedBox(height: 16-24) spacing
    ],
  ),
)
```

### AppBar for Push Screens

```dart
AppBar(
  title: const Text('Screen Title'),
  backgroundColor: BillyTheme.scaffoldBg,
  foregroundColor: BillyTheme.gray800,
  elevation: 0,
  leading: IconButton(
    icon: const Icon(Icons.arrow_back),
    onPressed: () => Navigator.of(context).maybePop(),
  ),
)
```

---

## Layout Guidelines

- **Screen padding:** `EdgeInsets.fromLTRB(20, 8, 20, 120)` — 120 bottom clears the nav bar
- **Card padding:** `EdgeInsets.all(20)` for content cards
- **Between cards:** `SizedBox(height: 16)` or `SizedBox(height: 12)` for tighter spacing
- **Between sections:** `SizedBox(height: 24)` 
- **Card border radius:** 24px for major cards, 14px for list items / option tiles
- **Icon sizes:** 22px in nav bar, 24px in badges/buttons, 18-20px inline

---

## FAB & Bottom Nav

The bottom nav uses a custom implementation (not BottomNavigationBar):
- White background with `gray100` top border
- 5 items with a center gap for the floating scan FAB
- FAB: 52x52 emerald circle, positioned 24px above the nav bar
- Active items use `emerald600`, inactive use `gray400`
- Icon size 22px, label size 10px

---

## Common Widget Composition Pattern

Most screens follow this structure:

```dart
class SomeScreen extends ConsumerWidget {
  const SomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dataAsync = ref.watch(someProvider);
    final profile = ref.watch(profileProvider).valueOrNull;
    final currency = profile?['preferred_currency'] as String?;

    return dataAsync.when(
      data: (items) => SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 120),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header section
            // Content cards
            // List items
          ],
        ),
      ),
      loading: () => const Center(
        child: CircularProgressIndicator(color: BillyTheme.emerald600),
      ),
      error: (e, st) => Center(
        child: Text('Something went wrong', style: TextStyle(color: BillyTheme.gray500)),
      ),
    );
  }
}
```
