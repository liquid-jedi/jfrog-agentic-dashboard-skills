# Data Collection — API to JSON Mapping

How to fill every field in the JSON schema from JFrog APIs.
All calls use `jf rt curl` or `jf xr curl` with the configured server.

## Module Index

- Module: phase1-collect
- Module: phase1-platform-track
- Module: phase1-curation-track
- Module: phase1-violations-track
- Module: important-curation-detection
- Module: meta
- Module: platform
- Module: curation
- Module: curation-audit-transform
- Module: violations
- Module: collection-determinism-guards
- Module: license
- Module: operational
- Module: benefit (derived metrics)
- Module: comparison
- Module: governance
- Module: threat-velocity
- Module: recommendations-metadata
- Module: adding-a-kpi
- Module: methodology (optional, configurable explanations)
- Module: storage-upload
- Module: error-handling

## Module: phase1-collect

Run Phase 1 as three concurrent tracks (platform, curation, violations) and
wait for all of them before Phase 2 transform.

```bash
set -euo pipefail

rm -f /tmp/ciso-track-platform.log /tmp/ciso-track-curation.log /tmp/ciso-track-violations.log

# Track 1: platform metadata
(
  jf rt curl -s --server-id "$SERVER_ID" "/api/v1/system/version" > /tmp/ciso-version.json
  jf rt curl -s --server-id "$SERVER_ID" "/api/repositories?type=local" > /tmp/ciso-repos-local.json
  jf rt curl -s --server-id "$SERVER_ID" "/api/repositories?type=remote" > /tmp/ciso-repos-remote.json
  jf xr curl -s --server-id "$SERVER_ID" -XGET "/api/v2/watches" > /tmp/ciso-watches.json
  jf xr curl -s --server-id "$SERVER_ID" -XGET "/api/v2/policies" > /tmp/ciso-policies.json
  jf xr curl -s --server-id "$SERVER_ID" -XGET "/api/v1/binMgr/default/repos" > /tmp/ciso-indexed-repos.json
  jf xr curl -s --server-id "$SERVER_ID" -XGET "/api/v1/curation/policies" > /tmp/ciso-curation-policies.json || true
) > /tmp/ciso-track-platform.log 2>&1 &
PID_PLATFORM=$!

# Track 2: curation track (use Module: phase1-curation-track)
(
python3 - <<'PY'
import json, os, subprocess, sys
from datetime import datetime, timedelta, timezone

server = os.environ["SERVER_ID"].strip()
date_from = os.environ["DATE_FROM"].strip()
date_to = os.environ["DATE_TO"].strip()
report_type = os.environ.get("REPORT_TYPE", "weekly").strip().lower()
limit = 2000
concurrency = max(1, min(int(os.environ.get("CISO_CURATION_CONCURRENCY", "3")), 6))

def parse_rfc3339(s: str) -> datetime:
    if s.endswith("Z"):
        s = s[:-1] + "+00:00"
    return datetime.fromisoformat(s)

def chunks(start: str, end: str):
    s = parse_rfc3339(start)
    e = parse_rfc3339(end)
    step = timedelta(days=6)
    out = []
    cur = s
    while cur < e:
        nxt = min(cur + step, e)
        out.append((
            cur.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            nxt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        ))
        cur = nxt
    return out

def enforce_weekly_168h(df: str, dt: str):
    start = parse_rfc3339(df)
    end = parse_rfc3339(dt)
    hours = (end - start).total_seconds() / 3600.0
    if report_type == "weekly" and hours > 168.0:
        # Clamp to exact 168h to avoid curation API zero/empty behavior.
        start = end - timedelta(hours=168)
        return (
            start.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
            end.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        )
    return df, dt

def get_page(start: str, end: str, offset: int):
    path = (
      "/api/v1/curation/audit/packages"
      f"?order_by=id&direction=desc&num_of_rows={limit}"
      f"&created_at_start={start}&created_at_end={end}"
      f"&include_total=true&dry_run=false&offset={offset}"
    )
    p = subprocess.run(
      ["jf","xr","curl","-s","-w","%{http_code}","--server-id",server,"-XGET",path],
      capture_output=True, text=True
    )
    raw = p.stdout or ""
    status = int(raw[-3:]) if len(raw) >= 3 and raw[-3:].isdigit() else (200 if p.returncode == 0 else 500)
    body = raw[:-3] if len(raw) >= 3 and raw[-3:].isdigit() else raw
    data = json.loads(body) if body.strip() else {}
    return status, data

def paginate_window(start: str, end: str):
    pages = {}
    status0, page0 = get_page(start, end, 0)
    if status0 in (403, 404):
      return status0, pages
    pages[0] = page0
    if len(page0.get("data") or []) < limit:
      return 200, pages

    high = 0
    while len(pages[high].get("data") or []) >= limit:
      batch_start = high + limit
      offsets = [batch_start + i * limit for i in range(concurrency)]
      done = {}
      for off in offsets:
        st, pg = get_page(start, end, off)
        if st in (403, 404):
          return st, pages
        done[off] = pg
      for off in sorted(done):
        pages[off] = done[off]
        if len(done[off].get("data") or []) < limit:
          return 200, {k: v for k, v in pages.items() if k <= off}
      high = offsets[-1]
    return 200, pages

date_from, date_to = enforce_weekly_168h(date_from, date_to)
all_rows = []
pages_fetched = 0
reported_total = 0
http_status = 200

windows = chunks(date_from, date_to) if report_type == "monthly" else [(date_from, date_to)]
for wstart, wend in windows:
  st, pages = paginate_window(wstart, wend)
  if st in (403, 404):
    http_status = st
    all_rows = []
    pages_fetched = 0
    reported_total = 0
    break
  ordered_offsets = sorted(pages.keys())
  pages_fetched += len(ordered_offsets)
  for off in ordered_offsets:
    all_rows.extend(pages[off].get("data") or [])
  window_reported = max([int((pages[o].get("meta") or {}).get("total_count", 0) or 0) for o in ordered_offsets] + [0])
  reported_total += window_reported if report_type == "monthly" else window_reported

payload = {"data": all_rows, "meta": {"total_count": reported_total}}
if http_status in (403, 404):
  payload = {"data": [], "meta": {"total_count": 0}}

json.dump(payload, open("/tmp/ciso-curation.json", "w"), indent=2)
json.dump({
  "http_status": http_status,
  "mode": "monthly_chunked" if report_type == "monthly" else "weekly",
  "pages_fetched": pages_fetched,
  "rows_fetched": len(all_rows),
  "total_count_reported": reported_total,
  "date_from": date_from,
  "date_to": date_to
}, open("/tmp/ciso-curation-diagnostics.json", "w"), indent=2)
print(f"curation rows={len(all_rows)} pages={pages_fetched} status={http_status}")
PY
) > /tmp/ciso-track-curation.log 2>&1 &
PID_CURATION=$!

# Track 3: violations track (use Module: phase1-violations-track)
(
python3 - <<'PY'
import json, os, subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed

server = os.environ["SERVER_ID"].strip()
date_from = os.environ["DATE_FROM"].strip()
date_to = os.environ["DATE_TO"].strip()
limit = int(os.environ.get("CISO_VIOLATIONS_LIMIT", "500"))
concurrency = max(1, min(int(os.environ.get("CISO_VIOLATIONS_CONCURRENCY", "4")), 8))

def fetch(offset: int):
  body = json.dumps({
    "filters":{"created_from":date_from, "created_until":date_to},
    "pagination":{"limit":limit, "offset":offset, "order_by":"severity", "direction":"desc"}
  })
  p = subprocess.run(
    ["jf","xr","curl","-s","--server-id",server,"-XPOST","/api/v1/violations","-H","Content-Type: application/json","-d",body],
    capture_output=True, text=True, check=True
  )
  data = json.loads(p.stdout or "{}")
  if not isinstance(data, dict):
    raise TypeError(f"violations page offset={offset}: expected JSON object, got {type(data).__name__}")
  return data

pages = {0: fetch(0)}
if len(pages[0].get("violations") or []) >= limit:
  high = 0
  while len(pages[high].get("violations") or []) >= limit:
    batch_start = high + limit
    offsets = [batch_start + i * limit for i in range(concurrency)]
    got = {}
    with ThreadPoolExecutor(max_workers=concurrency) as pool:
      futs = {pool.submit(fetch, off): off for off in offsets}
      for fut in as_completed(futs):
        got[futs[fut]] = fut.result()
    for off in sorted(got):
      pages[off] = got[off]
      if len(got[off].get("violations") or []) < limit:
        pages = {k: v for k, v in pages.items() if k <= off}
        high = None
        break
    if high is None:
      break
    high = offsets[-1]

violations = []
total_violations = 0
for off in sorted(pages):
  pg = pages[off]
  if not isinstance(pg, dict):
    raise TypeError(f"violations merge offset={off}: expected object page, got {type(pg).__name__}")
  violations.extend(pg.get("violations") or [])
  total_violations = max(total_violations, int(pg.get("total_violations") or 0))
if total_violations == 0 and violations:
  total_violations = len(violations)
json.dump({"violations": violations, "total_violations": total_violations}, open("/tmp/ciso-violations.json", "w"), indent=2)
print(f"violations rows={len(violations)} total={total_violations}")
PY
) > /tmp/ciso-track-violations.log 2>&1 &
PID_VIOLATIONS=$!

FAIL=0
for pid in "$PID_PLATFORM" "$PID_CURATION" "$PID_VIOLATIONS"; do
  wait "$pid" || FAIL=1
done

if [ "$FAIL" -ne 0 ]; then
  echo "Phase 1 failed. Logs:"
  echo "  /tmp/ciso-track-platform.log"
  echo "  /tmp/ciso-track-curation.log"
  echo "  /tmp/ciso-track-violations.log"
  exit 1
fi
```

