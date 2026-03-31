# Per-User Gemini API Key Setup

Each user can have their own Google Gemini API key. This avoids rate limits and lets you track usage per user.

---

## 1. Run the migration in Supabase

1. Go to **Supabase Dashboard** → **SQL Editor** → **New Query**
2. Paste and run:

```sql
alter table public.profiles
  add column if not exists gemini_api_key text;

comment on column public.profiles.gemini_api_key is 'User-specific Google Gemini API key. If null, app uses default key.';
```

---

## 2. Where to manage users and API keys in Supabase

### See all users

**Authentication** → **Users**

- Lists every user: email, id (UUID), created_at, last sign in
- Copy a user's **id** to find them in the profiles table

### Edit API key per user

**Table Editor** → **profiles**

- Each row = one user (id matches auth.users.id)
- Find the user by `id` (same as in Authentication > Users)
- Edit the `gemini_api_key` column: paste the user's Google API key
- Leave blank to use the app's default key

### Quick workflow

1. **Authentication** → **Users** → copy user's UUID
2. **Table Editor** → **profiles** → filter or search by that id
3. Click the row → edit `gemini_api_key` → paste key → Save

---

## 3. Where to see Google API usage (not in Supabase)

Google Gemini usage is tracked in **Google Cloud Console**, not Supabase:

1. Go to [console.cloud.google.com](https://console.cloud.google.com)
2. Select the project that owns the API key
3. **APIs & Services** → **Dashboard** or **Credentials**
4. For quota/usage: **APIs & Services** → **Enabled APIs** → **Generative Language API** → **Quotas**

Each user's key = separate project/quota. Your app's default key = one project.

---

## 4. How it works in the app

- **Single-shot extraction**: Exactly 1 Gemini API call per image. No retries, no model fallbacks.
- **Per-user key**: Before each scan, the app fetches `gemini_api_key` from the user's profile.
- **Fallback**: If the user has no key, the app uses the default key from `lib/config/gemini_config.dart`.

---

## 5. Users can set their own key (optional)

In the app: **Profile** → **Settings** → **Gemini API Key** → enter key → Save.

Or you can set it for them in Supabase Table Editor.
