# {{PERSONA_NAME}} Report — Data Collection Mapping

This file maps each schema field to a JFrog API call (and any external
source). Fill in the TODOs for your persona. For authoritative API paths,
read `../../jfrog/SKILL.md` and `../../jfrog/references/`. Do NOT hardcode
API paths from memory.

## Conventions

- All `jf` commands pass `--server-id "$SERVER_ID"` explicitly.
- All Xray queries include a `created_from` (or equivalent) to avoid
  large-instance timeouts.
- For Curation, the maximum audit window per request is 168 hours.
  Chunk longer periods and merge.
- For each field, document: source, command, parsing (jq), fallback.

## Field-by-field mapping

### meta.period_start / meta.period_end

- Source: user prompt
- Default: last {{CADENCE}} window
- Fallback: today minus 7 days

### platform.url

- Source: `jf c show "$SERVER_ID"` (parse `Url`)
- Fallback: TODO

### platform.products_in_scope

- Source: TODO (entitlements API or static config)
- Fallback: derive from successful API responses

### kpis[]

For each KPI defined for `{{PERSONA_NAME}}`:

| KPI id | Source | Command | jq path | Notes |
|--------|--------|---------|---------|-------|
| TODO   | TODO   | TODO    | TODO    | TODO  |

### sections[]

For each schema section the renderer expects:

| Section id | Source | Command | jq path | Notes |
|------------|--------|---------|---------|-------|
| TODO       | TODO   | TODO    | TODO    | TODO  |

### recommendations[]

Recommendations are typically derived, not fetched. Build them from
collected data using rules such as:

- If `<kpi>` exceeds `<threshold>`, raise a `P1` recommendation with
  `score = clamp(0..100, weighted formula)`.
- Use the `methodology.scoring` block in DATA as the source of truth so
  customers can tune without code changes.

Each recommendation MUST include `priority` and `score`. Optional
metadata (`effort`, `owner`, `due_date`, `dependencies`) is encouraged.

### comparison

- Source: previous snapshot stored in Artifactory (or local).
- If no previous snapshot exists, set `comparison.available = false`.

## Data quality and trust

- Add a `trust` block to any metric or recommendation when source
  attribution is required.
- If an API fails, set the field to a safe default and add a note in
  `meta.warnings[]` so the renderer can surface it.

## Performance tips

- Batch `jf` commands into single bash blocks where possible.
- Cache previous snapshots to avoid re-querying historical data.
- For monthly reports, chunk Curation audit calls by 168h windows.
