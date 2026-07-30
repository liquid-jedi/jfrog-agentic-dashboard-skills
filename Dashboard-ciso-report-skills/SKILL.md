---
name: jfrog-ciso-report
description: >-
  Generate a branded CISO Security & Curation HTML dashboard from a JFrog
  Platform instance. Use when the user asks for a security report, curation
  report, CISO dashboard, executive security summary, weekly/monthly
  security report, blast prevention report, or supply chain health report.
  Do NOT use for individual CVE lookups or single package checks — those
  are handled by the jfrog base skill and the package-safety workflow.
metadata:
  role: workflow
  author: Avinash Giri
  version: 3.0.0
---

# JFrog CISO Report Generator

## CRITICAL — READ THIS FIRST

You are NOT authoring HTML. You are NOT writing CSS. You are NOT designing
a report layout. Your only generated report content is JSON. A pre-built
HTML dashboard already exists and renders the report from your JSON. Your job:

1. Collect data from JFrog APIs
2. Build a JSON object matching the schema
3. Save the JSON to `/tmp/ciso-data.json`
4. Run the injection command (given below) — this is a python3 one-liner
5. Upload when Artifactory storage is enabled

If you generate HTML from scratch, the report will be broken. The dashboard
template has 1200 lines of CSS, JS, sidebar layout, severity bars, and
section rendering that you cannot reproduce. Do NOT attempt it.

**Role separation:** Phases 0–3 (collection through render): your only output is JSON — do not generate prose or interpretive text. Phase 4 (after runner succeeds): switch to analyst mode and deliver the executive interpretation as a chat response only; no prose is injected into the report HTML.

**Constraint precedence (highest wins):**
1. Transport fail-fast (no HTTP response received — always stop)
2. Runtime integrity contract
3. Determinism contract
4. Execution checklist
5. DO NOT rules

When two constraints conflict, the lower-numbered constraint takes priority.

## Execution checklist

Before collecting data:

- Confirm tools: `jf`, `jq`, `python3`, and `node` must be on PATH. PDF
  generation also requires Puppeteer or a Chrome/Chromium-compatible browser
  (the runner detects Google Chrome, Chromium, and Microsoft Edge, or uses
  `CISO_CHROME_BIN`). If missing,
  stop and tell the user to install/configure them using `../jfrog/SKILL.md`.
- Resolve report period. Default to `weekly`. Weekly window: seven calendar days. For current weekly reports, use the last complete seven-day window ending today unless the prompt specifies dates. For historical weeks, resolve `DATE_FROM`, `DATE_TO`, and save under the period end date. All repos unless the prompt narrows scope.
- Resolve server. If multiple JFrog CLI servers exist and the prompt does
  not name one, you MUST stop and ask the user to choose. Do NOT use the
  JFrog CLI default server. Do NOT guess.
- Resolve local output root. You MUST always surface the final resolved
  local path before data collection starts. If no path was provided and
  `CISO_LOCAL_ROOT` is not set, ask once for a stable local root, create it,
  and persist it before data collection starts.
- Resolve storage. If no storage preference is given, default to local-only.
  Do NOT ask about storage unless the user explicitly said "save to Artifactory".

Command style rule for IDE agents:

- Prefer direct single commands over compound shell snippets.
- Do NOT use shell command substitution or probe wrappers such as
  `STATUS=$(...)`, `echo "$PWD"`, or multi-line variable-assignment blocks for
  routine preflight checks.
- When server, repo, or output path are already known, inline the resolved
  values in the command or in the execution summary instead of asking the shell
  to expand them.
- This reduces IDE approval prompts caused by "Contains expansion" checks.

After those checkpoints, execute without further questions. If an API fails, set the affected field to the schema-typed zero-value: numeric → `0`, array → `[]`, boolean → `false`, string → `""`, nullable object → `null`. Do not use `"N/A"` for any typed field. Continue collection.
Batch `jf` commands into single bash blocks. Pass `--server-id "$SERVER_ID"`
to every `jf` command.

Exception (MANDATORY fail-fast): distinguish transport failures from API failures. A **transport failure** means no HTTP response was received (TCP connection refused, DNS failure, TLS error, or timeout before any bytes arrive) — stop immediately and report the error. An **API failure** means an HTTP response was received (any status code, including 4xx/5xx) — apply zero-value defaults above and continue. When in doubt: if `jf` exits with a network/connectivity error message rather than an HTTP status code, treat it as a transport failure.
Do NOT use prior local files, prior snapshots, cached payloads, or "last
successful run" data as a substitute for current collection unless the user
explicitly requests fallback mode in the prompt.

