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
  version: 2.1.1
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

## Execution checklist

Before collecting data:

- Confirm tools: `jf`, `jq`, and `python3` must be on PATH. If missing,
  stop and tell the user to install/configure them using `../jfrog/SKILL.md`.
- Resolve report period. Default to `weekly`, last 7 days, all repos.
- Resolve server. If multiple JFrog CLI servers exist and the prompt does
  not name one, you MUST stop and ask the user to choose. Do NOT use the
  JFrog CLI default server. Do NOT guess.
- Resolve local output root. You MUST always surface the final resolved
  local path before data collection starts. If no path was provided and
  `CISO_LOCAL_ROOT` is not set, ask once for a stable local root, create it,
  and persist it before data collection starts.
- Resolve storage. If no storage preference is given, default to local-only.
  Do NOT ask about storage unless the user explicitly said "save to Artifactory".

Command style rule for IDE agents such as Cursor:

- Prefer direct single commands over compound shell snippets.
- Do NOT use shell command substitution or probe wrappers such as
  `STATUS=$(...)`, `echo "$PWD"`, or multi-line variable-assignment blocks for
  routine preflight checks.
- When server, repo, or output path are already known, inline the resolved
  values in the command or in the execution summary instead of asking the shell
  to expand them.
- This reduces IDE approval prompts caused by "Contains expansion" checks.

After those checkpoints, execute without further questions. If an API fails,
set that JSON field to `0`, `[]`, `false`, `null`, or `"N/A"` and continue.
Batch `jf` commands into single bash blocks. Pass `--server-id "$SERVER_ID"`
to every `jf` command.

Exception (MANDATORY fail-fast): if failures indicate blocked network,
sandbox denial, DNS/connectivity, TLS handshake issues, or auth transport
errors that prevent live API collection, stop the run and report the error.
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
  file. Only report artifacts (`report.html`, `data.json`, `snapshot.json`,
  `run-meta.json`) and transient `/tmp/ciso-*` files may be created or changed.
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

Execute in order. **Profiles (CISO_REPORT_PROFILE) are parked** — use default layout only.

| Phase | Name | What happens |
|-------|------|----------------|
| **0** | Preflight | Report type, dates, `SERVER_ID`, `LOCAL_ROOT`, storage, prior snapshot lookup |
| **1** | Collect | Run `report-data-collection.md` modules directly (`phase1-collect`, `curation`, `violations`) with no required standalone scripts |
| **2** | Transform | jq mapping + **mandatory** curation audit transform + merge into JSON |
| **3** | Render & publish | Gates, injection, upload, `run-meta.json` |
| **4** | Finalize | Cleanup `/tmp/ciso-*` transient files |

```
Phase 0 → Phase 1 (module tracks in parallel) → Phase 2 (transform) → Phase 3 (render) → Phase 4 (cleanup)
```

Legacy step numbers below map to phases: Steps 1–4 → Phase 0; Step 5 → Phase 1; Step 6 → Phase 2; Steps 7–8 → Phase 3; Step 9 → Phase 4.

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

Do not begin by deleting prior runtime files. For portability and clearer
agent behavior, each run must overwrite runtime payloads during collection
and perform cleanup at the end of the run.

| Prompt says | Type | Window |
|-------------|------|--------|
| "weekly" or "CISO report" | weekly | Last 7 days |
| "monthly" | monthly | Last calendar month |
| "for April" / "for March" | monthly | That month |
| Custom dates | custom | As specified |

`all repos` is the default scope for every report type unless the prompt
explicitly narrows the scope.

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

Use `REPORT_REPO="ciso-reports-local"` unless the prompt names another repo.

Also resolve local output root for every run. This determines where local
artifacts are written even when Artifactory upload is enabled.

Resolve raw DATA persistence mode for local artifacts:

| Condition | Action |
|-----------|--------|
| Prompt explicitly asks to skip raw data file (`no data.json`, `skip raw data`) | Set `SAVE_DATA_JSON=false`. |
| Prompt explicitly asks to keep raw data file (`save data.json`, `keep raw data`) | Set `SAVE_DATA_JSON=true`. |
| `CISO_SAVE_DATA_JSON` env var is set | Use its value (`true/false`). |
| No preference provided | Default to `SAVE_DATA_JSON=true`. |

Resolve token usage capture mode for run metadata:

