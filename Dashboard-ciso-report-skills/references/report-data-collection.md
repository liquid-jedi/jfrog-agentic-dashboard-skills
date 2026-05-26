# Data Collection — API to JSON Mapping

How to fill every field in the JSON schema from JFrog APIs.
All calls use `jf rt curl` or `jf xr curl` with the configured server.

## Contents

- Important: Curation Detection
- meta
- platform
- curation
- violations
- license
- operational
- benefit
- comparison
- Storage upload
- Error handling

## Important: Curation Detection

**Do NOT gate curation on the entitlement check.** The `/api/system/version`
addons field may not list "curation" even when curation is active.

Instead: always call the curation audit API. If the API returns `200` with
a JSON body containing `data` or `meta`, curation is reachable. If it returns
404/403, set `available: false`.

## meta

```bash
SERVER_ID=$(jf config show 2>/dev/null | awk '/^Server ID:/{id=$NF} /^Default:.*true/{print id; exit}')
JFROG_URL=$(jf config show "$SERVER_ID" 2>/dev/null | grep "JFrog Platform URL:" | head -1 | awk '{print $NF}')
HOST=$(echo "$JFROG_URL" | sed 's|https://||;s|/$||')
```

Date computation (macOS):
```bash
DATE_FROM=$(date -v-${DAYS}d +%Y-%m-%dT00:00:00.000Z)
DATE_TO=$(date +%Y-%m-%dT23:59:59.999Z)
```

Date computation (Linux):
```bash
DATE_FROM=$(date -u -d "${DAYS} days ago" +%Y-%m-%dT00:00:00.000Z)
DATE_TO=$(date -u +%Y-%m-%dT23:59:59.999Z)
```

## platform

### All repos
```bash
jf rt curl -s --server-id "$SERVER_ID" -XGET /api/repositories | jq '[.[] | {key, type, packageType}]'
```
Derive: `repos_total` = length, `repo_types` = unique packageType values.

### Xray indexed repos
```bash
jf xr curl -s --server-id "$SERVER_ID" "/api/v1/binMgr/default/repos" | jq '[.indexed_repos[]?.name]'
```
Derive: `repos_indexed` = length, `repos_unindexed` = all repo keys minus indexed.

### Watches
```bash
jf xr curl -s --server-id "$SERVER_ID" "/api/v2/watches" | jq '{
  total: length,
  active: [.[] | select(.general_data.active == true)] | length
}'
```

### Policies
```bash
jf xr curl -s --server-id "$SERVER_ID" "/api/v2/policies" | jq '{
  total: length,
  security: [.[] | select(.type == "security")] | length,
  operational_risk: [.[] | select(.type == "operational_risk")] | length,
  license: [.[] | select(.type == "license")] | length
}'
```

### Curation policies (sidebar counts)
```bash
jf xr curl -s --server-id "$SERVER_ID" "/api/v1/curation/policies" 2>/dev/null | jq '{
  global: [.[] | select(.scope == "global")] | length,
  repo: [.[] | select(.scope == "repository")] | length,
  user: [.[] | select(.scope == "user")] | length
}'
```
If 404/403: set all policy counts to 0, show "Not configured" in sidebar.

## curation

**Authoritative API docs:** Read `../jfrog/references/xray-entities.md` → "Curation audit events".

### API path and parameters

```
GET /xray/api/v1/curation/audit/packages
```

**Critical constraints:**
- Max time window per request: **168 hours (7 days)**. Wider ranges return an error.
- For weekly reports: one request covers the full period.
- For monthly reports: split into 6-day chunks and merge results.
- Max `num_of_rows`: 2000. Use `offset` for pagination.
- Pass `--server-id "$SERVER_ID"` to every call.

### Collecting curation data (weekly = one window with pagination)