Required environment before running the command:
- `SERVER_ID`
- `DATE_FROM`
- `DATE_TO`
- `REPORT_TYPE` (`weekly` or `monthly`; optional, defaults to `weekly`)
- `REPORT_DATE` (`YYYY-MM-DD`, optional — default `date +%Y-%m-%d`; needed for Step 4 snapshot scan in `SKILL.md`)

Artifacts written by Phase 1:
- `/tmp/ciso-version.json`
- `/tmp/ciso-repos-local.json`
- `/tmp/ciso-repos-remote.json`
- `/tmp/ciso-watches.json`
- `/tmp/ciso-policies.json`
- `/tmp/ciso-curation.json`
- `/tmp/ciso-curation-diagnostics.json`
- `/tmp/ciso-violations.json`
- `/tmp/ciso-track-platform.log`
- `/tmp/ciso-track-curation.log`
- `/tmp/ciso-track-violations.log`

## Module: phase1-platform-track

Use this track when running platform collection outside the full phase1 block.
It must write only `/tmp/ciso-version.json`, `/tmp/ciso-repos-*.json`,
`/tmp/ciso-watches.json`, `/tmp/ciso-policies.json`,
`/tmp/ciso-indexed-repos.json`, `/tmp/ciso-curation-policies.json`.

## Module: phase1-curation-track

Use the inline Python runner shown in `Module: phase1-collect` for deterministic
curation pagination (offset merge + stop at first partial page).

## Module: phase1-violations-track

Use the inline Python runner shown in `Module: phase1-collect` for deterministic
parallel violations pagination (offset merge + stop at first partial page).

## Module: important-curation-detection

**Do NOT gate curation on the entitlement check.** The `/api/system/version`
addons field may not list "curation" even when curation is active.

Instead: always call the curation audit API. If the API returns `200` with
a JSON body containing `data` or `meta`, curation is reachable. If it returns
404/403, set `available: false`.

## Module: meta

```bash
SERVER_ID=$(jf config show 2>/dev/null | awk '/^Server ID:/{id=$NF} /^Default:.*true/{print id; exit}')
JFROG_URL=$(jf config show "$SERVER_ID" 2>/dev/null | grep "JFrog Platform URL:" | head -1 | awk '{print $NF}')
HOST=$(echo "$JFROG_URL" | sed 's|https://||;s|/$||')
```

Date computation (macOS):
```bash
# Weekly curation windows MUST stay within 168 hours.
DATE_TO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DATE_FROM=$(date -u -v-${DAYS}d +%Y-%m-%dT%H:%M:%SZ)
```

Date computation (Linux):
```bash
# Weekly curation windows MUST stay within 168 hours.
DATE_TO=$(date -u +%Y-%m-%dT%H:%M:%SZ)
DATE_FROM=$(date -u -d "${DAYS} days ago" +%Y-%m-%dT%H:%M:%SZ)
```

## Module: platform

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

### Curation policies (sidebar + enforcement summary)

Always persist the raw list to `/tmp/ciso-curation-policies.json` during Phase 1 platform track.

```bash
jf xr curl -s --server-id "$SERVER_ID" "/api/v1/curation/policies" > /tmp/ciso-curation-policies.json 2>/dev/null || echo '[]' > /tmp/ciso-curation-policies.json
```

API fields used: `name`, `scope` (`all_repos` | `specific_repos` | legacy `global`/`repository`/`user`),
`policy_action` (`block` | `dry_run` | …), `enabled`.

Sidebar counts (enabled, non-dry-run only):

```bash
jq '[
  .[] | select(.enabled != false) | select((.policy_action // "") | ascii_downcase != "dry_run")
]' /tmp/ciso-curation-policies.json 2>/dev/null | jq '{
  total_enforcing: length,
  all_repos: [.[] | select(.scope == "all_repos" or .scope == "global")] | length,
  specific_repos: [.[] | select(.scope == "specific_repos" or .scope == "repository")] | length,
  user: [.[] | select(.scope == "user")] | length
}'
```

Full `curation.policies_enforced` is built in `Module: curation-audit-transform` (merges policy registry + audit hits).

If 404/403: set platform curation policy counts to 0 and `curation.policies_enforced.available: false`.

### Platform merge (mandatory after Phase 1)

Phase 1 writes raw artifacts; this block produces coherent `platform.*` counts.
**Do not** use `/api/v2/xray/watches` or `/api/v2/xray/policies` — they return 404 on current Xray builds.