## Runtime integrity contract (MANDATORY)

Every run must satisfy all contract points below:

1. Live collection only: report payload must come from API responses gathered
  in the current run window.
2. No implicit fallback: prior local payloads, prior snapshots, cached
  payloads, or "last successful run" data are forbidden unless the user
  explicitly asked for fallback mode.
3. Provenance required: `run-meta.json` must record whether data source is
  `live` or `fallback`, and fallback must include an explicit user request
  marker.
4. Fail-fast on transport blocks: sandbox/network/DNS/TLS/connectivity errors
  must terminate the run.
5. Source immutability: normal dashboard generation must not edit this skill,
  repository scripts, references, dashboard templates, or any source-controlled
  file. Only report artifacts (`report.html`, `executive-report.pdf`, optional
  `full-report.pdf`, `data.json`, `snapshot.json`, `run-meta.json`) and
  transient `/tmp/ciso-*` files may be created or changed.
  If a runner or validation bug appears, stop and report it; patch source only
  when the user explicitly asks to improve or fix the skill implementation.
6. End-of-run cleanup: transient runtime payloads in `/tmp` must be removed
  as the finalization step after success, and also before exiting on failure
  paths where temporary payloads were written.

## Prerequisites

Read `../jfrog/SKILL.md` for CLI setup. Required on PATH: `jf`, `jq`, `python3`.
Before running any step, execute from this repository root (`$SKILL_DIR`) rather
than `$HOME` so helper discovery and file scans stay scoped to the project.

```bash
cd "$SKILL_DIR"
```

**For API paths:** Read `../jfrog/references/xray-entities.md` for the
authoritative curation audit and violations API documentation. Do NOT
hardcode API paths from memory — the base skill has the correct, versioned
paths. Our `report-data-collection.md` maps those API responses to our
JSON schema.

## Phased workflow (0–4)

Execute in order.

| Phase | Name | What happens |
|-------|------|----------------|
| **0** | Preflight | Report type, dates, `SERVER_ID`, `LOCAL_ROOT`, storage, prior snapshot lookup |
| **1** | Collect | Submit the **entire** `Module: phase1-collect` block from `report-data-collection.md` as a **single shell command**. That block launches platform, curation, and violations as three background processes (`&`) and waits for all three with `wait`. Do NOT split the block into separate tool calls — doing so serialises the tracks and triples collection time. |
| **2** | Transform | jq mapping + **mandatory** curation audit transform + merge into JSON |
| **3** | Render & publish | Gates, injection, upload, `run-meta.json` |
| **4** | Finalize | Cleanup `/tmp/ciso-*` transient files |

```
Phase 0 → Phase 1 (single-command parallel block) → Phase 2 (transform) → Phase 3 (render) → Phase 4 (cleanup)
```

> **Phase 2 jq error handling:** if a `jq` transform exits non-zero or produces empty output for any field, apply the same zero-value defaults as for API failures (numeric → `0`, array → `[]`, boolean → `false`, string → `""`, object → `{}`) and log the failing expression to stderr before continuing.

## Determinism contract (mandatory)

For all paginated collection modules:
- Merge pages strictly by ascending `offset`.
- Stop at the first partial page (`rows < limit`) and ignore higher offsets.
- Keep stable sort keys for display transforms (`C+D` for curation audit display).
- For monthly curation chunking: merge chunk results in chunk-order, not completion order.
- Run `report-data-collection.md` → `Module: collection-determinism-guards` before render.

## Step 1: Report type and date range

Parse from the user's prompt. If no report type is specified, use `weekly`.
If the prompt asks for an unsupported report type, stop and list valid
options: `weekly`, `monthly`, or `custom`.

The agent must not manually delete prior runtime files at the start of a run. The runner script (`bin/generate-ciso-report.sh`) handles clearing stale `/tmp/ciso-*` files internally as its first action — that is a runner responsibility, not an agent action. The agent overwrites runtime payloads during collection and runs cleanup at the end.

| Prompt says | Type | Window |
|-------------|------|--------|
| "weekly" or "CISO report" | weekly | Last 7 days |
| "monthly" | monthly | Last calendar month |
| "this month" / "current month" | custom | Month-to-date: first day of current month 00:00:00Z through today 23:59:59Z |
| "for April" / "for March" | monthly | That month |
| "first week of May" | weekly | May 1 00:00:00Z through May 7 23:59:59Z |
| "second week of June" | weekly | June 8 00:00:00Z through June 14 23:59:59Z |
| "fifth week of May" | weekly | May 29 00:00:00Z through May 31 23:59:59Z |
| Custom dates | custom | As specified |

