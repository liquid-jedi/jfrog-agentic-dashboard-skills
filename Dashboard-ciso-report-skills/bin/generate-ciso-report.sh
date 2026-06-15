#!/usr/bin/env bash
# Deterministic execution spine for the agentic CISO dashboard skill.
# The agent resolves intent and narrative; this script guarantees live collection,
# transform order, validation, and rendering.
#
# Usage:
#   "$SKILL_DIR/bin/generate-ciso-report.sh" <server-id> <local-root> [weekly|monthly|custom]
#
# Optional env:
#   REPORT_DATE=YYYY-MM-DD
#   DATE_FROM=RFC3339_Z
#   DATE_TO=RFC3339_Z
#   SAVE_DATA_JSON=true|false
set -euo pipefail
export PATH="${HOME}/.local/bin:/opt/homebrew/bin:/usr/local/bin:${PATH:-}"

SERVER_ID="${1:?server-id required}"
LOCAL_ROOT="${2:?local root required}"
REPORT_TYPE="${3:-${REPORT_TYPE:-weekly}}"
REPORT_TYPE_LOWER="$(printf '%s' "$REPORT_TYPE" | tr '[:upper:]' '[:lower:]')"
REPORT_DATE_EXPLICIT="${REPORT_DATE+x}"
if [[ -n "${REPORT_DATE:-}" ]]; then
    REPORT_DATE="$REPORT_DATE"
elif [[ -n "${DATE_TO:-}" ]]; then
    REPORT_DATE="$(printf '%s' "$DATE_TO" | sed -E 's/T.*$//')"
else
    REPORT_DATE="$(date +%Y-%m-%d)"
fi
SAVE_DATA_JSON="${SAVE_DATA_JSON:-${CISO_SAVE_DATA_JSON:-true}}"
SAVE_DATA_JSON="$(printf '%s' "$SAVE_DATA_JSON" | tr '[:upper:]' '[:lower:]')"
case "$SAVE_DATA_JSON" in
  1|true|yes|on) SAVE_DATA_JSON="true" ;;
  *) SAVE_DATA_JSON="false" ;;
esac

SKILL_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATE_PATH="$SKILL_DIR/references/dashboard.html"
SERVER_SLUG="$(printf '%s' "$SERVER_ID" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9._-]/-/g')"
REPORT_TYPE_SLUG="$REPORT_TYPE_LOWER"
LOCAL_DIR="${LOCAL_ROOT%/}/${SERVER_SLUG}/${REPORT_TYPE_SLUG}/${REPORT_DATE}"
export SERVER_SLUG REPORT_TYPE_SLUG

mkdir -p "$LOCAL_DIR"

OUTPUT_PATH="${LOCAL_DIR}/report.html"
DATA_COPY_PATH="${LOCAL_DIR}/data.json"
SNAPSHOT_COPY_PATH="${LOCAL_DIR}/snapshot.json"
RUN_META_PATH="${LOCAL_DIR}/run-meta.json"

if [[ -f "$OUTPUT_PATH" && "${CISO_OVERWRITE_REPORT:-false}" != "true" ]]; then
  RERUN_DIR="${LOCAL_DIR}/rerun-$(date +%H%M%S)"
  mkdir -p "$RERUN_DIR"
  OUTPUT_PATH="${RERUN_DIR}/report.html"
  DATA_COPY_PATH="${RERUN_DIR}/data.json"
  SNAPSHOT_COPY_PATH="${RERUN_DIR}/snapshot.json"
  RUN_META_PATH="${RERUN_DIR}/run-meta.json"
  echo "Existing report found. Writing rerun to: $RERUN_DIR"
fi

if [[ ! -f "$TEMPLATE_PATH" ]]; then
  echo "ERROR: missing dashboard template: $TEMPLATE_PATH" >&2
  exit 1
fi

if [[ -z "${DATE_FROM:-}" ]]; then
  case "$REPORT_TYPE_LOWER" in
    weekly)
            if [[ -z "${DATE_TO:-}" ]]; then
                DATE_TO="$(date -u +%Y-%m-%dT23:59:59Z)"
            fi
            DATE_FROM="$(python3 - "$DATE_TO" 6 <<'PY'
import sys
from datetime import datetime, timedelta, timezone
value = sys.argv[1].replace('Z', '+00:00')
days = int(sys.argv[2])
dt = datetime.fromisoformat(value).astimezone(timezone.utc) - timedelta(days=days)
print(dt.strftime('%Y-%m-%dT00:00:00Z'))
PY
)"
      ;;
    monthly)
            if [[ -z "${DATE_TO:-}" ]]; then
                DATE_TO="$(date -u +%Y-%m-%dT23:59:59Z)"
            fi
            DATE_FROM="$(python3 - "$DATE_TO" 29 <<'PY'
import sys
from datetime import datetime, timedelta, timezone
value = sys.argv[1].replace('Z', '+00:00')
days = int(sys.argv[2])
dt = datetime.fromisoformat(value).astimezone(timezone.utc) - timedelta(days=days)
print(dt.strftime('%Y-%m-%dT00:00:00Z'))
PY
)"
      ;;
    *)
      echo "ERROR: DATE_FROM is required for custom reports" >&2
      exit 1
      ;;
  esac
fi
if [[ -z "${DATE_TO:-}" ]]; then
    DATE_TO="$(date -u +%Y-%m-%dT23:59:59Z)"
fi

export SERVER_ID REPORT_TYPE REPORT_TYPE_LOWER REPORT_DATE DATE_FROM DATE_TO
export LOCAL_ROOT OUTPUT_PATH DATA_COPY_PATH SNAPSHOT_COPY_PATH RUN_META_PATH
export SKILL_DIR TEMPLATE_PATH SAVE_DATA_JSON
SOURCE_FINGERPRINT_PATH="/tmp/ciso-source-fingerprint-${SERVER_SLUG}-${REPORT_TYPE_SLUG}-$$.json"
export SOURCE_FINGERPRINT_PATH

echo "Running CISO report | server=$SERVER_ID | type=$REPORT_TYPE_LOWER | output=$(dirname "$OUTPUT_PATH")"

python3 - <<'PY'
import hashlib
import json
import os
from pathlib import Path

skill_dir = Path(os.environ["SKILL_DIR"])
tracked_suffixes = {".md", ".html", ".sh", ".json"}
fingerprint = {}
for path in sorted(skill_dir.rglob("*")):
    if not path.is_file() or path.suffix not in tracked_suffixes:
        continue
    rel = path.relative_to(skill_dir).as_posix()
    fingerprint[rel] = hashlib.sha256(path.read_bytes()).hexdigest()
json.dump(fingerprint, open(os.environ["SOURCE_FINGERPRINT_PATH"], "w"), indent=2)
PY

# A fresh run must never inherit previous runtime state.
rm -f /tmp/ciso-data.json /tmp/ciso-platform.json /tmp/ciso-curation.json \
  /tmp/ciso-curation-diagnostics.json /tmp/ciso-curation-page-*.json \
  /tmp/ciso-curation-policies.json /tmp/ciso-curation-policies-raw.json \
  /tmp/ciso-indexed-repos.json /tmp/ciso-indexed.json /tmp/ciso-indexed.json.err \
  /tmp/ciso-watches.json /tmp/ciso-policies.json /tmp/ciso-repos-all.json \
  /tmp/ciso-repos-remote.json /tmp/ciso-version.json /tmp/ciso-violations-page-*.json \
  /tmp/ciso-violations.json \
  /tmp/ciso-track-platform.log /tmp/ciso-track-curation.log /tmp/ciso-track-violations.log

echo "=== collect live payloads (parallel tracks) ==="
rm -f /tmp/ciso-track-platform.log /tmp/ciso-track-curation.log /tmp/ciso-track-violations.log

