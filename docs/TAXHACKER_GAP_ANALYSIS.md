# Billy vs TaxHacker — Gap Analysis & Implementation Roadmap

> **Date:** April 5, 2026
> **Reference:** [TaxHacker](https://github.com/vas3k/TaxHacker) (v0.7.0)
> **Billy version:** Current `main` branch

---

## Table of Contents

1. [Feature Comparison Matrix](#1-feature-comparison-matrix)
2. [Missing Features — Detailed Breakdown](#2-missing-features--detailed-breakdown)
3. [Implementation Roadmap](#3-implementation-roadmap)
4. [Implementation Details Per Feature](#4-implementation-details-per-feature)
5. [Priority Order](#5-priority-order)
6. [File & Folder Map](#6-file--folder-map)

---

## 1. Feature Comparison Matrix

| Feature | TaxHacker | Billy | Gap |
|---------|-----------|-------|-----|
| **AI Document Extraction** | OpenAI / Gemini / Mistral / Local LLM | Gemini (Edge Function) | Multi-LLM provider support |
| **Custom LLM Prompts** | User-editable system + field prompts | Hardcoded in Edge Function | Missing prompt customization |
| **Custom Fields** | Unlimited user-defined fields with AI prompts | Fixed schema (amount, vendor, date, etc.) | Missing custom fields |
| **Projects** | Multi-project grouping with colors + AI prompts | No project concept | Missing entirely |
| **Custom Categories** | User-created with colors + AI prompts | Fixed global + manual categories | Partial — no custom create/color/AI |
| **Multi-Currency + Auto-Convert** | 170+ currencies + crypto, historical rates | 7 hardcoded currencies, no conversion | Major gap |
| **Full-Text Search** | Search across recognized document text | Filter by category/source/status | Missing text search |
| **Unsorted / Inbox** | Documents staged in "unsorted" before processing | Direct scan → save flow | Missing staging area |
| **CSV Import** | Upload CSV → map columns → create transactions | No import capability | Missing entirely |
| **Data Backup & Restore** | Full JSON backup/restore of all data | No backup/restore | Missing entirely |
| **Invoice Generator** | Create and send invoices to customers | No invoice generation | Missing entirely |
| **Bulk Operations** | Select multiple → bulk delete/categorize | One-at-a-time operations | Missing bulk ops |
| **Income Tracking** | Expense + Income types per transaction | Expenses only (documents = expenses) | Missing income type |
| **Merchant Tracking** | Dedicated merchant field, searchable | Vendor field in extraction only | Partial |
| **Item Splitting** | Extract line items → create separate transactions | Line items shown but not splittable | Missing split-to-transactions |
| **Per-Project Analytics** | Stats broken down by project | No project concept | Missing |
| **Time Series Charts** | Income vs expense over time, day/month auto-group | Weekly spend chart, category breakdown | Partial |
| **Tax-Ready Reports** | Filtered export with documents for accountant | PDF/CSV export exists | Partial — no tax focus |
| **Business Profile** | Business name/address/bank/logo for invoices | Basic profile (display name, currency) | Missing business info |
| **Dashboard Stats** | Income/expenses/profit per currency, filtered | Week spend, category breakdown | Partial — no income/profit |
| **Lend/Borrow + Groups** | Not present | Full social ledger, group expenses | Billy is ahead |
| **Social / Friends** | Not present | Invitations, connections, splits | Billy is ahead |
| **Apple/Google OAuth** | Not present (email + self-hosted auth) | Google + Apple OAuth | Billy is ahead |
| **Sentry Monitoring** | Sentry integrated | Sentry integrated | Equal |
| **PDF Export** | CSV export with documents | PDF + CSV export | Billy is ahead |

---

## 2. Missing Features — Detailed Breakdown

### 2.1 Multi-Currency with Automatic Conversion

**What TaxHacker does:**
- Detects currency from scanned documents
- Fetches historical exchange rates from xe.com for the transaction date
- Converts to user's base currency automatically
- Supports 170+ fiat currencies and 14 cryptocurrencies
- Stores both original and converted amounts

**What Billy has:**
- 7 hardcoded currencies (USD, EUR, GBP, INR, JPY, CAD, AUD) in settings
- No automatic conversion
- Documents store a single `total_amount` with no currency field

**Gap:** No currency detection, no conversion, no historical rates, limited currency list.

---

### 2.2 Custom Fields (User-Defined)

**What TaxHacker does:**
- Users create unlimited custom fields (e.g., "Tax ID", "Project Code", "PO Number")
- Each field has: name, type (string/number/date), visibility settings, AI extraction prompt
- AI uses field prompts to extract custom data from documents
- Fields appear as extra columns in the transaction table

**What Billy has:**
- Fixed document schema: title, amount, date, category, vendor, notes
- No user-defined fields

**Gap:** No extensible schema, no custom AI extraction prompts per field.

---

### 2.3 Projects (Multi-Project Grouping)

**What TaxHacker does:**
- Users create projects (e.g., "Q1 Taxes", "Office Renovation", "Client ABC")
- Each project has name, color, optional AI prompt for auto-assignment
- Transactions linked to projects, filterable
- Per-project analytics (income/expenses/profit)

**What Billy has:**
- No project concept (expense groups are for splitting costs with friends, not project tagging)

**Gap:** Entirely missing. Documents cannot be grouped by project/purpose.

---

### 2.4 Custom Categories with Colors & AI Prompts

**What TaxHacker does:**
- Users create/edit/delete categories with custom name, color, AI prompt
- AI uses category prompts to auto-categorize documents
- Categories are fully user-owned

**What Billy has:**
- Global categories (system-defined, shared) + `category_source` tracking
- No user-created categories, no color, no AI prompt per category

**Gap:** Users can't create their own categories or customize AI categorization logic.

---

### 2.5 Customizable LLM Prompts

**What TaxHacker does:**
- Users can modify the system prompt template in settings
- Per-field AI extraction prompts (e.g., "Extract the VAT registration number")
- Per-category AI prompts (e.g., "Classify as 'Travel' if it mentions hotel, flight, taxi")
- Per-project AI prompts (e.g., "Assign to 'Office' if vendor is an office supply store")
- Full transparency into AI behavior

**What Billy has:**
- Hardcoded prompts in Edge Function `process-invoice`
- No user control over extraction behavior

**Gap:** Users cannot tune or customize AI extraction at all.

---

### 2.6 Income Tracking (Not Just Expenses)

**What TaxHacker does:**
- Transactions have a `type` field: `expense` or `income`
- Dashboard shows income, expenses, and profit
- Charts show income vs expenses over time

**What Billy has:**
- Documents are implicitly expenses
- Dashboard shows only spend (no income/profit concept)

**Gap:** No income transactions, no profit calculation.

---

### 2.7 CSV Import

**What TaxHacker does:**
- Upload a CSV file
- Map CSV columns to transaction fields
- Preview and bulk-create transactions
- Useful for importing bank statements or migrating from other tools

**What Billy has:**
- CSV export only, no import

**Gap:** No way to import historical data or bank statements.

---

### 2.8 Data Backup & Restore

**What TaxHacker does:**
- Full JSON backup of: settings, currencies, categories, projects, fields, files, transactions
- Download as archive
- Restore from backup (re-import everything)
- Complete data portability

**What Billy has:**
- Export to PDF/CSV (reports only)
- No full data backup/restore

**Gap:** No way to back up and restore all app data.

---

### 2.9 Invoice Generator

**What TaxHacker does:**
- Built-in invoice creation tool (an "app" within the app)
- Fill in client details, line items, tax rates
- Generate PDF invoices
- Templates for different invoice formats

**What Billy has:**
- Only receipt/invoice scanning (reading), no generation (writing)

**Gap:** No ability to create invoices to send to clients/customers.

---

### 2.10 Unsorted / Inbox (Document Staging)

**What TaxHacker does:**
- Uploaded files land in "Unsorted" / inbox
- User reviews and processes them when ready (manually or with AI)
- Clear separation: upload → review → process → transaction

**What Billy has:**
- Direct flow: scan → extract → save (draft/saved status exists but no dedicated inbox screen)

**Gap:** No dedicated staging area for batch uploads or deferred processing.

---

### 2.11 Full-Text Search

**What TaxHacker does:**
- Search across: name, merchant, description, notes, OCR text
- Case-insensitive, across all text fields

**What Billy has:**
- Filter by category, source, date range, status
- No text-based search across document content

**Gap:** Cannot search "Uber" or "Amazon" across all documents.

---

### 2.12 Bulk Operations

**What TaxHacker does:**
- Select multiple transactions
- Bulk delete, bulk categorize, bulk assign project

**What Billy has:**
- Single-document operations only

**Gap:** No multi-select or batch actions.

---

### 2.13 Item Splitting → Separate Transactions

**What TaxHacker does:**
- When AI extracts line items from an invoice, user can "split" them
- Each line item becomes its own transaction with its own category/project

**What Billy has:**
- Line items extracted and displayed in scan review
- Line items can trigger lend/borrow entries
- But cannot split into separate documents/transactions

**Gap:** No item-to-document splitting.

---

### 2.14 Business Profile

**What TaxHacker does:**
- Business name, address, bank details, logo
- Used in generated invoices
- Professional identity within the app

**What Billy has:**
- Basic profile: display name, preferred currency

**Gap:** No business identity fields.

---

## 3. Implementation Roadmap

The roadmap is organized into 6 sprints. Each sprint builds on the previous one and keeps Billy's existing simple flow intact.

```
Sprint 1 (Foundation)          Sprint 2 (Customization)       Sprint 3 (Intelligence)
┌─────────────────────┐       ┌─────────────────────┐       ┌─────────────────────┐
│ Multi-Currency +    │       │ Custom Categories   │       │ Customizable LLM    │
│ Auto-Conversion     │──────▶│ Custom Fields       │──────▶│ Prompts             │
│ Income Type         │       │ Projects            │       │ Full-Text Search    │
│ Full-Text Search    │       │                     │       │ Item Splitting      │
└─────────────────────┘       └─────────────────────┘       └─────────────────────┘
         │                              │                              │
         ▼                              ▼                              ▼
Sprint 4 (Productivity)       Sprint 5 (Data)                Sprint 6 (Professional)
┌─────────────────────┐       ┌─────────────────────┐       ┌─────────────────────┐
│ Unsorted / Inbox    │       │ CSV Import          │       │ Invoice Generator   │
│ Bulk Operations     │──────▶│ Data Backup &       │──────▶│ Business Profile    │
│ Better Dashboard    │       │ Restore             │       │ Tax-Ready Reports   │
└─────────────────────┘       └─────────────────────┘       └─────────────────────┘
```

---

## 4. Implementation Details Per Feature

### Sprint 1: Foundation Enhancements

#### 4.1 Multi-Currency + Auto-Conversion

**Database changes** (`supabase/migrations/`):

```sql
-- Add currency fields to documents
ALTER TABLE documents
  ADD COLUMN currency_code TEXT DEFAULT 'USD',
  ADD COLUMN converted_amount NUMERIC,
  ADD COLUMN converted_currency TEXT;

-- User currencies table (user's frequently used currencies)
CREATE TABLE user_currencies (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  UNIQUE(user_id, code)
);
-- RLS: user-scoped
```

**New files:**

| File | Purpose |
|------|---------|
| `lib/services/currency_service.dart` | Fetch historical rates from a free API (e.g., exchangerate.host or frankfurter.app) |
| `lib/features/settings/screens/currencies_screen.dart` | Manage user's currency list |
| `lib/providers/currency_provider.dart` | Cache rates, provide conversion helpers |

**Flow (unchanged simplicity):**
1. User scans document → AI extracts amount + detects currency
2. If currency differs from preferred, auto-convert using historical rate for that date
3. Document stores: `total_amount`, `currency_code`, `converted_amount`, `converted_currency`
4. Dashboard shows totals in preferred currency

**Edge Function update** (`process-invoice/index.ts`):
- Add `currency_code` to extraction schema
- AI prompt: "Also identify the currency used in this document"

---

#### 4.2 Income Type

**Database changes:**

```sql
ALTER TABLE documents
  ADD COLUMN transaction_type TEXT DEFAULT 'expense'
  CHECK (transaction_type IN ('expense', 'income'));
```

**UI changes:**
- `document_edit_screen.dart` — Add expense/income toggle
- `dashboard_screen.dart` — Show income + expenses + net
- `money_flow_chart.dart` — Income vs expense bars
- Scan review — Option to mark as income

**Provider changes:**
- `documents_provider.dart` — Filter by type
- `dashboard_spend_math.dart` — Calculate income, expenses, profit

---

#### 4.3 Full-Text Search

**Database changes:**

```sql
-- Add a tsvector column for full-text search
ALTER TABLE documents ADD COLUMN search_vector tsvector;

CREATE INDEX idx_documents_search ON documents USING gin(search_vector);

-- Trigger to auto-update search vector
CREATE OR REPLACE FUNCTION documents_search_update() RETURNS trigger AS $$
BEGIN
  NEW.search_vector := to_tsvector('english',
    coalesce(NEW.title, '') || ' ' ||
    coalesce(NEW.vendor, '') || ' ' ||
    coalesce(NEW.notes, '') || ' ' ||
    coalesce(NEW.extracted_text, '')
  );
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER documents_search_trigger
  BEFORE INSERT OR UPDATE ON documents
  FOR EACH ROW EXECUTE FUNCTION documents_search_update();
```

**UI changes:**
- `documents_history_screen.dart` — Add search bar at top
- Search uses Supabase `.textSearch('search_vector', query)`

**Flow:** User types in search bar → instant filtering across all text fields.

---

### Sprint 2: Customization

#### 4.4 Custom Categories

**Database changes:**

```sql
CREATE TABLE user_categories (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  color TEXT DEFAULT '#6B7280',
  llm_prompt TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, code)
);
-- RLS: user-scoped CRUD
```

**New files:**

| File | Purpose |
|------|---------|
| `lib/features/settings/screens/categories_screen.dart` | List, create, edit, delete categories |
| `lib/features/settings/widgets/category_form.dart` | Name, color picker, AI prompt editor |
| `lib/providers/categories_provider.dart` | Fetch/cache user categories |

**Flow:** Settings → Categories → Add/Edit → Name + Color + optional AI prompt.
Documents still use `category` field, but now resolved from `user_categories` first, then fallback to global `categories`.

---

#### 4.5 Custom Fields

**Database changes:**

```sql
CREATE TABLE user_fields (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  type TEXT DEFAULT 'string' CHECK (type IN ('string', 'number', 'date', 'boolean')),
  llm_prompt TEXT,
  is_visible_in_list BOOLEAN DEFAULT false,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, code)
);

-- Store custom field values in a JSONB column on documents
ALTER TABLE documents ADD COLUMN extra_fields JSONB DEFAULT '{}';
```

**New files:**

| File | Purpose |
|------|---------|
| `lib/features/settings/screens/fields_screen.dart` | Manage custom fields |
| `lib/features/settings/widgets/field_form.dart` | Name, type, AI prompt |
| `lib/providers/fields_provider.dart` | Fetch user's custom fields |

**Flow:**
1. User creates field (e.g., "Tax ID") with AI prompt ("Extract the tax identification number")
2. Edge Function includes custom field prompts in AI request
3. Extracted values stored in `documents.extra_fields` JSONB
4. Document detail/edit shows custom fields dynamically

---

#### 4.6 Projects

**Database changes:**

```sql
CREATE TABLE projects (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  code TEXT NOT NULL,
  name TEXT NOT NULL,
  color TEXT DEFAULT '#3B82F6',
  llm_prompt TEXT,
  created_at TIMESTAMPTZ DEFAULT now(),
  UNIQUE(user_id, code)
);

ALTER TABLE documents ADD COLUMN project_id UUID REFERENCES projects(id);
-- RLS: user-scoped
```

**New files:**

| File | Purpose |
|------|---------|
| `lib/features/settings/screens/projects_screen.dart` | Manage projects |
| `lib/features/settings/widgets/project_form.dart` | Name, color, AI prompt |
| `lib/providers/projects_provider.dart` | Fetch/cache projects |

**UI integration:**
- Document edit → project dropdown
- Document list → filter by project
- Analytics → per-project breakdown

---

### Sprint 3: Intelligence

#### 4.7 Customizable LLM Prompts

**Database changes:**

```sql
-- System prompt stored in profiles or a settings table
ALTER TABLE profiles ADD COLUMN llm_system_prompt TEXT;
```

**New files:**

| File | Purpose |
|------|---------|
| `lib/features/settings/screens/llm_settings_screen.dart` | Edit system prompt, view extraction template |

**Edge Function update:**
- `process-invoice` reads user's `llm_system_prompt` from DB
- Appends custom field prompts, category prompts, project prompts
- Constructs a dynamic prompt per user

**Flow:**
1. Settings → AI Settings → Edit system prompt
2. Each scan uses the custom prompt
3. Categories, fields, projects with `llm_prompt` are included automatically

---

#### 4.8 Item Splitting → Separate Documents

**UI changes in `scan_review_panel.dart`:**
- Each extracted line item gets a "Save as separate document" button
- Tapping it creates a new document with that line item's data pre-filled
- User can review and save

**New method in `supabase_service.dart`:**
```dart
Future<void> splitLineItemToDocument(Map<String, dynamic> lineItem, String parentDocId)
```

---

### Sprint 4: Productivity

#### 4.9 Unsorted / Inbox

**Database changes:**

```sql
ALTER TABLE documents ADD COLUMN is_unsorted BOOLEAN DEFAULT false;
```

**New files:**

| File | Purpose |
|------|---------|
| `lib/features/documents/screens/unsorted_screen.dart` | Inbox view for unprocessed uploads |

**Flow:**
1. User uploads file(s) without immediate processing → marked `is_unsorted = true`
2. Unsorted screen shows pending items
3. Tap to process with AI or manually categorize
4. Processing moves it to regular documents (`is_unsorted = false`)

**Navigation:** Add "Inbox" badge on dashboard or as a quick action.

---

#### 4.10 Bulk Operations

**UI changes in `documents_history_screen.dart`:**
- Long-press to enter selection mode
- Multi-select checkboxes appear
- Bottom action bar: Delete Selected, Set Category, Set Project

**New methods in `supabase_service.dart`:**
```dart
Future<void> bulkDeleteDocuments(List<String> ids)
Future<void> bulkUpdateCategory(List<String> ids, String categoryCode)
Future<void> bulkUpdateProject(List<String> ids, String projectId)
```

---

#### 4.11 Better Dashboard (Income/Expense/Profit)

**Update `dashboard_screen.dart`:**
- Hero cards: Total Income | Total Expenses | Net Profit (for selected period)
- Money flow chart: dual bars (income green, expense red)
- Category breakdown: split by income vs expense

**Update `dashboard_spend_math.dart`:**
- Add `totalIncome()`, `totalExpenses()`, `netProfit()` methods
- Group by currency, convert to preferred

---

### Sprint 5: Data Management

#### 4.12 CSV Import

**New files:**

| File | Purpose |
|------|---------|
| `lib/features/import/screens/csv_import_screen.dart` | File picker → preview → column mapping → import |
| `lib/features/import/widgets/column_mapper.dart` | Map CSV headers to document fields |
| `lib/features/import/services/csv_import_service.dart` | Parse CSV, create documents |

**Flow:**
1. Settings → Import Data → Pick CSV file
2. App shows preview table with CSV data
3. User maps columns: "Column A" → "Amount", "Column B" → "Date", etc.
4. Preview mapped data → Confirm → Documents created

**Uses existing `csv` package** already in `pubspec.yaml`.

---

#### 4.13 Data Backup & Restore

**New files:**

| File | Purpose |
|------|---------|
| `lib/features/settings/screens/backup_screen.dart` | Backup & Restore UI |
| `lib/services/backup_service.dart` | Export all tables to JSON, import from JSON |

**What gets backed up:**
- Documents (all fields + extra_fields)
- Categories (user-created)
- Projects
- Custom fields
- Lend/borrow entries
- Groups & group expenses
- Settings/preferences

**Flow:**
1. Settings → Backup → Create Backup → Downloads a `.json` file
2. Settings → Backup → Restore → Pick `.json` file → Confirm → Data restored

---

### Sprint 6: Professional

#### 4.14 Invoice Generator

**New files:**

| File | Purpose |
|------|---------|
| `lib/features/invoices/screens/invoice_list_screen.dart` | List created invoices |
| `lib/features/invoices/screens/invoice_create_screen.dart` | Form: client, items, tax, etc. |
| `lib/features/invoices/services/invoice_pdf_service.dart` | Generate PDF from invoice data |
| `lib/features/invoices/models/invoice_model.dart` | Invoice data structure |

**Database:**

```sql
CREATE TABLE generated_invoices (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  user_id UUID REFERENCES auth.users(id) ON DELETE CASCADE,
  invoice_number TEXT,
  client_name TEXT,
  client_address TEXT,
  items JSONB DEFAULT '[]',
  subtotal NUMERIC,
  tax_rate NUMERIC,
  tax_amount NUMERIC,
  total NUMERIC,
  currency_code TEXT DEFAULT 'USD',
  notes TEXT,
  issued_at DATE,
  due_at DATE,
  status TEXT DEFAULT 'draft' CHECK (status IN ('draft', 'sent', 'paid')),
  created_at TIMESTAMPTZ DEFAULT now()
);
-- RLS: user-scoped
```

**Flow:**
1. New tab or screen: "Invoices" → Create Invoice
2. Fill: client info, line items, tax rate
3. Preview → Generate PDF → Share/Download
4. Track status: Draft → Sent → Paid

---

#### 4.15 Business Profile

**Database changes:**

```sql
ALTER TABLE profiles
  ADD COLUMN business_name TEXT,
  ADD COLUMN business_address TEXT,
  ADD COLUMN business_bank_details TEXT,
  ADD COLUMN business_logo_url TEXT;
```

**UI:** Settings → Business Profile → Name, Address, Bank Details, Logo upload.
Used automatically in generated invoices.

---

#### 4.16 Tax-Ready Reports

**Update `lib/features/export/`:**
- New export type: "Tax Report"
- Filtered by date range + category + project
- PDF includes: summary totals, category breakdown, list of all transactions, attached document images
- Headers with business profile info

---

## 5. Priority Order

| # | Feature | Effort | Impact | Sprint |
|---|---------|--------|--------|--------|
| 1 | Multi-Currency + Conversion | Medium | High | 1 |
| 2 | Income Type | Small | High | 1 |
| 3 | Full-Text Search | Small | High | 1 |
| 4 | Custom Categories | Medium | High | 2 |
| 5 | Projects | Medium | High | 2 |
| 6 | Custom Fields | Medium | Medium | 2 |
| 7 | Customizable LLM Prompts | Medium | Medium | 3 |
| 8 | Item Splitting | Small | Medium | 3 |
| 9 | Unsorted / Inbox | Small | Medium | 4 |
| 10 | Bulk Operations | Medium | Medium | 4 |
| 11 | Better Dashboard | Small | High | 4 |
| 12 | CSV Import | Medium | Medium | 5 |
| 13 | Data Backup & Restore | Medium | Medium | 5 |
| 14 | Invoice Generator | Large | Medium | 6 |
| 15 | Business Profile | Small | Medium | 6 |
| 16 | Tax-Ready Reports | Medium | Medium | 6 |

---

## 6. File & Folder Map

New files/folders to add (follows Billy's existing feature-first structure):

```
lib/
├── features/
│   ├── import/                          # NEW — Sprint 5
│   │   ├── screens/
│   │   │   └── csv_import_screen.dart
│   │   ├── widgets/
│   │   │   └── column_mapper.dart
│   │   └── services/
│   │       └── csv_import_service.dart
│   ├── invoices/                        # UPDATED — Sprint 6
│   │   ├── screens/
│   │   │   ├── invoice_list_screen.dart
│   │   │   └── invoice_create_screen.dart
│   │   ├── models/
│   │   │   └── invoice_model.dart
│   │   └── services/
│   │       ├── invoice_ocr_pipeline.dart (existing)
│   │       └── invoice_pdf_service.dart
│   ├── documents/
│   │   └── screens/
│   │       └── unsorted_screen.dart     # NEW — Sprint 4
│   └── settings/
│       └── screens/
│           ├── categories_screen.dart   # NEW — Sprint 2
│           ├── fields_screen.dart       # NEW — Sprint 2
│           ├── projects_screen.dart     # NEW — Sprint 2
│           ├── currencies_screen.dart   # NEW — Sprint 1
│           ├── llm_settings_screen.dart # NEW — Sprint 3
│           └── backup_screen.dart       # NEW — Sprint 5
├── providers/
│   ├── categories_provider.dart         # NEW — Sprint 2
│   ├── fields_provider.dart             # NEW — Sprint 2
│   ├── projects_provider.dart           # NEW — Sprint 2
│   └── currency_provider.dart           # NEW — Sprint 1
├── services/
│   ├── currency_service.dart            # NEW — Sprint 1
│   └── backup_service.dart              # NEW — Sprint 5
│
supabase/
├── migrations/
│   ├── YYYYMMDD_multi_currency.sql      # Sprint 1
│   ├── YYYYMMDD_income_type.sql         # Sprint 1
│   ├── YYYYMMDD_fulltext_search.sql     # Sprint 1
│   ├── YYYYMMDD_user_categories.sql     # Sprint 2
│   ├── YYYYMMDD_custom_fields.sql       # Sprint 2
│   ├── YYYYMMDD_projects.sql            # Sprint 2
│   ├── YYYYMMDD_llm_prompts.sql         # Sprint 3
│   ├── YYYYMMDD_unsorted_inbox.sql      # Sprint 4
│   ├── YYYYMMDD_generated_invoices.sql  # Sprint 6
│   └── YYYYMMDD_business_profile.sql    # Sprint 6
└── functions/
    └── process-invoice/
        └── index.ts                     # UPDATED — Sprints 1, 2, 3
```

---

## Summary

Billy already has strong features that TaxHacker lacks (social/friends, group expenses, lend/borrow, settlements, Apple/Google OAuth, PDF export). The main gaps are around **financial power-user features**: multi-currency, custom fields, projects, income tracking, and customizable AI behavior.

The implementation follows Billy's existing patterns:
- **Feature-first folders** under `lib/features/`
- **Riverpod providers** for state
- **Supabase migrations** for schema changes
- **Edge Functions** for AI processing
- **Simple user flows** — no unnecessary complexity

Each sprint is independent and shippable. Start with Sprint 1 for maximum impact with minimum effort.