```bash
LIMIT=2000
OFFSET=0
rm -f /tmp/ciso-curation-pages.jsonl
while :; do
  RESP=$(jf xr curl -s --server-id "$SERVER_ID" -XGET \
    "/api/v1/curation/audit/packages?order_by=id&direction=desc&num_of_rows=${LIMIT}&created_at_start=${DATE_FROM}&created_at_end=${DATE_TO}&include_total=true&offset=${OFFSET}")
  echo "$RESP" >> /tmp/ciso-curation-pages.jsonl
  COUNT=$(echo "$RESP" | jq '(.data // []) | length')
  [ "$COUNT" -lt "$LIMIT" ] && break
  OFFSET=$((OFFSET + LIMIT))
done
jq -s '{data: map(.data // []) | add, meta: {total_count: (map(.meta.total_count // 0) | max)}}' \
  /tmp/ciso-curation-pages.jsonl > /tmp/ciso-curation.json

# Write diagnostics for payload-quality guards
python3 -c "
import json
pages=[json.loads(x) for x in open('/tmp/ciso-curation-pages.jsonl') if x.strip()]
rows=sum(len((p.get('data') or [])) for p in pages)
reported=max([(p.get('meta') or {}).get('total_count', 0) for p in pages] + [0])
diag={
  'http_status': 200,
  'mode': 'weekly',
  'pages_fetched': len(pages),
  'rows_fetched': rows,
  'total_count_reported': reported,
  'date_from': '${DATE_FROM}',
  'date_to': '${DATE_TO}'
}
json.dump(diag, open('/tmp/ciso-curation-diagnostics.json', 'w'), indent=2)
print('Curation diagnostics written to /tmp/ciso-curation-diagnostics.json')
"
```

### Collecting curation data (monthly = chunked)

Split the date range into 6-day windows. For each chunk, run the same
pagination loop with `CHUNK_START` and `CHUNK_END`:
```bash
jf xr curl -s --server-id "$SERVER_ID" -XGET \
  "/api/v1/curation/audit/packages?order_by=id&direction=desc&num_of_rows=2000&created_at_start=${CHUNK_START}&created_at_end=${CHUNK_END}&include_total=true&offset=0"
```
Merge all `.data[]` arrays. For the total, sum each chunk/window
`meta.total_count` after pagination; do not use only the first chunk.

After chunk merge, write diagnostics to `/tmp/ciso-curation-diagnostics.json`.
Include at least: `http_status`, `mode`, `pages_fetched`, `rows_fetched`,
`total_count_reported`, `date_from`, `date_to`.

Example:

```bash
python3 -c "
import json, glob

# Assumes each fetched chunk/page response is captured in jsonl files.
files=glob.glob('/tmp/ciso-curation-*.jsonl')
pages=[]
for f in files:
  for line in open(f):
    line=line.strip()
    if line:
      pages.append(json.loads(line))

rows=sum(len((p.get('data') or [])) for p in pages)
reported=sum(int((p.get('meta') or {}).get('total_count', 0) or 0) for p in pages)

diag={
  'http_status': 200,
  'mode': 'monthly_chunked',
  'pages_fetched': len(pages),
  'rows_fetched': rows,
  'total_count_reported': reported,
  'date_from': '${DATE_FROM}',
  'date_to': '${DATE_TO}'
}
json.dump(diag, open('/tmp/ciso-curation-diagnostics.json', 'w'), indent=2)
print('Curation diagnostics written to /tmp/ciso-curation-diagnostics.json')
"
```

If curation API returns 404/403, still write diagnostics with:

```json
{
  "http_status": 404,
  "mode": "weekly",
  "pages_fetched": 0,
  "rows_fetched": 0,
  "total_count_reported": 0,
  "date_from": "<DATE_FROM>",
  "date_to": "<DATE_TO>"
}
```

### Response shape

```json
{
  "data": [
    {
      "id": 32116,
      "created_at": "2026-04-23T23:18:32Z",
      "action": "blocked",
      "package_type": "npm",
      "package_name": "minimatch",
      "package_version": "3.0.4",
      "curated_repository_name": "npm-remote",
      "username": "dev@company.com",
      "user_mail": "dev@company.com",
      "policies": [
        {
          "policy_name": "block-malicious",
          "condition_name": "Malicious package",
          "condition_category": "security"
        }
      ]
    }
  ],
  "meta": { "total_count": 14081 }
}
```

**Action values:** `"blocked"` | `"approved"` | `"passed"` (no policy match).
- For this schema: keep `approved` and `passed` separate.

### Parse and map to JSON schema