For "this month" or "current month" prompts, set `REPORT_TYPE=custom`,
`DATE_FROM` to the first day of the current month, and `DATE_TO` to today's
23:59:59Z. Do not set `DATE_TO` to the last future day of the month.

For historical weekly prompts, set `DATE_FROM` and `DATE_TO` explicitly. If
`REPORT_DATE` is not provided, the runner derives it from `DATE_TO`, so the
output folder represents the week being reported, not the day the report was
run. Example: a report for `2026-06-08T00:00:00Z` through
`2026-06-14T23:59:59Z` saves under
`<LOCAL_ROOT>/<server>/weekly/2026-06-14/`.

Ordinal weeks of a named month are month-local calendar blocks, not rolling
seven-day windows that cross into the next month. The first week starts on day 1,
the second on day 8, the third on day 15, the fourth on day 22, and the fifth on
day 29 when present. Clip the final week to the last day of the named month. For
example, "fifth week of May 2026" must use `DATE_FROM=2026-05-29T00:00:00Z`,
`DATE_TO=2026-05-31T23:59:59Z`, and `REPORT_DATE=2026-05-31`; it must not run
May 29 through June 4. "First week of June 2026" starts fresh at
`2026-06-01T00:00:00Z` and ends at `2026-06-07T23:59:59Z`.

`all repos` is the default scope for every report type unless the prompt
explicitly narrows the scope.

**Fallback mode trigger** — if the prompt contains "use last run", "fallback mode", or "offline mode": skip all live API calls; load the most recent local snapshot from `LOCAL_ROOT` as input; set `data_source=fallback`, `fallback_mode.used=true`, `fallback_mode.user_requested=true` in `run-meta.json`; label the report header "FALLBACK — data from `<prior_date>`". Stop if no prior snapshot exists.

## Step 2: Select server — MANDATORY

```bash
jf config show | grep "^Server ID:" | wc -l
```

This step is a hard gate. If multiple servers exist and the prompt does not
name one, do not continue with collection, rendering, or any API call that
depends on a server choice.

| Condition | Action |
|-----------|--------|
| Prompt names a server | Use that server. |
| `CISO_SERVER_ID` env var is set | Use it as `SERVER_ID`. |
| One server exists | Use it silently. |
| Multiple servers exist and prompt names none | Ask which server to use and wait for the answer. Do NOT use the CLI default server. |
| No servers exist or `jf config show` fails | Stop and tell the user to configure JFrog CLI. |

When prompting, list the configured server IDs so the user can choose from
real values.

## Step 3: Resolve output and storage

Resolve each sub-step in order. After Step 3d, export all variables before proceeding to Step 4.

### Step 3a: Resolve storage repo

Use `REPORT_REPO="ciso-reports-local"` unless the prompt names another repo.

### Step 3b: Resolve local output root

Also resolve local output root for every run. This determines where local
artifacts are written even when Artifactory upload is enabled.

### Step 3c: Resolve data persistence flags

Resolve raw DATA persistence mode for local artifacts:

| Condition | Action |
|-----------|--------|
| Prompt explicitly asks to skip raw data file (`no data.json`, `skip raw data`) | Set `SAVE_DATA_JSON=false`. |
| Prompt explicitly asks to keep raw data file (`save data.json`, `keep raw data`) | Set `SAVE_DATA_JSON=true`. |
| `CISO_SAVE_DATA_JSON` env var is set | Use its value (`true/false`). |
| No preference provided | Default to `SAVE_DATA_JSON=true`. |

### Step 3d: Resolve token capture

Resolve token usage capture mode for run metadata:

| Condition | Action |
|-----------|--------|
| `CISO_AGENT_NAME` env var is set | Use it as `agent.name`. |
| Claude/Cursor/Codex environment markers are present | Record best-effort `agent.name` / `agent.detected`. |
| `CISO_TOTAL_TOKENS`, `CISO_INPUT_TOKENS`, `CISO_OUTPUT_TOKENS`, `CISO_CACHE_READ_TOKENS`, `CISO_CACHE_CREATION_TOKENS`, or `CISO_TOTAL_COST_USD` are set | Use these values for `token_usage`. |
| `CISO_TOKEN_USAGE_PATH` or `/tmp/ciso-token-usage.json` exists | Read token usage JSON from that file. |
| `CISO_CLAUDE_TRANSCRIPT_PATH` or `CLAUDE_TRANSCRIPT_PATH` points to a Claude Code JSONL transcript | Best-effort aggregate assistant message `usage` records. |
| No source is available | Set `token_usage.total_tokens` to `null` and `token_usage.status` to `unavailable`; ask the user to run `/usage` in Claude Code if they want manual capture. |

