# CISO Dashboard User Manual

This manual is the operator document for installing, running, extending,
and interpreting the CISO dashboard skill.

## Document Scope

| Document | Focus |
|----------|--------|
| [README](../README.md) | Project overview, quick start, documentation index |
| [INSTALL.md](INSTALL.md) | Prerequisites, install, verify, update, prechecks, first run |
| [ARCHITECTURE.md](ARCHITECTURE.md) | Data flow, execution contract, persona scaffolding |
| [BETA-SCHEMA.md](BETA-SCHEMA.md) | Schema 2.0-beta for custom JSON producers |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common issues |
| **This manual** | Permissions, supported agents, interpretation, tuning |

For installation steps, start with [INSTALL.md](INSTALL.md) rather than duplicating commands here.

## Audience

This document is written for:

- Platform engineers operating the skill locally or in CI.
- Security engineers tuning formulas, thresholds, or recommendation logic.
- Solution engineers adapting the project for new personas.

The current CISO dashboard is the first production example in a broader
dashboard blueprint pattern, so this manual focuses on operating the skill
as-is while keeping the extension path visible for future personas.

## Installation

See **[INSTALL.md](INSTALL.md)** for prerequisites, APM install, generic Skills install, prechecks, and verification.

Quick reference — APM install:

```bash
apm install liquid-jedi/jfrog-agentic-dashboard-skills/packages/apm/jfrog-ciso-report#v2.5.0
```

Quick reference — local development install:

```bash
REPO_ROOT="$(pwd)"
npx skills add "$REPO_ROOT" -g --skill jfrog-ciso-report
```

## Required Permissions

For a user to run the report, the minimum practical access is read-only platform access for the data the skill collects:

- Repository read/list access for platform metadata and Xray-indexed repository checks.
- Xray read access for watches, policies, and violations.
- Curation visibility for the curation audit API. If the token lacks `VIEW_POLICIES`, the report can still run, but curation will be marked unavailable.

If the run should upload `report.html` and `snapshot.json` to Artifactory, the user also needs write/deploy permission on the report storage repository, such as `ciso-reports-local`.

No admin permission is required for a standard local report run.

## JFrog Platform Skills Dependency