```bash
jq '{
  available: true,
  total: (.meta.total_count // ((.data // []) | length)),
  blocked: [(.data // [])[] | select(((.action // .status // "") | ascii_downcase) == "blocked")] | length,
  approved: [(.data // [])[] | select(((.action // .status // "") | ascii_downcase) == "approved")] | length,
  passed: [(.data // [])[] | select(((.action // .status // "") | ascii_downcase) == "passed")] | length,

  by_reason: {
    malicious: [(.data // [])[] | select(((.action // .status // "") | ascii_downcase) == "blocked")
      | (.policies // [])[]
      | select((.condition_category // "" | test("malicious";"i"))
        or (.condition_name // "" | test("malicious";"i"))
        or (.policy_name // "" | test("malicious";"i")))] | length,
    security: [(.data // [])[] | select(((.action // .status // "") | ascii_downcase) == "blocked")
      | (.policies // [])[] | select(.condition_category == "security")] | length,
    license: [(.data // [])[] | select(((.action // .status // "") | ascii_downcase) == "blocked")
      | (.policies // [])[] | select(.condition_category == "license")] | length,
    operational: [(.data // [])[] | select(((.action // .status // "") | ascii_downcase) == "blocked")
      | (.policies // [])[] | select(.condition_category == "operational")] | length
  },

  top_blocked: [(.data // [])[] | select(((.action // .status // "") | ascii_downcase) == "blocked")
    | {name: .package_name, type: .package_type,
       policy: ((.policies // [])[0].policy_name // "unknown"),
       malicious: ((.policies // []) | any(
         (.condition_category // "" | test("malicious";"i"))
         or (.condition_name // "" | test("malicious";"i"))
         or (.policy_name // "" | test("malicious";"i"))))}]
    | sort_by(.name)
    | group_by(.name)
    | map({package: .[0].name, ecosystem: .[0].type, count: length,
           policies: ([.[].policy] | unique | join(", ")),
           malicious: any(.[]; .malicious)})
    | sort_by(-.count),

  by_type: [(.data // [])[] | {type: .package_type, action: ((.action // .status // "") | ascii_downcase)}]
    | sort_by(.type)
    | group_by(.type)
    | map({type: .[0].type,
           total: length,
           blocked: [.[] | select(.action == "blocked")] | length})
    | sort_by(-.blocked),

  audit_events: [(.data // [])[] | {
    status: ((.action // .status // "") | ascii_downcase),
    package: .package_name,
    version: .package_version,
    type: .package_type,
    repo: .curated_repository_name,
    policy: ((.policies // [])[0].policy_name // "—"),
    requested_by: (.username // .user_mail // "—"),
    date: (.created_at // "")[0:10],
    timestamp: (.created_at // "")
  }] | sort_by(.timestamp) | reverse
}'
```

### Derived fields
- `block_rate`: `blocked / total * 100` (use `meta.total_count` for total)
- `curated_types`: unique `.package_type` values from `.data[]` (for sidebar pills)
- `curation_repos_count`: unique `.curated_repository_name` values from `.data[]`
- If `blocked > 0` but `audit_events` ends up empty after parsing, do NOT emit
  "no blocked events". Populate summary data from `by_reason`, `by_type`, and
  `top_blocked` so the report still reflects blocked activity.
- If API returns 404: set `curation.available: false`, all counts to 0. Continue with other sections.
- Do not merge `approved` and `passed` in beta JSON output.

## violations

**Authoritative API docs:** Read `../jfrog/references/xray-entities.md` → "Violations" → "API: POST /api/v1/violations".

```bash
jf xr curl -s --server-id "$SERVER_ID" -XPOST "/api/v1/violations" \
  -H "Content-Type: application/json" \
  -d "{\"filters\":{\"created_from\":\"${DATE_FROM}\",\"created_until\":\"${DATE_TO}\"},\"pagination\":{\"limit\":500,\"order_by\":\"severity\",\"direction\":\"desc\"}}"
```

**Performance note:** Always include `created_from` to avoid timeouts on large instances.

For large instances, paginate until the response returns fewer than `limit`
violations. Merge all `.violations[]` arrays and keep the maximum
`.total_violations` value:

