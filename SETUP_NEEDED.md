# Setup Needed for Billy

## ✅ Already Done

- GitHub connected (SSH)
- Supabase connected (URL + anon key in config)
- Project plan, AGENTS.md, Cursor rules, project skill

---

## ⏳ What You Need to Provide

### 1. Google Gemini API Key (Required for extraction)

1. Go to [Google AI Studio](https://aistudio.google.com/apikey)
2. Create an API key
3. Add to `.env`:
   ```
   GEMINI_API_KEY=your_key_here
   ```
4. Or share it here and we'll add it to config

### 2. Flutter SDK (If not installed)

- Download: https://docs.flutter.dev/get-started/install/windows
- Or: `winget install -e --id Google.Flutter`
- Run `flutter doctor` to verify

### 3. Domain (Later)

- You'll provide when ready for production
- We'll configure deployment then

### 4. Optional: Servers

- Supabase handles backend; may not need extra servers
- If needed: Vercel, Render, or Cloud Run for Edge Functions

---

## Skills from awesome-agent-skills

To install useful skills locally:

```powershell
.\scripts\install-skills.ps1
```

Or manually clone into `.cursor/skills/`:

| Skill | Clone From |
|-------|------------|
| Supabase Postgres | `https://github.com/supabase/agent-skills` → `skills/supabase-postgres-best-practices` |
| Gemini API | `https://github.com/google-gemini/gemini-skills` → `skills/gemini-api-dev` |

---

## Quick Start After Setup

1. Add `GEMINI_API_KEY` to `.env`
2. Run `flutter create .` (if Flutter project not yet created)
3. Add dependencies: `supabase_flutter`, `google_generative_ai`, `image_picker`
4. Start building from PROJECT_PLAN.md Phase 2