| Condition | Action |
|-----------|--------|
| `CISO_TOTAL_TOKENS` env var is set | Use that as `token_usage.total_tokens`. |
| `/tmp/ciso-token-usage.json` exists with `total_tokens` | Use that value. |
| Neither exists | Set `token_usage.total_tokens` to `null` and `token_usage.status` to `unavailable`. |

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
      ├── data.json (optional; controlled by SAVE_DATA_JSON)
      ├── snapshot.json
      └── run-meta.json
```

Where:
- `<server-id>` is lowercase slug from `SERVER_ID`
- `<report-type-lowercase>` is one of `weekly`, `monthly`, or `custom`
- `<report-date>` is `YYYY-MM-DD`

Local artifact hygiene is mandatory. The output directory for a run must
contain only report artifacts (`report.html`, optional `data.json`,
`snapshot.json`, `run-meta.json`). Do NOT persist agent memory files,
transcripts, prompts, or debug dumps in this directory.

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

## Step 5: Generate the dashboard data and artifacts

The skill stays agentic, but report execution uses a deterministic spine.
The agent resolves the request (server, period, local root, storage choice, and
executive context). The runner owns live collection, pagination, merge order,
validation gates, and template injection.

**Mandatory fresh-run command:**

```bash
SKILL_DIR="$(find ~/.agents/skills -name 'jfrog-ciso-report' -type d 2>/dev/null | head -1)"
[ -z "$SKILL_DIR" ] && SKILL_DIR="./Dashboard-ciso-report-skills"
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
- Render only by injecting JSON into `references/dashboard.html`.
- Write `report.html`, `data.json`, `snapshot.json`, and `run-meta.json`.
- Run the skill-private collection proof helper as a final live proof.

Do **not** manually stitch `report-data-collection.md` snippets for normal report generation. That document is the API/schema mapping reference and debugging guide. Manual snippet execution is allowed only while developing the skill itself.

The report is not valid unless the runner finishes successfully. If it exits
non-zero, stop and report the failing gate; do not generate or hand-edit HTML.

## Step 6: Agent-authored interpretation

After the runner succeeds, inspect the saved `data.json`, `snapshot.json`, and
`run-meta.json`. The agent should then provide the executive interpretation:

- Highlight the most important security, curation, governance, and coverage signals.
- Call out validation proof (for example indexed repos, watches, policies, curation rows, unique users, named policies).
- If needed, improve observations/recommendations in a controlled follow-up pass, then re-run validation/render through the runner or repair helper.

Use `references/report-schema.md` and `references/report-data-collection.md` when interpreting fields or debugging a failed runner gate.

### Manual gates retained for debugging

The checks below document what the runner enforces. They are not a substitute
for `bin/generate-ciso-report.sh` in normal skill execution.

**Platform backfill (self-heal missing watch/policy/indexed counts):**

```bash
python3 -c "
import json, subprocess, sys

server_id = sys.argv[1]
p = '/tmp/ciso-data.json'
d = json.load(open(p))
plat = d.setdefault('platform', {})
repos_total = int(plat.get('repos_total', 0) or 0)

def jf_get(path):
  proc = subprocess.run(
    ['jf', 'xr', 'curl', '-s', '--server-id', server_id, '-XGET', path],
    capture_output=True, text=True
  )
  if proc.returncode != 0:
    return None
  try:
    return json.loads(proc.stdout or 'null')
  except Exception:
    return None

if repos_total > 0:
  if int(plat.get('repos_indexed', 0) or 0) == 0:
    idx = jf_get('/api/v1/binMgr/default/repos') or {}
    indexed = idx.get('indexed_repos') or []
    plat['repos_indexed'] = len(indexed)
    plat['repos_unindexed'] = max(0, repos_total - int(plat['repos_indexed']))

  if int(plat.get('watches_total', 0) or 0) == 0:
    w = jf_get('/api/v2/watches')
    if isinstance(w, list):
      plat['watches_total'] = len(w)
      plat['watches_active'] = sum(1 for x in w if isinstance(x, dict) and ((x.get('general_data') or {}).get('active') is True))

  if int(plat.get('policies_total', 0) or 0) == 0:
    pol = jf_get('/api/v2/policies')
    if isinstance(pol, list):
      plat['policies_total'] = len(pol)
      plat['policies_security'] = sum(1 for x in pol if isinstance(x, dict) and x.get('type') == 'security')
      plat['policies_operational'] = sum(1 for x in pol if isinstance(x, dict) and x.get('type') == 'operational_risk')
      plat['policies_license'] = sum(1 for x in pol if isinstance(x, dict) and x.get('type') == 'license')

json.dump(d, open(p, 'w'), indent=2)
print('Platform backfill complete')
" "$SERVER_ID"
```