Token capture is best effort. Billing systems remain authoritative. Boost token
savings are terminal-output savings, not the same thing as total model/session
tokens.

This step is also mandatory. Do not silently choose an output location.
On first run, bootstrap a stable local root instead of falling back to `$PWD`.

| Condition | Action |
|-----------|--------|
| Prompt includes a local path (for example: "save under /Users/me/reports") | Use it as `LOCAL_ROOT`. |
| `CISO_LOCAL_ROOT` env var is set | Use it as `LOCAL_ROOT`. |
| No location provided and `CISO_LOCAL_ROOT` is not set | Ask the user once for a stable local root (recommend `~/ciso-reports`), create the directory, and persist it as `CISO_LOCAL_ROOT` for future runs before continuing. |
| Resolved `LOCAL_ROOT` equals `$HOME` and user did not explicitly request home root | Ask for confirmation or use `~/ciso-reports` before proceeding. |

Set these once during Phase 0 / Step 3 (before Step 4 snapshot lookup or any
Python that references them). Step 7 render reuses the same values:

```bash
export REPORT_DATE="${REPORT_DATE:-$(date +%Y-%m-%d)}"
export REPORT_TYPE_LOWER="$(echo "${REPORT_TYPE:-weekly}" | tr '[:upper:]' '[:lower:]')"
export SERVER_SLUG="$(echo "$SERVER_ID" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')"
export REPORT_TYPE_SLUG="$REPORT_TYPE_LOWER"
```

**→ Export checkpoint:** all variables above must be exported before Step 4 begins.

Before Step 4 begins, print a short status line to the user. This is
informational only — do not wait for acknowledgement, do not ask a
question. Proceed immediately after printing:

```text
Running: <REPORT_TYPE> report | server: <SERVER_ID> | output: <LOCAL_ROOT> | storage: <local-only|artifactory:<REPORT_REPO>>
```

If a bootstrap prompt was needed because `CISO_LOCAL_ROOT` was missing, ask
only for the local root path. After the user answers, create the directory and
persist the setting before collecting data. Do not ask again on later runs
unless the user wants to change the path.

Local structure must always be:

```text
<LOCAL_ROOT>/
└── <server-id>/
  └── <report-type-lowercase>/
    └── <report-date>/
      ├── report.html
      ├── executive-report.pdf (when CISO_PDF_MODE is executive or both)
      ├── full-report.pdf (when CISO_PDF_MODE is full or both)
      ├── data.json (optional; controlled by SAVE_DATA_JSON)
      ├── snapshot.json
      └── run-meta.json
```

Where:
- `<server-id>` is lowercase slug from `SERVER_ID`
- `<report-type-lowercase>` is one of `weekly`, `monthly`, or `custom`
- `<report-date>` is `YYYY-MM-DD`

Local artifact hygiene is mandatory. The output directory for a run must
contain only report artifacts (`report.html`, optional `executive-report.pdf`,
optional `full-report.pdf`, optional `data.json`, `snapshot.json`, `run-meta.json`). Do
NOT persist agent memory files, transcripts, prompts, or debug dumps in this
directory.

Repo existence check, only when Artifactory storage was explicitly requested:

```bash
jf rt curl -s --server-id "<SERVER_ID>" -XGET "/api/repositories/<REPORT_REPO>"
```

Use the direct command form above. Do NOT wrap it in shell variables or
command substitution just to capture the HTTP status.

| Condition | Action |
|-----------|--------|
| Prompt says `local only` | Skip Artifactory storage. |
| Prompt says `save to Artifactory` or names a repo | Use that repo. Check it exists; if 404, ask to create it. |
| No storage preference in prompt | Default to local-only silently. Skip the repo check. |
| Repo check returns `200` | Use it silently. |
| Repo check returns `403` | Continue local-only and tell the user. |

If the user approves creating the default `ciso-reports-local`, run:

```bash
jf rt curl --server-id "$SERVER_ID" -XPUT /api/repositories/ciso-reports-local \
  -H "Content-Type: application/json" \
  -d '{"rclass":"local","packageType":"generic","description":"CISO report HTML and JSON snapshots"}'
```

## Step 4: Download previous snapshot

