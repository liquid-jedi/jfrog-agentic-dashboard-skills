#!/usr/bin/env bash
# Re-run platform merge + curation-audit-transform on an existing data.json skeleton.
# Private helper. Invoke through ../bin/generate-ciso-report.sh.
# Usage: internal/enrich-ciso-datajson.sh <server-id> <input-data.json> [output-data.json]
set -euo pipefail
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-}"

SERVER_ID="${1:?server-id required}"
INPUT="${2:?input data.json required}"
OUTPUT="${3:-$INPUT}"
SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
COLLECTION_DOC="$SKILL_DIR/references/report-data-collection.md"

export SERVER_ID
: "${CISO_ENRICH_ALLOW_EXISTING_TMP:=false}"

extract_py_block() {
  local heading="$1"
  python3 - "$COLLECTION_DOC" "$heading" <<'PY'
import sys
from pathlib import Path

path = Path(sys.argv[1])
heading = sys.argv[2]
lines = path.read_text().splitlines()

start = None
for i, line in enumerate(lines):
    if line.strip() == heading:
        start = i
        break
if start is None:
    raise SystemExit(f"ERROR: heading not found: {heading}")

fence = None
for i in range(start + 1, len(lines)):
    if lines[i].strip() == "```bash":
        fence = i
        break
    if lines[i].startswith("#") and i > start + 1:
        break
if fence is None:
    raise SystemExit(f"ERROR: bash fence not found after heading: {heading}")

py_start = None
for i in range(fence + 1, len(lines)):
    if lines[i].startswith("python3 - <<'PY'"):
        py_start = i + 1
        break
    if lines[i].strip() == "```":
        break
if py_start is None:
    raise SystemExit(f"ERROR: python heredoc not found after heading: {heading}")

for i in range(py_start, len(lines)):
    if lines[i].strip() == "PY":
        print("\n".join(lines[py_start:i]))
        raise SystemExit(0)

raise SystemExit(f"ERROR: python heredoc terminator not found after heading: {heading}")
PY
}

merge_curation_pages() {
  if [[ "$CISO_ENRICH_ALLOW_EXISTING_TMP" != "true" ]]; then
    echo "ERROR: refusing to enrich from ambient /tmp/ciso-* payloads. Use bin/generate-ciso-report.sh for fresh generation, or set CISO_ENRICH_ALLOW_EXISTING_TMP=true only immediately after fresh collection." >&2
    exit 1
  fi
  if [[ -f /tmp/ciso-curation.json ]] && [[ -s /tmp/ciso-curation.json ]]; then
    return 0
  fi
  python3 - <<'PY'
import glob, json, os
pages = sorted(glob.glob("/tmp/ciso-curation-page-*.json"))
if not pages:
    raise SystemExit("No /tmp/ciso-curation-page-*.json — re-run curation pagination first")
rows, reported = [], 0
for path in pages:
    body = json.load(open(path))
    rows.extend(body.get("data") or [])
    reported = max(reported, int((body.get("meta") or {}).get("total_count") or 0))
payload = {"data": rows, "meta": {"total_count": reported}}
json.dump(payload, open("/tmp/ciso-curation.json", "w"))
json.dump({
    "http_status": 200,
    "rows_fetched": len(rows),
    "total_count_reported": reported,
}, open("/tmp/ciso-curation-diagnostics.json", "w"), indent=2)
print(f"merged curation pages: rows={len(rows)} reported={reported}")
PY
}

ensure_indexed() {
  if [[ -f /tmp/ciso-indexed-repos.json ]] && [[ -s /tmp/ciso-indexed-repos.json ]]; then
    return 0
  fi
  jf xr curl -s --server-id "$SERVER_ID" "/api/v1/binMgr/default/repos" > /tmp/ciso-indexed-repos.json
}

