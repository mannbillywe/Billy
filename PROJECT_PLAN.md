# Billy — Project Plan

## Overview

**Billy** is a production-level Flutter financial app for individuals to:
- Manage invoices and receipts
- Extract data from documents using Google Gemini AI
- Export all financial info (PDF, Excel, etc.)

---

## Tech Stack

| Layer | Technology |
|-------|------------|
| **Frontend** | Flutter (cross-platform: iOS, Android, Web) |
| **Backend** | Supabase (PostgreSQL, Auth, Storage, Realtime) |
| **AI/Extraction** | Google Gemini API (document understanding, OCR) |
| **Version Control** | GitHub |
| **Deployment** | TBD (domain provided later) |

---

## Phase 1: Foundation (Current)

- [x] GitHub connected (SSH)
- [x] Supabase connected
- [ ] Google Gemini API key added
- [ ] Flutter project scaffold
- [ ] Project skills & AGENTS.md

---

## Phase 2: Core App

### 2.1 Flutter Setup
- Create Flutter app structure
- Add: `supabase_flutter`, `google_generative_ai`, `image_picker`, `file_picker`
- Configure Supabase + Gemini in app

### 2.2 Supabase Schema
- `profiles` — user profile (linked to Supabase Auth)
- `invoices` — invoice records (vendor, amount, date, items, image_url)
- `receipts` — receipt records (merchant, amount, date, category, image_url)
- `documents` — raw document storage (Supabase Storage)
- RLS policies for user-scoped data

### 2.3 Gemini Integration
- Image → Gemini (multimodal) for receipt/invoice extraction
- Structured output: vendor, amount, date, items, tax, etc.
- Fallback for low-confidence extractions

### 2.4 Core Features
- Auth (email/password, Google OAuth via Supabase)
- Capture: camera + gallery for receipts/invoices
- AI extraction flow
- List, filter, search invoices/receipts
- Edit/correct extracted data

---

## Phase 3: Export & Polish

- Export to PDF (summary reports)
- Export to Excel/CSV (full data)
- Categories and tags
- Basic analytics (spending by category, month)

---

## Phase 4: Production

- Domain setup (you provide)
- App store deployment (iOS, Android)
- Web deployment (optional)
- Servers: Supabase handles most; Edge Functions if needed

---

## Keys & Setup Checklist

| Item | Status | Notes |
|------|--------|-------|
| GitHub | ✅ | SSH connected |
| Supabase URL + anon key | ✅ | In config |
| **Google Gemini API key** | ⏳ | Needed for extraction |
| Flutter SDK | ⏳ | Install if not present |
| Domain | ⏳ | You'll provide later |

---

## Skills to Install (from awesome-agent-skills)

| Skill | Repo Path | Purpose |
|-------|-----------|---------|
| Supabase Postgres | `supabase/agent-skills` → `supabase-postgres-best-practices` | DB design, RLS |
| Google Gemini | `google-gemini/gemini-skills` | Gemini API usage |
| PDF | `openai/skills` → `pdf` | PDF handling for export |
| Spreadsheet | `openai/skills` → `spreadsheet` | Excel/CSV export |

---

## File Structure (Target)

```
billy_con/
├── lib/
│   ├── main.dart
│   ├── config/
│   │   └── supabase.dart
│   ├── features/
│   │   ├── auth/
│   │   ├── capture/
│   │   ├── extraction/
│   │   └── export/
│   └── services/
│       ├── supabase_service.dart
│       └── gemini_service.dart
├── .cursor/
│   ├── rules/
│   ├── skills/
│   └── AGENTS.md
├── config/
├── supabase/
│   └── migrations/
└── PROJECT_PLAN.md
```
