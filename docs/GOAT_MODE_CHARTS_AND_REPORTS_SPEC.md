# GOAT Mode — charts & drill-down reports (backend ↔ frontend contract)

The Flutter client already renders **coverage** and **forecast percentiles** from existing JSON. This document describes **optional extensions** so the backend agent can add richer series and pre-built chart payloads without breaking older clients (everything is optional / best-effort).

## 1. Forecast time series (preferred: use existing `series` on each target)

The Python contract already includes `ForecastTargetOut.series` with `ForecastPoint` rows (`step`, `date`, `p10`, `p50`, `p90`). **Persist it inside `forecast_json.targets[].series`** for each target when available.

Minimal shape per target:

```json
{
  "target": "end_of_month_liquidity",
  "status": "ok",
  "model_used": "rolling_median",
  "horizon_days": 30,
  "value": { "p10": 1000, "p50": 4500, "p90": 8200 },
  "series": {
    "horizon_days": 30,
    "unit": "INR",
    "points": [
      { "step": 0, "date": "2026-04-19", "p10": 1200, "p50": 4000, "p90": 7800 },
      { "step": 1, "date": "2026-04-26", "p10": 1100, "p50": 3900, "p90": 7600 }
    ]
  }
}
```

Frontend uses `points[].p50` (and optional `p10`/`p90`) for a **line + band** chart when `points.length >= 2`. Typos like `p11` are ignored; missing numbers are skipped.

## 2. Optional `charts` block inside `summary_json` (no DB migration)

Add a top-level key on the existing `summary_json` column:

```json
{
  "layer_errors": {},
  "charts": {
    "version": 1,
    "timeseries": [
      {
        "id": "spend_90d",
        "title": "Outflows (90d)",
        "unit": "INR",
        "points": [{ "d": "2026-01-15", "v": 12000.5 }, { "d": "2026-02-01", "v": 11800 }]
      }
    ],
    "bars": [
      {
        "id": "category_spend_mtd",
        "title": "Spend by category (MTD)",
        "unit": "INR",
        "items": [
          { "label": "Food", "value": 4200 },
          { "label": "Transit", "value": 900 }
        ]
      }
    ]
  }
}
```

Rules:

- `version` is an int; clients ignore unknown versions but still try to read known keys.
- `points[].d` is ISO date; `points[].v` is a number.
- `items[].label` short string; `items[].value` number.
- Keep arrays **bounded** (e.g. ≤ 120 points per series, ≤ 24 bars) for mobile performance.

The Flutter app parses this into `GoatSnapshot.charts` when present and can attach charts to metric drill-downs by matching `id` (convention: `metric:<metric_key>` if tied to a deterministic metric).

## 3. Optional per-metric narrative for reports

Inside each `metrics_json.metrics[]` object, optional string fields (ignored if absent):

- `report_title` — headline for the metric drill-down.
- `report_summary` — 1–3 sentences plain language.

## 4. What the app does today without backend changes

- **Coverage pillar bar chart** from existing `coverage_json.breakdown` (0–1 weights).
- **Forecast detail sheet** with percentile range + **line chart** when `series.points` exists; otherwise the existing range bar only.

No migration required for §2–3: only JSON content changes.
