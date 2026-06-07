#!/usr/bin/env bash
# Live proof that CISO report fields are retrievable from JFrog APIs.
# Private helper. Invoke through ../bin/generate-ciso-report.sh for normal reports.
# Usage: internal/verify-ciso-collection-proof.sh [server-id]
set -euo pipefail
export PATH="${HOME}/.local/bin:${PATH:-/opt/homebrew/bin:/usr/local/bin:$PATH}"

SERVER_ID="${1:-solenglatest}"
echo "=== CISO collection proof for ${SERVER_ID} ==="

python3 - <<PY
import json, os, subprocess, datetime
from collections import Counter, defaultdict

server = os.environ.get("SERVER_ID", "${SERVER_ID}").strip()

def jf_xr(path, method="GET", body=None):
    cmd = ["jf", "xr", "curl", "-s", "--server-id", server, "-X" + method, path]
    if body is not None:
        cmd += ["-H", "Content-Type: application/json", "-d", json.dumps(body)]
    p = subprocess.run(cmd, capture_output=True, text=True)
    return p.stdout

def jf_rt(path):
    p = subprocess.run(["jf", "rt", "curl", "-s", "--server-id", server, "-XGET", path],
                       capture_output=True, text=True)
    return p.stdout

def parse(raw):
    raw = (raw or "").strip()
    if raw.startswith("404") or raw.startswith("403"):
        return None
    try:
        return json.loads(raw)
    except Exception:
        return None

fail = []

# 1. Indexed
idx = parse(jf_xr("/api/v1/binMgr/default/repos")) or {}
n_idx = len(idx.get("indexed_repos") or [])
print(f"[{'OK' if n_idx else 'FAIL'}] repos_indexed: {n_idx}")
if not n_idx:
    fail.append("repos_indexed")

# 2. Watches / policies
w = parse(jf_xr("/api/v2/watches"))
n_w = len(w) if isinstance(w, list) else 0
print(f"[{'OK' if n_w else 'FAIL'}] watches_total: {n_w}")
if not n_w:
    fail.append("watches")

pol = parse(jf_xr("/api/v2/policies"))
if isinstance(pol, list):
    n_p = len(pol)
elif isinstance(pol, dict) and isinstance(pol.get("result"), list):
    n_p = len(pol.get("result") or [])
elif isinstance(pol, dict) and pol.get("total") is not None:
    n_p = int(pol.get("total") or 0)
else:
    n_p = 0
print(f"[{'OK' if n_p else 'FAIL'}] xray policies_total: {n_p}")
if not n_p:
    fail.append("xray_policies")

# 3. Curation policies
items, offset, total = [], 0, 0
while True:
    body = parse(jf_xr(f"/api/v1/curation/policies?num_of_rows=200&offset={offset}")) or {}
    batch = body.get("data") or []
    total = int((body.get("meta") or {}).get("total_count") or total or len(batch))
    items.extend(batch)
    if not batch or len(items) >= total:
        break
    offset += len(batch)
block = sum(1 for p in items if p.get("enabled", True) and (p.get("policy_action") or "").replace("-", "_").lower() != "dry_run")
dry = sum(1 for p in items if p.get("enabled", True) and (p.get("policy_action") or "").replace("-", "_").lower() == "dry_run")
print(f"[{'OK' if total else 'FAIL'}] curation policies registered: {total} (block={block}, dry_run={dry})")
if not total:
    fail.append("curation_policies")

# 4. Audit users + blocking policies (scan up to 10k rows)
dt = datetime.datetime.now(datetime.timezone.utc)
df = (dt - datetime.timedelta(days=7)).strftime("%Y-%m-%dT%H:%M:%SZ")
dt_s = dt.strftime("%Y-%m-%dT%H:%M:%SZ")
users, pol_blk = set(), Counter()
blocked_events = 0
for offset in range(0, 12000, 2000):
    page = parse(jf_xr(
        f"/api/v1/curation/audit/packages?num_of_rows=2000&offset={offset}"
        f"&created_at_start={df}&created_at_end={dt_s}&dry_run=false"
    )) or {}
    rows = page.get("data") or []
    if not rows:
        break
    for ev in rows:
        u = (ev.get("username") or "").strip() or (ev.get("user_mail") or "").strip()
        if u:
            users.add(u)
        if (ev.get("action") or ev.get("status") or "").lower() == "blocked":
            blocked_events += 1
            for pol in ev.get("policies") or []:
                if pol.get("dry_run"):
                    continue
                n = (pol.get("policy_name") or "").strip()
                if n:
                    pol_blk[n] += 1

print(f"[{'OK' if users else 'FAIL'}] curation unique_users (partial/full scan): {len(users)}")
if not users:
    fail.append("unique_users")
print(f"[{'OK' if pol_blk else 'WARN'}] blocking policies with names: {len(pol_blk)}")
for name, c in pol_blk.most_common(5):
    print(f"      top block: {name} ({c})")
if not pol_blk:
    if blocked_events:
        print(f"      {blocked_events} blocked event(s) found, but audit rows did not include policy names")
    else:
        fail.append("blocking_policies")

# 5. Remote curated count (list + sample only for speed in CI)
remotes = parse(jf_rt("/api/repositories?type=remote")) or []
keys = [r.get("key") for r in remotes if isinstance(r, dict) and r.get("key")]
sample = keys[:5]
connected_sample = 0
for key in sample:
    cfg = parse(jf_rt(f"/api/repositories/{key}"))
    if isinstance(cfg, dict) and cfg.get("curated") is True:
        connected_sample += 1
print(f"[INFO] remote repos listed: {len(keys)} (sample curated {connected_sample}/{len(sample)} — run platform merge for full {len(keys)} scan)")
print("")
if fail:
    print("FAILED checks:", ", ".join(fail))
    raise SystemExit(1)
print("All critical fields are retrievable. Run platform merge + curation-audit-transform before rendering.")
PY
