# Report Schema — Head of Engineering

Schema version: `1.0-head-of-engineering`
Generated: 2026-05-19

## Root object

| Field | Type | Required | Description |
|-------|------|----------|-------------|
| `meta` | object | yes | Report metadata and audit fields |
| `platform` | object | yes | JFrog platform context |
| `methodology` | object | yes | Scoring rules and band definitions |
| `kpis` | array | yes | Top-level KPI summary cards |
| `sections` | array | yes | Content sections (tables, charts, breakdowns) |
| `recommendations` | array | yes | Ranked action items for the engineering head |
| `comparison` | object | yes | Period-over-period delta data |

---

## `meta`

| Field | Type | Description |
|-------|------|-------------|
| `schema_version` | string | `"1.0-head-of-engineering"` |
| `persona` | string | `"Head of Engineering"` |
| `report_type` | string | `"daily"` \| `"weekly"` \| `"monthly"` \| `"on-demand"` |
| `period_start` | string | ISO date — start of reporting period |
| `period_end` | string | ISO date — end of reporting period |
| `generated_at` | string | ISO datetime of generation |
| `generated_by` | string | User ID or token identity (required for audit log) |
| `server_id` | string | JFrog platform server identifier |
| `approval_status` | string | `"pending"` \| `"approved"` \| `"rejected"` |
| `approved_by` | string \| null | Approver identity; null until approved |
| `approved_at` | string \| null | ISO datetime of approval; null until approved |
| `warnings` | array | Non-fatal data-collection warnings; strings |

---

## `platform`

| Field | Type | Description |
|-------|------|-------------|
| `url` | string | JFrog platform base URL |
| `products_in_scope` | array | `["xray","curation","artifactory","distribution","evidence"]` |
| `github_orgs` | array | GitHub org names in scope |

---

## `methodology`

Scoring is normalized 0–100. **Lower is better.** Rising trend is bad.

### Score bands

| Band | Score range | Meaning |
|------|-------------|---------|
| `healthy` | 0–20 | On track, no immediate action |
| `watch` | 21–50 | Monitor closely |
| `risk` | 51–80 | Intervention required |
| `alert` | 81–100 | Escalate immediately |

### CVE severity weights

| Severity | Points |
|----------|--------|
| Critical | 100 |
| High | 20 |
| Medium | 5 |
| Low | 1 |

---

## `kpis[]`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique KPI identifier |
| `label` | string | Display label |
| `value` | string \| number | Current period value |
| `delta` | number | Change vs prior period (positive = worse for `down_is_good`) |
| `direction` | string | `"up_is_good"` \| `"down_is_good"` |
| `source` | string | Data source attribution (e.g. `"xray"`) |
| `unit` | string | Display unit (e.g. `"%"`, `"count"`, `"score"`) |

### Required KPIs for Head of Engineering

| ID | Label | Source | Direction |
|----|-------|--------|-----------|
| `k-cve-critical` | Open Critical CVEs | xray | down_is_good |
| `k-curation-block-rate` | Curation Block Rate | curation | up_is_good |
| `k-build-reproducibility` | Build Reproducibility % | artifactory + evidence | up_is_good |
| `k-dep-health-score` | Dependency Health Score (0–100) | xray | down_is_good |
| `k-delivery-risk` | Delivery Risk Index (0–100) | xray + distribution | down_is_good |
| `k-gh-throughput` | PRs Merged (throughput) | github | up_is_good |

---

## `sections[]`

Each section must include `id`, `title`, `kind`, `source_attribution`, and `data`.

### Required sections

| ID | Title | Kind | Primary source |
|----|-------|------|---------------|
| `cve-by-team` | Critical CVEs by Team & Project | `table` | xray |
| `delivery-risk` | Delivery Risk by Project | `heatmap` | xray + distribution |
| `curation-summary` | Curation Decisions | `bar` | curation |
| `build-health` | Build Reproducibility & Evidence | `table` | artifactory + evidence |
| `dep-trend` | Dependency Health Trend | `trend` | xray |
| `gh-activity` | GitHub Team Activity | `table` | github |
| `user-group-breakdown` | Security Debt by User Group | `table` | xray + artifactory |

### Section object shape

```json
{
  "id": "cve-by-team",
  "title": "Critical CVEs by Team & Project",
  "kind": "table",
  "source_attribution": "JFrog Xray",
  "data": {
    "columns": ["project", "team", "critical", "high", "medium", "score", "trend"],
    "rows": [
      {
        "project": "my-project",
        "team": "platform-eng",
        "critical": 3,
        "high": 12,
        "medium": 45,
        "score": 72,
        "trend": "up"
      }
    ]
  }
}
```

### `heatmap` kind shape

```json
{
  "kind": "heatmap",
  "data": {
    "axes": { "x": "project", "y": "risk_band" },
    "cells": [
      { "project": "my-project", "risk_band": "alert", "score": 84, "label": "3 critical" }
    ]
  }
}
```

### `trend` kind shape

```json
{
  "kind": "trend",
  "data": {
    "x_label": "Period",
    "y_label": "Score",
    "series": [
      {
        "name": "Platform Eng",
        "points": [
          { "period": "2026-W18", "value": 65 },
          { "period": "2026-W19", "value": 58 }
        ]
      }
    ]
  }
}
```

---

## `recommendations[]`

| Field | Type | Description |
|-------|------|-------------|
| `id` | string | Unique recommendation ID (e.g. `"r1"`) |
| `title` | string | Short action title |
| `detail` | string | Full description with context |
| `priority` | string | `P1` \| `P2` \| `P3` |
| `score` | number | Urgency score 0–100 |
| `effort` | string | `S` (days) \| `M` (weeks) \| `L` (months) |
| `owner` | string | Suggested owner team or role |
| `source` | string | Data source attribution |
| `affected_projects` | array | Project names impacted |
| `affected_groups` | array | User group names impacted |

---

## `comparison`

| Field | Type | Description |
|-------|------|-------------|
| `available` | boolean | Whether prior-period data exists |
| `prior_period_start` | string | ISO date of prior period start |
| `prior_period_end` | string | ISO date of prior period end |
| `kpi_deltas` | object | Map of KPI ID → numeric delta vs prior period |

```json
{
  "available": true,
  "prior_period_start": "2026-05-05",
  "prior_period_end": "2026-05-11",
  "kpi_deltas": {
    "k-cve-critical": -2,
    "k-curation-block-rate": 3,
    "k-build-reproducibility": 1,
    "k-dep-health-score": -4,
    "k-delivery-risk": -5,
    "k-gh-throughput": 8
  }
}
```