Look for a prior snapshot in this priority order:

**1. Artifactory (when storage mode is artifactory):**

Download `manifest.json` from `<REPORT_REPO>/<SERVER_ID>/manifest.json` and use the most recent snapshot entry for this report type.
See `references/report-data-collection.md` → "comparison" section.

**2. Local folder scan (always run this if Artifactory is not in use, or if manifest download failed/returned no prior entry):**

```bash
# Find the most recent snapshot.json in LOCAL_ROOT under this server and report type,
# excluding today's date folder.
PREV_SNAPSHOT=$(find "${LOCAL_ROOT}/${SERVER_SLUG}/${REPORT_TYPE_SLUG}" \
  -mindepth 2 -maxdepth 2 \
  -name snapshot.json \
  -not -path "*/${REPORT_DATE}/*" \
  -not -path "*/rerun-*" \
  2>/dev/null \
  | sort | tail -1)

if [ -n "$PREV_SNAPSHOT" ]; then
  cp "$PREV_SNAPSHOT" /tmp/ciso-snapshot.json
  echo "Prior snapshot found locally: $PREV_SNAPSHOT"
else
  echo "No prior snapshot found. comparison.available will be false."
fi
```

If a prior snapshot is found via either path, compute comparison deltas per `references/report-data-collection.md`.
If no previous data from either path: set `comparison.available: false`.

> **Note:** local trend analysis requires a stable `LOCAL_ROOT` across runs. If `LOCAL_ROOT` defaults to `$PWD` and the agent is launched from different directories each time, prior snapshots will not be found and trend comparison will always be empty. Set `CISO_LOCAL_ROOT` to a fixed path (e.g. `~/ciso-reports`) for reliable trend data without Artifactory.

> **Rerun note:** when the current run is itself a rerun (output is going into a `rerun-*` subdirectory), also scan the parent date folder for `snapshot.json` before falling back to the cross-date search. Use the most recent snapshot found — whether from a prior date or the same-date primary run.

## Step 5: Generate the dashboard data and artifacts

The skill stays agentic, but report execution uses a deterministic spine.
The agent resolves the request (server, period, local root, storage choice, and
executive context). The runner owns live collection, pagination, merge order,
validation gates, and template injection.

**Mandatory fresh-run command:**

```bash
SKILL_DIR="$(find ~/.agents/skills -name 'jfrog-ciso-report' -type d 2>/dev/null | head -1)"
if [ -z "$SKILL_DIR" ] || [ ! -f "$SKILL_DIR/bin/generate-ciso-report.sh" ]; then
  SKILL_DIR="./Dashboard-ciso-report-skills"
fi
if [ ! -f "$SKILL_DIR/bin/generate-ciso-report.sh" ]; then
  echo "ERROR: Runner script not found. Verify the skill is installed at ~/.agents/skills/jfrog-ciso-report or at ./Dashboard-ciso-report-skills and retry."
  exit 1
fi
"$SKILL_DIR/bin/generate-ciso-report.sh" "$SERVER_ID" "$LOCAL_ROOT" "$REPORT_TYPE_LOWER"
```

Before running it, export any resolved period values:

```bash
export REPORT_DATE="$REPORT_DATE"
export DATE_FROM="$DATE_FROM"
export DATE_TO="$DATE_TO"
export SAVE_DATA_JSON="$SAVE_DATA_JSON"
```

The runner must:

- Clear stale `/tmp/ciso-*` runtime files before collection.
- Collect live platform metadata, curation audit events, curation policies, and Xray violations.
- Build `/tmp/ciso-data.json`, run platform merge, run `curation-audit-transform`, and populate governance.
- Fail before render if platform, curation, violation, governance, or diagnostics fields are incoherent.
- Render HTML by injecting JSON into `references/dashboard.html`.
- Render PDF by injecting the same JSON into `references/dashboard-pdf.html`
  and running `bin/generate-ciso-pdf.js`. `CISO_PDF_MODE` controls the PDF
  export:
  - unset or `executive`: write CISO-shareable `executive-report.pdf` from
    `dashboard-pdf.html`.
  - `full`: write detailed internal `full-report.pdf` from
    `dashboard-pdf-full.html`.
  - `both`: write `executive-report.pdf` and `full-report.pdf`.
- Write `report.html`, optional `executive-report.pdf`, optional `full-report.pdf`, `data.json`,
  `snapshot.json`, and `run-meta.json`.
- Run the skill-private collection proof helper as a final live proof.