```bash
LIMIT=500
OFFSET=0
rm -f /tmp/ciso-violations-pages.jsonl
while :; do
  RESP=$(jf xr curl -s --server-id "$SERVER_ID" -XPOST "/api/v1/violations" \
    -H "Content-Type: application/json" \
    -d "{\"filters\":{\"created_from\":\"${DATE_FROM}\",\"created_until\":\"${DATE_TO}\"},\"pagination\":{\"limit\":${LIMIT},\"offset\":${OFFSET},\"order_by\":\"severity\",\"direction\":\"desc\"}}")
  echo "$RESP" >> /tmp/ciso-violations-pages.jsonl
  COUNT=$(echo "$RESP" | jq '(.violations // []) | length')
  [ "$COUNT" -lt "$LIMIT" ] && break
  OFFSET=$((OFFSET + LIMIT))
done
jq -s '{violations: map(.violations // []) | add, total_violations: (map(.total_violations // 0) | max)}' \
  /tmp/ciso-violations-pages.jsonl > /tmp/ciso-violations.json
```

Parse:
```bash
jq '{
  total: (.total_violations // (.violations | length)),
  risk_score_raw: (
    ([.violations[]? | select(.severity == "Critical")] | length) * 100 +
    ([.violations[]? | select(.severity == "High")] | length) * 20 +
    ([.violations[]? | select(.severity == "Medium")] | length) * 5 +
    ([.violations[]? | select(.severity == "Low")] | length)
  ),
  by_severity: {
    critical: [(.violations // [])[] | select(.severity == "Critical")] | length,
    high: [(.violations // [])[] | select(.severity == "High")] | length,
    medium: [(.violations // [])[] | select(.severity == "Medium")] | length,
    low: [(.violations // [])[] | select(.severity == "Low")] | length
  },
  by_type: {
    security: [(.violations // [])[] | select(.type == "Security")] | length,
    operational: [(.violations // [])[] | select(.type == "Operational Risk")] | length,
    license: [(.violations // [])[] | select(.type == "License")] | length
  },
  violation_details: [(.violations // [])[] | {
    issue_id: .issue_id, cve: (.cve // .issue_id), severity: .severity,
    cvss: (.cvss_v3 // .cvss_v2 // "N/A"), type: .type,
    component: (.infected_components[0] // .component // "unknown"),
    watch: (.watch_name // "—"), description: (.description // "")[0:150]
  }] | sort_by(if .severity == "Critical" then 0 elif .severity == "High" then 1 else 2 end)
  | .[0:20],
  unique_components: [(.violations // [])[] | .component // empty] | unique | length,
  unique_issues: [(.violations // [])[] | .issue_id // empty] | unique | length
}'
```

Risk score should be normalized to 0-100 for dashboard readability:

```text
risk_score = round((risk_score_raw / (total_violations * 100)) * 100, 1)
```

If `total_violations` is 0, set `risk_score = 0`.

### severity_pct
Compute `count / security_total * 100` per severity level.

### critical_issues
Group violations by `issue_id` where severity = Critical, count hits per ID:
```bash
jq '[(.violations // [])[] | select(.severity == "Critical")
  | {
      id: .issue_id,
      desc: (.description // "See Xray console")[0:120],
      first_seen: ((.created // .created_at // "")[0:10]),
      exploit_status: (.exploit_status // "unknown"),
      affected_environments: (.affected_environments // []),
      playbook_link: (.playbook_link // null)
    }]
  | sort_by(.id)
  | group_by(.id)
  | map({
      id: .[0].id,
      description: .[0].desc,
      hits: length,
      first_seen: .[0].first_seen,
      days_open: 0,
      exploit_status: .[0].exploit_status,
      affected_environments: .[0].affected_environments,
      playbook_link: .[0].playbook_link
    })
  | sort_by(-.hits)'
```

If external enrichment is unavailable, keep `exploit_status: "unknown"`,
`affected_environments: []`, and `playbook_link: null`.

### top_repos
Group by impacted artifact display name, count:
```bash
jq '[(.violations // [])[] | (.impacted_artifacts // [])[] | .display_name // "unknown"]
  | sort_by(.)
  | group_by(.) | map({repo: .[0], count: length}) | sort_by(-.count) | .[0:10]'
```

## license