**Gate 1 — JSON validity + risk score normalization (run together):**

```bash
python3 -c "
import json, sys

p = '/tmp/ciso-data.json'
try:
  d = json.load(open(p))
except Exception as e:
  print(f'ERROR: JSON invalid: {e}'); sys.exit(1)

# Normalize risk score in place.
v = d.setdefault('violations', {})
sev = v.get('by_severity', {}) or {}
c = float(sev.get('critical', 0) or 0)
h = float(sev.get('high', 0) or 0)
m = float(sev.get('medium', 0) or 0)
l = float(sev.get('low', 0) or 0)
total = c + h + m + l
raw = (c*100) + (h*20) + (m*5) + (l*1)
score = round((raw / (total*100)) * 100, 1) if total > 0 else 0.0
v['risk_score_raw'] = round(raw, 1)
v['risk_score'] = score
prev = v.get('risk_score_previous', 0)
try: prev = float(prev)
except: prev = 0.0
v['risk_score_previous'] = round(max(0.0, min(100.0, prev)), 1)

# Validate bounds.
for name, val in [('risk_score', v['risk_score']), ('risk_score_previous', v['risk_score_previous'])]:
  if not (0 <= float(val) <= 100):
    print(f'ERROR: {name}={val} out of bounds'); sys.exit(1)

json.dump(d, open(p, 'w'), indent=2)
print(f'Gate 1 passed: JSON valid, risk_score={v[\"risk_score\"]}')
"
```

**Gate 2 — Report type, window, and curation consistency (run together):**

```bash
python3 -c "
import json, sys, os

report_type = sys.argv[1].strip().lower()
d = json.load(open('/tmp/ciso-data.json'))
meta = d.get('meta', {})
plat = d.get('platform', {}) or {}
cur = d.get('curation', {}) or {}

# Report type must match.
meta_type = str(meta.get('report_type', '')).strip().lower()
if meta_type != report_type:
  print(f'ERROR: report_type mismatch: requested={report_type}, meta={meta_type}'); sys.exit(1)

# Window sanity (prevents monthly payload on weekly run).
window_days = int(meta.get('window_days', 0) or 0)
if report_type == 'weekly' and not (6 <= window_days <= 8):
  print(f'ERROR: weekly window_days={window_days}, expected ~7'); sys.exit(1)
if report_type == 'monthly' and window_days < 27:
  print(f'ERROR: monthly window_days={window_days}, expected full-month range'); sys.exit(1)

# Weekly curation API windows must stay <= 168h.
diag_path = '/tmp/ciso-curation-diagnostics.json'
if report_type == 'weekly' and os.path.exists(diag_path):
  from datetime import datetime
  dg = json.load(open(diag_path))
  ds = str(dg.get('date_from', ''))
  de = str(dg.get('date_to', ''))
  if ds and de:
    ds = ds.replace('Z', '+00:00')
    de = de.replace('Z', '+00:00')
    try:
      hours = (datetime.fromisoformat(de) - datetime.fromisoformat(ds)).total_seconds() / 3600.0
      if hours > 168.0:
        print(f'ERROR: weekly curation window is {hours:.1f}h (>168h). Clamp date range before collection.'); sys.exit(1)
    except Exception:
      pass

# Curation consistency: available=false while platform shows curation configured.
curation_available = bool(cur.get('available', False))
policy_total = sum(int(plat.get(k, 0) or 0) for k in ('curation_policies_global','curation_policies_repo','curation_policies_user'))
repo_count = int(plat.get('curation_repos_count', 0) or 0)
if not curation_available and (plat.get('curation_enabled') or repo_count > 0 or policy_total > 0):
  print(f'ERROR: curation.available=false but platform shows curation configured (repos={repo_count}, policies={policy_total})'); sys.exit(1)

# Curation zero-plausibility: cross-check diagnostics when present.
if os.path.exists(diag_path):
  diag = json.load(open(diag_path))
  cur_total = int(cur.get('total', 0) or 0)
  rows = int(diag.get('rows_fetched', 0) or 0)
  reported = int(diag.get('total_count_reported', 0) or 0)
  if cur_total == 0 and (rows > 0 or reported > 0):
    print(f'ERROR: curation payload total=0 but diagnostics rows={rows}, reported={reported}'); sys.exit(1)
elif curation_available:
  print('ERROR: missing /tmp/ciso-curation-diagnostics.json while curation.available=true'); sys.exit(1)

print('Gate 2 passed: report type, window, and curation consistent')
" "$REPORT_TYPE"
```