Do **not** manually stitch `report-data-collection.md` snippets for normal report generation. That document is the API/schema mapping reference and debugging guide. Manual snippet execution is allowed only while developing the skill itself.

The report is not valid unless the runner finishes successfully. If it exits
non-zero, stop and report the failing gate; do not generate or hand-edit HTML.

## Step 6: Agent-authored interpretation

After the runner succeeds, inspect the saved `data.json`, `snapshot.json`, and
`run-meta.json`. The agent should then provide the executive interpretation:

- Highlight up to 3 findings per section (security, curation, governance, coverage), ranked first by severity (critical before high), then by absolute delta versus the prior snapshot (largest change first).
- Call out validation proof (for example indexed repos, watches, policies, curation rows, unique users, named policies).
- If needed, improve observations/recommendations in a controlled follow-up pass, then re-run validation/render through the runner or repair helper.

Use `references/report-schema.md` and `references/report-data-collection.md` when interpreting fields or debugging a failed runner gate.

### Manual gates (debugging reference)

Gate implementations (Platform backfill, Gates 1–5, and the collection proof smoke test) are documented in [`references/debugging-gates.md`](references/debugging-gates.md). Run them only when diagnosing a failed runner; they are not a substitute for `bin/generate-ciso-report.sh`.

**Support-only repair path** (not normal user-facing generation): if an already-created report folder is under-enriched, run the repository support tool from the source checkout:

```bash
./scripts/repair-ciso-report.sh "$SERVER_ID" /path/to/<server>/<weekly|monthly|custom>/<date>
```

This helper clears stale `/tmp/ciso-*` files, recollects live curation +
violation + platform data, enriches `data.json`, regenerates `report.html` and
PDF exports, rewrites `snapshot.json` / `run-meta.json`, and runs the
skill-private proof helper. Do not call `internal/enrich-ciso-datajson.sh`
directly; it is a private implementation detail used by the runner.

**Every schema field MUST be present.** Use 0, [], "", null, or false for
unavailable data. The dashboard handles missing data gracefully.

Generate each `observation` string as a single structured sentence ≤320 characters total. Use inline markers `What changed:`, `Why it matters:`, and `Action:`. Include at least one concrete metric, name, package, policy, repository, or XRAY/CVE ID when data exists. If all three markers cannot fit within 320 characters, omit `Action:` and keep the other two. Avoid generic advice.

For `curation.observation`, if `curation.total == 0` but diagnostics confirm
that the API was reachable and the earliest audit event falls after the
requested reporting window, say that explicitly so the user can distinguish a
historically accurate zero from a collection failure.

Example:
`XRAY-123456 accounted for 18 critical hits, mostly in docker-local; prioritize
upgrading log4j-core from 2.14.1 to a fixed version.`

Generate `recommendations` — numbered, actionable items. Include:
- One recommendation per unique critical Xray ID (not just the top one)
- Specific package names, versions, and upgrade targets
- Curation coverage gaps (ecosystems with zero blocks)
- Inactive watches or policies with no resources
- License compliance actions
- Priority labels: P1 (Critical), P2 (High), P3 (Medium)
For each recommendation `detail`, use concise readable structure:
`Impact: ... Next step: ...`
and include at least one concrete identifier (CVE/XRAY/package/repo/policy).

Populate beta fields when available:
- `meta.schema_version`
- `curation.clean_packages` = policy-inspected `approved` outcomes; never use
  `passed`/`without_inspection` as clean
- `curation.request_results.without_inspection`, `top_blocked`,
  `user_package_activity`, waiver counts, policy baseline/cache posture, and
  pass-through repositories
- `benefit.upgrade_rate` from a blocked package later approved at a higher version
- `violations.posture_signals` (independent signals; no composite score),
  `unique_issue_count`, and `top_repos`
- `violations.critical_issues[*].first_seen`, `days_open`, `exploit_status`,
  `affected_environments`, `playbook_link`
- `benefit.roi_estimate`
- `governance.xray_policy_effectiveness` and `governance.curation_policy_effectiveness` (built in `curation-audit-transform`; legacy `policy_effectiveness` = Xray list)
- `governance.repo_watch_coverage`
- `threat_velocity` with a rich `trend_summary` (see below)
- `curation.request_results`, `policy_inventory`, `curation_state`, `policy_violations_by_type`, `blocking_events_per_policy`, `package_types`
- `meta.curation_uninspected_label` = `Passed without inspection`
- `violations.top_cves`, `violations.top_watch_policies`