# ── Track 1: platform metadata ────────────────────────────────────────────────
(python3 - <<'PY'
import json, os, subprocess

server = os.environ["SERVER_ID"]

def run(cmd):
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise SystemExit(f"ERROR: command failed: {' '.join(cmd)}\n{proc.stderr}")
    raw = proc.stdout or ""
    try:
        return json.loads(raw or "null")
    except Exception:
        return raw

def jf_rt(path):
    return run(["jf", "rt", "curl", "-s", "--server-id", server, "-XGET", path])

def jf_xr(path):
    return run(["jf", "xr", "curl", "-s", "--server-id", server, "-XGET", path])

print("track: platform")
json.dump(jf_rt("/api/repositories") or [], open("/tmp/ciso-repos-all.json", "w"), indent=2)
json.dump(jf_rt("/api/repositories?type=remote") or [], open("/tmp/ciso-repos-remote.json", "w"), indent=2)
json.dump(jf_xr("/api/v2/watches") or [], open("/tmp/ciso-watches.json", "w"), indent=2)
json.dump(jf_xr("/api/v2/policies") or [], open("/tmp/ciso-policies.json", "w"), indent=2)
json.dump(jf_xr("/api/v1/binMgr/default/repos") or {}, open("/tmp/ciso-indexed-repos.json", "w"), indent=2)
print("track: platform done")
PY
) > /tmp/ciso-track-platform.log 2>&1 &
PID_PLATFORM=$!

# ── Track 2: curation (policies + audit) ─────────────────────────────────────
(python3 - <<'PY'
import json, os, subprocess
from datetime import datetime, timedelta, timezone

server = os.environ["SERVER_ID"]
report_type = os.environ["REPORT_TYPE_LOWER"]
date_from = os.environ["DATE_FROM"]
date_to = os.environ["DATE_TO"]

def parse_time(v):
    return datetime.fromisoformat(v.replace("Z", "+00:00"))

def fmt(v):
    return v.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

def jf_xr_raw(path):
    proc = subprocess.run(
        ["jf", "xr", "curl", "-s", "--server-id", server, "-XGET", path],
        capture_output=True, text=True
    )
    raw = proc.stdout or ""
    try:
        return json.loads(raw or "null")
    except Exception:
        return {}

def get_xr_with_status(path):
    proc = subprocess.run(
        ["jf", "xr", "curl", "-s", "-w", "%{http_code}", "--server-id", server, "-XGET", path],
        capture_output=True, text=True,
    )
    raw = proc.stdout or ""
    status = int(raw[-3:]) if len(raw) >= 3 and raw[-3:].isdigit() else (200 if proc.returncode == 0 else 500)
    body = raw[:-3] if len(raw) >= 3 and raw[-3:].isdigit() else raw
    return status, json.loads(body or "{}")

start = parse_time(date_from)
end = parse_time(date_to)
if report_type == "weekly" and (end - start).total_seconds() > 168 * 3600:
    start = end - timedelta(hours=168)
    date_from = fmt(start)

def month_windows():
    if report_type != "monthly":
        return [(date_from, date_to)]
    out, cur = [], start
    while cur < end:
        nxt = min(cur + timedelta(days=6), end)
        out.append((fmt(cur), fmt(nxt)))
        cur = nxt
    return out

# Curation policies
print("track: curation policies")
policies, offset, total_policies = [], 0, 0
while True:
    body = jf_xr_raw(f"/api/v1/curation/policies?num_of_rows=200&offset={offset}") or {}
    batch = (body.get("data") or []) if isinstance(body, dict) else []
    total_policies = int((body.get("meta") or {}).get("total_count") or total_policies or len(batch)) if isinstance(body, dict) else 0
    policies.extend(batch)
    if not batch or len(policies) >= total_policies:
        break
    offset += len(batch)
json.dump({"data": policies, "meta": {"total_count": total_policies}}, open("/tmp/ciso-curation-policies.json", "w"), indent=2)

# Curation audit
print("track: curation audit")
all_rows, pages_fetched, reported_total, http_status = [], 0, 0, 200
limit = 2000
for wstart, wend in month_windows():
    offset = 0
    while True:
        path = (
            "/api/v1/curation/audit/packages"
            f"?order_by=id&direction=desc&num_of_rows={limit}"
            f"&created_at_start={wstart}&created_at_end={wend}"
            f"&include_total=true&offset={offset}"
        )
        http_status, page = get_xr_with_status(path)
        if http_status in (403, 404):
            all_rows, reported_total = [], 0
            break
        batch = page.get("data") or []
        all_rows.extend(batch)
        pages_fetched += 1
        if report_type == "monthly" and offset == 0:
            reported_total += int((page.get("meta") or {}).get("total_count") or 0)
        else:
            reported_total = max(reported_total, int((page.get("meta") or {}).get("total_count") or 0))
        if len(batch) < limit:
            break
        offset += limit
    if http_status in (403, 404):
        break
json.dump({"data": all_rows, "meta": {"total_count": reported_total}}, open("/tmp/ciso-curation.json", "w"), indent=2)
json.dump({
    "http_status": http_status,
    "mode": "monthly_chunked" if report_type == "monthly" else "weekly",
    "pages_fetched": pages_fetched,
    "rows_fetched": len(all_rows),
    "total_count_reported": reported_total,
    "date_from": date_from,
    "date_to": date_to,
}, open("/tmp/ciso-curation-diagnostics.json", "w"), indent=2)
print(f"track: curation done rows={len(all_rows)} pages={pages_fetched} status={http_status}")
PY
) > /tmp/ciso-track-curation.log 2>&1 &
PID_CURATION=$!

# ── Track 3: violations ───────────────────────────────────────────────────────
# --http1.1 forces HTTP/1.1 to prevent CURLE_HTTP2_STREAM (exit 92) on large
# instances. limit=500 is kept for efficiency (~23 pages for 11k violations).
# Override with CISO_VIOLATIONS_LIMIT env var if needed.
(python3 - <<'PY'
import json, os, subprocess

server = os.environ["SERVER_ID"]
date_from = os.environ["DATE_FROM"]
date_to = os.environ["DATE_TO"]
limit = int(os.environ.get("CISO_VIOLATIONS_LIMIT", "500"))

violations, total_violations, offset, page_idx = [], 0, 0, 0
while True:
    body = {
        "filters": {"created_from": date_from, "created_until": date_to},
        "pagination": {"limit": limit, "offset": offset, "order_by": "severity", "direction": "desc"},
    }
    proc = subprocess.run(
        ["jf", "xr", "curl", "-s", "--http1.1", "--server-id", server, "-XPOST", "/api/v1/violations",
         "-H", "Content-Type: application/json", "-d", json.dumps(body)],
        capture_output=True, text=True
    )
    if proc.returncode != 0:
        raise SystemExit(f"violations page {page_idx} failed (exit {proc.returncode}): {proc.stderr[:300]}")
    page = json.loads(proc.stdout or "{}") if proc.stdout else {}
    batch = page.get("violations") or []
    total_violations = int(page.get("total_violations") or total_violations or len(batch))
    violations.extend(batch)
    json.dump(page, open(f"/tmp/ciso-violations-page-{page_idx}.json", "w"), indent=2)
    page_idx += 1
    if len(batch) < limit or offset + len(batch) >= total_violations:
        break
    offset += limit
json.dump({"violations": violations, "total_violations": total_violations}, open("/tmp/ciso-violations.json", "w"), indent=2)
print(f"track: violations done rows={len(violations)} total={total_violations}")
PY
) > /tmp/ciso-track-violations.log 2>&1 &
PID_VIOLATIONS=$!

