#!/usr/bin/env bash
# Live repair for an under-enriched CISO report folder.
# Usage: ./scripts/repair-ciso-report.sh <server-id> <report-dir>
set -euo pipefail
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-}"

SERVER_ID="${1:?server-id required}"
REPORT_DIR="${2:?report directory required}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
SKILL_DIR="$REPO_ROOT/Dashboard-ciso-report-skills"
DATA_PATH="${REPORT_DIR%/}/data.json"
REPORT_PATH="${REPORT_DIR%/}/report.html"
SNAPSHOT_PATH="${REPORT_DIR%/}/snapshot.json"
RUN_META_PATH="${REPORT_DIR%/}/run-meta.json"
TEMPLATE_PATH="$SKILL_DIR/references/dashboard.html"

if [[ ! -f "$DATA_PATH" ]]; then
  echo "ERROR: missing $DATA_PATH" >&2
  exit 1
fi
if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "ERROR: missing dashboard template: $TEMPLATE_PATH" >&2
  exit 1
fi

export SERVER_ID REPORT_DIR DATA_PATH REPORT_PATH SNAPSHOT_PATH RUN_META_PATH

# Never reuse stale runtime data for a repair.
rm -f /tmp/ciso-data.json /tmp/ciso-platform.json /tmp/ciso-curation.json \
  /tmp/ciso-curation-diagnostics.json /tmp/ciso-curation-page-*.json \
  /tmp/ciso-curation-policies.json /tmp/ciso-curation-policies-raw.json \
  /tmp/ciso-indexed-repos.json /tmp/ciso-watches.json /tmp/ciso-policies.json \
  /tmp/ciso-repos-all.json /tmp/ciso-repos-remote.json /tmp/ciso-violations-page-*.json

python3 - <<'PY'
import json, os
from datetime import datetime, timedelta, timezone

data = json.load(open(os.environ["DATA_PATH"]))
meta = data.get("meta", {})
run_meta_path = os.environ["RUN_META_PATH"]
diag = {}
if os.path.isfile(run_meta_path):
    diag = (json.load(open(run_meta_path)).get("curation_diagnostics") or {})

date_to = diag.get("date_to")
date_from = diag.get("date_from")
if not date_to or not date_from:
    end = datetime.now(timezone.utc)
    start = end - timedelta(days=int(meta.get("window_days") or 7))
    date_from = start.strftime("%Y-%m-%dT%H:%M:%SZ")
    date_to = end.strftime("%Y-%m-%dT%H:%M:%SZ")

os.environ["DATE_FROM"] = date_from
os.environ["DATE_TO"] = date_to
os.environ["REPORT_TYPE"] = str(meta.get("report_type") or "weekly").lower()
print(f"repair window: {date_from} -> {date_to}")
PY

export DATE_FROM="$(python3 - <<'PY'
import json, os
run = json.load(open(os.environ["RUN_META_PATH"])) if os.path.isfile(os.environ["RUN_META_PATH"]) else {}
diag = run.get("curation_diagnostics") or {}
print(diag.get("date_from") or "")
PY
)"
export DATE_TO="$(python3 - <<'PY'
import json, os
run = json.load(open(os.environ["RUN_META_PATH"])) if os.path.isfile(os.environ["RUN_META_PATH"]) else {}
diag = run.get("curation_diagnostics") or {}
print(diag.get("date_to") or "")
PY
)"
if [[ -z "$DATE_FROM" || -z "$DATE_TO" ]]; then
  DATE_TO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  if date -u -v-7d +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
    DATE_FROM="$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)"
  else
    DATE_FROM="$(date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ)"
  fi
fi
export REPORT_TYPE="$(python3 - <<'PY'
import json, os
d = json.load(open(os.environ["DATA_PATH"]))
print(str((d.get("meta") or {}).get("report_type") or "weekly").lower())
PY
)"

echo "=== collect curation audit ==="
python3 - <<'PY'
import json, os, subprocess
from datetime import datetime, timedelta, timezone

server = os.environ["SERVER_ID"]
date_from = os.environ["DATE_FROM"]
date_to = os.environ["DATE_TO"]
report_type = os.environ.get("REPORT_TYPE", "weekly").lower()
limit = 2000