```bash
python3 - <<'PY'
import json, os, subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed

server = os.environ["SERVER_ID"].strip()

def jf_rt(path):
  p = subprocess.run(["jf","rt","curl","-s","--server-id",server,"-XGET",path], capture_output=True, text=True)
  try:
    return json.loads(p.stdout or "null")
  except Exception:
    return None

def jf_xr(path):
  p = subprocess.run(["jf","xr","curl","-s","--server-id",server,"-XGET",path], capture_output=True, text=True)
  raw = (p.stdout or "").strip()
  if raw.startswith("404") or raw.startswith("403"):
    return None
  try:
    return json.loads(raw)
  except Exception:
    return None

def load(path, default):
  if not os.path.isfile(path):
    return default
  try:
    return json.load(open(path))
  except Exception:
    return default

all_repos = load("/tmp/ciso-repos-all.json", None)
if all_repos is None:
  all_repos = jf_rt("/api/repositories") or []
json.dump(all_repos, open("/tmp/ciso-repos-all.json", "w"))

remote = load("/tmp/ciso-repos-remote.json", None)
if remote is None:
  remote = jf_rt("/api/repositories?type=remote") or []
json.dump(remote, open("/tmp/ciso-repos-remote.json", "w"))

indexed_body = load("/tmp/ciso-indexed-repos.json", {}) or {}
indexed_names = {r.get("name") for r in (indexed_body.get("indexed_repos") or []) if isinstance(r, dict) and r.get("name")}
if not indexed_names and isinstance(indexed_body, list):
  indexed_names = set(indexed_body)

watches = load("/tmp/ciso-watches.json", None)
if isinstance(watches, dict) and watches.get("total") is not None:
  watches_total = int(watches.get("total") or 0)
  watches_active = int(watches.get("active") or 0)
elif isinstance(watches, list) and len(watches) > 0:
  watches_total = len(watches)
  watches_active = sum(1 for w in watches if isinstance(w, dict) and ((w.get("general_data") or {}).get("active") is True))
else:
  w = jf_xr("/api/v2/watches") or []
  watches = w if isinstance(w, list) else []
  json.dump(watches, open("/tmp/ciso-watches.json", "w"))
  watches_total = len(watches)
  watches_active = sum(1 for x in watches if isinstance(x, dict) and ((x.get("general_data") or {}).get("active") is True))

policies = load("/tmp/ciso-policies.json", None)
if isinstance(policies, dict) and policies.get("total") is not None:
  policies_total = int(policies["total"])
  policies_security = int(policies.get("security") or 0)
  policies_operational = int(policies.get("operational_risk") or policies.get("operational") or 0)
  policies_license = int(policies.get("license") or 0)
elif isinstance(policies, dict) and isinstance(policies.get("result"), list):
  policy_items = policies.get("result") or []
  policies_total = len(policy_items)
  policies_security = sum(1 for x in policy_items if isinstance(x, dict) and x.get("type") == "security")
  policies_operational = sum(1 for x in policy_items if isinstance(x, dict) and x.get("type") == "operational_risk")
  policies_license = sum(1 for x in policy_items if isinstance(x, dict) and x.get("type") == "license")
elif isinstance(policies, list) and len(policies) > 0:
  policies_total = len(policies)
  policies_security = sum(1 for x in policies if isinstance(x, dict) and x.get("type") == "security")
  policies_operational = sum(1 for x in policies if isinstance(x, dict) and x.get("type") == "operational_risk")
  policies_license = sum(1 for x in policies if isinstance(x, dict) and x.get("type") == "license")
else:
  pol = jf_xr("/api/v2/policies") or []
  if isinstance(pol, list):
    json.dump(pol, open("/tmp/ciso-policies.json", "w"))
    policy_items = pol
  elif isinstance(pol, dict) and isinstance(pol.get("result"), list):
    json.dump(pol, open("/tmp/ciso-policies.json", "w"))
    policy_items = pol.get("result") or []
  else:
    policy_items = []
  policies_total = len(policy_items)
  policies_security = sum(1 for x in policy_items if isinstance(x, dict) and x.get("type") == "security")
  policies_operational = sum(1 for x in policy_items if isinstance(x, dict) and x.get("type") == "operational_risk")
  policies_license = sum(1 for x in policy_items if isinstance(x, dict) and x.get("type") == "license")

repo_types = sorted({(r.get("packageType") or r.get("package_type") or "unknown") for r in all_repos if isinstance(r, dict)})
repos_total = len(all_repos) if isinstance(all_repos, list) else 0
repos_indexed = len(indexed_names)
repos_unindexed = max(0, repos_total - repos_indexed)

def normalize_pkg_type(value):
  if not value:
    return "unknown"
  key = str(value).strip()
  aliases = {
    "pypi": "PyPI", "Pypi": "PyPI",
    "npm": "npm", "Npm": "npm",
    "maven": "Maven", "Maven": "Maven",
    "docker": "Docker", "Docker": "Docker",
    "go": "Go", "Go": "Go",
    "nuget": "NuGet", "Nuget": "NuGet",
    "huggingfaceml": "HuggingFaceML", "HuggingFaceML": "HuggingFaceML",
    "aieditorextensions": "AIEditorExtensions",
    "gems": "Gems", "cargo": "Cargo", "composer": "Composer", "conan": "Conan",
    "debian": "Debian", "gradle": "Gradle", "pub": "Pub",
  }
  return aliases.get(key, aliases.get(key.lower(), key))

def load_supported_pkg_types():
  path = "/tmp/ciso-curation-policies.json"
  types = set()
  if os.path.isfile(path):
    raw = json.load(open(path))
    items = raw if isinstance(raw, list) else (raw.get("data") or [])
    for p in items:
      if not isinstance(p, dict):
        continue
      for t in ((p.get("condition") or {}).get("supported_pkg_types") or []):
        types.add(normalize_pkg_type(t))
  if not types:
    types = {
      "npm", "PyPI", "Maven", "Docker", "Go", "NuGet", "HuggingFaceML",
      "Gems", "Cargo", "Composer", "Conan", "Debian", "Gradle", "Pub",
      "AIEditorExtensions", "Alpine",
    }
  return types

supported_pkg_types = load_supported_pkg_types()
supported_norm = {normalize_pkg_type(t) for t in supported_pkg_types}

remote_keys = [r.get("key") for r in remote if isinstance(r, dict) and r.get("key")]
connected = 0
supported_remote_total = 0
supported_connected = 0
by_pkg = {}
pass_through_repos = []

def fetch_curated(key):
  cfg = jf_rt(f"/api/repositories/{key}")
  if not isinstance(cfg, dict):
    return key, False, "unknown"
  pkg = cfg.get("packageType") or "unknown"
  curated = cfg.get("curated") is True
  return key, curated, pkg

workers = min(12, max(4, len(remote_keys) // 20 or 4))
with ThreadPoolExecutor(max_workers=workers) as ex:
  futs = [ex.submit(fetch_curated, k) for k in remote_keys]
  for fut in as_completed(futs):
    key, curated, pkg = fut.result()
    norm = normalize_pkg_type(pkg)
    slot = by_pkg.setdefault(norm, {"package_type": norm, "remote_total": 0, "connected": 0, "blocked_packages_period": 0})
    slot["remote_total"] += 1
    if curated:
      connected += 1
      slot["connected"] += 1
    supported = normalize_pkg_type(pkg) in supported_norm
    if supported:
      supported_remote_total += 1
      if curated:
        supported_connected += 1
    if not curated:
      pass_through_repos.append({
        "repo": key,
        "package_type": norm,
        "supported": supported,
      })

package_types_in_scope = [
  v for v in by_pkg.values()
  if v["remote_total"] > 0 and normalize_pkg_type(v["package_type"]) in supported_norm
]

curation_state = {
  "remote_total": len(remote_keys),
  "connected": connected,
  "not_connected": max(0, len(remote_keys) - connected),
  "connected_pct": round((connected / len(remote_keys)) * 100, 2) if remote_keys else 0,
  "supported_remote_total": supported_remote_total,
  "supported_connected": supported_connected,
  "supported_not_connected": max(0, supported_remote_total - supported_connected),
  "supported_connected_pct": round((supported_connected / supported_remote_total) * 100, 2) if supported_remote_total else 0,
  "package_types_total": len(package_types_in_scope),
  "by_package_type": sorted(by_pkg.values(), key=lambda x: -x["remote_total"]),
  "note": "Connected = remote repositories with Artifactory curated=true. Supported-ecosystem counts include remotes whose package type is covered by Curation policies.",
}

plat = {
  "watches_total": watches_total,
  "watches_active": watches_active,
  "policies_total": policies_total,
  "policies_security": policies_security,
  "policies_operational": policies_operational,
  "policies_license": policies_license,
  "repos_total": repos_total,
  "repos_indexed": repos_indexed,
  "repos_unindexed": repos_unindexed,
  "repo_types": repo_types,
  "indexed_repo_names": sorted(indexed_names),
  "pass_through_repos": sorted(pass_through_repos, key=lambda row: (not row["supported"], row["package_type"], row["repo"])),
  "curation_state": curation_state,
}
json.dump(plat, open("/tmp/ciso-platform.json", "w"), indent=2)
print(f"platform merge: watches={watches_total} policies={policies_total} indexed={repos_indexed}/{repos_total} curation_connected={connected}/{len(remote_keys)}")
PY
```

### Merge platform into `/tmp/ciso-data.json` (mandatory)

Run **after** Phase 2 jq has written `/tmp/ciso-data.json` and **before** curation-audit-transform:

```bash
python3 - <<'PY'
import json, sys, os

data_path = "/tmp/ciso-data.json"
plat_path = "/tmp/ciso-platform.json"
if not os.path.isfile(data_path):
  print(f"ERROR: missing {data_path}", file=sys.stderr); sys.exit(1)
if not os.path.isfile(plat_path):
  print(f"ERROR: missing {plat_path} — run Platform merge block first", file=sys.stderr); sys.exit(1)

data = json.load(open(data_path))
plat = json.load(open(plat_path))
if not isinstance(data, dict) or not isinstance(plat, dict):
  print("ERROR: data/platform must be objects", file=sys.stderr); sys.exit(1)

merged = data.setdefault("platform", {})
for key, val in plat.items():
  if key == "curation_state" and isinstance(val, dict):
    merged["curation_state"] = val
  else:
    merged[key] = val

# Mirror curation_state on curation for templates that read either path.
curation = data.setdefault("curation", {})
if merged.get("curation_state"):
  curation["curation_state"] = merged["curation_state"]

json.dump(data, open(data_path, "w"), indent=2)
cs = merged.get("curation_state") or {}
print(
  f"platform merged: indexed={merged.get('repos_indexed')}/{merged.get('repos_total')} "
  f"watches={merged.get('watches_total')} curation_policies_block={merged.get('curation_policies_block')} "
  f"supported_connected={cs.get('supported_connected')}/{cs.get('supported_remote_total')} "
  f"package_types_total={cs.get('package_types_total')}"
)
PY
```

## Module: curation

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

### Collecting curation data (weekly/monthly)

Use the inline deterministic collector from `Module: phase1-curation-track`.
That module supports both:
- weekly mode (single date window)
- monthly mode (6-day windows, merged in window order)

Determinism requirements:
- Keep `order_by=id&direction=desc` on every page request.
- Merge pages by ascending `offset`.
- Stop at first partial page (`len(data) < num_of_rows`) and ignore higher offsets.
- For monthly mode, concatenate rows by window order and sum each window's
  reported `meta.total_count`.

Diagnostics are required in `/tmp/ciso-curation-diagnostics.json`:
`http_status`, `mode`, `pages_fetched`, `rows_fetched`, `total_count_reported`,
`date_from`, `date_to`.

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

Set availability from diagnostics before mapping:

```bash
CUR_HTTP_STATUS=$(jq -r '.http_status // 0' /tmp/ciso-curation-diagnostics.json 2>/dev/null || echo 0)
if [ "$CUR_HTTP_STATUS" = "403" ] || [ "$CUR_HTTP_STATUS" = "404" ]; then
  CURATION_AVAILABLE=false
else
  CURATION_AVAILABLE=true
fi
```

Then map:

