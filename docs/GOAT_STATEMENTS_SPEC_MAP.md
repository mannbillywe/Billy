# GOAT statement ingestion — spec ↔ Billy schema map

This project implements the three-layer ingestion model using **existing table names** from `20260415120000_goat_statements.sql` plus additive columns and companion tables from `20260416120000_goat_statement_ingestion_layers.sql`.

| Spec name | Billy implementation |
|-----------|----------------------|
| `uploaded_documents` | `statement_imports` (file metadata, status pipeline, `mime_type`, `source_hint`, `document_family`, balances, `extractor_version`, `ai_model_last`) |
| `document_ingestion_jobs` | Merged into `statement_imports` (`import_status`, `parser_version`, `parse_confidence`, `error_message`, `metadata`) |
| `document_raw_extractions` | `statement_raw_extractions` (per-import `raw_text`, optional `raw_tables` / `ocr_json`, `extraction_meta`) |
| `parsed_statement_headers` | Header-level fields on `statement_imports` + `statement_transactions_raw.raw_payload` row zero / metadata as needed |
| `parsed_statement_rows` | `statement_transactions_raw` |
| `normalized_transactions` | `statement_transactions` |
| `ingestion_review_queue` | `statement_import_reviews` (import-level) + `statement_row_reviews` (row/field-level) |
| `statement_document_links` | `statement_document_links` |
| `canonical_financial_events` | `canonical_financial_events` |
| `statement_accounts` | `statement_accounts` (`include_in_forecast` for forecast filtering) |

**Storage:** private bucket `statement-files`, path shape `{uid}/statements/{yyyy}/{mm}/{import_id}/{file}`.

**Analysis lens:** `profiles.goat_analysis_lens` (`smart`, `statements_only`, `ocr_only`, `combined_raw`). Dataset composition for home spend and related widgets is centralized in `lib/features/goat/statements/goat_lens_datasets.dart`.

**Optional AI (assistive):** Edge Function `statement-classify` — pass-1 classification from a **text excerpt only**; updates `document_family` and `metadata.ai_classification`. Client: `StatementClassificationService`.