The CISO skill depends on the base `jfrog` skill ([jfrog-skills](https://github.com/jfrog/jfrog-skills)). Install and verify steps are in [INSTALL.md](INSTALL.md).

## Supported Agents

The skill is framework-driven and works with agents that support skill-based workflows and local file/tool execution. Commonly supported environments include:

- Claude Code
- Cursor
- Codex
- Gemini-cli 
- Cline (Test Pending)
- Windsurf (Test Pending)
- VS Code skill-enabled chat flows
- Similar agent environments that can read files and execute shell commands

Core runtime dependencies are the same across agents:

- Data collection: `jf rt curl`, `jf xr curl`
- Parsing and shaping: `jq`, `python3`
- Rendering: `Dashboard-ciso-report-skills/references/dashboard.html`

## Runtime Readiness Gate

Use the runtime checker before report generation, regardless of where the user runs commands from:

```bash
REPO_ROOT="/path/to/your/jfrog-ciso-dashboard-clone"
bash "$REPO_ROOT/scripts/agentic-dashboard-prechecks.sh"
```

Optional guided auto-fix (installs missing skills only when requested):

```bash
bash "$REPO_ROOT/scripts/agentic-dashboard-prechecks.sh" --fix
```

Non-interactive auto-fix for scripted onboarding:

```bash
bash "$REPO_ROOT/scripts/agentic-dashboard-prechecks.sh" --fix --yes
```

This is the source-of-truth readiness gate for customer environments. It validates:

- required tools on PATH (`jf`, `jq`, `python3`, `npx`)
- global skill installation (`jfrog`, `jfrog-ciso-report`)
- JFrog CLI server configuration presence
- multi-server warning conditions where runtime must ask for server choice
- valid local source path for the CISO skill

Treat checker failures as blockers before running report generation.

Precheck OS support:

- macOS: supported
- Linux: supported
- Windows: supported through WSL
- Native PowerShell/CMD: not the primary supported execution path for this script

Cursor sandbox/network note:

- In Cursor Auto-Run sandbox mode, outbound network can be restricted by default.
- Allow network egress to your JFrog endpoints in Cursor sandbox settings for live API collection.
- If network is blocked, the run should fail fast and must not reuse stale prior payloads.

Runtime cleanup model:

- Cleanup is handled by agent logic in the skill workflow, not by an external script.
- At run end, the agent should remove transient runtime payloads from `/tmp`.
- If a run is interrupted, the next run must overwrite runtime payloads and must not reuse stale data.

## Runtime Integrity Contract

Every compliant run must satisfy all of the following:

- Live collection only: report payload data must come from API responses gathered in the current run window.
- No implicit fallback: agents must not reuse prior local payloads, cached payloads, prior snapshots, or "last successful run" data unless the user explicitly requested fallback mode.
- Fail-fast on transport blocks: sandbox/network denial, DNS failures, TLS/connectivity errors, or equivalent transport issues must terminate the run.
- Provenance in metadata: `run-meta.json` should record data source intent (`live` or `fallback`). If fallback is used, it must record that the user explicitly requested it.
- Finalization cleanup: transient runtime payloads in `/tmp` should be removed at run end, and also removed before exit on failure paths when temp payloads were written.

## Agent Compliance Checklist

Use this checklist before approving a new agent/runtime combination for
team use.

The agent should pass all items below during a simple weekly-report test.

### Required behavior

- If multiple JFrog CLI servers are configured and the prompt does not name one, the agent must ask the user which server to use.
- The agent must not silently use the JFrog CLI default server when multiple servers exist.
- If the prompt omits a local output path, the agent may default to `$PWD`, but it must explicitly show the resolved local output root before collection begins.
- Before collecting data, the agent should surface a short execution summary containing:
  - resolved server
  - resolved local output root
  - resolved storage mode
- The agent must generate JSON first and inject it into the existing template.
- The agent must not generate HTML from scratch.
- The agent must preserve the local artifact structure:
  - `<LOCAL_ROOT>/<instance>/<report-type>/<date>/...`
- On duplicate same-day runs, the agent must create a `rerun-HHMMSS` folder rather than overwrite prior artifacts.
- If storage mode is not specified in the prompt, the agent must default to local-only silently without asking.
- If runtime reports blocked network/sandbox transport errors, the agent must fail fast and stop report generation.
- The agent must not enter fallback mode unless the user explicitly asks for fallback mode.

### Quick validation prompt

Use a prompt like this when testing:

```text
Generate a weekly CISO report. If multiple servers exist, ask me which one to use. Before collection, show me the resolved local output root and storage mode.
```

### Pre-Run Verification

An agent/runtime is considered compliant for this skill only if:

- it does not hide server selection when multiple choices exist
- it does not hide the resolved local output root
- it follows the JSON-first template injection flow
- it preserves the required local artifact layout
- it enforces fail-fast behavior for network/sandbox transport failures
- it does not silently reuse stale payloads from previous runs

## Operating System Guidance

### macOS

Works as-is with the documented flow.

Notes:

- `date -v` examples in some references are macOS-native.
- `sed -i.bak` usage in the skill is compatible with macOS.

### Linux

Supported with minor shell-awareness.

Notes:

- Use GNU `date` syntax where the references provide Linux alternatives.
- `sed -i.bak` also works on most common Linux distributions.

### Windows

Supported best through a POSIX-compatible shell environment.

Recommended options:

- WSL2
- Git Bash

Why:

- The skill workflow assumes `bash`/POSIX shell semantics.
- The instructions rely on commands such as `grep`, `find`, `sed`, and standard shell variable expansion.

Native PowerShell or CMD execution is not the primary documented path. If Windows is required, use WSL2 for the most consistent behavior.

## Runtime Flow

The CISO skill follows a fixed execution contract:

1. Resolve report period.
2. Resolve server.
3. Resolve local output root and storage mode.
4. Download prior snapshot when available.
5. Collect data from JFrog APIs.
6. Build a full JSON payload.
7. Inject JSON into the HTML template.
8. Save local artifacts.
9. Upload to Artifactory when enabled.
10. Finalize run by cleaning transient runtime payloads from `/tmp`.

The skill must always generate JSON first. It must not generate HTML from scratch.

## Default Runtime Behavior

If the prompt does not specify server, local path, or storage mode:

- Server: if one CLI server exists, it is used automatically; if multiple exist, the skill must ask the user to choose and must not use the CLI default server.
- Local output root: if a path is provided in the prompt, use it. Otherwise use `CISO_LOCAL_ROOT` when set. If `CISO_LOCAL_ROOT` is missing, the first run should ask once for a stable local root, create it, and persist it for later runs.
- Artifactory storage: defaults to local-only unless the prompt says `save to Artifactory` or names a repo.

> **Trend analysis requires a stable `LOCAL_ROOT`.** The skill looks first in Artifactory (when enabled) and then scans the local folder tree under `LOCAL_ROOT` for prior snapshots. See **Recommended Environment Setup** below.

Date-window default for `monthly`:

- Plain `monthly` resolves to the **last full calendar month**.
- Example: if today is May 20, `monthly` resolves to April 1-30.
- To target the current month-to-date, specify explicit dates or ask for
  month-to-date directly.

Before collection begins, the skill should surface a short execution summary containing:

- resolved server
- resolved local output root
- resolved storage mode

## Recommended Environment Setup

For reliable trend analysis across runs, set a stable local root that persists across all terminals and IDE sessions. The runtime can bootstrap this on the first run, but setting it explicitly keeps behavior deterministic across terminals and CI. Add it to **both** shell profile files so it is sourced by login shells (new terminal windows, SSH) and interactive shells (integrated terminals inside IDEs):

```bash
echo 'export CISO_LOCAL_ROOT=~/ciso-reports' >> ~/.zprofile
echo 'export CISO_LOCAL_ROOT=~/ciso-reports' >> ~/.zshrc
mkdir -p ~/ciso-reports
```

Restart your IDEs after running this. Every report run will then write to a consistent location:

```text
~/ciso-reports/<server-id>/<report-type>/<YYYY-MM-DD>/
```

For example:

```text
~/ciso-reports/<server-id>/weekly/2026-05-20/
~/ciso-reports/<another-server-id>/monthly/2026-05-01/
```

Without a stable `LOCAL_ROOT`, each run that defaults to `$PWD` lands in whatever directory the agent is launched from, and the local snapshot lookup for trend comparison will fail to find prior runs.

## Prompting Model

Server name is optional.

- `Generate a weekly CISO report.`
- `Generate a monthly CISO report. Local only.`
- `Generate a weekly CISO report for <server-id>. Save to Artifactory.`
- `Generate a weekly CISO report. Local only. Save local artifacts under /Users/me/security-reports.`
- `Generate a monthly CISO report for May 2026.`
- `Generate a CISO report for 2026-05-01 to 2026-05-20.`

If the prompt omits both server and local path, the operator should still expect the skill to show the resolved values before collection starts.

## Local Output Model

Each run writes a deterministic local artifact bundle:

```text
<LOCAL_ROOT>/
└── <instance-slug>/
    └── <report-type>/
        └── <YYYY-MM-DD>/
            ├── report.html
            ├── data.json (optional)
            ├── snapshot.json
            └── run-meta.json
```

Data persistence control:

- `SAVE_DATA_JSON` controls whether `data.json` is written.
- Resolution order: prompt intent -> `CISO_SAVE_DATA_JSON` env var -> default `true`.

Token usage metadata:

- `run-meta.json` includes `token_usage.total_tokens` when available.
- Capture sources:
  - `CISO_TOTAL_TOKENS` environment variable, or
  - `/tmp/ciso-token-usage.json` containing `total_tokens`.
- If no source is available, `token_usage.total_tokens` is `null` and status is `unavailable`.

If the same instance/report-type/date already exists, the skill writes the next run into:

```text
<LOCAL_ROOT>/<instance-slug>/<report-type>/<YYYY-MM-DD>/rerun-HHMMSS/
```

This prevents overwriting partial or previous same-day runs.

## Artifactory Output Model

When Artifactory storage is enabled, the skill uploads report artifacts to:

```text
ciso-reports-local/<server-id>/<report-type>/<report-date>/
```

Typical contents:

- `report.html`
- `snapshot.json`
- `manifest.json` at the server root for historical lookup

## Skill Builder (Blueprint Generator)

This project includes a separate builder skill for creating new persona packs:

- Skill folder: `Dashboard-blueprint-skills/`
- Purpose: scaffold a new dashboard/report skill for a persona such as CTO, Head of Engineering, Compliance, or DevOps leadership

Recommended installation:

```bash
apm install liquid-jedi/jfrog-agentic-dashboard-skills/packages/apm/jfrog-dashboard-blueprint#v2.3.0
```

Typical builder prompt:

```text
Scaffold a new dashboard pack for Engineering Head.
```

### Builder Flow

The blueprint generator does not query JFrog APIs. Its job is to scaffold a new skill pack through this flow:

1. Ask a short persona interview.
2. Capture audience, top questions, decisions, data sources, cadence, outputs, and trust requirements.
3. Create a new persona skill folder.
4. Generate `SKILL.md`, `report-schema.md`, `report-data-collection.md`, `dashboard.html`, and `sample-data.json` from templates.
5. Leave persona-specific TODOs in the generated files where implementation is still needed.

Use the builder when you want to create a new reporting pack without copying the CISO skill by hand.

## Where to Change Logic

There are three important control points in the project.

### 1. Workflow contract

- File: `Dashboard-ciso-report-skills/SKILL.md`
- Owns: execution order, mandatory checkpoints, validation rules, output handling

### 2. Data producer logic

- File: `Dashboard-ciso-report-skills/references/report-data-collection.md`
- Owns: API mapping, field derivation, formulas, classification logic, recommendation scoring

### 3. Renderer logic

- File: `Dashboard-ciso-report-skills/references/dashboard.html`
- Owns: section layout, visual presentation, interpretation callouts, sorting, and rendering behavior

Runtime payloads are generated artifacts, not source-of-truth code:

- `/tmp/ciso-data.json`
- local run `data.json`
- checked-in HTML examples under `Example Reports/`

## Recommendation Contract

Recommendations are generated automatically from live data after platform enrichment. The runner produces:

- **P1** — one recommendation per critical-issue component group (real XRAY IDs, hit counts, description from violation data)
- **P2** — unindexed repository coverage gap, with percentage blind spot
- **P2** — dry-run curation policies that should be promoted to block mode, with audit-event count
- **P3** — packages that passed without inspection (bypass events)

A fallback P1 is added if no critical issues exist.

Every recommendation must include:

- `priority` (`P1`, `P2`, `P3`)
- `score` (numeric urgency/ranking)

Optional but recommended:

- `effort`
- `owner`
- `due_date`
- `dependencies`

Validation must happen before template injection.

## Report Interpretation

### Executive KPIs

- Packages Evaluated: total curation audit events in the period.
- Blocked at the Gate: requests denied by curation policy.
- Approved Overrides: requests explicitly approved.
- Passed by Policy: requests allowed because no blocking rule matched.
- Threats Found Inside: total Xray violations.
- Critical Findings: critical-severity subset.
- Risk Score: normalized weighted index from 0 to 100.

### Severity and Risk Method

Severity meanings:

- Critical: exploit likely or high-impact compromise path.
- High: serious weakness needing near-term remediation.
- Medium: meaningful exposure with lower immediate blast radius.
- Low: limited immediate impact, typically suited to batched remediation.

Risk score formula (3-factor composite, computed after platform enrichment):

```text
# Factor 1 — Severity mix (50%)
# Weighted average of severity tiers. All-critical = 100, all-low ≈ 6.
sev = (critical×4 + high×2 + medium×1) / (total×4) × 100

# Factor 2 — Volume, log-scaled (30%)
# 0 violations = 0, ~100 = 50, 10 000+ = 100.
vol = min(100, log10(max(1, total)) / log10(10000) × 100)

# Factor 3 — Coverage gap (20%)
# Fraction of repositories not indexed by Xray.
cov = (1 - repos_indexed / repos_total) × 100

risk_score = sev×0.5 + vol×0.3 + cov×0.2
```

The score and each component are stored in `violations.risk_score` and `violations.risk_score_breakdown` in `data.json`. The gauge ring in the report shows the live breakdown.

Interpretation:

- Lower is better.
- Rising trend is bad.
- Typical bands: 0–15 low, 15–35 moderate, 35–60 high, 60+ critical.
- A score of 0 violations with some unindexed repos still shows residual risk from the coverage gap factor.

### Curation

- Block rate = blocked / total evaluated.
- High blocked volume may indicate stronger prevention, higher incoming threat pressure, or both.
- Read blocked count together with block reasons, ecosystems, and top blocked packages.

### Xray Violations

- By type: security, operational risk, license.
- By severity: critical, high, medium, low.
- Critical issues list: unique IDs, hit counts, age, exploitability, and environment context when available.

### License and Operational Risk

- License section reflects policy-backed compliance exposure.
- Operational risk highlights stale, unmaintained, or end-of-life component risk.

### Governance and Trend Sections

- Governance shows policy effectiveness and repository watch coverage.
- Comparison appears only when prior snapshots exist.
- Threat velocity requires enough historical runs to populate trend periods.

## Configurable Methodology Block

The renderer supports an optional top-level `methodology` object in DATA so teams can tune explanations and thresholds without editing renderer logic.

```json
"methodology": {
  "severity_levels": {
    "critical": { "meaning": "...", "signal": "..." },
    "high": { "meaning": "...", "signal": "..." },
    "medium": { "meaning": "...", "signal": "..." },
    "low": { "meaning": "...", "signal": "..." }
  },
  "risk_score": {
    "weights": { "critical": 100, "high": 20, "medium": 5, "low": 1 },
    "bands": [
      { "min": 0, "max": 15, "label": "Low weighted exposure", "signal": "Good" },
      { "min": 15, "max": 35, "label": "Moderate weighted exposure", "signal": "Watch trend" },
      { "min": 35, "max": 60, "label": "High weighted exposure", "signal": "Bad" },
      { "min": 60, "max": null, "label": "Critical weighted exposure", "signal": "Very bad" }
    ]
  },
  "curation_actions": {
    "blocked": "Denied by policy.",
    "approved": "Explicit override approval.",
    "passed": "Evaluated and allowed because no blocking rule matched."
  },
  "repo_watch_risk_levels": [
    { "level": "critical", "rule": "Repository has critical findings and no watch coverage." },
    { "level": "high", "rule": "Repository has critical findings or high violation volume." },
    { "level": "medium", "rule": "Repository has violations, or is indexed with zero watches." },
    { "level": "low", "rule": "No significant findings and covered." }
  ]
}
```

If omitted, built-in defaults are used.