```bash
jq --argjson available "$CURATION_AVAILABLE" '{
  available: $available,
  total: ([
    (.meta.total_count // 0),
    ((.data // []) | length),
    ([ (.data // [])[] | select(((.action // .status // "") | ascii_downcase) == "blocked"
      or ((.action // .status // "") | ascii_downcase) == "approved"
      or ((.action // .status // "") | ascii_downcase) == "passed") ] | length)
  ] | max),
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
       policy_names: (
         [(.policies // [])[] | (.policy_name // .condition_name // empty) | select(length > 0)]
         + (if ((.reason // "") | length) > 0 then [.reason] else [] end)
       ),
       malicious: ((.policies // []) | any(
         (.condition_category // "" | test("malicious";"i"))
         or (.condition_name // "" | test("malicious";"i"))
         or (.policy_name // "" | test("malicious";"i"))))}]
    | sort_by(.name)
    | group_by(.name)
    | map({package: .[0].name, ecosystem: .[0].type, count: length,
           malicious: any(.[]; .malicious)})
    | sort_by(-.count),

  by_type: [(.data // [])[] | {type: .package_type, action: ((.action // .status // "") | ascii_downcase)}]
    | sort_by(.type)
    | group_by(.type)
    | map({type: .[0].type,
           total: length,
           blocked: [.[] | select(.action == "blocked")] | length})
    | sort_by(-.blocked),

  unique_users: [(.data // [])[]
    | (.username // .user_mail // empty)
    | select(length > 0)] | unique | length,

  top_users: [(.data // [])[]
    | select((.username // .user_mail // "") | length > 0)
    | {
        user: (.username // .user_mail),
        action: ((.action // .status // "") | ascii_downcase)
      }]
    | group_by(.user)
    | map({
        user: .[0].user,
        events: length,
        blocked: [.[] | select(.action == "blocked")] | length,
        approved: [.[] | select(.action == "approved")] | length,
        passed: [.[] | select(.action == "passed")] | length
      })
    | sort_by(-.events, .user)
    | .[0:10],

  audit_events: [(.data // [])[] | select(((.action // .status // "") | ascii_downcase) == "blocked") | {
    status: "blocked",
    package: .package_name,
    version: .package_version,
    type: .package_type,
    repo: .curated_repository_name,
    policy: ((.policies // [])[0].policy_name // "—"),
    requested_by: (.username // .user_mail // "—"),
    date: (.created_at // "")[0:10],
    timestamp: (.created_at // ""),
    malicious: ((.policies // []) | any(
      (.condition_category // "" | test("malicious";"i"))
      or (.condition_name // "" | test("malicious";"i"))
      or (.policy_name // "" | test("malicious";"i"))))
  }]
}'
```

### Derived fields
- `block_rate`: `blocked / total * 100` (use `meta.total_count` for total)
- `passed` policy decision (dashboard convention): if API `passed` rows are missing/zero but `total > blocked`, treat `passed = total - blocked`.
- `curated_types`: unique `.package_type` values from `.data[]` (for sidebar pills)
- `curation_repos_count`: unique `.curated_repository_name` values from `.data[]`
- `unique_users` / `top_users`: derive from **all** paginated audit rows in the
  window (not blocked-only). Identity = `username` if set, else `user_mail`;
  skip rows with neither. `top_users` = top 20 by `events` (tie-break on `user`);
  the full user/package activity is written as `curation-user-package-activity.csv`
  next to the report instead of being embedded in the HTML.
  There is no separate curation-users API — use
  `GET /xray/api/v1/curation/audit/packages` (`jf xr curl`) per
  `../jfrog/references/xray-entities.md` § Curation audit events.
- If `blocked > 0` but `audit_events` ends up empty after parsing, do NOT emit
  "no blocked events". Populate summary data from `by_reason`, `by_type`, and
  `top_blocked` so the report still reflects blocked activity.
- If API returns 404: set `curation.available: false`, all counts to 0. Continue with other sections.
- Do not merge `approved` and `passed` in beta JSON output.



---

## Module: curation-audit-transform

After `/tmp/ciso-curation.json` is merged, build:

- blocked-only `audit_events` + top-50 `audit_events_display` (sort **C+D**)
- `clean_packages` from approved outcomes, with `without_inspection` kept separate
- `top_blocked`, block-then-upgrade rate, and the full aggregated user/package export
- **`unique_users`** and **top-20 `top_users`** (from all audit rows — required for dashboard)
- **`policies_enforced`** (from `/tmp/ciso-curation-policies.json` + audit policy hits; dry-run excluded)

**Prerequisite:** `/tmp/ciso-data.json` must already exist (initial jq merge from Phase 2). Do not run this transform before the base `curation` object is written.