Optional business context: if the user supplies a JSON mapping file, set
`CISO_REPO_CRITICALITY_JSON` to its path. The file may be an array or an object
with `repositories`/`repo_criticality`; each row uses `repo`,
`business_service`, `criticality`, `environment`, and `owner`. Never infer
business criticality from repository names.

**`threat_velocity.trend_summary` (required when `threat_velocity.available`):** Write 2–4 sentences as the reporting agent, not a stub. Include explicit **from → to** for **blocked**, **violations**, and **critical** using the last two `periods` entries. Add brief interpretation (e.g., gate pressure vs in-repo backlog) and one actionable recommendation grounded in the numbers. Example pattern: “Critical findings moved from 340 to 312 (−8%); curation blocks rose from 198 to 213 (+8%), suggesting stronger gate enforcement while in-repo critical backlog is easing — prioritize remediation on top XRAY IDs and extend dry-run policies to block mode for npm remotes.”

For optional enrichment (exploit status, runbooks, freshness): attempt
collection, but if unavailable, continue and set schema defaults.

Use structured recommendation metadata in addition to text:
- `priority` (P1/P2/P3)
- `effort` (low/medium/high)
- required: `score`
- optional: `owner`, `due_date`, `dependencies`

Beta enforcement: every recommendation MUST include `priority` and `score`.
Validation is covered by Gate 3 above.

> **Note (debugging only):** the runner already writes `/tmp/ciso-snapshot.json` as part of normal execution. The block below is provided only for manually reproducing or validating the snapshot format outside the runner. Do not run this in a normal report generation flow.

Compact comparison snapshot (debug/reference only):

```bash
python3 -c "
import json
data = json.load(open('/tmp/ciso-data.json'))
snap = {
  'date': data['meta']['generated'],
  'type': data['meta']['report_type'].lower(),
  'server_id': data['meta']['server_id'],
  'curation': {
    'total': data['curation']['total'],
    'blocked': data['curation']['blocked'],
    'approved': data['curation']['approved']
  },
  'violations': {
    'total': data['violations']['total'],
    'critical': data['violations']['by_severity']['critical'],
    'high': data['violations']['by_severity']['high'],
    'medium': data['violations']['by_severity']['medium'],
    'low': data['violations']['by_severity']['low']
  },
  'components': len(data.get('operational', {}).get('top_components', [])),
  'license': data['license']['total']
}
json.dump(snap, open('/tmp/ciso-snapshot.json', 'w'), indent=2)
print('Snapshot written to /tmp/ciso-snapshot.json')
"
```

## Step 7: Render and verify artifacts

For normal skill execution, `bin/generate-ciso-report.sh` renders the
interactive HTML and an editorial A4 PDF, writes artifacts, and verifies them.
By default, `executive-report.pdf` is the concise CISO-shareable export. Set
`CISO_PDF_MODE=full` for detailed `full-report.pdf`, or `CISO_PDF_MODE=both` to
emit both PDF exports. Do not run this section separately after the runner
succeeds.

The render implementation (slug exports, `LOCAL_DIR` construction, Python template injection, `run-meta.json` write, and artifact hygiene) lives in `bin/generate-ciso-report.sh`. Refer to that script directly when debugging a render failure.

**Verify the output:**
```bash
echo "=== Verification ==="
grep -c "const DATA = {" "$OUTPUT_PATH"
# Must print: 1
grep -c "buildMast" "$OUTPUT_PATH"
# Must print: 1 or more
wc -l "$OUTPUT_PATH"
# Must be > 1000 lines
python3 -c "from pathlib import Path; p=Path('$PDF_OUTPUT_PATH'); assert p.read_bytes()[:5] == b'%PDF-' and p.stat().st_size > 10000"
```

If verification fails, print the error and stop. Both artifacts must come from
template injection with `__CISO_DATA__`; do not build either report ad hoc.

## Step 8: Upload to Artifactory

