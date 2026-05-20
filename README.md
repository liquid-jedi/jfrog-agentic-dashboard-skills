# JFrog Dashboard & Reports

Reports and dashboards are something every organization and platform admin
needs. But meeting everyone's requirements is hard. Every org has different
priorities, every team tracks different metrics, and every persona from
CISO to DevOps lead to compliance officer needs a different view of the
same platform data.

Using AI agents and skills, we can now generate dashboards that are
customized for each organization and persona, on demand, from live
JFrog Platform data.

This project delivers the skills to make that happen. The plan is to build
one skill per persona. First off the block is the **CISO Security &
Curation Dashboard**.

The longer-term goal is to open this pattern to a wider audience by
shipping reusable dashboard blueprint skills that other teams can extend
for their own personas and reporting needs.

## Why Agentic Reporting

This project uses a **skill-first agentic workflow**, not a rigid one-size-fits-all reporting tool.

- The agent gathers live platform data, applies persona-specific logic, and produces structured JSON.
- A fixed, reusable dashboard template renders that JSON into a deterministic HTML report.
- Customers can tune scoring, thresholds, recommendations, and interpretation rules in the data contract without rewriting the full UI.
- The same pattern can be replicated across personas (CISO, DevOps, Platform Ops, Compliance) by swapping skill logic and schema mappings.

In short: agents provide adaptability, while schema + template provide consistency and governance.

## Value Delivered

- **Customer-defined priorities:** each team can emphasize the metrics that matter most in their environment.
- **Live decision support:** reports are generated from current JFrog data, not static exports.
- **Consistent executive output:** every run renders through the same template for comparable reporting.
- **Faster persona expansion:** new dashboards are created by adding a skill and mapping, not rebuilding a product.
- **Reusable blueprint path:** the same framework can be packaged into dashboard blueprint skills for broader internal and partner use.
- **Auditability and trust:** JSON-first generation makes the report logic inspectable and testable.
- **Portable architecture:** works across AI coding agents that support the Skills framework.

## Release Highlights

This release introduces production-focused improvements for reliability,
clarity, and operator adoption:

- **Instance-aware filenames:** report artifacts include the server instance slug.
- **Safe rerun behavior:** existing same-day outputs are never overwritten; reruns are stored in timestamped folders.
- **Structured local artifacts:** reports, JSON payload, snapshot, and run metadata are stored in a consistent hierarchy.
- **Default local behavior:** if no output location is specified, the current working directory is used automatically.
- **Severity insights upgraded:** the severity panel now highlights concentration (Critical+High share and dominant severity).
- **Curation audit resilience:** if row-level blocked events are missing but blocked totals exist, the report shows a useful summary instead of a false "no blocked events" message.

**Author:** Avinash Giri

---

## CISO Report & Dashboard

The CISO skill generates a comprehensive security posture dashboard
designed for security leadership. It pulls live data from your JFrog
Platform instance and produces a single, self contained HTML file you
can open in any browser, email to stakeholders, or archive in Artifactory.

### What it shows

**Supply Chain Defense (Curation)**
- Packages evaluated, blocked at the gate, approved through
- Blocks by reason: malicious, security (CVE), license, operational
- Top blocked packages with triggering policies and ecosystem
- Full curation audit trail with per event detail

**Vulnerability Posture (Xray)**
- Total violations by type: security, operational risk, license
- Severity distribution with visual bars: critical, high, medium, low
- Risk score (weighted by severity) with period-over-period delta
- Every unique critical issue listed with Xray ID and hit count
- Critical issue context: first seen, days open, exploit status, environment scope, runbook link (when available)
- Top affected repositories and artifact locations

**Compliance & Risk**
- License violations by SPDX identifier with severity
- Operational risk: end of life, unmaintained, outdated components
- Top impacted components and artifact paths

**Executive View**
- At a glance KPI cards across the top
- Combined security value: curation prevention vs Xray detection
- Period over period comparison (available after two or more runs)
- Prioritized recommendations with specific Xray IDs and actions
- Structured recommendation metadata: priority, effort, owner, due date, dependencies

**Governance & Trends (Beta)**
- Policy effectiveness table (policy hit volume and share)
- Repository watch coverage table (indexed state, watch depth, risk level)
- Threat velocity trend across recent periods (blocked, violations, critical)

**Platform Context (Sidebar)**
- Platform URL, watches (total and active), policies by type
- Curation status, curated repos, policy counts
- Xray indexed repos with package type indicators
- Report period and generation date

---

## Prerequisites

1. **JFrog Platform account.** SaaS or self hosted. The skills work with
   either deployment model.