# ── Wait for all three tracks ─────────────────────────────────────────────────
FAIL=0
for pid in "$PID_PLATFORM" "$PID_CURATION" "$PID_VIOLATIONS"; do
  wait "$pid" || FAIL=1
done
cat /tmp/ciso-track-platform.log /tmp/ciso-track-curation.log /tmp/ciso-track-violations.log
if [ "$FAIL" -ne 0 ]; then
  echo "ERROR: one or more collection tracks failed. See logs above." >&2
  exit 1
fi
echo "All tracks complete"

echo "=== merge collection ==="
python3 - <<'PY'
import json, os, subprocess
from collections import Counter, defaultdict
from datetime import datetime, timezone

server = os.environ["SERVER_ID"]
report_type = os.environ["REPORT_TYPE_LOWER"]
date_from = os.environ["DATE_FROM"]
date_to = os.environ["DATE_TO"]

def parse_time(value):
    return datetime.fromisoformat(value.replace("Z", "+00:00"))

# Load curation track outputs
curation_data = json.load(open("/tmp/ciso-curation.json")) if os.path.isfile("/tmp/ciso-curation.json") else {"data": [], "meta": {"total_count": 0}}
all_rows = curation_data.get("data") or []
reported_total = int((curation_data.get("meta") or {}).get("total_count") or len(all_rows))
diag = json.load(open("/tmp/ciso-curation-diagnostics.json")) if os.path.isfile("/tmp/ciso-curation-diagnostics.json") else {"http_status": 200}
http_status = int(diag.get("http_status") or 200)

# Load violations track outputs
viol_data = json.load(open("/tmp/ciso-violations.json")) if os.path.isfile("/tmp/ciso-violations.json") else {"violations": [], "total_violations": 0}
violations = viol_data.get("violations") or []
total_violations = int(viol_data.get("total_violations") or len(violations))

def sev_key(value):
    v = str(value or "").lower()
    if v.startswith("crit"): return "critical"
    if v.startswith("high"): return "high"
    if v.startswith("med"): return "medium"
    if v.startswith("low"): return "low"
    return None

def type_key(value):
    v = str(value or "").lower()
    if "operational" in v: return "operational"
    if "license" in v: return "license"
    return "security"

sev = Counter()
typ = Counter()
watch_hits = Counter()
cve_hits = Counter()
critical = defaultdict(lambda: {"hits": 0, "description": "", "component": "unknown", "first_seen": ""})
details = []
for item in violations:
    sk = sev_key(item.get("severity"))
    if sk:
        sev[sk] += 1
    typ[type_key(item.get("type"))] += 1
    watch = (item.get("watch_name") or "").strip()
    if watch:
        watch_hits[watch] += 1
    issue = item.get("cve") or item.get("issue_id") or "unknown"
    cve_hits[issue] += 1
    component = (item.get("infected_components") or [item.get("component") or "unknown"])[0]
    if sk == "critical":
        row = critical[issue]
        row["hits"] += 1
        row["description"] = row["description"] or str(item.get("description") or "See Xray console")[:220]
        row["component"] = row["component"] if row["component"] != "unknown" else component
        row["first_seen"] = row["first_seen"] or str(item.get("created") or item.get("created_at") or "")[:10]
    details.append({
        "issue_id": item.get("issue_id") or issue,
        "cve": issue,
        "severity": item.get("severity") or "Unknown",
        "cvss": item.get("cvss_v3") or item.get("cvss_v2") or "N/A",
        "type": item.get("type") or "Security",
        "component": component,
        "watch": watch or "—",
        "description": str(item.get("description") or "")[:150],
    })

severity_total = sum(sev[k] for k in ("critical", "high", "medium", "low"))
risk_score = 0.0  # placeholder — recalculated after enrich using 3-factor formula

def display_date(value):
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00")).strftime("%b %-d, %Y")
    except Exception:
        return value[:10]

meta = {
    "schema_version": "2.0-beta",
    "server_id": server,
    "url": "",
    "host": "",
    "generated": os.environ["REPORT_DATE"],
    "curation_audit_ui_path": "/ui/package-curation/audit",
    "curation_uninspected_label": "Passed without inspection",
    "date_from": display_date(date_from),
    "date_to": display_date(date_to),
    "period_start": date_from,
    "period_end": date_to,
    "report_type": report_type.capitalize(),
    "window_days": max(1, round((parse_time(date_to) - parse_time(date_from)).total_seconds() / 86400)),
}
try:
    cfg = subprocess.run(["jf", "c", "show", server], capture_output=True, text=True)
    for line in cfg.stdout.splitlines():
        if line.startswith("JFrog Platform URL:"):
            meta["url"] = line.split()[-1]
            meta["host"] = meta["url"].replace("https://", "").rstrip("/")
except Exception:
    pass

cur_blocked = sum(1 for row in all_rows if str(row.get("action") or row.get("status") or "").lower() == "blocked")
cur_approved = sum(1 for row in all_rows if str(row.get("action") or row.get("status") or "").lower() == "approved")
cur_passed = sum(1 for row in all_rows if str(row.get("action") or row.get("status") or "").lower() in ("passed", "pass", "allowed"))

data = {
    "meta": meta,
    "platform": {"repos_total": 0, "repos_indexed": 0, "watches_total": 0, "policies_total": 0},
    "curation": {
        "available": http_status not in (403, 404),
        "total": reported_total or len(all_rows),
        "blocked": cur_blocked,
        "approved": cur_approved,
        "passed": cur_passed,
        "block_rate": round((cur_blocked / max(reported_total or len(all_rows), 1)) * 100, 1) if all_rows else 0,
        "by_reason": {"malicious": 0, "security": cur_blocked, "license": 0, "operational": 0},
        "top_blocked": [],
        "observation": f"What changed: Curation processed {reported_total or len(all_rows)} package requests and blocked {cur_blocked}. Why it matters: Gate enforcement is active before download. Action: Review top blocking policies and expand connected remotes.",
    },
    "violations": {
        "total": total_violations or len(violations),
        "risk_score": risk_score,
        "risk_score_previous": 0,
        "by_type": {k: int(typ[k]) for k in ("security", "operational", "license")},
        "by_severity": {k: int(sev[k]) for k in ("critical", "high", "medium", "low")},
        "severity_pct": {k: round((int(sev[k]) / max(severity_total, 1)) * 100, 1) for k in ("critical", "high", "medium", "low")},
        "violation_details": sorted(details, key=lambda x: {"Critical": 0, "High": 1, "Medium": 2, "Low": 3}.get(x["severity"], 9))[:20],
        "critical_issues": [
            {
                "id": issue,
                "description": row["description"],
                "hits": row["hits"],
                "first_seen": row["first_seen"],
                "days_open": 0,
                "exploit_status": "unknown",
                "affected_environments": [],
                "playbook_link": None,
            }
            for issue, row in sorted(critical.items(), key=lambda kv: -kv[1]["hits"])[:10]
        ],
        "top_cves": [
            {"id": issue, "cvss": None, "severity": "Critical", "packages": 1, "hits": hits}
            for issue, hits in cve_hits.most_common(5)
        ],
        "top_watch_policies": [
            {"policy": name, "type": "security", "hits": hits, "delta_pct": 0}
            for name, hits in watch_hits.most_common(15)
        ],
        "observation": f"What changed: Xray reported {total_violations or len(violations)} violations, including {sev['critical']} critical. Why it matters: Critical concentration drives executive risk. Action: Prioritize the highest-hit XRAY IDs.",
    },
    "license": {"total": int(typ["license"]), "licenses": [], "observation": "What changed: License signal was collected from Xray violations. Why it matters: Policy violations may block release paths. Action: Review license rows in Xray for remediation ownership."},
    "operational": {"total": int(typ["operational"]), "top_components": [], "observation": "What changed: Operational risk signal was collected from Xray violations. Why it matters: Deprecated or risky components affect reliability. Action: Prioritize operational-risk packages with active usage."},
    "benefit": {"roi_estimate": None, "observation": "What changed: Prevented downloads reduce downstream remediation work. Why it matters: Curation blocks risk before it enters builds. Action: Track blocked package trends against incident avoidance."},
    "governance": {},
    "threat_velocity": {"available": False, "periods": [], "trend_summary": "Trend comparison will be available after another validated run."},
    "comparison": {"available": False},
    "recommendations": [],
}
json.dump(data, open("/tmp/ciso-data.json", "w"), indent=2)
print(f"base data: curation_total={data['curation']['total']} violations={data['violations']['total']}")
PY