**Gate 3 — Recommendation metadata:**

```bash
python3 -c "
import json, sys
r = json.load(open('/tmp/ciso-data.json')).get('recommendations', [])
bad = [i for i,x in enumerate(r, start=1) if 'priority' not in x or 'score' not in x]
if bad:
  print(f'ERROR: Missing priority/score in recommendations: {bad}'); sys.exit(1)
print('Gate 3 passed: recommendation metadata valid')
"
```

**Gate 4 — Cross-section data integrity (run together):**

```bash
python3 -c "
import json, sys
d = json.load(open('/tmp/ciso-data.json'))
p = d.get('platform', {}) or {}
c = d.get('curation', {}) or {}
v = d.get('violations', {}) or {}

blocked = int(c.get('blocked', 0) or 0)
approved = int(c.get('approved', 0) or 0)
passed = int(c.get('passed', 0) or 0)
cur_total = int(c.get('total', 0) or 0)
sum_actions = blocked + approved + passed
if cur_total < sum_actions:
  print(f'ERROR: curation.total={cur_total} is less than blocked+approved+passed={sum_actions}'); sys.exit(1)

sev = v.get('by_severity', {}) or {}
sev_sum = sum(int(sev.get(k, 0) or 0) for k in ('critical', 'high', 'medium', 'low'))
v_total = int(v.get('total', 0) or 0)
if sev_sum != v_total:
  print(f'ERROR: violations.total={v_total} does not match by_severity sum={sev_sum}'); sys.exit(1)

bt = v.get('by_type', {}) or {}
type_sum = sum(int(bt.get(k, 0) or 0) for k in ('security', 'operational', 'license'))
if type_sum != v_total:
  print(f'ERROR: violations.total={v_total} does not match by_type sum={type_sum}'); sys.exit(1)

repos_total = int(p.get('repos_total', 0) or 0)
repos_indexed = int(p.get('repos_indexed', 0) or 0)
watches_total = int(p.get('watches_total', 0) or 0)
policies_total = int(p.get('policies_total', 0) or 0)
if repos_total > 0 and repos_indexed == 0 and v_total > 0:
  print('ERROR: repos_indexed is 0 while violations are present; indexed-repos collection likely failed'); sys.exit(1)
if repos_total > 0 and watches_total == 0 and policies_total == 0 and v_total > 0:
  print('ERROR: watches/policies both 0 while violations are present; platform metadata collection likely failed'); sys.exit(1)

print('Gate 4 passed: cross-section data integrity valid')
"
```

**Gate 5 — Platform + curation enrichment (run after transform + guards):**

```bash
python3 -c "
import json, sys
d = json.load(open('/tmp/ciso-data.json'))
p = d.get('platform', {}) or {}
c = d.get('curation', {}) or {}
g = d.get('governance', {}) or {}

if int(p.get('repos_total', 0) or 0) > 0 and int(p.get('repos_indexed', 0) or 0) == 0:
  print('ERROR: repos_indexed still 0 after platform merge'); sys.exit(1)

inv = c.get('policy_inventory') or {}
if int(c.get('blocked', 0) or 0) > 0:
  if not inv.get('total_registered'):
    print('ERROR: policy_inventory missing'); sys.exit(1)
  if not c.get('blocking_events_per_policy'):
    print('ERROR: blocking_events_per_policy missing'); sys.exit(1)
  if int(c.get('unique_users', 0) or 0) == 0 and (c.get('top_users') or []):
    print('ERROR: unique_users=0 but top_users populated'); sys.exit(1)

bad = [r for r in (g.get('curation_policy_effectiveness') or []) if str(r.get('policy','')).lower() == 'unknown']
if bad:
  print('ERROR: governance has Unknown curation rows'); sys.exit(1)

cs = p.get('curation_state') or c.get('curation_state') or {}
if int(cs.get('supported_remote_total', 0) or 0) > 0 and int(cs.get('supported_connected', 0) or 0) == 0:
  print('ERROR: supported_connected=0 while remotes exist — platform merge likely skipped'); sys.exit(1)

print('Gate 5 passed: platform + curation enrichment present')
"
```