2. **JFrog Xray** enabled on the platform for vulnerability and violation data.

3. **JFrog Curation** is optional. The dashboard gracefully shows
   "Not configured" if curation is unavailable.

4. **JFrog CLI** (`jf`) installed and authenticated with at least one server:
   ```bash
   brew install jfrog-cli              # macOS
   curl -fL https://install-cli.jfrog.io | sh   # Linux

   jf config add myserver --url=https://myinstance.jfrog.io --interactive
   ```

5. **JFrog Platform Skills (required dependency).**
   This project depends on the base `jfrog` skill from JFrog Platform Skills.
   Repository: https://github.com/jfrog/jfrog-skills

   Install the base skill:
   ```bash
   npx skills add jfrog -g -y
   ```

   Verify it is available:
   ```bash
   npx skills list
   ```

   The list should include `jfrog` before running `jfrog-ciso-report`.

6. **Tools on PATH:** `jf`, `jq`, `python3`

---

## Installation

For consumers installing directly from GitHub, use the repository URL and
select the skill by name:

```bash
npx skills add git@github.com:liquid-jedi/jfrog-agentic-dashboard-skills.git -g --skill jfrog-ciso-report
```

Optional installs from the same repo:

```bash
npx skills add git@github.com:liquid-jedi/jfrog-agentic-dashboard-skills.git -g --skill jfrog-dashboard-blueprint
npx skills add git@github.com:liquid-jedi/jfrog-agentic-dashboard-skills.git -g --skill jfrog-head-of-engineering-report
```

For development, register the skill from a local clone so edits take effect
immediately:

```bash
npx skills add /absolute/path/to/jfrog-ciso-dashboard -g --skill jfrog-ciso-report
```

Equivalent local-clone installs for the other skills:

```bash
npx skills add /absolute/path/to/jfrog-ciso-dashboard -g --skill jfrog-dashboard-blueprint
npx skills add /absolute/path/to/jfrog-ciso-dashboard -g --skill jfrog-head-of-engineering-report
```

Why this is the recommended approach:

- Your edits take effect immediately while you iterate.
- The skill stays linked to the source in this repository.
- It avoids duplicated local copies drifting from the checked-in version.

If you later need a frozen distribution copy for another machine or team,
create that as a separate packaging step rather than using it as the main
authoring workflow.

**Verify:** Your agent should list `jfrog-ciso-report` among its available
skills. In Claude Code you can check with:
```bash
claude -p "What skills do you have?" --allowedTools "Read" "Write"
```

### Runtime readiness check (works from any directory)

Before running reports, validate the runtime with the included checker:

```bash
bash /absolute/path/to/jfrog-ciso-dashboard/scripts/agentic-dashboard-prechecks.sh
```

Optional auto-fix mode (opt-in):

```bash
bash /absolute/path/to/jfrog-ciso-dashboard/scripts/agentic-dashboard-prechecks.sh --fix
```

Non-interactive auto-fix (for setup scripts/CI):

```bash
bash /absolute/path/to/jfrog-ciso-dashboard/scripts/agentic-dashboard-prechecks.sh --fix --yes
```

What good looks like:

- `jf`, `jq`, `python3`, and `npx` are on PATH
- Global skills include `jfrog` and `jfrog-ciso-report`
- At least one JFrog CLI server is configured
- If multiple servers are configured, runtime behavior asks for server choice
- Runtime echoes resolved local output root before collection begins

If the checker fails, fix the reported blockers before running report generation.

Platform support for prechecks:

- macOS: supported
- Linux: supported
- Windows: supported via WSL (recommended)
- Native CMD/PowerShell: not the primary path for this script

Cursor runtime note:

- If Cursor is running in sandbox auto-run mode, outbound network may be blocked by default.
- For live JFrog API collection, allow network egress to your JFrog endpoints in Cursor sandbox settings.
- If network is blocked, the report run must fail fast instead of reusing stale payloads.

Runtime cleanup model:

- Cleanup is agent-driven and part of the skill workflow, not an external script.
- The agent must remove transient runtime payloads in `/tmp` at the end of each run.
- If a run is interrupted, the next run must overwrite runtime payloads and must not reuse stale data.

---

## How to Run

### Interactive

Open your AI agent and ask:

```
Generate a weekly CISO report
Generate a monthly CISO report for solenglatest
Generate a CISO dashboard for the last 30 days
```

Server name is optional:

- If your prompt names a server, the skill uses it.
- If only one JFrog CLI server is configured, the skill uses it silently.
- If multiple JFrog CLI servers are configured and the prompt names none, the skill must ask which one to use. It must not fall back to the JFrog CLI default server.