echo "=== enrich and transform ==="
CISO_ENRICH_ALLOW_EXISTING_TMP=true "$SKILL_DIR/internal/enrich-ciso-datajson.sh" "$SERVER_ID" /tmp/ciso-data.json /tmp/ciso-data.json

echo "=== derive executive insights ==="
python3 - <<'PY'
import json, os, re
from collections import Counter, defaultdict
from datetime import datetime, timezone
from pathlib import Path

def load_json(path, default):
    try:
        if os.path.isfile(path) and os.path.getsize(path) > 0:
            return json.load(open(path))
    except Exception:
        return default
    return default

def as_rows(body, keys):
    if isinstance(body, list):
        return body
    if isinstance(body, dict):
        for key in keys:
            val = body.get(key)
            if isinstance(val, list):
                return val
        for key in ("data", "items", "results"):
            val = body.get(key)
            if isinstance(val, list):
                return val
    return []

def load_violations():
    rows = []
    for path in sorted(Path("/tmp").glob("ciso-violations-page-*.json")):
        rows.extend(as_rows(load_json(str(path), {}), ("violations", "data")))
    if rows:
        return rows
    for path in ("/tmp/ciso-violations.json", "/tmp/ciso-violations-clean.json", "/tmp/ciso-violations-parsed.json"):
        rows = as_rows(load_json(path, {}), ("violations", "data"))
        if rows:
            return rows
    return []

def parse_time(value):
    if not value:
        return None
    if isinstance(value, (int, float)):
        try:
            return datetime.fromtimestamp(value / 1000 if value > 10_000_000_000 else value, tz=timezone.utc)
        except Exception:
            return None
    text = str(value).strip()
    if not text:
        return None
    for fmt in ("%Y-%m-%d", "%Y-%m-%dT%H:%M:%S.%f%z", "%Y-%m-%dT%H:%M:%S%z"):
        try:
            return datetime.strptime(text.replace("Z", "+0000"), fmt)
        except Exception:
            pass
    try:
        return datetime.fromisoformat(text.replace("Z", "+00:00"))
    except Exception:
        return None

def walk(obj):
    if isinstance(obj, dict):
        yield obj
        for value in obj.values():
            yield from walk(value)
    elif isinstance(obj, list):
        for value in obj:
            yield from walk(value)

def first_text(row, keys):
    for obj in walk(row):
        for key in keys:
            val = obj.get(key) if isinstance(obj, dict) else None
            if isinstance(val, str) and val.strip():
                return val.strip()
            if isinstance(val, (int, float)):
                return str(val)
    return ""

def values_for_keys(row, keys):
    vals = []
    for obj in walk(row):
        for key, val in obj.items():
            if key.lower() not in keys:
                continue
            if isinstance(val, str) and val.strip():
                vals.append(val.strip())
            elif isinstance(val, list):
                for item in val:
                    if isinstance(item, str) and item.strip():
                        vals.append(item.strip())
                    elif isinstance(item, dict):
                        vals.extend(values_for_keys(item, keys))
            elif isinstance(val, dict):
                vals.extend(values_for_keys(val, keys))
    return vals

def issue_id(row):
    return first_text(row, ("cve", "issue_id", "issueId", "xray_id", "xrayId", "id")) or "unknown"

def severity(row):
    return first_text(row, ("severity", "severity_level", "severityLevel")).lower()

def component(row):
    comps = values_for_keys(row, {"infected_components", "infectedcomponents", "components", "component", "package_name", "packagename"})
    for val in comps:
        if val and val.lower() not in ("unknown", "n/a"):
            return val
    return "unknown"

def artifact_id(row):
    return first_text(row, ("artifact_path", "artifactPath", "artifact", "path", "location", "impacted_artifact", "impactedArtifact", "sha256", "name"))

def clean_repo_name(value):
    text = str(value or "").strip().strip("/")
    if not text or text.lower() in ("unknown", "n/a", "none", "null", "default"):
        return ""
    return text

def repo_from_text(text, repo_names):
    text = str(text or "").strip()
    if not text or text.startswith(("http://", "https://")):
        return ""
    parts = [p for p in text.strip("/").split("/") if p]
    if repo_names:
        for part in parts:
            if part in repo_names:
                return part
        for name in repo_names:
            if text == name or text.startswith(name + "/") or f"/{name}/" in text or text.startswith("default/" + name + "/"):
                return name
    if parts:
        return clean_repo_name(parts[0])
    return ""

def repo_from_row(row, repo_names):
    direct = first_text(row, ("repo", "repo_key", "repoKey", "repository", "repo_name", "repoName"))
    if direct:
        repo = repo_from_text(direct, repo_names)
        if repo:
            return repo
    candidates = []
    for obj in walk(row):
        for key, val in obj.items():
            lk = key.lower()
            if any(tok in lk for tok in ("repo", "artifact", "path", "location")) and isinstance(val, str):
                candidates.append(val)
            elif any(tok in lk for tok in ("artifact", "path", "location")) and isinstance(val, list):
                candidates.extend(item for item in val if isinstance(item, str))
    if repo_names:
        for text in candidates:
            repo = repo_from_text(text, repo_names)
            if repo:
                return repo
    for text in candidates:
        repo = repo_from_text(text, repo_names)
        if repo:
            return repo
    return "unknown"

def extract_repo_names():
    names = set()
    for path in ("/tmp/ciso-repos-all.json", "/tmp/ciso-repos-remote.json"):
        for row in as_rows(load_json(path, {}), ("data", "repositories")):
            if not isinstance(row, dict):
                continue
            name = row.get("key") or row.get("repoKey") or row.get("name") or row.get("repo_key")
            if name:
                names.add(str(name))
    return names

def extract_watch_mapping(repo_names):
    watches = as_rows(load_json("/tmp/ciso-watches.json", {}), ("data", "watches"))
    mapping = defaultdict(list)
    exposed = False
    for watch in watches:
        if not isinstance(watch, dict):
            continue
        name = str(watch.get("name") or watch.get("watch_name") or watch.get("watchName") or watch.get("id") or "Unnamed watch")
        found = set()
        for obj in walk(watch):
            if not isinstance(obj, dict):
                continue
            for key, val in obj.items():
                lk = key.lower()
                if lk not in {"repo", "repos", "repository", "repositories", "repokey", "repo_key", "repo_name", "reponame"}:
                    continue
                exposed = True
                vals = val if isinstance(val, list) else [val]
                for item in vals:
                    if isinstance(item, str):
                        found.add(item)
                    elif isinstance(item, dict):
                        nested = item.get("key") or item.get("name") or item.get("repoKey") or item.get("repo_key")
                        if nested:
                            found.add(str(nested))
        if repo_names:
            found = {r for r in found if r in repo_names}
        for repo in found:
            mapping[repo].append(name)
    return mapping, bool(exposed)