Optional live API smoke test before render (debugging only; the runner already runs this):

```bash
"$SKILL_DIR/internal/verify-ciso-collection-proof.sh" "$SERVER_ID"
```

**Support-only repair path** (not normal user-facing generation): if an already-created report folder is under-enriched, run the repository support tool from the source checkout:

```bash
./scripts/repair-ciso-report.sh "$SERVER_ID" /path/to/<server>/<weekly|monthly|custom>/<date>
```

This helper clears stale `/tmp/ciso-*` files, recollects live curation + violation + platform data, enriches `data.json`, regenerates `report.html`, rewrites `snapshot.json` / `run-meta.json`, and runs the skill-private proof helper. Do not call `internal/enrich-ciso-datajson.sh` directly; it is a private implementation detail used by the runner.

**Every schema field MUST be present.** Use 0, [], "", null, or false for
unavailable data. The dashboard handles missing data gracefully.

Generate each `observation` string as one or two concise, data-driven
sentences. Include at least one concrete metric, name, package, policy,
repository, or XRAY/CVE ID when data exists. Avoid generic advice.
Write observations in this readability format (single paragraph, clear markers):
`What changed: ...  Why it matters: ...  Action: ...`
Keep each observation under 320 characters.

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
- `curation.approved` and `curation.passed` as separate values
- `violations.risk_score` and `violations.risk_score_previous`
- `violations.critical_issues[*].first_seen`, `days_open`, `exploit_status`,
  `affected_environments`, `playbook_link`
- `benefit.roi_estimate`
- `governance.xray_policy_effectiveness` and `governance.curation_policy_effectiveness` (built in `curation-audit-transform`; legacy `policy_effectiveness` = Xray list)
- `governance.repo_watch_coverage`
- `threat_velocity` with a rich `trend_summary` (see below)
- `curation.request_results`, `policy_inventory`, `curation_state`, `policy_violations_by_type`, `blocking_events_per_policy`, `package_types`
- `meta.curation_uninspected_label` = `Passed without inspection`
- `violations.top_cves`, `violations.top_watch_policies`

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

Also save a compact comparison snapshot:

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

For normal skill execution, `bin/generate-ciso-report.sh` performs render,
artifact writes, and output verification. Do not run this section separately
after the runner succeeds.

The command below is retained only as a debugging reference for skill
development. It is the render method used by the runner, but it must not be
used to bypass collection or validation gates:

