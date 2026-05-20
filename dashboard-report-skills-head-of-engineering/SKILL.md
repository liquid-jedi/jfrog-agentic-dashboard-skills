---
name: jfrog-head-of-engineering-report
description: >-
  Generate a branded Head of Engineering dashboard from a JFrog Platform instance.
  Use when the Head of Engineering asks for a security & delivery efficiency report,
  team health summary, or supply chain status update. Produces HTML and email summary.
  Covers Xray, Curation, Artifactory, Distribution, Evidence, and GitHub data,
  categorized by project and user group. Supports daily, weekly, monthly, and
  on-demand cadences with period-over-period comparison. Report requires human
  approval before publishing and maintains an audit log.
metadata:
  role: reporting
  author: TODO: your-name
  persona: Head of Engineering
  audience: engineering-leadership
  cadence: daily | weekly | monthly | on-demand
  outputs: html, email
  generated_date: 2026-05-19
---

# Head of Engineering — JFrog Dashboard Skill

## Persona

**Name:** Head of Engineering
**Audience:** Engineering leadership (managers + executives). Shared externally with the board.
**Cadence:** Daily / Weekly / Monthly / On-demand (with period-over-period comparison)
**Output formats:** Self-contained HTML dashboard, Email summary

## Key questions this report answers (per project and user group)

- Which teams and projects have the most open critical CVEs?
- Where is delivery risk concentrated (by project and user group)?
- Are builds reproducible and traceable across all projects?
- Is dependency health improving over time (per project/team)?
- Are we blocking malicious packages effectively, and what slipped through?

## Decisions this report drives

- Development team efficiency optimization
- Security friction reduction and policy calibration
- Release go/no-go per project/team
- Team load balancing
- Policy enforcement escalation

## Data sources

- **JFrog Xray** — vulnerability scanning, CVE details, severity breakdowns by project
- **JFrog Curation** — blocked/allowed package decisions, policy hits
- **JFrog Artifactory** — artifact inventory, build records, download stats, user groups
- **JFrog Distribution** — release bundle health, distribution status
- **JFrog Evidence** — attestations, provenance, compliance records
- **GitHub** — PR/commit activity, developer throughput, repo health by team

## Trust & governance

- Source attribution required per metric (every KPI card must cite its source)
- Human approval required before publishing each report
- Audit log of who generated each report (stored in `meta.generated_by` and `meta.approved_by`)
- Retention policy applies (TODO: define retention period in days)
- No redaction or masking required

## JSON-first execution contract

**CRITICAL — every run of this skill MUST follow this contract in order:**

1. **Collect** — query each data source per `references/report-data-collection.md`.
2. **Assemble** — produce a single JSON object conforming to `references/report-schema.md`.
3. **Validate** — check all required fields are present; abort with a clear error if not.
4. **Render** — inject the JSON into `references/dashboard.html` at the `__DATA__` placeholder.
5. **Deliver** — write the HTML file; generate the email summary from the same JSON.
6. **Audit** — log generation event; set `meta.approval_status = "pending"` until approved.

The agent MUST produce valid JSON (step 2) before any HTML is written (step 4).
Do NOT hardcode data into the HTML template. All data flows through JSON.

## Workflow

```
1. Determine cadence and period (daily/weekly/monthly/on-demand)
2. Collect data from all in-scope sources (see report-data-collection.md)
3. Assemble JSON payload (see report-schema.md)
4. Validate JSON against schema
5. Render HTML from dashboard.html template by replacing __DATA__
6. Generate email summary from the same JSON payload
7. Log generation event (audit trail), set approval_status = "pending"
8. Notify approver; await approval before distributing
```

## File map

| File | Purpose |
|------|---------|
| `references/report-schema.md` | JSON schema definition for the report payload |
| `references/report-data-collection.md` | API queries and data collection logic per source |
| `references/dashboard.html` | Self-rendering HTML template (consumes `__DATA__`) |
| `references/sample-data.json` | Golden fixture for local development and testing |