def fix_state(row):
    fix_keys = {"fix_versions", "fixed_versions", "fixed_version", "fixedversion", "fixedversions", "fix_version", "fixversion"}
    vals = values_for_keys(row, fix_keys)
    if vals:
        return "available", sorted(set(vals))[:5]
    text = " ".join(str(first_text(row, ("remediation", "recommendation", "summary", "description"))).lower().split())
    if re.search(r"fixed in|upgrade to|version .* fixes|fix version", text):
        return "available", []
    if "no fix" in text or "not fixed" in text:
        return "none", []
    return "unknown", []

def prior_snapshot():
    local_root = os.environ.get("LOCAL_ROOT", "")
    server_slug = os.environ.get("SERVER_SLUG", "")
    report_type_slug = os.environ.get("REPORT_TYPE_SLUG", "")
    report_date = os.environ.get("REPORT_DATE", "")
    scan_dir = Path(local_root) / server_slug / report_type_slug
    if not scan_dir.is_dir():
        return {}
    candidates = sorted(p for p in scan_dir.glob("*/snapshot.json") if p.parent.name != report_date and not p.parent.name.startswith("rerun-"))
    return load_json(str(candidates[-1]), {}) if candidates else {}

data = load_json("/tmp/ciso-data.json", {})
violations = [row for row in load_violations() if isinstance(row, dict)]
repo_names = extract_repo_names()
watch_map, watch_assignment_exposed = extract_watch_mapping(repo_names)
meta = data.get("meta") or {}
period_end = parse_time(meta.get("period_end") or meta.get("generated")) or datetime.now(timezone.utc)
prev = prior_snapshot()
prev_critical_ids = set(((prev.get("violations") or {}).get("critical_ids") or []))

critical_rows = [row for row in violations if severity(row).startswith("crit")]
issue_stats = defaultdict(lambda: {"hits": 0, "repos": set(), "artifacts": set(), "component": "unknown", "first_seen": None, "description": "", "fix_versions": set(), "fix_statuses": Counter()})
repo_stats = defaultdict(lambda: {"violations": 0, "critical": 0})
component_stats = defaultdict(lambda: {"critical_issues": set(), "hits": 0})

for row in violations:
    repo = repo_from_row(row, repo_names)
    rid = issue_id(row)
    art = artifact_id(row)
    repo_stats[repo]["violations"] += 1
    if severity(row).startswith("crit"):
        repo_stats[repo]["critical"] += 1
        stat = issue_stats[rid]
        stat["hits"] += 1
        if repo != "unknown":
            stat["repos"].add(repo)
        if art:
            stat["artifacts"].add(art)
        comp = component(row)
        if stat["component"] == "unknown" and comp != "unknown":
            stat["component"] = comp
        created = parse_time(first_text(row, ("created", "created_at", "createdAt", "first_seen", "firstSeen", "updated")))
        if created and (stat["first_seen"] is None or created < stat["first_seen"]):
            stat["first_seen"] = created
        stat["description"] = stat["description"] or str(row.get("description") or row.get("summary") or "See Xray console")[:220]
        fstate, fvers = fix_state(row)
        stat["fix_statuses"][fstate] += 1
        stat["fix_versions"].update(fvers)
        component_stats[comp]["critical_issues"].add(rid)
        component_stats[comp]["hits"] += 1

critical_issues = []
sla_breach_issues = 0
bucket_defs = [("0-7 days", 0, 7), ("8-30 days", 8, 30), ("31-90 days", 31, 90), ("90+ days", 91, None)]
buckets = {label: {"label": label, "issues": 0, "hits": 0} for label, _, _ in bucket_defs}
fix_counts = Counter()
fix_hits = Counter()
new_issues = new_hits = existing_issues = 0

for rid, stat in issue_stats.items():
    first = stat["first_seen"]
    days = max(0, (period_end - first).days) if first else 0
    if days > 30:
        sla_breach_issues += 1
    for label, low, high in bucket_defs:
        if days >= low and (high is None or days <= high):
            buckets[label]["issues"] += 1
            buckets[label]["hits"] += stat["hits"]
            break
    if stat["fix_statuses"].get("available"):
        fstatus = "available"
    elif stat["fix_statuses"] and not stat["fix_statuses"].get("unknown"):
        fstatus = "none"
    else:
        fstatus = "unknown"
    fix_counts[fstatus] += 1
    fix_hits[fstatus] += stat["hits"]
    is_new = bool(prev_critical_ids) and rid not in prev_critical_ids
    if is_new:
        new_issues += 1
        new_hits += stat["hits"]
    else:
        existing_issues += 1
    critical_issues.append({
        "id": rid,
        "description": stat["description"],
        "component": stat["component"],
        "hits": stat["hits"],
        "repo_count": len(stat["repos"]),
        "artifact_count": len(stat["artifacts"]),
        "first_seen": first.date().isoformat() if first else "",
        "days_open": days,
        "fix_status": fstatus,
        "fix_available": fstatus == "available",
        "fix_versions": sorted(stat["fix_versions"])[:5],
        "exploit_status": "unknown",
        "affected_environments": [],
        "playbook_link": None,
    })

critical_issues.sort(key=lambda row: (-row["hits"], -row["days_open"], row["id"]))

blind_spots = []
for repo, stat in repo_stats.items():
    if not clean_repo_name(repo) or repo == "unknown" or stat["violations"] <= 0:
        continue
    names = watch_map.get(repo, [])
    if names:
        continue
    risk = "critical" if stat["critical"] else "elevated"
    blind_spots.append({"repo": repo, "violation_count": stat["violations"], "critical_count": stat["critical"], "watch_count": 0, "watch_names": [], "risk_level": risk})
blind_spots.sort(key=lambda row: (-row["critical_count"], -row["violation_count"], row["repo"]))

total_critical_hits = sum(stat["hits"] for stat in issue_stats.values()) or 1
highest_impact = []
for comp, stat in component_stats.items():
    if comp == "unknown":
        continue
    highest_impact.append({
        "component": comp,
        "critical_issues": len(stat["critical_issues"]),
        "hits": stat["hits"],
        "hit_share_pct": round(stat["hits"] / total_critical_hits * 100, 1),
    })
highest_impact.sort(key=lambda row: (-row["hits"], row["component"]))

blast = [{
    "issue": rid,
    "repos": len(stat["repos"]),
    "artifacts": len(stat["artifacts"]),
    "component": stat["component"],
    "hits": stat["hits"],
} for rid, stat in issue_stats.items()]
blast.sort(key=lambda row: (-row["repos"], -row["artifacts"], -row["hits"]))

v = data.setdefault("violations", {})
v["critical_issues"] = critical_issues[:50]
v["executive_insights"] = {
    "sla_risk_backlog": {"buckets": [buckets[label] for label, _, _ in bucket_defs], "sla_breach_issues": sla_breach_issues, "sla_days": 30},
    "remediation_readiness": {
        "fix_available_issues": fix_counts.get("available", 0),
        "fix_available_hits": fix_hits.get("available", 0),
        "no_fix_issues": fix_counts.get("none", 0),
        "unknown_issues": fix_counts.get("unknown", 0),
    },
    "highest_impact_fixes": highest_impact[:10],
    "new_critical_introductions": {"new_issues": new_issues, "new_hits": new_hits, "existing_issues": existing_issues, "baseline_available": bool(prev_critical_ids)},
    "watch_blind_spots": blind_spots[:25],
    "watch_blind_spots_meta": {"available": watch_assignment_exposed, "reason": "Watch payload did not expose repository assignments" if not watch_assignment_exposed else ""},
    "blast_radius": blast[:10],
}

c = data.setdefault("curation", {})
p = data.get("platform") or {}
cur_state = (p.get("curation_state") or c.get("curation_state") or {})
by_type = cur_state.get("by_package_type") or []
supported_names = {"docker", "maven", "npm", "pypi", "go", "nuget", "conan", "composer", "debian", "rpm", "rubygems"}
gate_gaps = []
type_violations = Counter()
for repo, stat in repo_stats.items():
    low = repo.lower()
    for name in supported_names:
        if name in low:
            type_violations[name] += stat["violations"]
            break
