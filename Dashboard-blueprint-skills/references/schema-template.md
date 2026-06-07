# {{PERSONA_NAME}} Report — JSON Schema

This is the contract between the data-collection agent and the
`dashboard.html` renderer. Every field listed under "Required" MUST be
present before injection. Optional fields may be omitted; the renderer
will fall back to defaults.

## Top-level shape

```json
{
  "meta": { ... },
  "platform": { ... },
  "methodology": { ... },
  "kpis": [ ... ],
  "sections": [ ... ],
  "recommendations": [ ... ],
  "comparison": { "available": false }
}
```

## meta (required)

| Field | Type | Notes |
|-------|------|-------|
| `schema_version` | string | e.g. `1.0-{{PERSONA_SLUG}}` |
| `persona` | string | `{{PERSONA_NAME}}` |
| `report_type` | string | `weekly` \| `monthly` \| `custom` |
| `period_start` | ISO date | |
| `period_end` | ISO date | |
| `generated_at` | ISO datetime | |
| `server_id` | string | JFrog CLI server id used |

## platform (required)

| Field | Type | Notes |
|-------|------|-------|
| `url` | string | JFrog Platform URL |
| `products_in_scope` | string[] | e.g. `["xray","curation"]` |

## methodology (optional, recommended)

Used by the renderer to drive on-screen explanations. Persona-specific.
At minimum, define:

```json
{
  "scoring": { "weights": {}, "bands": [] },
  "definitions": { "<term>": "<plain-language meaning>" }
}
```

## kpis (required, 4-8 entries)

Each KPI:

| Field | Type | Notes |
|-------|------|-------|
| `id` | string | stable id, used by renderer |
| `label` | string | display label |
| `value` | number \| string | current value |
| `delta` | number \| null | period-over-period delta if comparison available |
| `direction` | `"up_is_good"` \| `"down_is_good"` \| `"neutral"` | |
| `source` | string (optional) | API or system source |

## sections (required)

Open-ended array of named sections. Each section:

```json
{
  "id": "<section-id>",
  "title": "<display title>",
  "kind": "<table|chart|list|callout>",
  "data": { ... }
}
```

The persona pack defines which section ids the renderer expects. Keep
section ids stable across runs so comparisons work.

### Suggested section ids (fill in based on KEY_QUESTIONS)

{{KEY_QUESTIONS}}

## recommendations (required)

Each recommendation:

| Field | Type | Required | Notes |
|-------|------|----------|-------|
| `id` | string | yes | stable id |
| `title` | string | yes | short headline |
| `detail` | string | yes | 1-3 sentences of context |
| `priority` | `"P1"` \| `"P2"` \| `"P3"` | yes | |
| `score` | number | yes | 0-100, higher = more urgent |
| `effort` | `"S"` \| `"M"` \| `"L"` | no | |
| `owner` | string | no | team or role |
| `due_date` | ISO date | no | |
| `dependencies` | string[] | no | |

**Hard rule:** if any recommendation is missing `priority` or `score`,
fail generation before template injection.

## comparison (optional)

```json
{
  "available": true,
  "previous_period": { "start": "...", "end": "..." },
  "kpi_deltas": { "<kpi.id>": { "value": 12, "direction": "up_is_good" } }
}
```

If `available=false`, the renderer hides the comparison section.

## Trust attribution (optional)

Any metric or recommendation may include a `trust` block:

```json
{
  "trust": {
    "source": "xray-violations-api",
    "endpoint": "/api/v1/violations",
    "timestamp": "2026-05-19T10:00:00Z",
    "confidence": "high"
  }
}
```