If repo exists:
```bash
FOLDER="${SERVER_ID}/${REPORT_TYPE}/${REPORT_DATE}"

# Save snapshot for future comparison
jf rt upload /tmp/ciso-snapshot.json "${REPORT_REPO}/${FOLDER}/snapshot.json" --flat --server-id "$SERVER_ID"
jf rt upload "$OUTPUT_PATH" "${REPORT_REPO}/${FOLDER}/report.html" --flat --server-id "$SERVER_ID"
jf rt upload "$PDF_OUTPUT_PATH" "${REPORT_REPO}/${FOLDER}/executive-report.pdf" --flat --server-id "$SERVER_ID"

# Update manifest
# Update manifest (python3 avoids shell substitution, which IDE agents reject)
python3 -c "
import json, os, sys
p = '/tmp/ciso-manifest.json'
m = json.load(open(p)) if os.path.exists(p) else {'runs': []}
m['runs'].append({'date': sys.argv[1], 'type': sys.argv[2], 'snapshot_path': sys.argv[3], 'report_path': sys.argv[4], 'pdf_path': sys.argv[5]})
json.dump(m, open('/tmp/manifest-updated.json', 'w'), indent=2)
" "$REPORT_DATE" "$REPORT_TYPE" "${FOLDER}/snapshot.json" "${FOLDER}/report.html" "${FOLDER}/executive-report.pdf"
jf rt upload /tmp/manifest-updated.json "${REPORT_REPO}/${SERVER_ID}/manifest.json" --flat --server-id "$SERVER_ID"
```

After a successful upload or local-only run, remove project-local temporary
files if any were created accidentally. Runtime JSON files belong in `/tmp`,
not the project folder.

Final runtime cleanup (last step of the run):

```bash
rm -f /tmp/ciso-data.json /tmp/ciso-snapshot.json /tmp/ciso-token-usage.json /tmp/ciso-curation-diagnostics.json /tmp/ciso-manifest.json /tmp/manifest-updated.json
```

If the run exits early after writing any temporary runtime payloads, run the
same cleanup command before exiting so failed runs do not leak stale data.

Tell the user:
```
Report saved: /<local-root>/<server-id>/weekly/<REPORT_DATE>/report.html
Executive PDF saved: /<local-root>/<server-id>/weekly/<REPORT_DATE>/executive-report.pdf (when CISO_PDF_MODE is executive or both)
Full PDF saved: /<local-root>/<server-id>/weekly/<REPORT_DATE>/full-report.pdf (when CISO_PDF_MODE is full or both)
Data saved: /<local-root>/<server-id>/weekly/<REPORT_DATE>/data.json (only when SAVE_DATA_JSON is on)
Snapshot saved: /<local-root>/<server-id>/weekly/<REPORT_DATE>/snapshot.json
Run metadata: /<local-root>/<server-id>/weekly/<REPORT_DATE>/run-meta.json (includes token_usage.total_tokens when available)
Uploaded to:  ${REPORT_REPO}/<server-id>/weekly/<REPORT_DATE>/
```

## Edge cases

| Situation | Action |
|-----------|--------|
| Template not found | Print error, stop. Do NOT generate HTML. |
| JSON validation fails | Fix the JSON. Do NOT generate HTML. |
| Verification fails | Print error, stop. Do NOT generate HTML. |
| Curation API returns 404 | Set `curation.available: false`. Continue. |
| Xray API returns 404 | Set `violations.total: 0`. Continue. |
| Any API returns empty | Use schema defaults (0, [], null). Continue. |
| Network blocked / sandbox denies outbound API calls | Fail fast. Do NOT fall back to prior run data unless user explicitly requested fallback mode. |
| Fallback mode was used without explicit user request | Treat as contract violation. Fail the run. |
| Previous snapshot missing | Set `comparison.available: false`. Continue. |
| Upload fails (403/409) | Report saved locally. Tell user. Continue. |
| Agent sidecar files appear in output folder | Remove known sidecar patterns and keep only report artifacts. Continue. |

## DO NOT

- Do NOT generate HTML from scratch — ever, under any circumstances
- Do NOT write CSS or JavaScript
- Do NOT create your own report layout
- Do NOT skip the curation API call based on entitlement checks
- Do NOT bypass `bin/generate-ciso-report.sh` with the python3 injection command during normal report generation
- Do NOT modify dashboard.html beyond replacing __CISO_DATA__

## Headless / CI usage

Include server and storage in the prompt for zero interaction:
```bash
claude -p "Generate a weekly CISO report for <server-id>. Save to Artifactory." \
  --allowedTools "Bash(jf *)" "Bash(jq *)" "Bash(eval *)" \
  "Bash(cat *)" "Bash(echo *)" "Bash(date *)" "Bash(sed *)" \
  "Bash(cp *)" "Bash(mkdir *)" "Bash(python3 *)" "Bash(wc *)" \
  "Bash(grep *)" "Bash(find *)" "Read" "Write"
```

> **Note:** The `--allowedTools` flag is specific to the Claude CLI. Other IDE agents (VS Code Copilot, Cursor, etc.) use their own tool-authorization mechanisms — supply the equivalent allow-list for your agent runner.