for row in by_type:
    if not isinstance(row, dict):
        continue
    ptype = str(row.get("package_type") or row.get("type") or "Unknown")
    supported = row.get("supported")
    is_supported = supported is True or (supported is None and ptype.lower() in supported_names)
    if not is_supported:
        continue
    total = int(row.get("supported_remote_total") or row.get("remote_total") or row.get("total") or 0)
    connected = int(row.get("supported_connected") or row.get("connected") or 0)
    unconnected = max(0, total - connected)
    if unconnected <= 0:
        continue
    known = int(row.get("violations") or row.get("known_violations") or type_violations.get(ptype.lower(), 0))
    gate_gaps.append({"package_type": ptype, "supported": True, "unconnected": unconnected, "connected": connected, "total": total, "known_violations": known, "priority": "P1" if known or unconnected >= 5 else "P2"})
gate_gaps.sort(key=lambda row: (row["priority"], -row["known_violations"], -row["unconnected"], row["package_type"]))

policies = as_rows(load_json("/tmp/ciso-curation-policies.json", {}), ("data", "policies"))
dry_run_names = []
malicious_policies = 0
for pol in policies:
    if not isinstance(pol, dict):
        continue
    text = json.dumps(pol).lower()
    name = str(pol.get("name") or pol.get("policy_name") or pol.get("id") or "Unnamed policy")
    if "dry" in text and "run" in text:
        dry_run_names.append(name)
    if "malicious" in text:
        malicious_policies += 1
audit_rows = as_rows(load_json("/tmp/ciso-curation.json", {}), ("data", "items"))
would_block = 0
malicious_blocks = 0
malicious_pkgs = Counter()
for row in audit_rows:
    if not isinstance(row, dict):
        continue
    text = json.dumps(row).lower()
    action = str(row.get("action") or row.get("status") or "").lower()
    if "dry" in text and ("block" in text or "violation" in text):
        would_block += 1
    if "malicious" in text and action == "blocked":
        malicious_blocks += 1
        pkg = first_text(row, ("package_name", "packageName", "package", "name")) or "unknown"
        malicious_pkgs[pkg] += 1
c["executive_insights"] = {
    "gate_coverage_gaps": gate_gaps[:15],
    "enforcement_opportunity": {
        "dry_run_policies": int(p.get("curation_policies_dry_run") or len(set(dry_run_names))),
        "would_have_blocked": would_block,
        "top_policies": [{"policy": name, "events": 0} for name in sorted(set(dry_run_names))[:5]],
    },
    "malicious_package_defense": {
        "malicious_blocks": malicious_blocks or int((c.get("by_reason") or {}).get("malicious") or 0),
        "malicious_policies": malicious_policies,
        "top_packages": [{"package": pkg, "blocks": count} for pkg, count in malicious_pkgs.most_common(5)],
    },
}

json.dump(data, open("/tmp/ciso-data.json", "w"), indent=2)
print("executive insights:", {
    "critical_issues": len(critical_issues),
    "sla_breach": sla_breach_issues,
    "fix_available": fix_counts.get("available", 0),
    "watch_blind_spots": len(blind_spots),
    "gate_gaps": len(gate_gaps),
})
PY

echo "=== build recommendations ==="
python3 - <<'PY'
import json
from collections import Counter, defaultdict

data = json.load(open("/tmp/ciso-data.json"))
p  = data.get("platform") or {}
c  = data.get("curation") or {}
v  = data.get("violations") or {}
vei = v.get("executive_insights") or {}
cei = (c.get("executive_insights") or {})

recs = []

sla = vei.get("sla_risk_backlog") or {}
if (sla.get("sla_breach_issues") or 0) > 0:
    recs.append({
        "priority": "P1",
        "effort": "medium",
        "score": 96,
        "text": f"Clear {sla.get('sla_breach_issues')} critical issues beyond the {sla.get('sla_days', 30)}-day SLA",
        "detail": "Impact: aged critical findings are the highest executive accountability risk. Next step: assign owners to the oldest critical XRAY IDs and track closure weekly."
    })

rr = vei.get("remediation_readiness") or {}
if (rr.get("fix_available_issues") or 0) > 0:
    recs.append({
        "priority": "P1",
        "effort": "medium",
        "score": 94,
        "text": f"Patch {rr.get('fix_available_issues')} critical issues with known fixes",
        "detail": f"Impact: these fixes remove {rr.get('fix_available_hits', 0)} artifact hits without waiting for compensating controls. Next step: prioritize components in Highest-Impact Fixes."
    })

blind = vei.get("watch_blind_spots") or []
if blind:
    top_blind_repo = blind[0].get('repo') or 'repository not exposed by Xray payload'
    recs.append({
        "priority": "P1",
        "effort": "low",
        "score": 92,
        "text": f"Assign watches to {len(blind)} repositories with violations",
        "detail": f"Impact: the top blind spot ({top_blind_repo}) has {blind[0].get('violation_count')} violations and no watch mapping. Next step: attach the repository to an active Xray watch."
    })

gate_gaps = cei.get("gate_coverage_gaps") or []
if gate_gaps:
    total_unconnected = sum(g.get("unconnected") or 0 for g in gate_gaps)
    recs.append({
        "priority": "P2",
        "effort": "low",
        "score": 84,
        "text": f"Connect {total_unconnected} supported remotes to the Curation gate",
        "detail": f"Impact: supported remotes can bypass policy checks today, led by {gate_gaps[0].get('package_type')}. Next step: connect these repositories in Curation repository settings."
    })

# ── P1: top critical XRAY IDs (group by shared component/package keyword) ─────
critical_issues = v.get("critical_issues") or []
# Group issues by shared component root (first 20 chars of component path)
groups = defaultdict(list)
for ci in critical_issues:
    cid = ci.get("id", "")
    comp = (ci.get("component") or "unknown").split("/")[-1][:40]
    # Group by truncated component as a simple heuristic
    key = comp[:20]
    groups[key].append((cid, ci.get("hits", 0), comp, ci.get("description", "")))