Local path is also optional:

- If your prompt includes a local output path, the skill uses it.
- Else if `CISO_LOCAL_ROOT` is set, the skill uses that value.
- Else the skill defaults to the current working directory (`$PWD`).
- In all cases, the skill should surface the resolved local output root before data collection starts.

### Headless

**Claude Code:**
```bash
claude -p "Generate a weekly CISO report for solenglatest. Local only." \
  --allowedTools "Bash(jf *)" "Bash(jq *)" "Bash(eval *)" \
  "Bash(cat *)" "Bash(echo *)" "Bash(date *)" "Bash(sed *)" \
  "Bash(cp *)" "Bash(mkdir *)" "Bash(python3 *)" "Bash(wc *)" \
  "Bash(grep *)" "Bash(find *)" "Read" "Write" \
  2>&1 | tee /tmp/ciso-run.log
```

**Any agent:**
```
Prompt: "Generate a weekly CISO report. Local only."
Required tools: jf, jq, python3, file read/write
```

Include "Save to Artifactory" for remote storage with historical
comparison, or "Local only" to force a purely local run. If neither is
provided, the skill uses the default behavior described below.

### Sample prompts

```
Generate a weekly CISO report.
Generate a monthly CISO report. Local only.
Generate a CISO security dashboard for March 2026.
Generate a weekly CISO report for solenglatest. Save to Artifactory.
Generate a weekly CISO report. Local only. Save local artifacts under /Users/me/security-reports.
Generate a weekly CISO report.
```

---

## Default Runtime Behavior

If the prompt does not specify server, local path, or storage mode, the
skill behaves as follows:

- **Server selection:** if one JFrog CLI server is configured, it is used automatically. If multiple servers are configured, the skill asks which one to use.
- **Local artifact root:** defaults to the current working directory (`$PWD`) unless the prompt provides a path or `CISO_LOCAL_ROOT` is set.
- **Pre-run summary:** before data collection begins, the skill should state the resolved server, local output root, and storage mode so defaults are visible rather than implicit.
- **Artifactory storage:** defaults to local-only unless the prompt says `save to Artifactory` or names a repo. If the prompt requests Artifactory and the repo exists, it is used; if it does not exist, the skill asks to create it. If access is denied (`403`), the skill continues local-only.

## Local Artifact Storage

Every run writes a local artifact bundle with a deterministic path model.

Default root:

- Explicit path in prompt, else `CISO_LOCAL_ROOT` env var, else current working directory (`$PWD`).

> **Trend analysis requires a stable root.** If `LOCAL_ROOT` defaults to `$PWD` and you launch the agent from different directories, prior snapshots won't be found and comparison will always be empty. Set `CISO_LOCAL_ROOT` to a fixed path for reliable trend data:
> ```bash
> echo 'export CISO_LOCAL_ROOT=~/ciso-reports' >> ~/.zprofile
> echo 'export CISO_LOCAL_ROOT=~/ciso-reports' >> ~/.zshrc
> ```

Directory structure:

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

Artifact controls:

- `data.json` persistence can be toggled with `CISO_SAVE_DATA_JSON=true|false`.
- Default is `true`.
- `run-meta.json` includes a `token_usage` block.
- `token_usage.total_tokens` is populated when available from:
   - `CISO_TOTAL_TOKENS`, or
   - `/tmp/ciso-token-usage.json` (with `total_tokens` field)
- If unavailable, token usage is recorded as `null` with status `unavailable`.

If a run already exists for the same instance/report-type/date, the skill
stores the next run under a rerun folder instead of overwriting:

```text
<LOCAL_ROOT>/<instance-slug>/<report-type>/<YYYY-MM-DD>/rerun-HHMMSS/
```

This keeps local history clean and prevents partial-file collisions after
interrupted runs.

Repository note:

- Checked-in sample reports live under `samples/`.
- Generated local artifacts should not be committed; `.gitignore` excludes the runtime artifact layout.

---

## Repository Layout

```text
dashboard-report-skills/              # CISO skill workflow + renderer contract
dashboard-blueprint-skills/           # Persona skill scaffolder / builder
dashboard-report-skills-head-of-engineering/  # Example scaffolded persona pack
docs/                                 # Operator documentation
samples/                              # Checked-in example HTML reports
```

## Artifactory Storage (Optional)

Reports and snapshots can be stored in Artifactory for historical
tracking and period over period comparison:

```
ciso-reports-local/
├── solenglatest/
│   ├── weekly/2026-04-24/snapshot.json, report.html
│   ├── monthly/2026-04/snapshot.json, report.html
│   └── manifest.json
├── LiquidJedi/
│   └── weekly/...
```