Filter violations where type = "License":
```bash
jq '{
  total: [(.violations // [])[] | select(.type == "License")] | length,
  licenses: [(.violations // [])[] | select(.type == "License") | .license_name // "Unknown"]
    | sort_by(.)
    | group_by(.) | map({spdx: .[0], name: "", count: length, severity: "High"})
    | sort_by(-.count)
}'
```

## operational

Filter violations where type = "Operational Risk":
```bash
jq '{
  total: [(.violations // [])[] | select(.type == "Operational Risk")] | length,
  top_components: [(.violations // [])[] | select(.type == "Operational Risk") | .component // "unknown"]
    | sort_by(.)
    | group_by(.) | map({component: .[0], hits: length}) | sort_by(-.hits) | .[0:10],
  top_locations: [(.violations // [])[] | select(.type == "Operational Risk")
    | (.impacted_artifacts // [])[] | .display_name // "unknown"]
    | sort_by(.)
    | group_by(.) | map({location: .[0], hits: length}) | sort_by(-.hits) | .[0:10]
}'
```

## benefit (derived metrics)

Computed by the agent from collected data:

- `curation_headline`: "Stopped {blocked} packages before entering any repository"
- `xray_headline`: "Surfaced {total} violations across {unique_components} components"
- `compare_line`: "Curation stopped {blocked} at the gate. Xray found {total} already inside."
- `cves_prevented`: count of unique CVE reasons in blocked package reasons
- `upgrade_rate`: detect block-then-upgrade (same package blocked at version X, later approved at version Y). Rate = upgrades / unique blocked packages * 100
- `xray_coverage`: (repos_indexed / repos_total) * 100
- `roi_estimate`: optional deterministic estimate for beta.

Recommended beta heuristic:
```
cost_avoided_usd = blocked * 2500
calculation_basis = "beta heuristic: blocked_packages * 2500"
confidence = "low"
```

If not used, set zero defaults.

### Block-then-upgrade detection
For each unique blocked package name, check if the same package appears in
approved events at a different (higher) version. Record: package,
blocked_version, upgraded_version, days_between.

## comparison

### Download previous snapshot
```bash
REPORT_REPO="${REPORT_REPO:-ciso-reports-local}"
jf rt dl "${REPORT_REPO}/${SERVER_ID}/manifest.json" /tmp/ciso-manifest.json --flat 2>/dev/null
PREV_PATH=$(jq -r --arg t "$REPORT_TYPE" '[.runs[] | select(.type == $t)] | sort_by(.date) | last | .snapshot_path // empty' /tmp/ciso-manifest.json 2>/dev/null)
[ -n "$PREV_PATH" ] && jf rt dl "${REPORT_REPO}/${PREV_PATH}" /tmp/ciso-prev-snapshot.json --flat 2>/dev/null
```

If previous snapshot exists, compute deltas:
```
For each metric (Packages Blocked, Violations, Critical):
  change_pct = previous > 0 ? round((current - previous) / previous * 100) : 0
  direction = current > previous ? "up" : current < previous ? "down" : "flat"
  good = depends on metric:
    - Violations/critical going down = good
    - Violations/critical going up = bad
    - Blocked going up = neutral (could mean more threats OR better detection)
```

If no previous data: `comparison.available: false`.

Also compute `risk_score_previous` when previous snapshot contains
`violations.risk_score`.

## governance

### policy_effectiveness

Group policy/watch hits and compute share + delta.

```json
{
  "policy": "block-malicious",
  "type": "security",
  "hits": 182,
  "pct_of_events": 31,
  "delta_pct": -5
}
```

If no previous data, set `delta_pct: 0`.

### repo_watch_coverage

Build a risk-prioritized list of repositories with watch depth.

```json
{
  "repo": "docker-local",
  "indexed": true,
  "watch_count": 3,
  "risk_level": "high"
}
```

## threat_velocity

Build rolling periods from historical snapshots.

```json
{
  "available": true,
  "periods": [
    {"label":"2026-W16","blocked":71,"violations":163,"critical":18},
    {"label":"2026-W17","blocked":77,"violations":154,"critical":16},
    {"label":"2026-W18","blocked":80,"violations":149,"critical":14},
    {"label":"2026-W19","blocked":82,"violations":141,"critical":12}
  ],
  "trend_summary": "Critical findings decreased for four consecutive periods while blocked packages increased modestly."
}
```