# Emit one P1 per group with the top 3 IDs
for key, items in sorted(groups.items(), key=lambda kv: -sum(i[1] for i in kv[1]))[:5]:
    items_sorted = sorted(items, key=lambda x: -x[1])
    total_hits = sum(i[1] for i in items_sorted)
    ids = ", ".join(i[0] for i in items_sorted[:3])
    extra = f" + {len(items_sorted)-3} more" if len(items_sorted) > 3 else ""
    comp_name = items_sorted[0][2]
    desc = items_sorted[0][3][:120] if items_sorted[0][3] else ""
    recs.append({
        "priority": "P1",
        "effort": "medium",
        "score": min(98, 70 + total_hits // 2),
        "text": f"Remediate {comp_name} ({ids}{extra} — {total_hits} hits)",
        "detail": f"Impact: {desc or 'Critical vulnerability — immediate remediation required.'}. Next step: review affected artifacts in Xray console for {ids.split(',')[0]}."
    })

# ── P2: unindexed repos ─────────────────────────────────────────────────────────
repos_unindexed = (p.get("repos_total") or 0) - (p.get("repos_indexed") or 0)
repos_total = p.get("repos_total") or 0
if repos_unindexed > 0 and repos_total > 0:
    pct = round(repos_unindexed / repos_total * 100)
    recs.append({
        "priority": "P2",
        "effort": "medium",
        "score": 80,
        "text": f"Extend Xray coverage to {repos_unindexed} unindexed repositories ({pct}% blind spot)",
        "detail": f"Impact: {pct}% coverage gap means violations in {repos_unindexed} repos are invisible to any watch or policy. Next step: enable indexing on all remote repos via Xray → Repositories → Indexed Resources, prioritizing Docker, npm, and Maven."
    })

# ── P2: dry-run policies ────────────────────────────────────────────────────────
dry_run_count = p.get("curation_policies_dry_run") or 0
dry_run_hits = 0
bep = c.get("blocking_events_per_policy") or []
pvt = c.get("policy_violations_by_type") or {}
# Sum hits from policies that contain "aged" in their name (audit-mode aged-package policies)
for pol in bep:
    if "aged" in (pol.get("policy") or "").lower():
        dry_run_hits += pol.get("hits") or 0
if dry_run_count > 0:
    detail_hit = f" — {dry_run_hits} events logged in audit mode" if dry_run_hits else ""
    recs.append({
        "priority": "P2",
        "effort": "low",
        "score": 72,
        "text": f"Promote {dry_run_count} dry-run curation policies to block mode",
        "detail": f"Impact: {dry_run_count} policies are running in dry-run (audit-only){detail_hit}. Promoting them to block mode would increase enforced gate coverage. Next step: review audit-log false-positive rate, then enable block mode in Curation policy settings."
    })

# ── P3: passed without inspection ──────────────────────────────────────────────
without_inspection = c.get("without_inspection") or c.get("passed") or 0
if without_inspection > 0:
    recs.append({
        "priority": "P3",
        "effort": "low",
        "score": 60,
        "text": f"Investigate {without_inspection:,} requests that passed without inspection",
        "detail": f"Impact: Passed-without-inspection events bypass curation analysis entirely and may indicate unsupported ecosystems or configuration gaps. Next step: cross-reference curation_state with the remote repo list to identify uncovered ecosystems."
    })

# Fallback if no critical issues were found
if not any(r["priority"] == "P1" for r in recs):
    recs.insert(0, {
        "priority": "P1",
        "effort": "medium",
        "score": 90,
        "text": "Review and remediate top critical Xray violations",
        "detail": "Impact: Critical violations represent immediate risk. Next step: open the Xray tab, sort by Critical severity, and assign remediation owners for the top-hit XRAY IDs."
    })

data["recommendations"] = recs
json.dump(data, open("/tmp/ciso-data.json", "w"), indent=2)
print(f"recommendations: {len(recs)} generated (P1={sum(1 for r in recs if r['priority']=='P1')}, P2={sum(1 for r in recs if r['priority']=='P2')}, P3={sum(1 for r in recs if r['priority']=='P3')})")
PY

echo "=== comparison (prior snapshot) ==="
python3 - <<'PY'
import json, os
from pathlib import Path

local_root = os.environ.get('LOCAL_ROOT', '')
server_slug = os.environ.get('SERVER_SLUG', '')
report_type_slug = os.environ.get('REPORT_TYPE_SLUG', '')
report_date = os.environ.get('REPORT_DATE', '')

scan_dir = Path(local_root) / server_slug / report_type_slug
prior_snap_path = None
if scan_dir.is_dir():
    candidates = sorted([
        p for p in scan_dir.glob('*/snapshot.json')
        if p.parent.name != report_date and not p.parent.name.startswith('rerun-')
    ])
    if candidates:
        prior_snap_path = candidates[-1]

data = json.load(open('/tmp/ciso-data.json'))
if prior_snap_path:
    prev = json.load(open(prior_snap_path))
    pc = prev.get('curation', {})
    pv = prev.get('violations', {})
    dc = data.get('curation', {})
    dv = data.get('violations', {})
    def delta(a, b):
        return (a - b) if (a is not None and b is not None) else None
    def pct(a, b):
        return round((a - b) / b * 100, 1) if b else None
    data['comparison'] = {
        'available': True,
        'previous_date': prev.get('date', ''),
        'curation': {
            'total': dc.get('total', 0),
            'total_previous': pc.get('total', 0),
            'total_delta': delta(dc.get('total'), pc.get('total')),
            'blocked': dc.get('blocked', 0),
            'blocked_previous': pc.get('blocked', 0),
            'blocked_delta': delta(dc.get('blocked'), pc.get('blocked')),
            'blocked_pct': pct(dc.get('blocked'), pc.get('blocked')),
        },
        'violations': {
            'total': dv.get('total', 0),
            'total_previous': pv.get('total', 0),
            'total_delta': delta(dv.get('total'), pv.get('total')),
            'critical': (dv.get('by_severity') or {}).get('critical', 0),
            'critical_previous': pv.get('critical', 0),
            'critical_delta': delta((dv.get('by_severity') or {}).get('critical', 0), pv.get('critical', 0)),
        },
    }
    # Signal deltas — compare posture signals against prior snapshot if stored.
    # Older snapshots predate posture_signals, so derive comparable values where possible.
    def derived_signals_from_data(doc):
        vv = doc.get('violations') or {}
        pp = doc.get('platform') or {}
        sev = vv.get('by_severity') or {}
        crit = int(sev.get('critical') or vv.get('critical') or 0)
        high = int(sev.get('high') or vv.get('high') or 0)
        med = int(sev.get('medium') or vv.get('medium') or 0)
        low = int(sev.get('low') or vv.get('low') or 0)
        total = crit + high + med + low
        repos_total = int(pp.get('repos_total') or 0)
        repos_indexed = int(pp.get('repos_indexed') or 0)
        return {
            'severity_mix': round((crit*4 + high*2 + med*1) / (total*4) * 100, 1) if total else None,
            'violation_volume': vv.get('total'),
            'coverage_gap': round((1 - repos_indexed / repos_total) * 100, 1) if repos_total else None,
        }
    prev_signals = prev.get('posture_signals') or derived_signals_from_data(prev)
    curr_signals = (dv.get('posture_signals') or
                    (data.get('violations') or {}).get('posture_signals') or
                    derived_signals_from_data(data))
    def sig_delta(curr, prev_v):
        if curr is None or prev_v is None: return None
        return round(curr - prev_v, 1)
    data['comparison']['signal_deltas'] = {
        'severity_mix':     sig_delta(curr_signals.get('severity_mix'),     prev_signals.get('severity_mix')),
        'violation_volume': sig_delta(curr_signals.get('violation_volume'), prev_signals.get('violation_volume')),
        'coverage_gap':     sig_delta(curr_signals.get('coverage_gap'),     prev_signals.get('coverage_gap')),
        'coverage_gap_prev': prev_signals.get('coverage_gap'),
    }
    print(f"comparison: prior={prev.get('date')} blocked_delta={data['comparison']['curation']['blocked_delta']} viol_delta={data['comparison']['violations']['total_delta']}")
    print(f"signal deltas: sev_mix={data['comparison']['signal_deltas']['severity_mix']} vol={data['comparison']['signal_deltas']['violation_volume']} gap={data['comparison']['signal_deltas']['coverage_gap']}")
    json.dump(data, open('/tmp/ciso-data.json', 'w'), indent=2)
else:
    print(f"comparison: no prior snapshot found in {scan_dir}")
PY

echo "=== compute posture signals ==="
# Three independent signals — no composite score or vendor-defined weighting.
# Operators can derive their own composite from these values if desired.
python3 - <<'PY'
import json

data = json.load(open("/tmp/ciso-data.json"))
v    = data.get("violations") or {}
p    = data.get("platform")   or {}
sev  = v.get("by_severity")   or {}

crit  = int(sev.get("critical", 0))
high  = int(sev.get("high",     0))
med   = int(sev.get("medium",   0))
low   = int(sev.get("low",      0))
total = crit + high + med + low

repos_total   = int(p.get("repos_total",   0))
repos_indexed = int(p.get("repos_indexed", 0))

# Signal 1 — Severity mix (0–100)
# What fraction of violations are the worst kind, weighted by severity tier.
# All-critical → 100, all-high → 50, all-medium → 25, all-low → ~6
sev_mix = round((crit*4 + high*2 + med*1) / (total*4) * 100, 1) if total else 0.0

# Signal 2 — Violation volume (raw count, no normalisation)
# Let the operator judge scale in context. Trends shown via comparison deltas.
vol_total = v.get("total", 0)

# Signal 3 — Coverage gap (0–100)
# Percentage of repos with no Xray indexing → blind spots.
coverage_gap = round((1 - repos_indexed / repos_total) * 100, 1) if repos_total else 0.0

signals = {
    "severity_mix":       sev_mix,    # % weighted toward critical
    "violation_volume":   vol_total,   # raw count across all repos
    "coverage_gap":       coverage_gap # % repos not indexed
}

data["violations"]["posture_signals"] = signals
# Remove any legacy composite score fields from prior runs
data["violations"].pop("risk_score", None)
data["violations"].pop("risk_score_breakdown", None)

json.dump(data, open("/tmp/ciso-data.json", "w"), indent=2)
print(f"posture signals: sev_mix={sev_mix}%  vol={vol_total}  coverage_gap={coverage_gap}%")
PY

echo "=== hard validation ==="
python3 - <<'PY'
import json
import os
import sys

d = json.load(open("/tmp/ciso-data.json"))
diag = json.load(open("/tmp/ciso-curation-diagnostics.json"))
p = d.get("platform") or {}
c = d.get("curation") or {}
v = d.get("violations") or {}
g = d.get("governance") or {}
errors = []

def n(obj, key):
    return int(obj.get(key) or 0)

if n(p, "repos_indexed") <= 0 and n(v, "total") > 0:
    errors.append("platform.repos_indexed is 0 while violations exist")
if n(p, "watches_total") <= 0 and n(v, "total") > 0:
    errors.append("platform.watches_total is 0 while violations exist")
if n(p, "policies_total") <= 0 and n(v, "total") > 0:
    errors.append("platform.policies_total is 0 while violations exist")
if n(c, "total") != int(diag.get("total_count_reported") or 0):
    errors.append(f"curation.total={c.get('total')} does not match diagnostics={diag.get('total_count_reported')}")
if n(c, "blocked") > 0 and not c.get("blocking_events_per_policy"):
    errors.append("curation.blocking_events_per_policy missing")
if n(c, "blocked") > 0 and not (c.get("policy_inventory") or {}).get("total_registered"):
    errors.append("curation.policy_inventory missing")
if n(v, "total") > 0 and not v.get("top_watch_policies"):
    errors.append("violations.top_watch_policies missing")
if n(v, "total") > 0 and not g.get("xray_policy_effectiveness"):
    errors.append("governance.xray_policy_effectiveness missing")
if n(c, "blocked") > 0 and not g.get("curation_policy_effectiveness"):
    errors.append("governance.curation_policy_effectiveness missing")
cs = p.get("curation_state") or c.get("curation_state") or {}
if n(cs, "supported_remote_total") > 0 and n(cs, "supported_connected") == 0:
    errors.append("curation supported_connected is 0 while supported remotes exist")

if errors:
    for err in errors:
        print("ERROR:", err)
    sys.exit(1)

print("validation passed:", {
    "repos_indexed": p.get("repos_indexed"),
    "watches_total": p.get("watches_total"),
    "policies_total": p.get("policies_total"),
    "curation_total": c.get("total"),
    "unique_users": c.get("unique_users"),
    "xray_governance": len(g.get("xray_policy_effectiveness") or []),
    "curation_governance": len(g.get("curation_policy_effectiveness") or []),
})
PY

echo "=== render ==="
python3 - <<'PY'
import os
import sys

template = open(os.environ["TEMPLATE_PATH"]).read()
data = open("/tmp/ciso-data.json").read().strip()
if "__CISO_DATA__" not in template:
    print("ERROR: template missing __CISO_DATA__")
    sys.exit(1)
open(os.environ["OUTPUT_PATH"], "w").write(template.replace("__CISO_DATA__", data))
print("report written:", os.environ["OUTPUT_PATH"])
PY

if [[ "$SAVE_DATA_JSON" == "true" ]]; then
  cp /tmp/ciso-data.json "$DATA_COPY_PATH"
fi

echo "=== write snapshot and run metadata ==="
python3 - <<'PY'
import json
import os

d = json.load(open("/tmp/ciso-data.json"))
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
    # Posture signals stored for period-over-period delta computation
    "posture_signals": d.get("violations", {}).get("posture_signals", {}),
    "components": len(d.get("operational", {}).get("top_components", [])),
    "license": d.get("license", {}).get("total", 0),
}
json.dump(snap, open(os.environ["SNAPSHOT_COPY_PATH"], "w"), indent=2)

