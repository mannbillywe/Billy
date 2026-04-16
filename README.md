# Billy – AI Financial OS

Flutter app (Android, iOS, Web) for managing invoices, receipts, and expenses with Gemini AI extraction and Supabase backend.

## Deploy to Vercel (Web)

**Primary production URL (this repo)**

- **[https://web-iota-lilac-34.vercel.app](https://web-iota-lilac-34.vercel.app)** — use this domain for Billy web. Each push to `main` that touches `lib/`, `web/`, or `pubspec` runs [Deploy web to Vercel](.github/workflows/deploy-vercel-web.yml) **only if** GitHub Actions secrets point at this Vercel project.

**GitHub Actions → deploy here**

1. Open Vercel → project whose production domain is **web-iota-lilac-34.vercel.app** → **Settings → General** and copy **Project ID** (`prj_…`).
2. In GitHub: **mannbillywe/Billy** → **Settings → Secrets and variables → Actions**, set **`VERCEL_PROJECT_ID`** to that value. Also set **`VERCEL_ORG_ID`** (team id `team_…`) and **`VERCEL_TOKEN`** ([create token](https://vercel.com/account/tokens)).
3. Confirm **Actions** tab shows a green **Deploy web to Vercel** run after your push, or run the workflow manually (**Actions → Deploy web to Vercel → Run workflow**).

If `VERCEL_PROJECT_ID` is for a different project (for example **billycon**), production will update that other URL instead: [https://billycon.vercel.app](https://billycon.vercel.app).

**Why `web-iota-lilac-34` can look “blank” (only title *billy*)**

Vercel is serving the **source** `web/` folder (HTML + `flutter_bootstrap.js` shell) **without** running `flutter build web`. The compiled **`main.dart.js`**, **CanvasKit**, and assets live under **`build/web/`** only after a local/CI build. Fix: deploy **`build/web`**, not **`web/`**.

**Ways to deploy correctly**

1. **Local:** `scripts/deploy-vercel.ps1` (builds, copies `vercel.json` + `web/api/`, deploys from `build/web`).
2. **GitHub:** Actions → **Deploy web to Vercel** (`deploy-vercel-web.yml`). Set `VERCEL_TOKEN`, `VERCEL_ORG_ID`, `VERCEL_PROJECT_ID` in repo secrets; use the **Project ID** of the project whose domain you want (e.g. `web-iota-lilac-34`).
3. **Vercel dashboard:** For the broken project, either **disconnect Git** and deploy only via (1)/(2), or remove **Root Directory = `web`** and do **not** rely on a static export — Vercel’s default image has **no Flutter SDK**, so Git auto-build cannot compile Dart unless you add a custom approach.

**Important:** Do **not** run `vercel deploy` from the **`web/`** folder alone; the site will be missing compiled Dart and will fail to boot.

**Windows:** If `flutter build web` fails with *“Building with plugins requires symlink support”*, enable **Developer Mode** (Settings → System → For developers → Developer Mode), then run `start ms-settings:developers` to open the page. Alternatively build on macOS/Linux or use CI.

**First-time `vercel link`:** If the CLI reports a GitHub connection error, set the correct repository under Vercel → Project → Settings → Git (owner/repo must match, e.g. `mannbillywe/Billy`).

1. **Prerequisites**
   - Flutter SDK installed
   - Node.js (for Vercel CLI)
   - Vercel account

2. **One-time setup**
   ```powershell
   npm install -g vercel
   # Or use npx (no install): npx vercel
   ```

3. **Deploy**
   ```powershell
   $env:VERCEL_TOKEN = "vcp_your_token_here"
   .\scripts\deploy-vercel.ps1
   ```
   Or run `vercel login` first and omit the token.

4. **What you need for Vercel**
   - **Token**: Create at [vercel.com/account/tokens](https://vercel.com/account/tokens)
   - **Scope**: Use `$env:VERCEL_SCOPE = "mannbillywes-projects"` if different team
   - **GitHub** (optional): Connect repo for auto-deploy on push
   - **Custom domain** (optional): Add in Vercel dashboard → Project → Settings → Domains

---

## Supabase

Connected to: `https://wpzopkigbbldcfpxuvcm.supabase.co`

### Config files
- `.env` – URL and anon key (gitignored)
- `config/supabase.js` – for web/Node.js
- `config/supabase.dart` – for Flutter

### Deploy `statement-classify` (GOAT Edge Function)

The Supabase CLI may reject newer access tokens (`sbp_v0_…`). To deploy with a token that works on `api.supabase.com`, use:

```powershell
# SUPABASE_ACCESS_TOKEN in env, or in repo-root .env.local (gitignored)
.\scripts\deploy-statement-classify-supabase-api.ps1
```

Requires `curl.exe`. Project ref defaults to this repo’s Supabase project; override via `supabase/.temp/project-ref` after `supabase link`.

### Flutter setup
```yaml
# pubspec.yaml
dependencies:
  supabase_flutter: ^2.0.0
```

```dart
// main.dart
import 'package:supabase_flutter/supabase_flutter.dart';
import 'config/supabase.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Supabase.initialize(
    url: SupabaseConfig.url,
    anonKey: SupabaseConfig.anonKey,
  );
  runApp(MyApp());
}
```

### Web/JS setup
```bash
npm install @supabase/supabase-js
```

```js
import { createClient } from '@supabase/supabase-js';
import { supabaseConfig } from './config/supabase.js';

const supabase = createClient(supabaseConfig.url, supabaseConfig.anonKey);
```