```bash
python3 - <<'PY'
import json, re, sys, os, subprocess
from collections import Counter, defaultdict
from datetime import datetime, timezone

CAP = 50
MAL = re.compile(r"malicious", re.I)
SCOPE_LABELS = {
    "all_repos": "All remote repositories",
    "global": "All remote repositories",
    "specific_repos": "Selected repositories",
    "repository": "Selected repositories",
    "user": "User-scoped",
}

for path in ("/tmp/ciso-curation.json", "/tmp/ciso-data.json"):
  if not os.path.isfile(path):
    print(f"ERROR: missing {path} — run curation jq mapping before curation-audit-transform", file=sys.stderr)
    sys.exit(1)

cur = json.load(open("/tmp/ciso-curation.json"))
data = json.load(open("/tmp/ciso-data.json"))
if not isinstance(data, dict):
  print("ERROR: /tmp/ciso-data.json must be a JSON object", file=sys.stderr)
  sys.exit(1)

def load_policy_registry():
  path = "/tmp/ciso-curation-policies.json"
  if not os.path.isfile(path):
    return []
  raw = json.load(open(path))
  if isinstance(raw, list):
    return raw
  if isinstance(raw, dict):
    items = list(raw.get("data") or raw.get("policies") or [])
    meta = raw.get("meta") or {}
    total = int(meta.get("total_count") or 0)
    if total > len(items):
      server = (data.get("meta") or {}).get("server_id") or os.environ.get("SERVER_ID", "")
      offset = len(items)
      while offset < total:
        p = subprocess.run(
          ["jf", "xr", "curl", "-s", "--server-id", server, "-XGET",
           f"/api/v1/curation/policies?num_of_rows=200&offset={offset}"],
          capture_output=True, text=True
        )
        page = json.loads(p.stdout or "{}")
        batch = page.get("data") or []
        if not batch:
          break
        items.extend(batch)
        offset += len(batch)
    return items
  return []

def audit_meta_total(dry_run: bool):
  server = (data.get("meta") or {}).get("server_id") or os.environ.get("SERVER_ID", "")
  diag = json.load(open("/tmp/ciso-curation-diagnostics.json")) if os.path.isfile("/tmp/ciso-curation-diagnostics.json") else {}
  df = diag.get("date_from") or ""
  dt = diag.get("date_to") or ""
  dr = "true" if dry_run else "false"
  path = (
    f"/api/v1/curation/audit/packages?num_of_rows=1&offset=0&include_total=true"
    f"&created_at_start={df}&created_at_end={dt}&dry_run={dr}"
  )
  p = subprocess.run(["jf", "xr", "curl", "-s", "--server-id", server, "-XGET", path], capture_output=True, text=True)
  body = json.loads(p.stdout or "{}")
  return int((body.get("meta") or {}).get("total_count") or 0)

def build_request_results(events):
  ctr = Counter((ev.get("action") or ev.get("status") or "").lower() for ev in events)
  blocked = int(ctr.get("blocked", 0))
  approved = int(ctr.get("approved", 0))
  dry_run = audit_meta_total(dry_run=True)
  # The main audit stream is non-dry-run. Its approved rows are the packages
  # that Curation inspected and allowed ("clean packages"). The UI "Passed"
  # remainder was not policy-inspected and must never be counted as clean.
  non_dry_total = int((data.get("curation") or {}).get("total", 0) or len(events))
  without_inspection = max(0, non_dry_total - blocked - approved)
  return {
    "blocked": blocked,
    "approved": approved,
    "clean_packages": approved,
    "dry_run": dry_run,
    "without_inspection": without_inspection,
  }

def build_top_blocked(events):
  grouped = {}
  for ev in events:
    if (ev.get("action") or ev.get("status") or "").lower() != "blocked":
      continue
    package = (ev.get("package_name") or ev.get("package") or "unknown").strip()
    ecosystem = normalize_pkg_type(ev.get("package_type"))
    key = (package, ecosystem)
    row = grouped.setdefault(key, {
      "package": package,
      "ecosystem": ecosystem,
      "count": 0,
      "malicious": False,
    })
    row["count"] += 1
    row["malicious"] = row["malicious"] or is_malicious(ev)
  return sorted(
    grouped.values(),
    key=lambda row: (not row["malicious"], -row["count"], row["package"], row["ecosystem"]),
  )[:25]

def version_key(value):
  parts = re.findall(r"\d+|[A-Za-z]+", str(value or ""))
  return tuple((0, int(part)) if part.isdigit() else (1, part.lower()) for part in parts)

def build_upgrade_rate(events):
  blocked = defaultdict(list)
  approved = defaultdict(list)
  for ev in events:
    action = (ev.get("action") or ev.get("status") or "").lower()
    if action not in ("blocked", "approved"):
      continue
    package = (ev.get("package_name") or ev.get("package") or "").strip()
    ecosystem = normalize_pkg_type(ev.get("package_type"))
    version = str(ev.get("package_version") or ev.get("version") or "").strip()
    timestamp = str(ev.get("created_at") or "")
    if not package or not version:
      continue
    target = blocked if action == "blocked" else approved
    target[(package, ecosystem)].append((timestamp, version))
  upgraded = 0
  for key, blocked_events in blocked.items():
    approved_events = approved.get(key) or []
    matched = any(
      approved_ts > blocked_ts and version_key(approved_version) > version_key(blocked_version)
      for blocked_ts, blocked_version in blocked_events
      for approved_ts, approved_version in approved_events
    )
    if matched:
      upgraded += 1
  total = len(blocked)
  return {
    "upgrade_rate": round((upgraded / total) * 100, 1) if total else 0,
    "upgrade_rate_computed": bool(total),
    "upgraded_packages": upgraded,
    "unique_blocked_packages": total,
  }

def build_curation_state(events):
  plat_path = "/tmp/ciso-platform.json"
  if os.path.isfile(plat_path):
    st = (json.load(open(plat_path)).get("curation_state") or {})
    if int(st.get("remote_total") or 0) > 0:
      return st
  remote_total = 0
  if os.path.isfile("/tmp/ciso-repos-remote.json"):
    rem = json.load(open("/tmp/ciso-repos-remote.json"))
    if isinstance(rem, list):
      remote_total = len(rem)
  active = len({ev.get("curated_repository_name") for ev in events if ev.get("curated_repository_name")})
  not_connected = max(0, remote_total - active) if remote_total else 0
  pct = round((active / remote_total) * 100, 1) if remote_total else 0
  return {
    "remote_total": remote_total,
    "connected": active,
    "not_connected": not_connected,
    "connected_pct": pct,
    "by_package_type": [],
    "note": "Connected = unique repos seen in audit (fallback). Run platform merge for curated=true counts.",
  }

def normalize_pkg_type(value):
  if not value:
    return "unknown"
  key = str(value).strip()
  aliases = {
    "pypi": "PyPI", "Pypi": "PyPI", "npm": "npm", "Npm": "npm",
    "maven": "Maven", "docker": "Docker", "go": "Go", "nuget": "NuGet",
    "huggingfaceml": "HuggingFaceML", "aieditorextensions": "AIEditorExtensions",
    "gems": "Gems", "cargo": "Cargo", "composer": "Composer", "conan": "Conan",
    "debian": "Debian", "gradle": "Gradle", "pub": "Pub",
  }
  return aliases.get(key, aliases.get(key.lower(), key))

def classify_blocked_event(ev):
  for pol in ev.get("policies") or []:
    if not isinstance(pol, dict) or pol.get("dry_run"):
      continue
    blob = " ".join([
      pol.get("condition_category") or "",
      pol.get("condition_name") or "",
      pol.get("policy_name") or "",
    ]).lower()
    if "malicious" in blob:
      return "malicious"
    cat = (pol.get("condition_category") or "").lower()
    if cat == "license":
      return "license"
    if cat == "operational":
      return "operational"
    if cat in ("security", "vulnerability", "cve"):
      return "security"
  if is_malicious(ev):
    return "malicious"
  return "security"

def build_policy_violations_by_type(events):
  ctr = Counter()
  for ev in events:
    action = (ev.get("action") or ev.get("status") or "").lower()
    if action != "blocked":
      continue
    ctr[classify_blocked_event(ev)] += 1
  return {
    "malicious": int(ctr.get("malicious", 0)),
    "security": int(ctr.get("security", 0)),
    "license": int(ctr.get("license", 0)),
    "operational": int(ctr.get("operational", 0)),
    "total_blocked": sum(ctr.values()),
  }

def build_package_types_insights(events, state):
  blocked_by_pkg = Counter()
  for ev in events:
    if (ev.get("action") or ev.get("status") or "").lower() != "blocked":
      continue
    blocked_by_pkg[normalize_pkg_type(ev.get("package_type"))] += 1
  top_by_blocked = [
    {"package_type": k, "blocked": v}
    for k, v in blocked_by_pkg.most_common(5)
  ]
  by_pkg = {row.get("package_type"): row for row in (state.get("by_package_type") or [])}
  for row in top_by_blocked:
    meta = by_pkg.get(row["package_type"]) or {}
    row["connected_repos"] = int(meta.get("connected") or 0)
    row["remote_total"] = int(meta.get("remote_total") or 0)
  total = int(state.get("package_types_total") or 0)
  if not total:
    total = len([k for k, v in by_pkg.items() if (v.get("remote_total") or 0) > 0])
  return {"total": total, "top_by_blocked": top_by_blocked}

def policy_risk_type(policy):
  condition = policy.get("condition") or {}
  blob = " ".join([
    str(policy.get("name") or ""),
    str(condition.get("name") or ""),
    str(condition.get("risk_type") or ""),
  ]).lower()
  if "malicious" in blob:
    return "malicious"
  rt = str(condition.get("risk_type") or "unknown").lower()
  if rt in ("vulnerability", "cve"):
    return "security"
  return rt

def build_policy_inventory(registry):
  enabled = [p for p in registry if isinstance(p, dict) and p.get("enabled", True) is not False]
  block = [p for p in enabled if not is_dry_run_policy(p)]
  dry = [p for p in enabled if is_dry_run_policy(p)]
  risk = Counter()
  for p in enabled:
    rt = policy_risk_type(p)
    risk[rt] += 1
  block_by_risk = Counter()
  block_list = []
  for p in block:
    rt = policy_risk_type(p)
    block_by_risk[rt] += 1
    block_list.append({
      "name": p.get("name"),
      "risk_type": rt,
      "scope": scope_label(p.get("scope")),
      "condition": (p.get("condition") or {}).get("name") or "—",
    })
  def policy_age_days(policy):
    value = policy.get("updated_at") or policy.get("created_at") or ""
    if not value:
      return None
    try:
      stamp = datetime.fromisoformat(str(value).replace("Z", "+00:00"))
      if stamp.tzinfo is None:
        stamp = stamp.replace(tzinfo=timezone.utc)
      return max(0, (datetime.now(timezone.utc) - stamp).days)
    except Exception:
      return None
  dry_run_policies = [
    {
      "name": p.get("name") or f"policy-{p.get('id', '?')}",
      "scope": scope_label(p.get("scope")),
      "days_in_dry_run": policy_age_days(p),
    }
    for p in dry
  ]
  malicious_org_wide = [
    p for p in block
    if "malicious" in json.dumps(p).lower()
    and (p.get("scope") or "") in ("all_repos", "global")
  ]
  cache_enforced = [p for p in block if p.get("block_from_cache") is True]
  return {
    "block_active": len(block),
    "dry_run_active": len(dry),
    "total_registered": len(registry),
    "by_risk_type": [{"type": k, "count": v} for k, v in risk.most_common()],
    "block_by_risk_type": [{"type": k, "count": v} for k, v in block_by_risk.most_common()],
    "block_policies": block_list[:20],
    "dry_run_policies": dry_run_policies,
    "baseline_policy_posture": {
      "block_malicious_org_wide": bool(malicious_org_wide),
      "matching_policies": [p.get("name") or f"policy-{p.get('id', '?')}" for p in malicious_org_wide],
    },
    "cached_package_enforcement": {
      "global_enabled": None,
      "policies_enforcing_cache": len(cache_enforced),
      "blocking_policies_total": len(block),
      "policies_missing_cache_enforcement": [
        p.get("name") or f"policy-{p.get('id', '?')}"
        for p in block if p.get("block_from_cache") is not True
      ],
    },
  }

def is_dry_run_policy(p):
  action = (p.get("policy_action") or "").replace("-", "_").lower()
  return action == "dry_run"

def scope_label(scope):
  return SCOPE_LABELS.get(scope or "", scope or "Unknown")

def build_policies_enforced(events, registry):
  reg = [p for p in registry if isinstance(p, dict)]
  enabled = [p for p in reg if p.get("enabled", True) is not False]
  enforcing_reg = [p for p in enabled if not is_dry_run_policy(p)]
  dry_run_count = len(enabled) - len(enforcing_reg)

  audit_hits = Counter()
  blocked_hits = Counter()
  clean_hits = Counter()
  for ev in events:
    action = (ev.get("action") or ev.get("status") or "").lower()
    for pol in ev.get("policies") or []:
      if not isinstance(pol, dict):
        continue
      if pol.get("dry_run"):
        continue
      name = (pol.get("policy_name") or pol.get("name") or "").strip()
      if not name:
        pid = pol.get("policy_id")
        if pid is not None:
          name = str(pid)
      if not name:
        continue
      audit_hits[name] += 1
      if action == "blocked":
        blocked_hits[name] += 1
      elif action == "approved":
        clean_hits[name] += 1

  by_scope = defaultdict(lambda: {"count": 0, "enforcing": 0})
  for p in enabled:
    sc = p.get("scope") or "unknown"
    by_scope[sc]["count"] += 1
    if not is_dry_run_policy(p):
      by_scope[sc]["enforcing"] += 1

  by_policy = []
  seen = set()
  for p in enforcing_reg:
    name = (p.get("name") or "").strip() or f"policy-{p.get('id', '?')}"
    seen.add(name)
    decided = int(blocked_hits.get(name, 0)) + int(clean_hits.get(name, 0))
    by_policy.append({
      "name": name,
      "scope": p.get("scope") or "unknown",
      "scope_label": scope_label(p.get("scope")),
      "action": p.get("policy_action") or "—",
      "enabled": bool(p.get("enabled", True)),
      "audit_hits": int(audit_hits.get(name, 0)),
      "blocked_hits": int(blocked_hits.get(name, 0)),
      "clean_hits": int(clean_hits.get(name, 0)),
      "blocked_pct": round(int(blocked_hits.get(name, 0)) / decided * 100, 1) if decided else 0,
      "clean_pct": round(int(clean_hits.get(name, 0)) / decided * 100, 1) if decided else 0,
    })
  for name, hits in audit_hits.items():
    if name in seen:
      continue
    decided = int(blocked_hits.get(name, 0)) + int(clean_hits.get(name, 0))
    by_policy.append({
      "name": name,
      "scope": "audit_only",
      "scope_label": "Seen in audit only",
      "action": "—",
      "enabled": True,
      "audit_hits": int(hits),
      "blocked_hits": int(blocked_hits.get(name, 0)),
      "clean_hits": int(clean_hits.get(name, 0)),
      "blocked_pct": round(int(blocked_hits.get(name, 0)) / decided * 100, 1) if decided else 0,
      "clean_pct": round(int(clean_hits.get(name, 0)) / decided * 100, 1) if decided else 0,
    })

  by_policy.sort(key=lambda x: (-x["audit_hits"], -x["blocked_hits"], x["name"]))

  scope_rows = []
  for sc, vals in sorted(by_scope.items(), key=lambda kv: -kv[1]["enforcing"]):
    scope_rows.append({
      "scope": sc,
      "label": scope_label(sc),
      "registered": vals["count"],
      "enforcing": vals["enforcing"],
    })

  total_reg = len(registry)
  if os.path.isfile("/tmp/ciso-curation-policies.json"):
    meta = (json.load(open("/tmp/ciso-curation-policies.json")).get("meta") or {})
    total_reg = int(meta.get("total_count") or total_reg)

  return {
    "available": bool(reg) or bool(audit_hits),
    "total_registered": total_reg,
    "enabled": len(enabled),
    "enforcing": len(enforcing_reg),
    "dry_run_excluded": dry_run_count,
    "by_scope": scope_rows,
    "by_policy": by_policy[:25],
  }

def policy_names_for_event(ev, pols):
  names = []
  if isinstance(pols, list):
    for p in pols:
      if not isinstance(p, dict):
        continue
      n = (p.get("policy_name") or p.get("condition_name") or "").strip()
      if n:
        names.append(n)
  reason = (ev.get("reason") or "").strip()
  if reason:
    names.append(reason)
  return ", ".join(dict.fromkeys(names)) if names else "—"

def is_malicious(ev):
    if ev.get("malicious") is True:
        return True
    if MAL.search(ev.get("policy") or ""):
        return True
    for p in ev.get("policies") or []:
        blob = " ".join([
            p.get("condition_category") or "",
            p.get("condition_name") or "",
            p.get("policy_name") or "",
        ])
        if MAL.search(blob):
            return True
    return False

rows = []
for ev in cur.get("data") or []:
    action = (ev.get("action") or ev.get("status") or "").lower()
    if action != "blocked":
        continue
    pols = ev.get("policies") or []
    rows.append({
        "status": "blocked",
        "package": ev.get("package_name") or "",
        "version": ev.get("package_version") or "",
        "type": ev.get("package_type") or "",
        "repo": ev.get("curated_repository_name") or "",
        "policy": policy_names_for_event(ev, pols),
        "requested_by": ev.get("username") or ev.get("user_mail") or "—",
        "date": (ev.get("created_at") or "")[:10],
        "timestamp": ev.get("created_at") or "",
        "malicious": is_malicious(ev),
    })

counts = {}
for r in rows:
    key = (r["package"], r["type"])
    counts[key] = counts.get(key, 0) + 1

display = sorted(
    rows,
    key=lambda r: (
        1 if r.get("malicious") else 0,
        counts.get((r["package"], r["type"]), 0),
        r.get("timestamp") or "",
    ),
    reverse=True,
)[:CAP]

def user_id(ev):
    u = (ev.get("username") or "").strip()
    m = (ev.get("user_mail") or "").strip()
    return u or m or None

user_stats = {}
for ev in cur.get("data") or []:
    uid = user_id(ev)
    if not uid:
        continue
    st = user_stats.setdefault(uid, {
        "user": uid,
        "events": 0,
        "blocked": 0,
        "approved": 0,
        "passed": 0,
        "_packages": Counter(),
    })
    st["events"] += 1
    action = (ev.get("action") or ev.get("status") or "").lower()
    if action in ("blocked", "approved", "passed"):
        st[action] += 1
    package = (ev.get("package_name") or ev.get("package") or "unknown").strip()
    ecosystem = normalize_pkg_type(ev.get("package_type"))
    st["_packages"][(package, ecosystem)] += 1

attributed_events = sum(st["events"] for st in user_stats.values())
user_package_activity = [
    {
        "user": st["user"],
        "user_events": st["events"],
        "user_events_pct": round(st["events"] / attributed_events * 100, 1) if attributed_events else 0,
        "user_blocked": st["blocked"],
        "user_approved": st["approved"],
        "package": package,
        "ecosystem": ecosystem,
        "requests": count,
    }
    for st in user_stats.values()
    for (package, ecosystem), count in st["_packages"].items()
]
user_package_activity.sort(key=lambda row: (-row["requests"], row["user"], row["package"], row["ecosystem"]))
top_users = []
for st in sorted(user_stats.values(), key=lambda x: (-x["events"], x["user"]))[:25]:
    packages = [
        {"package": package, "ecosystem": ecosystem, "requests": count}
        for (package, ecosystem), count in st.pop("_packages").most_common(25)
    ]
    st["events_pct"] = round(st["events"] / attributed_events * 100, 1) if attributed_events else 0
    st["packages"] = packages
    top_users.append(st)

curation = data.setdefault("curation", {})
curation["audit_events"] = rows
curation["audit_events_display"] = display
curation["audit_events_display_meta"] = {
    "cap": CAP,
    "sort": "malicious_then_package_count_then_newest",
    "total_blocked": len(rows),
}
registry = load_policy_registry()
events = cur.get("data") or []

curation["unique_users"] = len(user_stats)
curation["top_users"] = top_users
curation["user_package_activity"] = user_package_activity
curation["request_results"] = build_request_results(events)
curation["blocked"] = curation["request_results"]["blocked"]
curation["approved"] = curation["request_results"]["approved"]
curation["clean_packages"] = curation["request_results"]["clean_packages"]
decided = curation["blocked"] + curation["clean_packages"]
curation["clean_rate"] = round(curation["clean_packages"] / decided * 100, 1) if decided else 0
curation["without_inspection"] = curation["request_results"]["without_inspection"]
curation["top_blocked"] = build_top_blocked(events)
curation["policies_enforced"] = build_policies_enforced(events, registry)
curation["policy_inventory"] = build_policy_inventory(registry)
if os.path.isfile("/tmp/ciso-curation-waivers.json"):
  curation["waiver_requests"] = json.load(open("/tmp/ciso-curation-waivers.json"))
else:
  curation["waiver_requests"] = {"available": False, "pending": 0, "approved": 0, "rejected": 0}
curation["curation_state"] = build_curation_state(events)
state = curation["curation_state"]
curation["policy_violations_by_type"] = build_policy_violations_by_type(events)
# Keep by_reason aligned with audit-derived violations (overwrite jq partial counts when events exist).
if curation["policy_violations_by_type"]["total_blocked"] > 0:
  curation["by_reason"] = {
    "malicious": curation["policy_violations_by_type"]["malicious"],
    "security": curation["policy_violations_by_type"]["security"],
    "license": curation["policy_violations_by_type"]["license"],
    "operational": curation["policy_violations_by_type"]["operational"],
  }
by_pol = curation["policies_enforced"].get("by_policy") or []
curation["blocking_events_per_policy"] = sorted(
  [
    {
      "name": p.get("name"),
      "scope_label": p.get("scope_label"),
      "blocked_events": int(p.get("blocked_hits") or 0),
      "audit_events": int(p.get("audit_hits") or 0),
      "action": p.get("action"),
    }
    for p in by_pol
    if int(p.get("blocked_hits") or 0) > 0
  ],
  key=lambda x: (-x["blocked_events"], -x["audit_events"], x["name"] or ""),
)[:5]
if not curation["blocking_events_per_policy"] and int(curation.get("blocked") or 0) > 0:
  curation["blocking_events_per_policy"] = [{
    "name": "Policy attribution unavailable",
    "scope_label": "Audit event did not include policy details",
    "blocked_events": int(curation.get("blocked") or 0),
    "audit_events": int(curation.get("blocked") or 0),
    "action": "blocked",
  }]
curation["top_policies"] = curation["blocking_events_per_policy"]
curation["package_types"] = build_package_types_insights(events, state)
# Blocked-by-ecosystem on package type rows for UI table
blocked_pkg = {r["package_type"]: r["blocked"] for r in curation["package_types"].get("top_by_blocked") or []}
for row in state.get("by_package_type") or []:
  pt = row.get("package_type")
  row["blocked_period"] = int(blocked_pkg.get(pt, 0))

plat = data.setdefault("platform", {})
inv = curation["policy_inventory"]
pe = curation["policies_enforced"]
plat["curation_policies_global"] = sum(s.get("enforcing", 0) for s in pe.get("by_scope", []) if s.get("scope") in ("all_repos", "global"))
plat["curation_policies_repo"] = sum(s.get("enforcing", 0) for s in pe.get("by_scope", []) if s.get("scope") in ("specific_repos", "repository"))
plat["curation_policies_user"] = sum(s.get("enforcing", 0) for s in pe.get("by_scope", []) if s.get("scope") == "user")
plat["curation_policies_block"] = inv.get("block_active", 0)
plat["curation_policies_dry_run"] = inv.get("dry_run_active", 0)
plat["curation_policies_total"] = inv.get("total_registered", pe.get("total_registered", 0))
if curation.get("curation_state"):
  plat["curation_state"] = curation["curation_state"]
state = curation.get("curation_state") or {}
plat["curation_enabled"] = bool(
  curation.get("available")
  or int(curation.get("total") or 0) > 0
  or int(curation.get("blocked") or 0) > 0
  or int(inv.get("total_registered") or 0) > 0
  or int(plat.get("curation_policies_total") or 0) > 0
  or int(state.get("remote_total") or 0) > 0
  or int(state.get("supported_remote_total") or 0) > 0
  or int(state.get("connected") or 0) > 0
  or int(state.get("supported_connected") or 0) > 0
)
if not int(plat.get("curation_repos_count") or 0) and int(state.get("remote_total") or 0) > 0:
  plat["curation_repos_count"] = int(state.get("remote_total") or 0)

benefit = data.setdefault("benefit", {})
benefit.update(build_upgrade_rate(events))

# curation.total must be full audit volume, not blocked-only.
if os.path.isfile("/tmp/ciso-curation-diagnostics.json"):
  diag = json.load(open("/tmp/ciso-curation-diagnostics.json"))
  reported = int(diag.get("total_count_reported") or 0)
  if reported > 0:
    curation["total"] = reported
  elif len(events) > 0 and int(curation.get("total", 0) or 0) < len(events):
    curation["total"] = len(events)

# Governance: Xray watches + Curation gate policies (never "Unknown" stub).
g = data.setdefault("governance", {})
v = data.get("violations") or {}
blocked_total = max(int(curation.get("blocked") or 0), 1)
v_total = max(int(v.get("total") or 0), 1)

xray_rows = []
for row in v.get("top_watch_policies") or []:
  hits = int(row.get("hits") or 0)
  if hits <= 0:
    continue
  xray_rows.append({
    "policy": row.get("policy") or "—",
    "type": row.get("type") or "security",
    "hits": hits,
    "pct_of_events": round((hits / v_total) * 100),
    "delta_pct": int(row.get("delta_pct") or 0),
  })
xray_rows.sort(key=lambda x: -x["hits"])

cur_rows = []
for row in curation.get("blocking_events_per_policy") or []:
  hits = int(row.get("blocked_events") or 0)
  if hits <= 0:
    continue
  cur_rows.append({
    "policy": row.get("name") or "—",
    "type": "curation",
    "hits": hits,
    "pct_of_events": round((hits / blocked_total) * 100),
    "delta_pct": 0,
    "scope_label": row.get("scope_label"),
  })
# Fallback: derive from policies_enforced if blocking list empty
if not cur_rows:
  for row in (curation.get("policies_enforced") or {}).get("by_policy") or []:
    hits = int(row.get("blocked_hits") or 0)
    if hits <= 0:
      continue
    cur_rows.append({
      "policy": row.get("name"),
      "type": "curation",
      "hits": hits,
      "pct_of_events": round((hits / blocked_total) * 100),
      "delta_pct": 0,
      "scope_label": row.get("scope_label"),
    })
cur_rows.sort(key=lambda x: -x["hits"])

g["xray_policy_effectiveness"] = xray_rows[:15]
g["curation_policy_effectiveness"] = cur_rows[:15]
g["policy_effectiveness"] = xray_rows[:15]
g["repo_watch_summary"] = {
  "total": int(plat.get("repos_total") or 0),
  "indexed": int(plat.get("repos_indexed") or 0),
  "unindexed": int(plat.get("repos_unindexed") or 0),
  "withWatch": None,
  "withoutWatch": None,
}

# Strip policy names from top_blocked for CISO-facing JSON (detail lives in policies_enforced).
for pkg in curation.get("top_blocked") or []:
  if isinstance(pkg, dict):
    pkg.pop("policies", None)
    pkg.pop("policy", None)

json.dump(data, open("/tmp/ciso-data.json", "w"), indent=2)
print(
  f"audit transform merged: blocked={len(rows)} display={len(display)} "
  f"unique_users={len(user_stats)} enforcing_policies={curation['policies_enforced'].get('enforcing', 0)}"
)
PY
```