If fewer than 2 prior snapshots exist, set `available: false` and empty lists.

## recommendations metadata

Add structured metadata fields to each recommendation:
- `priority`: `P1|P2|P3` (required)
- `effort`: `low|medium|high`
- `owner`, `due_date`, `dependencies`
- `score` (required)

### recommendation score (data-driven)

Compute recommendation ranking score from observed risk factors:

```text
score =
  (critical_hits * 10) +
  (high_hits * 4) +
  (medium_hits * 2) +
  (exploit_active ? 30 : exploit_poc ? 10 : 0) +
  (in_prod ? 20 : 0) +
  (coverage_gap ? 15 : 0)
```

Map score to priority:
- `P1`: `score >= 80`
- `P2`: `score >= 40 and < 80`
- `P3`: `score < 40`

Always prefer this score-derived priority over title-based heuristics.

## methodology (optional, configurable explanations)

The dashboard supports a configurable methodology block so each organization
can tune explanations and thresholds without changing template code:

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

If omitted, renderer defaults are applied.

### beta producer validation (hard-fail)

Before template injection, validate recommendation metadata strictly.
If any recommendation is missing `priority` or `score`, fail generation:

```bash
python3 -c "
import json, sys
data=json.load(open('/tmp/ciso-data.json'))
recs=data.get('recommendations', [])
bad=[i for i,r in enumerate(recs, start=1) if 'priority' not in r or 'score' not in r]
if bad:
  print(f'ERROR: Missing priority/score in recommendations at positions: {bad}')
  sys.exit(1)
print('Recommendation metadata valid')
"
```

### Snapshot JSON (saved for future comparison)
```json
{
  "date": "2026-04-24", "type": "weekly", "server_id": "<server-id>",
  "curation": { "total": 9959, "blocked": 82, "approved": 116 },
  "violations": { "total": 141, "critical": 15, "high": 95, "medium": 29, "low": 2 },
  "components": 88, "secrets": 2
}
```

## Storage upload

### Folder structure
```
${REPORT_REPO}/
├── <server-id-a>/
│   ├── weekly/2026-04-14/snapshot.json, report.html
│   ├── weekly/2026-04-21/snapshot.json, report.html
│   ├── monthly/2026-04/snapshot.json, report.html
│   └── manifest.json
├── <server-id-b>/
│   ├── weekly/...
│   └── manifest.json
```

### Upload commands
```bash
REPORT_REPO="${REPORT_REPO:-ciso-reports-local}"
FOLDER="${SERVER_ID}/${REPORT_TYPE}/${REPORT_DATE}"
jf rt upload /tmp/ciso-snapshot.json "${REPORT_REPO}/${FOLDER}/snapshot.json" --flat --server-id "$SERVER_ID"
jf rt upload "./ciso-report-${REPORT_DATE}.html" "${REPORT_REPO}/${FOLDER}/report.html" --flat --server-id "$SERVER_ID"
```

### Update manifest
```bash
MANIFEST=$(cat /tmp/ciso-manifest.json 2>/dev/null || echo '{"runs":[]}')
echo "$MANIFEST" | jq --arg d "$REPORT_DATE" --arg t "$REPORT_TYPE" \
  --arg sp "${FOLDER}/snapshot.json" --arg rp "${FOLDER}/report.html" \
  --argjson b "$BLOCKED" --argjson v "$VIOLATIONS" --argjson c "$CRITICAL" \
  '.runs += [{"date":$d,"type":$t,"snapshot_path":$sp,"report_path":$rp,"blocked":$b,"violations":$v,"critical":$c}]' \
  > /tmp/manifest-updated.json
jf rt upload /tmp/manifest-updated.json "${REPORT_REPO}/${SERVER_ID}/manifest.json" --flat --server-id "$SERVER_ID"
```

## Error handling

- 404/403 from any API: record 0 or "N/A" — never crash, never skip other sections
- `jf` not configured: stop with clear message
- Empty responses: use defaults from schema (0, [], null)
- Curation audit returns 404: set `curation.available: false`, but still collect all other data
- Always produce a report even with partial data — missing sections are better than no report
