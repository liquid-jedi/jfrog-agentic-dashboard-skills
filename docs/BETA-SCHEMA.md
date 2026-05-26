# Beta Schema Migration

Use this guide when you produce JSON **outside** the skill and inject it manually, or when upgrading older custom payloads toward the current CISO schema. The renderer remains compatible with older `2.0-beta`-style payloads and newer producer shapes.

## Required and new fields

- Set `meta.schema_version` (recommended: `2.0-beta`)
- Split curation allow outcomes:
  - `curation.approved` — explicit overrides
  - `curation.passed` — policy-pass outcomes
- Risk fields:
  - `violations.risk_score`
  - `violations.risk_score_previous`
- Enrich critical issues when available:
  - `first_seen`, `days_open`, `exploit_status`, `affected_environments`, `playbook_link`
- Governance:
  - `governance.policy_effectiveness[]`
  - `governance.repo_watch_coverage[]`
- Trends:
  - `threat_velocity.available`, `periods[]`, `trend_summary`
- Recommendation metadata:
  - **Required:** `priority`, `score`
  - **Optional:** `effort`, `owner`, `due_date`, `dependencies`

## Recommendation behavior

- Renderer uses structured `recommendations[].priority` (title inference disabled)
- Sort: `score` desc → `priority` (P1 > P2 > P3) → title
- **Producer:** fail generation if any recommendation lacks `priority` or `score`
- **Renderer safety:** malformed metadata shows a warning banner and continues

## Configurable methodology

Optional top-level `methodology` in DATA customizes on-screen explanations without template edits:

- Severity definitions and good/bad signals
- Risk score weights and health bands
- Curation action semantics (`blocked` / `approved` / `passed`)
- Repository watch risk-level rules

Omit `methodology` to use built-in defaults.

### Risk score normalization (recommended)

```text
raw = (Critical×100) + (High×20) + (Medium×5) + (Low×1)
risk_score = (raw / (total_violations×100)) × 100
```

- Lower score is better
- Rising trend is bad
- Flat at low range is healthy

If enrichment is unavailable, keep generating — the renderer degrades gracefully.

---

## Related docs

- [Architecture](ARCHITECTURE.md)
- `Dashboard-ciso-report-skills/references/report-schema.md`