---

## How It Works

Each dashboard skill is built around a clean separation of concerns.
The AI agent is responsible for collecting data from JFrog APIs and
building a structured JSON object. A pre built HTML template is
responsible for rendering. The agent fills the JSON, the template
does the rest.

```
AI agent collects data via JFrog CLI and REST APIs
        ↓
Builds a JSON object matching a defined schema
        ↓
Injects JSON into a pre built HTML template
        ↓
Self rendering HTML opens in any browser
```

Because the layout, styling, and section rendering are all handled by
the template, the output is consistent and branded every time. It does
not matter which AI agent runs the skill or how the agent phrases its
internal logic. The same JSON schema always produces the same dashboard.

This also means the skills are portable. Any AI coding agent that supports
the Skills framework can run them: Claude Code, Cursor, Cline, Windsurf,
Amp, Antigravity, and others.

The HTML template itself is fully customizable. It is a single self
contained file with standard HTML, CSS, and JavaScript. There is no build
step, no framework dependency, and no bundler. If you want to change the
branding, adjust colors, add a section, rearrange the layout, or embed
your company logo, you can edit `dashboard.html` directly and the changes
take effect on the next report run.

### Critical execution contract

The CISO skill has a strict execution model:

1. It must produce JSON first.
2. It must save that JSON to `/tmp/ciso-data.json`.
3. It must inject JSON into the template by replacing the `__CISO_DATA__` placeholder.
4. It must verify that the final report contains one `const DATA = { ... }` block.

The skill must not generate HTML from scratch. The report layout, section rendering,
severity bars, recommendations formatting, and sidebar are implemented in
`dashboard-report-skills/references/dashboard.html`.

### Mandatory runtime checkpoints

The workflow has one mandatory checkpoint before data collection:

1. Server selection (only when multiple JFrog CLI servers are configured and the prompt does not name one)

Storage defaults to local-only silently. After the server is resolved, execution continues without further prompting.
If any API call fails, the skill should still produce a report using defaults
(0, empty arrays, false, null) so the dashboard can render gracefully.

### Curation and Xray collection rules

- Curation detection must come from the curation audit API, not entitlement metadata.
- For curation audit windows, 168 hours is the maximum per request.
- Weekly reports can use one call; monthly reports should chunk date windows and merge.
- Xray violations queries should always include `created_from` to avoid large-instance timeouts.
- All jf commands must pass `--server-id` explicitly.

### JSON schema to dashboard mapping

The dashboard consumes a full JSON contract defined in
`dashboard-report-skills/references/report-schema.md`.

Key behavior in the renderer:

- Sidebar uses `meta` + `platform` fields (URL, watches, policies, curation status, indexed coverage).
- KPI strip uses `curation.total`, `curation.blocked`, `curation.approved`, `violations.total`, and `violations.by_severity.critical`.
- KPI strip also shows `curation.passed` and `violations.risk_score`.
- Curation section shows unavailable warning when `curation.available=false`.
- Curation section separates approved overrides from policy-pass outcomes.
- Curation audit table displays blocked events from `curation.audit_events`.
- Violations section renders type split, severity distribution, and critical issue list.
- Critical issue rows can include age, exploitability, environment scope, and runbook links.
- License section changes message based on both `license.total` and `platform.policies_license`.
- Operational section renders only when `operational.total > 0`.
- Governance section renders policy effectiveness and repository watch coverage when data exists.
- Threat velocity section renders rolling trend periods when historical snapshots are available.
- Comparison section renders deltas only when `comparison.available=true`.
- Recommendation priority is strictly driven by structured `priority` metadata.

### File responsibilities

- `dashboard-report-skills/SKILL.md`: Workflow orchestration and hard rules.
- `dashboard-report-skills/references/report-data-collection.md`: API and jq mapping guidance.
- `dashboard-report-skills/references/report-schema.md`: Data contract for every required field.
- `dashboard-report-skills/references/dashboard.html`: Presentation and rendering logic.

### Skill files

```
dashboard-report-skills/
├── SKILL.md                              # Agent workflow
└── references/
    ├── dashboard.html                    # Self rendering HTML template
    ├── report-schema.md                  # JSON schema contract
    └── report-data-collection.md         # API to JSON field mapping
```

| File | Purpose |
|------|---------|
| **SKILL.md** | The workflow the agent follows: collect, build JSON, inject, save |
| **report-schema.md** | The contract between agent and dashboard. Every JSON field defined. |
| **report-data-collection.md** | JFrog API calls and jq parsing for each schema field |
| **dashboard.html** | Self contained renderer. Agent injects JSON, never modifies layout. |