This must populate `curation.audit_events`, `curation.audit_events_display`,
`curation.audit_events_display_meta`, **`curation.unique_users`**, **`curation.top_users`**, and **`curation.policies_enforced`** in the final JSON.

Copy these fields into the saved `data.json` — do not drop them when merging sections.

**UI link:** set `meta.curation_audit_ui_path` to `/ui/package-curation/audit` (not `/ui/curation/audit`).


## Module: violations

**Authoritative API docs:** Read `../jfrog/references/xray-entities.md` → "Violations" → "API: POST /api/v1/violations".

```bash
jf xr curl -s --server-id "$SERVER_ID" -XPOST "/api/v1/violations" \
  -H "Content-Type: application/json" \
  -d "{\"filters\":{\"created_from\":\"${DATE_FROM}\",\"created_until\":\"${DATE_TO}\"},\"pagination\":{\"limit\":500,\"order_by\":\"severity\",\"direction\":\"desc\"}}"
```

**Performance note:** Always include `created_from` to avoid timeouts on large instances.

For large instances, run deterministic parallel pagination inline:

```bash
python3 - <<'PY'
import json, os, subprocess
from concurrent.futures import ThreadPoolExecutor, as_completed

server = os.environ["SERVER_ID"].strip()
date_from = os.environ["DATE_FROM"].strip()
date_to = os.environ["DATE_TO"].strip()
limit = int(os.environ.get("CISO_VIOLATIONS_LIMIT", "500"))
concurrency = max(1, min(int(os.environ.get("CISO_VIOLATIONS_CONCURRENCY", "4")), 8))

def fetch(offset: int):
  body = json.dumps({
    "filters":{"created_from":date_from, "created_until":date_to},
    "pagination":{"limit":limit, "offset":offset, "order_by":"severity", "direction":"desc"}
  })
  p = subprocess.run(
    ["jf","xr","curl","-s","--server-id",server,"-XPOST","/api/v1/violations","-H","Content-Type: application/json","-d",body],
    capture_output=True, text=True, check=True
  )
  data = json.loads(p.stdout or "{}")
  if not isinstance(data, dict):
    raise TypeError(f"violations page offset={offset}: expected JSON object, got {type(data).__name__}")
  return data

pages = {0: fetch(0)}
if len(pages[0].get("violations") or []) >= limit:
  high = 0
  while len(pages[high].get("violations") or []) >= limit:
    batch_start = high + limit
    offsets = [batch_start + i * limit for i in range(concurrency)]
    got = {}
    with ThreadPoolExecutor(max_workers=concurrency) as pool:
      futs = {pool.submit(fetch, off): off for off in offsets}
      for fut in as_completed(futs):
        got[futs[fut]] = fut.result()
    stop_offset = None
    for off in sorted(got):
      pages[off] = got[off]
      if len(got[off].get("violations") or []) < limit:
        stop_offset = off
        break
    if stop_offset is not None:
      pages = {k: v for k, v in pages.items() if k <= stop_offset}
      break
    high = offsets[-1]

violations = []
total_violations = 0
for off in sorted(pages):
  pg = pages[off]
  if not isinstance(pg, dict):
    raise TypeError(f"violations merge offset={off}: expected object page, got {type(pg).__name__}")
  violations.extend(pg.get("violations") or [])
  total_violations = max(total_violations, int(pg.get("total_violations") or 0))
if total_violations == 0 and violations:
  total_violations = len(violations)
json.dump({"violations": violations, "total_violations": total_violations}, open("/tmp/ciso-violations.json", "w"), indent=2)
print(f"violations merged: rows={len(violations)} total={total_violations}")
PY
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
  unique_issues: [(.violations // [])[] | .issue_id // empty] | unique | length,
  top_cves: [
    (.violations // [])[]
    | select(.severity == "Critical" or .severity == "High")
    | {
        id: (.cve // .issue_id // "unknown"),
        cvss: (.cvss_v3 // .cvss_v2 // null),
        component: (.infected_components[0] // .component // "unknown"),
        severity: .severity
      }
  ]
  | group_by(.id)
  | map({
      id: .[0].id,
      cvss: .[0].cvss,
      severity: .[0].severity,
      packages: ([.[].component] | unique | length),
      hits: length
    })
  | sort_by(-.hits)
  | .[0:5],
  top_watch_policies: [
    (.violations // [])[]
    | (.watch_name // empty)
    | select(. != "" and . != "—")
  ]
  | group_by(.)
  | map({ policy: .[0], type: "security", hits: length })
  | sort_by(-.hits)
  | .[0:15]
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
      days_open: (days from first_seen to report end date; compute in producer if API omits it),
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

## Module: collection-determinism-guards

Run after Phase 1 collect and after curation audit transform.

```bash
python3 - <<'PY'
import json, os, sys

