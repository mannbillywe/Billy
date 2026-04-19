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

Implemented in backend (`goat/summary_charts.py`, merged in `runner._snapshot_row` via `merge_summary_charts`). Example shape:

```json
{
  "layer_errors": {},
  "charts": {
    "version": 1,
    "timeseries": [
      {
        "id": "spend_90d",
        "title": "…",
        "unit": "INR",
        "points": [{ "d": "2026-01-15", "v": 12000.5 }]
      },
      {
        "id": "metric:emergency_fund_runway_months",
        "title": "…",
        "unit": null,
        "points": [{ "d": "…", "v": 4.2 }]
      }
    ],
    "bars": [
      {
        "id": "category_spend_mtd",
        "title": "…",
        "unit": "INR",
        "items": [{ "label": "Food", "value": 4200 }]
      },
      {
        "id": "metric:expense_total",
        "title": "…",
        "unit": "INR",
        "items": [{ "label": "…", "value": 1 }]
      }
    ]
  }
}
```

Rules:

- `version` is an int; clients ignore unknown versions but still try to read known keys.
- `points[].d` is ISO date; `points[].v` is a number.
- `items[].label` short string; `items[].value` number.
- Keep arrays **bounded** (e.g. ≤ 120 points per series; bars capped per backend policy).

The Flutter app parses this into `GoatSnapshot.charts` when present. **Metric drill-down charts** use ids `metric:<metric_key>` (e.g. `metric:expense_total`, `metric:emergency_fund_runway_months`). **Overview** lists each `timeseries` entry as a tappable row that opens a full chart sheet.

## 3. Optional per-metric narrative for reports

Backend (`goat/contracts.py` + `goat/deterministic.py` overview) may set on each `metrics_json.metrics[]` object:

- `report_title` — headline for the metric drill-down.
- `report_summary` — 1–3 sentences plain language.

Covered keys in backend include: `net_worth`, `income_total`, `expense_total`, `savings_rate`, `spend_trend_delta`, `emergency_fund_runway_months`.

## 4. What the app does today without backend changes

- **Coverage pillar bar chart** from existing `coverage_json.breakdown` (0–1 weights).
- **Forecast detail sheet** with percentile range + **line chart** when `series.points` exists; otherwise the existing range bar only.

No migration required for §2–3: only JSON content changes.