def parse_rfc3339(s):
    return datetime.fromisoformat(s.replace("Z", "+00:00"))

def clamp_weekly(start, end):
    s, e = parse_rfc3339(start), parse_rfc3339(end)
    if report_type == "weekly" and (e - s).total_seconds() > 168 * 3600:
        s = e - timedelta(hours=168)
        return s.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"), end
    return start, end

def get_page(offset):
    path = (
        "/api/v1/curation/audit/packages"
        f"?order_by=id&direction=desc&num_of_rows={limit}"
        f"&created_at_start={date_from}&created_at_end={date_to}"
        f"&include_total=true&offset={offset}"
    )
    p = subprocess.run(
        ["jf", "xr", "curl", "-s", "-w", "%{http_code}", "--server-id", server, "-XGET", path],
        capture_output=True, text=True,
    )
    raw = p.stdout or ""
    status = int(raw[-3:]) if len(raw) >= 3 and raw[-3:].isdigit() else (200 if p.returncode == 0 else 500)
    body = raw[:-3] if len(raw) >= 3 and raw[-3:].isdigit() else raw
    return status, json.loads(body or "{}")

date_from, date_to = clamp_weekly(date_from, date_to)
rows, pages, reported, status = [], 0, 0, 200
offset = 0
while True:
    status, body = get_page(offset)
    if status in (403, 404):
        rows, reported = [], 0
        break
    batch = body.get("data") or []
    rows.extend(batch)
    pages += 1
    reported = max(reported, int((body.get("meta") or {}).get("total_count") or 0))
    if len(batch) < limit:
        break
    offset += limit

json.dump({"data": rows, "meta": {"total_count": reported}}, open("/tmp/ciso-curation.json", "w"), indent=2)
json.dump({
    "http_status": status,
    "mode": report_type,
    "pages_fetched": pages,
    "rows_fetched": len(rows),
    "total_count_reported": reported,
    "date_from": date_from,
    "date_to": date_to,
}, open("/tmp/ciso-curation-diagnostics.json", "w"), indent=2)
print(f"curation rows={len(rows)} reported={reported} pages={pages} status={status}")
PY

echo "=== collect violations pages ==="
python3 - <<'PY'
import json, os, subprocess

server = os.environ["SERVER_ID"]
date_from = os.environ["DATE_FROM"]
date_to = os.environ["DATE_TO"]
limit = 500
offset = 0
pages = 0
total = 0
while True:
    body = {
        "filters": {"created_from": date_from, "created_until": date_to},
        "pagination": {"limit": limit, "offset": offset, "order_by": "severity", "direction": "desc"},
    }
    p = subprocess.run(
        ["jf", "xr", "curl", "-s", "--server-id", server, "-XPOST", "/api/v1/violations",
         "-H", "Content-Type: application/json", "-d", json.dumps(body)],
        capture_output=True, text=True,
    )
    payload = json.loads(p.stdout or "{}")
    batch = payload.get("violations") or []
    total = int(payload.get("total_violations") or total or len(batch))
    json.dump(payload, open(f"/tmp/ciso-violations-page-{pages}.json", "w"), indent=2)
    pages += 1
    if len(batch) < limit or offset + len(batch) >= total:
        break
    offset += limit
print(f"violations pages={pages} total={total}")
PY

echo "=== enrich data.json ==="
CISO_ENRICH_ALLOW_EXISTING_TMP=true "$SKILL_DIR/internal/enrich-ciso-datajson.sh" "$SERVER_ID" "$DATA_PATH" "$DATA_PATH"

echo "=== validate enriched data ==="
python3 - <<'PY'
import json, os, sys
d = json.load(open(os.environ["DATA_PATH"]))
p, c, v, g = d.get("platform", {}), d.get("curation", {}), d.get("violations", {}), d.get("governance", {})
diag = json.load(open("/tmp/ciso-curation-diagnostics.json"))
errors = []
if int(p.get("repos_indexed") or 0) <= 0:
    errors.append("platform.repos_indexed is still zero")
if int(p.get("watches_total") or 0) <= 0:
    errors.append("platform.watches_total is still zero")
