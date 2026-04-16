# Billy — Frontend Handoff for AI Assistance

## What is Billy?

Billy is a Flutter financial app for managing invoices, receipts, and expenses. It uses Supabase as the backend, Riverpod for state management, and a server-side Gemini OCR pipeline for document extraction.

**Stack:** Flutter 3.11+ · Supabase · Riverpod · Material 3

## How to use this folder

Give these files to Gemini (or any AI) when asking it to build frontend features. Each file covers a different aspect:

| File | What it covers |
|------|---------------|
| `ARCHITECTURE.md` | Project structure, folder conventions, state management patterns, navigation |
| `CURRENT_SCREENS.md` | Every existing screen, its location, what it does, and what needs to change |
| `DATABASE_SCHEMA.md` | All Supabase tables the frontend reads/writes, with column details |
| `UI_PATTERNS.md` | Theme system, color palette, widget patterns, code examples from the codebase |
| `FRONTEND_ROADMAP.md` | What screens/features need to be built next, ordered by priority |

## Quick Start for AI

When building a new screen or feature:

1. **Read `ARCHITECTURE.md`** first — understand folder structure and patterns
2. **Read `UI_PATTERNS.md`** — follow the existing theme and widget conventions
3. **Read `DATABASE_SCHEMA.md`** — know what data is available
4. **Read `CURRENT_SCREENS.md`** — understand what exists and how navigation works
5. **Read `FRONTEND_ROADMAP.md`** — see what needs to be built and in what order

## Key Rules

- Feature-first folder structure: `lib/features/<feature>/screens/`, `widgets/`, `models/`
- Shared providers live in `lib/providers/`
- Shared services live in `lib/services/`
- Always use `BillyTheme` colors — never hardcode hex values
- Use `ConsumerWidget` or `ConsumerStatefulWidget` (Riverpod)
- Navigation is `Navigator.push(MaterialPageRoute(...))` — no go_router
- All currency display should respect `profile['preferred_currency']`
- The app is web-first (deployed on Vercel) but should work on mobile too