```bash
SKILL_DIR="$(find ~/.agents/skills -name 'jfrog-ciso-report' -type d 2>/dev/null | head -1)"
[ -z "$SKILL_DIR" ] && SKILL_DIR="./Dashboard-ciso-report-skills"
REPORT_DATE="${REPORT_DATE:-$(date +%Y-%m-%d)}"
SERVER_SLUG="${SERVER_SLUG:-$(echo "$SERVER_ID" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')}"
REPORT_TYPE_SLUG="${REPORT_TYPE_SLUG:-$(echo "${REPORT_TYPE:-weekly}" | tr '[:upper:]' '[:lower:]')}"

# LOCAL_ROOT resolution order from Step 3:
# 1) explicit prompt path, 2) CISO_LOCAL_ROOT env, 3) first-run bootstrap prompt
# Example: LOCAL_ROOT="/path/to/ciso-reports"
if [ -z "$LOCAL_ROOT" ]; then
  LOCAL_ROOT="${CISO_LOCAL_ROOT:-}"
fi

if [ -z "$LOCAL_ROOT" ]; then
  echo "ERROR: LOCAL_ROOT is empty. Ask for a stable local root (recommended: ~/ciso-reports) before continuing."
  exit 1
fi
if [ "$LOCAL_ROOT" = "$HOME" ] && [ "${CISO_ALLOW_HOME_ROOT:-false}" != "true" ]; then
  echo "ERROR: LOCAL_ROOT resolves to \$HOME ($HOME). Use a dedicated folder (recommended: ~/ciso-reports) or set CISO_ALLOW_HOME_ROOT=true explicitly."
  exit 1
fi

if [ -z "$SAVE_DATA_JSON" ]; then
  SAVE_DATA_JSON="${CISO_SAVE_DATA_JSON:-true}"
fi
SAVE_DATA_JSON=$(echo "$SAVE_DATA_JSON" | tr '[:upper:]' '[:lower:]')
case "$SAVE_DATA_JSON" in
  1|true|yes|on) SAVE_DATA_JSON="true" ;;
  0|false|no|off) SAVE_DATA_JSON="false" ;;
  *) SAVE_DATA_JSON="true" ;;
esac

LOCAL_DIR="${LOCAL_ROOT%/}/${SERVER_SLUG}/${REPORT_TYPE_SLUG}/${REPORT_DATE}"
mkdir -p "$LOCAL_DIR"

OUTPUT_PATH="${LOCAL_DIR}/report.html"
DATA_COPY_PATH="${LOCAL_DIR}/data.json"
SNAPSHOT_COPY_PATH="${LOCAL_DIR}/snapshot.json"
RUN_META_PATH="${LOCAL_DIR}/run-meta.json"

if [ -f "$OUTPUT_PATH" ]; then
  RERUN_DIR="${LOCAL_DIR}/rerun-$(date +%H%M%S)"
  mkdir -p "$RERUN_DIR"
  OUTPUT_PATH="${RERUN_DIR}/report.html"
  DATA_COPY_PATH="${RERUN_DIR}/data.json"
  SNAPSHOT_COPY_PATH="${RERUN_DIR}/snapshot.json"
  RUN_META_PATH="${RERUN_DIR}/run-meta.json"
  echo "Existing report found for this server/type/date. Writing rerun to: $RERUN_DIR"
fi

TMP_OUTPUT="/tmp/.ciso-report-${SERVER_SLUG}-${REPORT_TYPE_SLUG}-${REPORT_DATE}-$$.html"

python3 -c "
import sys, os
template_path = sys.argv[1]
data_path = sys.argv[2]
output_path = sys.argv[3]
template = open(template_path, 'r').read()
data = open(data_path, 'r').read().strip()
if '__CISO_DATA__' not in template:
    print('ERROR: Template missing __CISO_DATA__ placeholder')
    sys.exit(1)
result = template.replace('__CISO_DATA__', data)
open(output_path, 'w').write(result)
print(f'Report written to {output_path} ({len(result)} bytes)')
" "$SKILL_DIR/references/dashboard.html" "/tmp/ciso-data.json" "$TMP_OUTPUT"

mv "$TMP_OUTPUT" "$OUTPUT_PATH"
if [ "$SAVE_DATA_JSON" = "true" ]; then
  cp /tmp/ciso-data.json "$DATA_COPY_PATH"
fi
cp /tmp/ciso-snapshot.json "$SNAPSHOT_COPY_PATH"

TOKEN_TOTAL=""
TOKEN_SOURCE="unavailable"
if [ -n "$CISO_TOTAL_TOKENS" ]; then
  TOKEN_TOTAL="$CISO_TOTAL_TOKENS"
  TOKEN_SOURCE="env:CISO_TOTAL_TOKENS"
elif [ -f /tmp/ciso-token-usage.json ]; then
  TOKEN_TOTAL=$(jq -r '.total_tokens // empty' /tmp/ciso-token-usage.json 2>/dev/null)
  if [ -n "$TOKEN_TOTAL" ]; then
    TOKEN_SOURCE="/tmp/ciso-token-usage.json"
  fi
fi

python3 -c "
import json, sys

run_meta_path = sys.argv[1]
server_id = sys.argv[2]
server_slug = sys.argv[3]
report_type = sys.argv[4]
report_date = sys.argv[5]
local_root = sys.argv[6]
output_path = sys.argv[7]
save_data_json = sys.argv[8].lower() == 'true'
token_total = sys.argv[9]
token_source = sys.argv[10]

diag_path = '/tmp/ciso-curation-diagnostics.json'
curation_diag = {
  'status': 'unavailable'
}
try:
  diag = json.load(open(diag_path))
  curation_diag = {
    'status': 'captured',
    'http_status': diag.get('http_status'),
    'mode': diag.get('mode'),
    'pages_fetched': diag.get('pages_fetched'),
    'rows_fetched': diag.get('rows_fetched'),
    'total_count_reported': diag.get('total_count_reported'),
    'date_from': diag.get('date_from'),
    'date_to': diag.get('date_to')
  }
except Exception:
  pass

meta = {
  'server_id': server_id,
  'server_slug': server_slug,
  'report_type': report_type,
  'report_date': report_date,
  'local_root': local_root,
  'output_path': output_path,
  'save_data_json': save_data_json,
  'data_source': 'live',
  'fallback_mode': {
    'used': False,
    'user_requested': False
  },
  'token_usage': {
    'total_tokens': int(token_total) if token_total.isdigit() else None,
    'source': token_source,
    'status': 'captured' if token_total.isdigit() else 'unavailable'
  },
  'curation_diagnostics': curation_diag
}

json.dump(meta, open(run_meta_path, 'w'), indent=2)
print('Run metadata written to', run_meta_path)
" "$RUN_META_PATH" "$SERVER_ID" "$SERVER_SLUG" "$REPORT_TYPE" "$REPORT_DATE" "$LOCAL_ROOT" "$OUTPUT_PATH" "$SAVE_DATA_JSON" "$TOKEN_TOTAL" "$TOKEN_SOURCE"

echo "Final report path: $OUTPUT_PATH"
echo "Local artifacts saved under: $(dirname "$OUTPUT_PATH")"

# Enforce local artifact hygiene in the run folder.
ARTIFACT_DIR="$(dirname "$OUTPUT_PATH")"
REMOVED=0
for pat in \
  '.cursor*' \
  '.copilot*' \
  'memory*.json' \
  'memory*.md' \
  'transcript*.json' \
  'transcript*.jsonl' \
  'chat*.json' \
  'chat*.md' \
  'prompt*.txt' \
  'session*.json' \
  'run-*.log'
do
  for f in "$ARTIFACT_DIR"/$pat; do
    [ -e "$f" ] || continue
    rm -f "$f"
    REMOVED=$((REMOVED+1))
  done
done

if [ "$REMOVED" -gt 0 ]; then
  echo "Local artifact hygiene: removed $REMOVED non-report sidecar file(s) from $ARTIFACT_DIR"
fi
```