if int(p.get("policies_total") or 0) <= 0:
    errors.append("platform.policies_total is still zero")
if int(c.get("total") or 0) != int(diag.get("total_count_reported") or 0):
    errors.append(f"curation.total {c.get('total')} != diagnostics total {diag.get('total_count_reported')}")
if int(c.get("blocked") or 0) > 0 and not c.get("blocking_events_per_policy"):
    errors.append("blocking_events_per_policy missing")
if int(v.get("total") or 0) > 0 and not v.get("top_watch_policies"):
    errors.append("violations.top_watch_policies missing")
if int(v.get("total") or 0) > 0 and not g.get("xray_policy_effectiveness"):
    errors.append("governance.xray_policy_effectiveness missing")
if int(c.get("blocked") or 0) > 0 and not g.get("curation_policy_effectiveness"):
    errors.append("governance.curation_policy_effectiveness missing")
if errors:
    for err in errors:
        print("ERROR:", err)
    sys.exit(1)
print("validated:", {
    "repos_indexed": p.get("repos_indexed"),
    "watches_total": p.get("watches_total"),
    "policies_total": p.get("policies_total"),
    "curation_total": c.get("total"),
    "unique_users": c.get("unique_users"),
    "xray_governance": len(g.get("xray_policy_effectiveness") or []),
    "curation_governance": len(g.get("curation_policy_effectiveness") or []),
})
PY

echo "=== render report.html ==="
python3 - <<'PY'
import os
template = open(os.path.join(os.getcwd(), "Dashboard-ciso-report-skills/references/dashboard.html")).read()
data = open(os.environ["DATA_PATH"]).read().strip()
if "__CISO_DATA__" not in template:
    raise SystemExit("ERROR: template missing __CISO_DATA__")
open(os.environ["REPORT_PATH"], "w").write(template.replace("__CISO_DATA__", data))
print("report written:", os.environ["REPORT_PATH"])
PY

echo "=== write snapshot and run metadata ==="
python3 - <<'PY'
import json, os
d = json.load(open(os.environ["DATA_PATH"]))
snap = {
    "date": d.get("meta", {}).get("generated"),
    "type": str(d.get("meta", {}).get("report_type") or "weekly").lower(),
    "server_id": d.get("meta", {}).get("server_id"),
    "curation": {
        "total": d.get("curation", {}).get("total", 0),
        "blocked": d.get("curation", {}).get("blocked", 0),
        "approved": d.get("curation", {}).get("approved", 0),
        "passed": d.get("curation", {}).get("passed", 0),
    },
    "violations": {
        "total": d.get("violations", {}).get("total", 0),
        "critical": d.get("violations", {}).get("by_severity", {}).get("critical", 0),
        "high": d.get("violations", {}).get("by_severity", {}).get("high", 0),
        "medium": d.get("violations", {}).get("by_severity", {}).get("medium", 0),
        "low": d.get("violations", {}).get("by_severity", {}).get("low", 0),
    },
    "components": len(d.get("operational", {}).get("top_components", [])),
    "license": d.get("license", {}).get("total", 0),
}
json.dump(snap, open(os.environ["SNAPSHOT_PATH"], "w"), indent=2)

run_meta = {}
if os.path.isfile(os.environ["RUN_META_PATH"]):
    run_meta = json.load(open(os.environ["RUN_META_PATH"]))
run_meta.update({
    "server_id": os.environ["SERVER_ID"],
    "output_path": os.environ["REPORT_PATH"],
    "data_source": "live",
    "fallback_mode": {"used": False, "user_requested": False},
    "repair": {"used": True, "script": "scripts/repair-ciso-report.sh"},
    "curation_diagnostics": json.load(open("/tmp/ciso-curation-diagnostics.json")),
})
json.dump(run_meta, open(os.environ["RUN_META_PATH"], "w"), indent=2)
print("snapshot written:", os.environ["SNAPSHOT_PATH"])
print("run metadata written:", os.environ["RUN_META_PATH"])
PY

echo "=== smoke proof ==="
"$SKILL_DIR/internal/verify-ciso-collection-proof.sh" "$SERVER_ID"
