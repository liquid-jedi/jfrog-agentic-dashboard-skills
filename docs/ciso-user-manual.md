# CISO Dashboard User Manual

This manual is the operator document for installing, running, extending,
and interpreting the CISO dashboard skill.

## Document Scope

| Document | Focus |
|----------|--------|
| [README](../README.md) | Project overview, quick start, documentation index |
| [INTERPRETING-THE-REPORT.md](INTERPRETING-THE-REPORT.md) | Reading the finished report, panel by panel |
| [INSTALL.md](INSTALL.md) | Prerequisites, install, verify, update, prechecks, first run |
| [TROUBLESHOOTING.md](TROUBLESHOOTING.md) | Common issues and platform support |
| **This manual** | Permissions, supported agents, interpretation, tuning |

For installation steps, start with [INSTALL.md](INSTALL.md) rather than duplicating commands here.

## Audience

This document is written for:

- Platform engineers operating the skill locally or in CI.
- Security engineers tuning formulas, thresholds, or recommendation logic.

If you are reading the finished report rather than running it, start with
**[Interpreting the report](INTERPRETING-THE-REPORT.md)** instead.

## Installation

See **[INSTALL.md](INSTALL.md)** for prerequisites, APM install, generic Skills install, prechecks, and verification.

Quick reference — APM install:

```bash
apm install liquid-jedi/jfrog-agentic-dashboard-skills/packages/apm/jfrog-ciso-report#v4.3.0
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

See the [compatibility table](TROUBLESHOOTING.md#compatibility) for the
supported matrix. The notes below cover what differs between platforms.

### macOS and Linux

Both work as-is. The runner needs `bash`, and it delegates all date arithmetic
to `python3` rather than shelling out to `date -d` or `date -v`, so there is no
BSD-versus-GNU difference to work around.

### Windows

Use **WSL2**. The runner is a bash script that assumes POSIX semantics and
writes its scratch files under `/tmp`, so native CMD and PowerShell are not
viable. Git Bash provides the shell and `/tmp`, but `node` there is a native
Windows binary and the combination is untested — prefer WSL2 if you can.

The one WSL2-specific step is the browser: WSL2 ships without one, and the PDF
check runs before collection starts. Install Chromium inside WSL or install
Puppeteer. Pointing `CISO_CHROME_BIN` at the Windows Chrome under `/mnt/c/...`
will launch it but it cannot write the PDF back to a Linux path. If you only
want the interactive HTML, ask for `html only` — the browser check is skipped
entirely in that mode.

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
- To target the current month-to-date, ask for `this month`, `current month`, or
  `month-to-date`; the report should end on today, not the last future day of the
  month.

Large active-user populations:

- The dashboard shows the top active Curation users only.
- Every active user is written to `curation-user-package-activity.csv` next to
  `report.html`. The file opens with a commented block defining **Active User**,
  the reporting period, and the active user count, then carries the tables below.

The export has two shapes. **Full** is the default and adds the per-package
breakdown. **Brief** keeps only the per-user counts and the curated repositories,
which is what you want on a very large instance — the package breakdown is the
part whose size grows without bound. Ask for it in the prompt:

```text
Generate a weekly CISO report for <server>, brief users
Generate a weekly CISO report for <server>, with package detail
```

Above roughly 250,000 curation events in the period, the skill reports the count
and asks which you want. Both shapes list every active user with identical
counts; brief simply stops after the `curated_repos` column and omits table 2.
Set `CISO_CURATION_USER_DETAIL=full|brief` to skip the question entirely.

**Table 1 — Active Users in this period**, one row per user (both shapes):

  | Column | Meaning |
  |--------|---------|
  | `rank` | Position by request volume, `1` to N. The last row's rank is the total active user count |
  | `user` | Username or user mail from the audit events |
  | `total_requests` | Package requests attributed to the user in the period |
  | `request_share_pct` | Share of all attributed requests |
  | `blocked` | Requests denied by Curation policy |
  | `clean_approved` | Requests allowed with no blocking rule matched |
  | `block_rate_pct` | `blocked / total_requests` — sort on this to find risky consumers regardless of volume |
  | `curated_repos` | Curated repositories the user pulled through |
  | `distinct_packages` | Full only. Distinct packages the user pulled in the period, counted across every repo |
  | `ecosystems` | Full only. Package types used, for example `Maven; npm` |
  | `top_packages` | Full only. Ten most requested packages as `name (count)` |

**Table 2 — Full request detail** (full shape only), one row per user, curated
repo, and package:

  | Column | Meaning |
  |--------|---------|
  | `user` | Same identity as table 1 |
  | `curated_repo` | Curated repository that served the request. Empty when the audit event does not name one |
  | `ecosystem` | Package type |
  | `package` | Package name |
  | `requests` | Requests for that user, repo, and package |

- Both tables are sorted by volume descending, so table 1's `rank` doubles as a
  running count of active users. A low-volume user with a high `block_rate_pct`
  is usually more interesting than the top requester.
- Table 2 is capped at 50,000 rows. When the cap trims the table, its heading
  states how many rows of the total were written. Table 1 always lists every
  active user, in both shapes.
- In brief mode the dashboard's Active Users table shows curated repositories in
  place of the top-packages column, and the CSV explains in its header why the
  package columns are absent.
- Comment lines start with `#`. Excel and Google Sheets show them as text rows;
  `pandas.read_csv(..., comment='#')` skips them. Because the file holds two
  tables, point a parser at the header row you want rather than reading the
  whole file as one frame.

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

Two outputs are also chosen from the prompt.

**PDF export.** The default is the CISO-shareable `executive-report.pdf`:

| Say | You get |
|-----|---------|
| nothing, or `executive pdf` | `executive-report.pdf` |
| `full pdf`, `detailed pdf` | `full-report.pdf` |
| `both pdfs` | both files |
| `html only`, `no pdf` | neither; the browser check is skipped |

**Curation user export.** The default is `full`:

| Say | You get |
|-----|---------|
| nothing, or `with package detail` | Per-user counts, curated repos, package breakdown, and the detail table |
| `brief users`, `user counts only` | Per-user counts and curated repos only |

Above roughly 250,000 curation events the skill reports the count and asks.
`CISO_PDF_MODE` and `CISO_CURATION_USER_DETAIL` override both, which is how you
keep a headless run from stopping at a question.

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
  - `CISO_TOTAL_TOKENS` or detailed token environment variables.
  - `CISO_TOKEN_USAGE_PATH` or `/tmp/ciso-token-usage.json`.
  - `CISO_CLAUDE_TRANSCRIPT_PATH` / `CLAUDE_TRANSCRIPT_PATH` for best-effort Claude Code transcript aggregation.
- If no source is available, `token_usage.total_tokens` is `null` and status is `unavailable`.
- Boost token savings are terminal-output savings and are separate from model/session token usage.

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
- checked-in HTML examples under `docs/examples/`

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

Moved to its own guide: **[Interpreting the report](INTERPRETING-THE-REPORT.md)**,
written for the person reading the finished report rather than running it. It
walks the dashboard in the order the report is laid out and covers what each
panel means, what "good" looks like, and the readings people most often get
wrong.
