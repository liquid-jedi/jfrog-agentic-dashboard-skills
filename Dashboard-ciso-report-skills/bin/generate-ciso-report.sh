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
REPORT_DATE="${REPORT_DATE:-$(date +%Y-%m-%d)}"
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

if [[ -z "${DATE_TO:-}" ]]; then
  DATE_TO="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
fi
if [[ -z "${DATE_FROM:-}" ]]; then
  case "$REPORT_TYPE_LOWER" in
    weekly)
      if date -u -v-7d +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
        DATE_FROM="$(date -u -v-7d +%Y-%m-%dT%H:%M:%SZ)"
      else
        DATE_FROM="$(date -u -d "7 days ago" +%Y-%m-%dT%H:%M:%SZ)"
      fi
      ;;
    monthly)
      if date -u -v-30d +%Y-%m-%dT%H:%M:%SZ >/dev/null 2>&1; then
        DATE_FROM="$(date -u -v-30d +%Y-%m-%dT%H:%M:%SZ)"
      else
        DATE_FROM="$(date -u -d "30 days ago" +%Y-%m-%dT%H:%M:%SZ)"
      fi
      ;;
    *)
      echo "ERROR: DATE_FROM is required for custom reports" >&2
      exit 1
      ;;
  esac
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
(python3 - <<'PY'
import json, os, subprocess

server = os.environ["SERVER_ID"]
date_from = os.environ["DATE_FROM"]
date_to = os.environ["DATE_TO"]

violations, total_violations, offset, page_idx = [], 0, 0, 0
while True:
    body = {
        "filters": {"created_from": date_from, "created_until": date_to},
        "pagination": {"limit": 500, "offset": offset, "order_by": "severity", "direction": "desc"},
    }
    proc = subprocess.run(
        ["jf", "xr", "curl", "-s", "--server-id", server, "-XPOST", "/api/v1/violations",
         "-H", "Content-Type: application/json", "-d", json.dumps(body)],
        capture_output=True, text=True
    )
    page = json.loads(proc.stdout or "{}") if proc.stdout else {}
    batch = page.get("violations") or []
    total_violations = int(page.get("total_violations") or total_violations or len(batch))
    violations.extend(batch)
    json.dump(page, open(f"/tmp/ciso-violations-page-{page_idx}.json", "w"), indent=2)
    page_idx += 1
    if len(batch) < 500 or offset + len(batch) >= total_violations:
        break
    offset += 500
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
raw_score = sev["critical"] * 100 + sev["high"] * 20 + sev["medium"] * 5 + sev["low"]
risk_score = round((raw_score / (severity_total * 100)) * 100, 1) if severity_total else 0.0

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
    "recommendations": [
        {"priority": "P1", "effort": "medium", "score": 95, "text": "Review top critical XRAY IDs", "detail": "Impact: Critical vulnerabilities dominate current risk. Next step: assign remediation owners for the highest-hit XRAY IDs in the report."},
        {"priority": "P2", "effort": "low", "score": 80, "text": "Expand curation coverage", "detail": "Impact: Unconnected remotes can bypass package gate enforcement. Next step: connect remaining supported remote repositories to Curation."},
    ],
}
json.dump(data, open("/tmp/ciso-data.json", "w"), indent=2)
print(f"base data: curation_total={data['curation']['total']} violations={data['violations']['total']}")
PY

echo "=== enrich and transform ==="
CISO_ENRICH_ALLOW_EXISTING_TMP=true "$SKILL_DIR/internal/enrich-ciso-datajson.sh" "$SERVER_ID" /tmp/ciso-data.json /tmp/ciso-data.json

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
if "buildSidebar" not in s:
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
