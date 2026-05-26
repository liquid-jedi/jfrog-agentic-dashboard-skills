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
5. End-of-run cleanup: transient runtime payloads in `/tmp` must be removed
  as the finalization step after success, and also before exiting on failure
  paths where temporary payloads were written.

## Prerequisites

Read `../jfrog/SKILL.md` for CLI setup. Required on PATH: `jf`, `jq`, `python3`.

**For API paths:** Read `../jfrog/references/xray-entities.md` for the
authoritative curation audit and violations API documentation. Do NOT
hardcode API paths from memory — the base skill has the correct, versioned
paths. Our `report-data-collection.md` maps those API responses to our
JSON schema.

## Workflow

```
1. Determine report type and date range
2. Select server (MANDATORY if multiple)
3. Check/create report storage repo (MANDATORY if first run)
4. Download previous snapshot for comparison
5. Collect data from JFrog APIs
6. Build JSON matching schema → save to /tmp/ciso-data.json
7. Run injection command → creates final HTML report
8. Upload snapshot + report to Artifactory
9. Finalize run: cleanup transient /tmp runtime payloads
```

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
PREV_SNAPSHOT=$(find "${LOCAL_ROOT}/${SERVER_ID}/${REPORT_TYPE_LOWER}" \
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

## Step 5: Collect data

Read `references/report-data-collection.md` for every API call and jq command.

Live data integrity gate (MANDATORY): this report must be built from live API
responses collected in the current run window. If the runtime reports network
blocked/sandboxed execution, connection refused, DNS failures, TLS failures,
or equivalent transport errors, stop immediately and ask the user to allow
network egress for JFrog endpoints before retrying.

**Collect in this exact order:**

1. Platform metadata (repos, watches, policies)
2. **Curation audit events — ALWAYS call this, do NOT skip it, do NOT
   gate it on an entitlement check.** Call the API and check if data comes
   back. If data: curation is enabled. If 404: set available to false.
3. Xray violations (totals, severity, critical issues, repos)
4. License violations
5. Operational risk
6. Compute benefit metrics and comparison deltas

During curation collection, always persist diagnostics to
`/tmp/ciso-curation-diagnostics.json` so payload quality can be validated
before rendering. Include at least:

- `http_status` (last curation API status)
- `mode` (`weekly` or `monthly_chunked`)
- `pages_fetched`
- `rows_fetched`
- `total_count_reported`
- `date_from`, `date_to`

## Step 6: Build JSON

Read `references/report-schema.md` for the complete JSON structure.

Build a single JSON object matching every field in the schema. Save it:

```bash
cat > /tmp/ciso-data.json << 'ENDJSON'
{
  "meta": { ... },
  "platform": { ... },
  "curation": { ... },
  "violations": { ... },
  "license": { ... },
  "operational": { ... },
  "benefit": { ... },
  "governance": { ... },
  "threat_velocity": { ... },
  "comparison": { ... },
  "recommendations": [ ... ]
}
ENDJSON
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

# Curation consistency: available=false while platform shows curation configured.
curation_available = bool(cur.get('available', False))
policy_total = sum(int(plat.get(k, 0) or 0) for k in ('curation_policies_global','curation_policies_repo','curation_policies_user'))
repo_count = int(plat.get('curation_repos_count', 0) or 0)
if not curation_available and (plat.get('curation_enabled') or repo_count > 0 or policy_total > 0):
  print(f'ERROR: curation.available=false but platform shows curation configured (repos={repo_count}, policies={policy_total})'); sys.exit(1)

# Curation zero-plausibility: cross-check diagnostics when present.
diag_path = '/tmp/ciso-curation-diagnostics.json'
if os.path.exists(diag_path):
  diag = json.load(open(diag_path))
  cur_total = int(cur.get('total', 0) or 0)
  rows = int(diag.get('rows_fetched', 0) or 0)
  reported = int(diag.get('total_count_reported', 0) or 0)
  if cur_total == 0 and (rows > 0 or reported > 0):
    print(f'ERROR: curation payload total=0 but diagnostics rows={rows}, reported={reported}'); sys.exit(1)

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

**Every schema field MUST be present.** Use 0, [], "", null, or false for
unavailable data. The dashboard handles missing data gracefully.

Generate each `observation` string as one or two concise, data-driven
sentences. Include at least one concrete metric, name, package, policy,
repository, or XRAY/CVE ID when data exists. Avoid generic advice.

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

Populate beta fields when available:
- `meta.schema_version`
- `curation.approved` and `curation.passed` as separate values
- `violations.risk_score` and `violations.risk_score_previous`
- `violations.critical_issues[*].first_seen`, `days_open`, `exploit_status`,
  `affected_environments`, `playbook_link`
- `benefit.roi_estimate`
- `governance.policy_effectiveness`, `governance.repo_watch_coverage`
- `threat_velocity`

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

## Step 7: Inject JSON into dashboard — EXACT COMMAND

This is the ONLY way to produce the report. Run this exact command:

```bash
SKILL_DIR="$(find ~/.agents/skills -name 'jfrog-ciso-report' -type d 2>/dev/null | head -1)"
[ -z "$SKILL_DIR" ] && SKILL_DIR="./Dashboard-ciso-report-skills"
REPORT_DATE=$(date +%Y-%m-%d)
SERVER_SLUG=$(echo "$SERVER_ID" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')
REPORT_TYPE_SLUG=$(echo "$REPORT_TYPE" | tr '[:upper:]' '[:lower:]')

# LOCAL_ROOT resolution order from Step 3:
# 1) explicit prompt path, 2) CISO_LOCAL_ROOT env, 3) first-run bootstrap prompt
# Example: LOCAL_ROOT="/path/to/ciso-reports"
if [ -z "$LOCAL_ROOT" ]; then
  LOCAL_ROOT="${CISO_LOCAL_ROOT:-}"
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
- Do NOT skip the python3 injection command
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
