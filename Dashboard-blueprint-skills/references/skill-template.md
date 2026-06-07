---
name: jfrog-{{PERSONA_SLUG}}-report
description: >-
  Generate a branded {{PERSONA_NAME}} dashboard from a JFrog Platform
  instance. Use when the user asks for a {{PERSONA_NAME}} report,
  {{PERSONA_NAME}} dashboard, or {{CADENCE}} {{PERSONA_NAME}} summary.
metadata:
  role: workflow
  author: TODO
  generated: {{GENERATED_DATE}}
---

# JFrog {{PERSONA_NAME}} Report Generator

## CRITICAL — READ THIS FIRST

You are NOT authoring HTML. You are NOT writing CSS. You are NOT designing
the layout. Your only generated content is JSON. A pre-built HTML
dashboard already exists and renders the report from your JSON. Your job:

1. Collect data from JFrog APIs
2. Build a JSON object matching `references/report-schema.md`
3. Save the JSON to `/tmp/{{PERSONA_SLUG}}-data.json`
4. Inject JSON into `references/dashboard.html` by replacing `__DATA__`
5. (Optional) Upload to Artifactory if storage is enabled

If you generate HTML from scratch, the report will be broken. Do NOT
attempt it.

## Audience and intent

- Persona: {{PERSONA_NAME}}
- Audience: {{AUDIENCE}}
- Cadence: {{CADENCE}}
- Output formats: {{OUTPUT_FORMATS}}

## Key questions this report must answer

{{KEY_QUESTIONS}}

## Decisions this report supports

{{DECISIONS}}

## Data sources in scope

{{DATA_SOURCES}}

## Trust and governance requirements

{{TRUST_REQS}}

## Execution checklist

Before collecting data:

- Confirm tools: `jf`, `jq`, `python3` on PATH.
- Resolve period from the user prompt; default to {{CADENCE}}.
- Resolve server. Ask only when multiple JFrog CLI servers exist and the
  prompt did not name one.
- Resolve storage. Ask only when storage preference is absent.

After those checkpoints, execute without further questions. If an API
fails, set the JSON field to a safe default (`0`, `[]`, `false`, `null`,
`"N/A"`) and continue. Pass `--server-id "$SERVER_ID"` to every `jf`
command.

## Workflow

```
1. Determine report type and date range
2. Select server (MANDATORY if multiple)
3. Check/create storage repo (MANDATORY if first run, optional otherwise)
4. Download previous snapshot for comparison
5. Collect data from JFrog APIs (see references/report-data-collection.md)
6. Build JSON matching schema → save to /tmp/{{PERSONA_SLUG}}-data.json
7. Inject JSON into dashboard.html (replace `__DATA__` placeholder)
8. (Optional) Upload snapshot + report to Artifactory
```

## Hard rules

- Produce JSON before any HTML injection.
- Validate required fields from `references/report-schema.md` before
  injection. Fail fast if missing.
- Every recommendation must include `priority` and `score`.
- Use the `methodology` block in DATA to drive on-screen explanations.
- Never write a raw secret value into the generated report.
- Never bypass the HTML template.

## References

- `references/report-schema.md` — JSON contract
- `references/report-data-collection.md` — API mapping per field
- `references/dashboard.html` — Self-rendering template
- `references/sample-data.json` — Golden fixture for smoke tests