ensure_policies() {
  if [[ ! -f /tmp/ciso-curation-policies.json ]] || [[ ! -s /tmp/ciso-curation-policies.json ]]; then
    jf xr curl -s --server-id "$SERVER_ID" "/api/v1/curation/policies?num_of_rows=200&offset=0" \
      > /tmp/ciso-curation-policies-raw.json 2>/dev/null || true
    python3 - <<'PY'
import json, subprocess, os
server = os.environ["SERVER_ID"]
items, offset, total = [], 0, 0
while True:
    path = f"/api/v1/curation/policies?num_of_rows=200&offset={offset}"
    p = subprocess.run(["jf","xr","curl","-s","--server-id",server,"-XGET",path], capture_output=True, text=True)
    body = json.loads(p.stdout or "{}")
    batch = body.get("data") or []
    total = int((body.get("meta") or {}).get("total_count") or total or len(batch))
    items.extend(batch)
    if not batch or len(items) >= total:
        break
    offset += len(batch)
json.dump({"data": items, "meta": {"total_count": total}}, open("/tmp/ciso-curation-policies.json", "w"), indent=2)
print(f"curation policies: {total}")
PY
  fi
}

if [[ "$INPUT" != "/tmp/ciso-data.json" ]]; then
  cp "$INPUT" /tmp/ciso-data.json
fi
merge_curation_pages
ensure_indexed
ensure_policies

echo "=== platform merge ==="
extract_py_block "### Platform merge (mandatory after Phase 1)" | python3

echo "=== merge platform into data.json ==="
extract_py_block '### Merge platform into `/tmp/ciso-data.json` (mandatory)' | python3

echo "=== patch violations.top_watch_policies ==="
python3 - <<'PY'
import json, os
from collections import Counter

data_path = "/tmp/ciso-data.json"
violations = []
import glob
for path in sorted(glob.glob("/tmp/ciso-violations-page-*.json")):
    body = json.load(open(path))
    violations.extend(body.get("violations") or [])
if not violations:
    for path in ("/tmp/ciso-violations-clean.json", "/tmp/ciso-violations-parsed.json"):
        if os.path.isfile(path) and os.path.getsize(path) > 2:
            body = json.load(open(path))
            violations = body if isinstance(body, list) else (body.get("violations") or [])
            if violations:
                break
if not violations:
    print("skip top_watch_policies: empty violations list")
    raise SystemExit(0)

hits = Counter()
for row in violations:
    if not isinstance(row, dict):
        continue
    watch = (row.get("watch_name") or row.get("watch") or "").strip()
    if watch and watch != "—":
        hits[watch] += 1

data = json.load(open(data_path))
v = data.setdefault("violations", {})
v["top_watch_policies"] = [
    {"policy": name, "type": "security", "hits": count, "delta_pct": 0}
    for name, count in hits.most_common(15)
]
json.dump(data, open(data_path, "w"), indent=2)
print(f"top_watch_policies: {len(v['top_watch_policies'])} watches")
PY

echo "=== curation-audit-transform ==="
extract_py_block "## Module: curation-audit-transform" | python3

if [[ "$OUTPUT" != "/tmp/ciso-data.json" ]]; then
  cp /tmp/ciso-data.json "$OUTPUT"
fi
python3 -c "
import json, sys
d = json.load(open(sys.argv[1]))
p = d.get('platform', {})
c = d.get('curation', {})
g = d.get('governance', {})
print('repos_indexed:', p.get('repos_indexed'))
print('watches_total:', p.get('watches_total'))
print('curation.total:', c.get('total'), 'blocked:', c.get('blocked'))
print('unique_users:', c.get('unique_users'))
print('policy_inventory:', (c.get('policy_inventory') or {}).get('total_registered'))
print('blocking_events:', len(c.get('blocking_events_per_policy') or []))
print('governance xray:', len(g.get('xray_policy_effectiveness') or []))
print('governance curation:', len(g.get('curation_policy_effectiveness') or []))
cs = p.get('curation_state') or {}
print('supported_connected:', cs.get('supported_connected'), '/', cs.get('supported_remote_total'))
" "$OUTPUT"
