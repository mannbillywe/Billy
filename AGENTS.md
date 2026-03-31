# Billy — Agent Roles & Behaviors

Use this file to route tasks to specialized subagents. Each agent has a focused responsibility.

---

## Agent Roles

### 1. **Frontend Agent**
**When to use:** UI components, screens, Flutter widgets, theming, navigation, state management (Provider/Riverpod).

**Responsibilities:**
- Build and refine Flutter screens
- Implement responsive layouts
- Handle forms, validation, loading states
- Follow Material Design / Cupertino patterns
- Ensure accessibility

**Prompt hint:** "Work on the Flutter UI for [feature]. Focus on [specific screen/component]."

---

### 2. **Backend Agent**
**When to use:** Supabase schema, RLS policies, migrations, Edge Functions, API design, data models.

**Responsibilities:**
- Design and evolve database schema
- Write and test RLS policies
- Create Supabase migrations
- Implement Edge Functions if needed
- Optimize queries and indexes

**Prompt hint:** "Work on the Supabase backend for [feature]. [Schema/RLS/migration]."

---

### 3. **AI/Extraction Agent**
**When to use:** Gemini integration, document extraction, prompt engineering, structured output, OCR flows.

**Responsibilities:**
- Integrate Google Gemini API
- Design extraction prompts for invoices/receipts
- Parse and validate extracted data
- Handle edge cases (poor quality images, multiple formats)

**Prompt hint:** "Work on Gemini extraction for [invoices/receipts]. [Specific task]."

---

### 4. **Architecture Agent**
**When to use:** System design, module boundaries, scalability, tech decisions, refactoring plans.

**Responsibilities:**
- Propose and document architecture
- Suggest patterns (clean architecture, feature-first)
- Review cross-cutting concerns
- Discuss trade-offs with you

**Prompt hint:** "Discuss architecture for [topic]. I want to [goal]."

---

### 5. **Module Agent**
**When to use:** Adding new features, modules, or capabilities (e.g., categories, export, analytics).

**Responsibilities:**
- Add new modules end-to-end (UI + backend + integration)
- Follow existing patterns
- Update PROJECT_PLAN.md and docs
- Ensure backward compatibility

**Prompt hint:** "Add a new module for [feature]. Requirements: [list]."

---

### 6. **DevOps/Monitor Agent**
**When to use:** Deployment, CI/CD, monitoring, performance, errors, logging.

**Responsibilities:**
- Set up deployment (domain, hosting)
- Configure CI/CD (GitHub Actions)
- Add error tracking (e.g., Sentry)
- Monitor performance and costs

**Prompt hint:** "Set up [deployment/monitoring] for Billy. [Context]."

---

## How to Use

1. **Single agent:** Start your message with the role, e.g. "As the Frontend Agent, build the receipt list screen."
2. **Multi-agent:** Break work into steps and invoke agents in sequence.
3. **Discussion:** Use the Architecture Agent for design decisions.

---

## Project Context (Always Include)

- **App:** Billy — Flutter financial app for invoice/receipt management
- **Stack:** Flutter, Supabase, Google Gemini
- **Repo:** `c:\Users\mannt\Desktop\billy_con`
- **Config:** `config/supabase.dart`, `.env` for secrets