viol = json.load(open('/tmp/ciso-violations.json'))
cur = json.load(open('/tmp/ciso-curation.json'))
diag = json.load(open('/tmp/ciso-curation-diagnostics.json'))
data = json.load(open('/tmp/ciso-data.json'))

# Guard 1: violations totals should never undercount merged rows.
v_rows = len(viol.get('violations') or [])
v_total = int(viol.get('total_violations') or 0)
if v_total < v_rows:
  print(f"ERROR: total_violations({v_total}) < rows({v_rows})")
  sys.exit(1)

# Guard 2: curation diagnostics coherence.
c_rows = len(cur.get('data') or [])
d_rows = int(diag.get('rows_fetched') or 0)
if c_rows != d_rows and int(diag.get('http_status') or 0) == 200:
  print(f"ERROR: curation rows mismatch data={c_rows} diagnostics={d_rows}")
  sys.exit(1)

# Guard 3: blocked-only audit_events + display metadata.
curation = data.get('curation', {}) or {}
events = curation.get('audit_events') or []
bad = [e for e in events if str(e.get('status', '')).lower() != 'blocked']
if bad:
  print(f"ERROR: audit_events includes non-blocked rows ({len(bad)})")
  sys.exit(1)
meta = curation.get('audit_events_display_meta') or {}
if not meta.get('cap') or not meta.get('sort'):
  print("ERROR: missing audit_events_display_meta.cap/sort")
  sys.exit(1)

