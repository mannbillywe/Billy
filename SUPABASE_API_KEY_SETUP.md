# Gemini API key for invoice extraction (per user in Supabase)

The Flutter app does **not** store or send your Google API key. Scanning calls the Edge Function **`extract-invoice`**, which picks a key in this order:

1. **`profiles.gemini_api_key`** for the **logged-in user** (same UUID as `auth.users.id`)
2. If that is null/empty → **`GEMINI_API_KEY`** on the Edge Function (optional shared default)

There is still **one Gemini request per scan** on the server.

---

## 1. Set a key per user (Table Editor)

1. Supabase → **Authentication** → **Users** → copy the user’s **UUID**.
2. **Table Editor** → **`profiles`** → find the row where **`id`** = that UUID.
3. Edit **`gemini_api_key`** → paste the Google AI Studio / Gemini API key → **Save**.

Requirements:

- RLS must allow the user to **read** their own `profiles` row (default “own profile” select policy is enough).
- The Edge Function uses the **user’s JWT** to query `profiles`, so only **their** row is visible.

---

## 2. Optional: default key for everyone without a profile key

Dashboard → **Edge Functions** → **Secrets** (or CLI):

```bash
supabase secrets set GEMINI_API_KEY=your_default_key
```

Users with a non-empty **`profiles.gemini_api_key`** still use **their** key first.

---

## 3. Deploy the function

```bash
supabase functions deploy extract-invoice
```

---

## 4. Logs

In function logs you’ll see `key_source=profiles.gemini_api_key` or `key_source=GEMINI_API_KEY secret` (the key value is never logged).
