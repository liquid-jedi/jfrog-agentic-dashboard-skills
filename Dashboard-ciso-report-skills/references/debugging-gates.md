# CISO Report — Manual Validation Gates

**Debugging reference only.** These gates document what `bin/generate-ciso-report.sh`
enforces internally. Run them **only** when diagnosing a failed runner — they are not
a substitute for the runner in normal report generation.

Ensure the following are exported before running any gate:

```bash
SERVER_ID="<your-server-id>"
REPORT_TYPE="weekly"   # or monthly / custom
```

---

## Platform backfill

Self-heals missing watch/policy/indexed counts when the runner's primary collection
is incomplete:

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

---

## Gate 1 — JSON validity + risk score normalization

Risk score weighting: critical=100, high=20, medium=5, low=1.
Normalized score = `weighted_sum / (total × 100) × 100` (equivalent to `weighted_sum / total`).

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

---

## Gate 2 — Report type, window, and curation consistency

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

---

## Gate 3 — Recommendation metadata

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

---

## Gate 4 — Cross-section data integrity

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

---

## Gate 5 — Platform + curation enrichment

Run after transform and `collection-determinism-guards`:

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

---

## Collection proof smoke test

Optional live API smoke test. The runner already runs this internally; use here only when debugging:

```bash
"$SKILL_DIR/internal/verify-ciso-collection-proof.sh" "$SERVER_ID"
```
