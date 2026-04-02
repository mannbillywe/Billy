# Invoice scan — Gemini API key (profiles + optional secret)

Scanning uses Edge Function **`process-invoice`**: **one** call to **`gemini-2.0-flash`** per file (good balance of speed and cost for vision + PDF).

The API key is resolved in this order:

1. **`profiles.gemini_api_key`** for the **signed-in user** (same `id` as `auth.users`)
2. If empty → **`GEMINI_API_KEY`** on the Edge Function (optional fallback for all users)

The Flutter app **never** sends or stores the Gemini key.

---

## 1. Per-user key (Table Editor — you as admin)

1. Supabase → **Authentication** → **Users** → copy the user’s UUID.
2. **Table Editor** → **`profiles`** → row where **`id`** = that UUID.
3. Set **`gemini_api_key`** to a Google AI Studio / Gemini API key → **Save**.

Repeat for each user who should scan, or use the fallback below so you only manage one secret.

---

## 2. Fallback: one key for everyone

Dashboard → **Edge Functions** → **process-invoice** → **Secrets**:

```bash
supabase secrets set GEMINI_API_KEY=your_key --project-ref YOUR_REF
```

Users with a non-empty **`profiles.gemini_api_key`** still use **their** profile key first.

---

## 3. Deploy

```bash
npm run supabase:deploy-process-invoice
```

---

## 4. Logs

Function logs show `key_source=profiles.gemini_api_key` or `key_source=GEMINI_API_KEY secret` (never the key value).
