# Billy - Installation Status

## Flutter SDK

**Status:** Installed via Git clone

**Location:** `C:\Users\mannt\AppData\Local\flutter`

**PATH:** Added to your user PATH. You may need to **restart your terminal or Cursor** for it to take effect.

### Verify Installation

Open a **new** terminal and run:

```powershell
flutter --version
flutter doctor
```

If `flutter` is not found, manually add to PATH:
- Add `C:\Users\mannt\AppData\Local\flutter\bin` to your system PATH

### First Run

The first time you run `flutter`, it will:
- Download the Dart SDK
- Build the Flutter tool
- Resolve dependencies

This can take 2–5 minutes. Wait for it to finish.

### Enable Web Support

```powershell
flutter config --enable-web
```

---

## API Keys Configured

| Service | Status |
|---------|--------|
| Supabase | Configured (URL + anon key) |
| Google Gemini | Configured (API key) |

---

## Phase 1 Complete

- Flutter project initialized
- Dependencies added (Supabase, Gemini, Riverpod, go_router, image_picker, pdf, etc.)
- Billy design system ported (theme, header, bottom nav)
- App shell with 5 tab placeholders (Dashboard, Scan, Analytics, Split, Profile)

## Next Steps (when you say "continue")

1. Create Supabase database schema
2. Build Dashboard screen
3. Build Scan screen with Gemini extraction
4. Build remaining screens

---

## Domain / Deployment

You mentioned you'll provide domain details later. When ready, we can:
- Set up hosting (Vercel, Netlify, or your server)
- Configure custom domain
- Set up CI/CD for automatic deploys
