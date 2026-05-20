# CISO Skill Changelog

## 2026-05-19 (Beta implementation pass)

Implemented the first end-to-end beta pass for decision-centric CISO output.

### Schema updates

- Expanded `report-schema.md` with beta fields and breaking changes:
  - `meta.schema_version`
  - curation split: `approved` and `passed`
  - violations risk model: `risk_score`, `risk_score_previous`
  - critical issue enrichment: `first_seen`, `days_open`, `exploit_status`,
    `affected_environments`, `playbook_link`
  - benefit ROI: `roi_estimate`
  - new sections: `governance`, `threat_velocity`
  - recommendations metadata: `priority`, `effort`, `owner`, `due_date`,
    `dependencies`, `score`

### Dashboard rendering updates

- Updated KPI strip to include policy-passed volume and risk score.
- Updated curation summary to display blocked, approved, and passed separately.
- Enriched critical issues table with exploitability and age context.
- Added governance section:
  - policy effectiveness table
  - repository watch coverage table
- Added threat velocity section with rolling-period trend table.
- Updated recommendations rendering to prefer structured `priority` and show
  metadata (`effort`, `owner`, `due_date`, `dependencies`) when present.

### Collection and workflow guidance

- Updated `report-data-collection.md` to align with split curation semantics
  and risk score computation guidance.
- Added governance/threat-velocity mapping guidance and optional enrichment
  fallback behavior.
- Updated `SKILL.md` Step 6 JSON skeleton and required beta fields.

### Next wave (beta)

- Regenerated `samples/ciso-report-2026-04-26.html` using the latest
  dashboard template and upgraded beta JSON payload.
- Added explicit data-driven recommendation scoring model to:
  - `report-schema.md`
  - `report-data-collection.md`
- Added a producer-focused migration section to `README.md` that lists
  required beta schema changes and fallback behavior.

### Wave 3 (beta)

- Implemented deterministic recommendation ordering in renderer and sample:
  - sort by `score` descending
  - tie-break by `priority` (P1 > P2 > P3)
  - final tie-break by title
- Added optional score display in recommendation metadata line.
- Documented ordering behavior in `README.md`.

### Wave 3.1 (beta)

- Disabled title-based priority inference in recommendation rendering.
- Recommendation badges now rely only on structured `priority` metadata.
- Kept deterministic ordering by `score`, `priority`, then title.

### Wave 3.2 (beta)

- Enforced beta producer rule: every recommendation must include both
  `priority` and `score`.
- Added hard-fail validation guidance in `SKILL.md` and
  `report-data-collection.md` to block generation when these fields are
  missing.
- Updated `README.md` migration guidance to mark `priority` and `score`
  as required recommendation metadata.

### Wave 3.3 (beta)

- Added renderer-level defensive validation banner in Recommendations:
  if recommendation `priority` or `score` is missing, the report shows a
  warning callout while still rendering.
- Mirrored the same behavior in the sample HTML.

## 2026-05-19

Updated `dashboard-report-skills` to reduce agent ambiguity, improve data
accuracy, and document runtime behavior more explicitly.

### Skill workflow

- Reworked execution rules into a pre-data-collection checklist.
- Added decision tables for server selection and report storage.
- Clarified default behavior: weekly, last 7 days, all repositories.
- Added unsupported report type handling for anything outside `weekly`,
  `monthly`, or `custom`.
- Added missing prerequisite handling for absent or misconfigured `jf`, `jq`,
  and `python3`.
- Clarified that the agent does not author HTML; it only produces JSON and
  injects that JSON into the existing dashboard template.
- Added a fallback template path for repo-local testing when the installed
  skill cannot be found under `~/.agents/skills`.

### Storage and snapshots

- Added the exact command for creating `ciso-reports-local` as a generic
  local repository when the user approves storage creation.
- Standardized storage examples on `REPORT_REPO` so named report repositories
  do not fall back to hardcoded `ciso-reports-local` paths.
- Corrected previous snapshot download paths to avoid duplicating the server
  ID when reading from the manifest.
- Added mandatory `/tmp/ciso-snapshot.json` creation so upload and future
  period-over-period comparison have a defined source file.
- Clarified that runtime JSON files belong in `/tmp`, not the project folder.

### Data collection

- Added a table of contents to `report-data-collection.md`.
- Clarified curation detection: use the audit API response, not entitlement
  metadata.
- Added Linux date command examples alongside macOS date commands.
- Added pagination loops for curation audit events and Xray violations.
- Fixed monthly curation guidance to sum chunk totals rather than using the
  first chunk total.
- Updated curation `approved` semantics to mean all non-blocked outcomes,
  including `approved` and `passed`.
- Made malicious package detection check category, condition name, and policy
  name.
- Added `sort_by(...)` before jq `group_by(...)` calls to avoid unstable or
  incorrect grouping.
- Added zero-division handling for comparison deltas and a `flat` direction.

### Recommendations and observations

- Replaced vague "AI-generated insights" wording with a concrete expected
  format: one or two concise, data-driven sentences containing a metric,
  package, policy, repository, or XRAY/CVE ID when available.
- Kept recommendation requirements specific: priority labels, critical Xray
  IDs, package/version details, curation gaps, inactive watches or policies,
  and license actions.

### Cleanup

- Identified project-local `.DS_Store` files as temporary cleanup candidates.