run_meta = {
    "server_id": os.environ["SERVER_ID"],
    "server_slug": os.environ["SERVER_SLUG"] if "SERVER_SLUG" in os.environ else "",
    "report_type": os.environ["REPORT_TYPE"],
    "report_date": os.environ["REPORT_DATE"],
    "local_root": os.environ["LOCAL_ROOT"],
    "output_path": os.environ["OUTPUT_PATH"],
    "save_data_json": os.environ["SAVE_DATA_JSON"] == "true",
    "data_source": "live",
    "fallback_mode": {"used": False, "user_requested": False},
    "runner": {"script": "bin/generate-ciso-report.sh", "version": 1},
    "curation_diagnostics": json.load(open("/tmp/ciso-curation-diagnostics.json")),
}
json.dump(run_meta, open(os.environ["RUN_META_PATH"], "w"), indent=2)
print("data:", os.environ["DATA_COPY_PATH"] if os.environ["SAVE_DATA_JSON"] == "true" else "not saved")
print("snapshot:", os.environ["SNAPSHOT_COPY_PATH"])
print("run-meta:", os.environ["RUN_META_PATH"])
PY

echo "=== output verification ==="
python3 - <<'PY'
import os
from pathlib import Path

p = Path(os.environ["OUTPUT_PATH"])
s = p.read_text()
if s.count("const DATA = {") != 1:
    raise SystemExit("ERROR: rendered report must contain exactly one DATA object")
if "buildMast" not in s:
    raise SystemExit("ERROR: rendered report missing dashboard JS")
if s.count("\n") + 1 < 1000:
    raise SystemExit("ERROR: rendered report is unexpectedly small")
print("report verification passed:", p)
PY

echo "=== live proof ==="
"$SKILL_DIR/internal/verify-ciso-collection-proof.sh" "$SERVER_ID"

echo "=== source immutability check ==="
python3 - <<'PY'
import hashlib
import json
import os
import sys
from pathlib import Path

skill_dir = Path(os.environ["SKILL_DIR"])
before = json.load(open(os.environ["SOURCE_FINGERPRINT_PATH"]))
tracked_suffixes = {".md", ".html", ".sh", ".json"}
after = {}
for path in sorted(skill_dir.rglob("*")):
    if not path.is_file() or path.suffix not in tracked_suffixes:
        continue
    rel = path.relative_to(skill_dir).as_posix()
    after[rel] = hashlib.sha256(path.read_bytes()).hexdigest()

changed = sorted(k for k in set(before) | set(after) if before.get(k) != after.get(k))
if changed:
    print("ERROR: report generation modified skill source files:")
    for item in changed:
        print(f"  - {item}")
    print("Source edits are allowed only when explicitly improving the skill, not during a dashboard run.")
    sys.exit(1)
print("source immutability passed")
PY
rm -f "$SOURCE_FINGERPRINT_PATH"

echo "Final report path: $OUTPUT_PATH"
