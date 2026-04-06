# Billy – AI Financial OS

Flutter app (Android, iOS, Web) for managing invoices, receipts, and expenses with Gemini AI extraction and Supabase backend.

## Deploy to Vercel (Web)

**Important:** Deploy **only** via `scripts/deploy-vercel.ps1` (or the same steps manually: `flutter build web` → copy `web/vercel.json` and `web/api/` into `build/web` → `vercel deploy` **from `build/web`**). Running `vercel deploy` from the `web/` folder uploads **templates only** (no compiled Dart), so the site will be blank.

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
