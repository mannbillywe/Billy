# Google sign-in with Supabase (fix “Unsupported provider” / “missing secret”)

That message means **Google is not fully configured in the Supabase dashboard**, not that your app code is wrong.

**Important:** `supabase1234` or `SUPABASE_ACCESS_TOKEN` in `.env` is a **Supabase personal access token** (for CLI). It is **not** the Google OAuth **Client Secret**. Do not paste it into the Google provider fields.

## 1. Google Cloud Console

1. Open [Google Cloud Console](https://console.cloud.google.com/) → select or create a project.
2. **APIs & Services** → **OAuth consent screen** → configure (External is fine for testing).
3. **APIs & Services** → **Credentials** → **Create credentials** → **OAuth client ID**.
4. Create a **Web application** client (needed for Billy web on Vercel):
   - **Authorized JavaScript origins** (add each URL users use):
     - `https://web-iota-lilac-34.vercel.app` (legacy domain; only if you still use it)
     - `https://billycon.vercel.app` (CLI / correct `build/web` deploys)
     - `http://localhost:PORT` (if you test Flutter web locally)
   - **Authorized redirect URIs** (required):
     - `https://wpzopkigbbldcfpxuvcm.supabase.co/auth/v1/callback`  
       (replace with your Supabase project URL if different: **Dashboard → Project Settings → API** → Project URL + `/auth/v1/callback`)
5. Copy the **Client ID** and **Client secret**.

Optional: add separate **iOS** / **Android** OAuth clients if you ship mobile apps; use those bundle IDs / SHA-1 as Google documents.

## 2. Supabase Dashboard

1. **Authentication** → **Providers** → **Google**.
2. Turn **Google enabled** on.
3. Paste **Client ID** and **Client Secret** from Google (the **Google** secret, not the Supabase PAT).
4. Save.

## 3. Supabase URL configuration (web)

1. **Authentication** → **URL Configuration**.
2. **Site URL:** your main app URL (pick one primary), e.g. `https://billycon.vercel.app` or `https://web-iota-lilac-34.vercel.app`.
3. **Redirect URLs:** add every origin you use:
   - `https://billycon.vercel.app/**`
   - `https://web-iota-lilac-34.vercel.app/**`
   - `http://localhost:**` (optional, for local web)

## 4. Retry

Hard-refresh the app (or use a private window) and try **Continue with Google** again.

If it still fails, open the browser **Network** tab, find the failing request to Supabase Auth, and read the JSON error message—it usually states whether the provider is disabled or redirect URLs do not match.