# Guard 4: unique users required when audit data exists.
if c_rows > 0 and int(curation.get('unique_users', 0) or 0) == 0:
  print('ERROR: curation.unique_users is 0 but audit rows exist — run curation-audit-transform')
  sys.exit(1)

diag_total = int(diag.get('total_count_reported') or 0)
if diag_total > 0 and int(curation.get('total', 0) or 0) < diag_total:
  print(f"ERROR: curation.total({curation.get('total')}) < audit total_count({diag_total})")
  sys.exit(1)

plat = data.get('platform', {}) or {}
v_total = int((data.get('violations') or {}).get('total', 0) or 0)
if v_total > 0 and int(plat.get('repos_indexed', 0) or 0) == 0:
  print('ERROR: platform.repos_indexed is 0 — run platform merge')
  sys.exit(1)
if v_total > 0 and int(plat.get('watches_total', 0) or 0) == 0 and int(plat.get('policies_total', 0) or 0) == 0:
  print('ERROR: platform watches/policies are 0 — use /api/v2/watches and /api/v2/policies')
  sys.exit(1)

inv = curation.get('policy_inventory') or {}
if int(curation.get('blocked', 0) or 0) > 0 and not inv.get('total_registered'):
  print('ERROR: policy_inventory missing — run curation-audit-transform after platform merge')
  sys.exit(1)

if int(curation.get('blocked', 0) or 0) > 0 and not curation.get('blocking_events_per_policy'):
  print('ERROR: blocking_events_per_policy missing')
  sys.exit(1)

g = data.get('governance') or {}
bad_gov = [r for r in (g.get('curation_policy_effectiveness') or []) if str(r.get('policy','')).lower() == 'unknown']
if bad_gov:
  print('ERROR: governance has Unknown curation policy rows — use transform governance builder')
  sys.exit(1)

pe = curation.get('policies_enforced') or {}
if curation.get('available') and not pe.get('available') and os.path.isfile('/tmp/ciso-curation-policies.json'):
  print('WARNING: curation.policies_enforced missing — re-run curation-audit-transform')

print("Determinism guards passed")
PY
```

## Module: license

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

## Module: operational

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

## Module: benefit (derived metrics)

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

### Block-then-upgrade detection (upgrade_rate)
For each unique blocked package name, check if the same package appears in
approved events at a different (higher) version in the same period.

```text
upgrade_rate = (packages with block-then-upgrade / unique blocked packages) * 100
```

Set `benefit.upgrade_rate_computed: true` when calculated. If not computed, omit
`upgrade_rate` or set `null` — do not use `approved / total` as a substitute.

## Module: comparison

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

## Module: governance

Populate in **`curation-audit-transform`** (do not hand-write `Unknown` / `curation` stubs).

| Field | Source |
|-------|--------|
| `governance.xray_policy_effectiveness` | `violations.top_watch_policies` |
| `governance.curation_policy_effectiveness` | `curation.blocking_events_per_policy` |
| `governance.policy_effectiveness` | Same as Xray list (legacy alias) |
| `governance.repo_watch_summary` | `platform.repos_indexed` / `repos_total` |

### policy_effectiveness (Xray)

**Use Xray watch policy hits from violations**, not the curation policy registry (curation policies belong in `curation.blocking_events_per_policy` / Gate defense).

Preferred source: `violations.top_watch_policies` from the violations jq mapping. For each row:

```json
{
  "policy": "watch-name-or-policy-name",
  "type": "security",
  "hits": 182,
  "pct_of_events": 31,
  "delta_pct": -5
}
```

`pct_of_events` = `round(hits / violations.total * 100)`. Compare hits to the previous snapshot’s per-policy counts for `delta_pct` when available.

Legacy: group policy/watch hits manually and compute share + delta.

```json
{
  "policy": "block-malicious",
  "type": "security",
  "hits": 182,
  "pct_of_events": 31,
  "delta_pct": -5
}
```

If no previous data, set `delta_pct: 0` (dashboard explains this as “no prior per-policy snapshot”).

### repo_watch_coverage

Build a risk-prioritized list of repositories with **per-repo** `watch_count` from Xray watch
resource mappings (not platform-wide `watches_active`). Do not substitute a single summary row
with `watch_count` equal to total watches — the dashboard hides misleading summary rows.

```json
{
  "repo": "docker-local",
  "indexed": true,
  "watch_count": 3,
  "risk_level": "high"
}
```

## Module: threat-velocity

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

## Module: recommendations-metadata

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

## Module: adding-a-kpi

When adding a badge/KPI months later, use this sequence to avoid broad rewrites:

1. **Collect**: add/extend one module block that fetches required source data to
   a new `/tmp/ciso-*.json` artifact.
2. **Map**: add one schema-mapping jq block that writes the KPI field into
   `/tmp/ciso-data.json`.
3. **Schema**: add the field contract to `report-schema.md` with type/default.
4. **Render**: add a renderer card/badge in `dashboard.html` that reads only that
   new field (no side effects on other sections).
5. **Guard**: add one deterministic check in `Module: collection-determinism-guards`
   or SKILL gates to ensure the KPI is populated/coherent.

This keeps changes scoped to one module per layer instead of touching all logic.

## Module: methodology (optional, configurable explanations)

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
    "approved": "Allowed after Curation policy evaluation (clean package).",
    "dry_run": "Evaluated in alert-only mode (passed with alert).",
    "without_inspection": "Download reached the client without policy inspection — may be vulnerable or malicious."
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

## Module: storage-upload

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

## Module: error-handling

- 404/403 from any API: record 0 or "N/A" — never crash, never skip other sections
- `jf` not configured: stop with clear message
- Empty responses: use defaults from schema (0, [], null)
- Curation audit returns 404: set `curation.available: false`, but still collect all other data
- Always produce a report even with partial data — missing sections are better than no report