---

## Creating New Persona Packs (Blueprint Generator)

The `dashboard-blueprint-skills/` skill scaffolds a new persona dashboard
pack from a short interview. Use it when you want to create a new
report for a persona (CTO, Engineering Head, Compliance, DevOps Lead,
etc.) without copy-pasting the CISO pack manually.

What it produces:

```
dashboard-report-skills-<persona-slug>/
├── SKILL.md
└── references/
    ├── report-schema.md
    ├── report-data-collection.md
    ├── dashboard.html
    └── sample-data.json
```

How to use:

```
Prompt: "Scaffold a new dashboard pack for <persona>"
```

The blueprint generator does NOT call JFrog APIs. It only creates the
starter files with persona-specific placeholders filled in. After
generation, implement the API mapping in `report-data-collection.md` and
register the skill globally:

```bash
npx skills add ./dashboard-report-skills-<persona-slug> -g -y
```

See `dashboard-blueprint-skills/references/blueprint-structure.md` for
the full output contract and design rules every pack must follow.

---

## User Manual

For operator-focused usage and interpretation guidance, see:

- `docs/ciso-user-manual.md`

Documentation split:

- README: project overview, prerequisites, installation, run flow, repository layout, and adoption guidance.
- User manual: operating model, supported agents, OS guidance, skill-builder flow, output model, and report interpretation.

---

## Beta Schema Migration

If you are producing JSON outside the skill and injecting manually, update
your payload for beta:

- Add `meta.schema_version` (recommended value: `2.0-beta`)
- Split curation allow outcomes into:
   - `curation.approved` (explicit overrides)
   - `curation.passed` (policy-pass outcomes)
- Add risk fields:
   - `violations.risk_score`
   - `violations.risk_score_previous`
- Enrich critical issues when data exists:
   - `first_seen`, `days_open`, `exploit_status`, `affected_environments`, `playbook_link`
- Add governance section:
   - `governance.policy_effectiveness[]`
   - `governance.repo_watch_coverage[]`
- Add trend section:
   - `threat_velocity.available`, `periods[]`, `trend_summary`
- Add recommendation metadata:
   - required: `priority`, `score`
   - optional: `effort`, `owner`, `due_date`, `dependencies`

Priority behavior in beta:

- Renderer prefers structured `recommendations[].priority`.
- Title-based inference is disabled.
- Recommendation ranking should be data-driven via `score` from the mapping
   guidance in `report-data-collection.md`.
- Renderer ordering is deterministic: sort by `score` (desc), then
   `priority` (P1 > P2 > P3), then title.
- Producer hard-fail rule: if any recommendation is missing `priority` or
   `score`, fail generation before template injection.
- Renderer defensive safety: if malformed recommendation metadata still reaches
   the template, the report shows a warning banner in the Recommendations
   section and continues rendering.

### Configurable Severity and Risk Methodology

The dashboard supports an optional top-level `methodology` object in DATA.
Use it to customize on-screen explanations without editing template logic:

- Severity definitions (`critical/high/medium/low`) and good-vs-bad signals
- Risk score weights and health bands
- Curation action semantics (`blocked/approved/passed`)
- Repository watch risk-level rule text (`critical/high/medium/low`)

If `methodology` is omitted, built-in defaults are used.

Risk score normalization (recommended):

```text
raw = (Critical*100) + (High*20) + (Medium*5) + (Low*1)
risk_score = (raw / (total_violations*100)) * 100
```

Treat score direction as:
- Lower is better
- Rising trend is bad
- Flat at low range is healthy

If optional enrichment is unavailable, keep generating reports with defaults.
The renderer is designed to degrade gracefully.

---

## Compatibility

| | Supported |
|---|---|
| JFrog SaaS | Yes |
| JFrog Self Hosted | Yes |
| JFrog Xray | Required |
| JFrog Curation | Optional |
| macOS | Yes |
| Linux | Yes (may need date command adjustment) |

---

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Skill not detected by agent | Run `npx skills add ~/.agents/skills/jfrog-ciso-report -g -y` |
| Agent generates its own HTML | Skill not registered. See installation steps. |
| Curation shows "Not configured" | Verify curation is enabled on your JPD and token has permissions |
| CLI tools not found | Ensure `jf`, `jq`, `python3` are installed and on PATH |
| API calls return 403 | Token needs admin or security reader permissions |
| Report missing sections | Check reference files exist at `~/.agents/skills/jfrog-ciso-report/references/` |
| Headless run stops for input | Include server name and "Local only" or "Save to Artifactory" in prompt |
| Report path unclear | Check the final console line: "Local artifacts saved under: ..." |