**Verify the output:**
```bash
echo "=== Verification ==="
grep -c "const DATA = {" "$OUTPUT_PATH"
# Must print: 1
grep -c "buildSidebar" "$OUTPUT_PATH"
# Must print: 1 or more
wc -l "$OUTPUT_PATH"
# Must be > 1000 lines
```

If verification fails, print the error and stop. The only valid report path
is template injection with `__CISO_DATA__`.

## Step 8: Upload to Artifactory

If repo exists:
```bash
FOLDER="${SERVER_ID}/${REPORT_TYPE}/${REPORT_DATE}"

# Save snapshot for future comparison
jf rt upload /tmp/ciso-snapshot.json "${REPORT_REPO}/${FOLDER}/snapshot.json" --flat --server-id "$SERVER_ID"
jf rt upload "$OUTPUT_PATH" "${REPORT_REPO}/${FOLDER}/report.html" --flat --server-id "$SERVER_ID"

# Update manifest
MANIFEST=$(cat /tmp/ciso-manifest.json 2>/dev/null || echo '{"runs":[]}')
echo "$MANIFEST" | jq --arg d "$REPORT_DATE" --arg t "$REPORT_TYPE" \
  --arg sp "${FOLDER}/snapshot.json" --arg rp "${FOLDER}/report.html" \
  '.runs += [{"date":$d,"type":$t,"snapshot_path":$sp,"report_path":$rp}]' \
  > /tmp/manifest-updated.json
jf rt upload /tmp/manifest-updated.json "${REPORT_REPO}/${SERVER_ID}/manifest.json" --flat --server-id "$SERVER_ID"
```

After a successful upload or local-only run, remove project-local temporary
files if any were created accidentally. Runtime JSON files belong in `/tmp`,
not the project folder.

Final runtime cleanup (last step of the run):

```bash
rm -f /tmp/ciso-data.json /tmp/ciso-snapshot.json /tmp/ciso-token-usage.json /tmp/ciso-curation-diagnostics.json
```

If the run exits early after writing any temporary runtime payloads, run the
same cleanup command before exiting so failed runs do not leak stale data.

Tell the user:
```
Report saved: /<local-root>/<server-id>/weekly/2026-04-24/report.html
Data saved: /<local-root>/<server-id>/weekly/2026-04-24/data.json (only when SAVE_DATA_JSON is on)
Snapshot saved: /<local-root>/<server-id>/weekly/2026-04-24/snapshot.json
Run metadata: /<local-root>/<server-id>/weekly/2026-04-24/run-meta.json (includes token_usage.total_tokens when available)
Uploaded to:  ${REPORT_REPO}/<server-id>/weekly/2026-04-24/
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
