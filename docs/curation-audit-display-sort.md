# Curation audit display — top 50, sort C+D

**Status:** Spec finalized. Apply code changes on branch `feature/ciso-profiles-phased-collection`.

## UI link (verified LiquidJedi)

```text
{meta.url}/ui/package-curation/audit
```

Example: https://liquidjedi.jfrog.io/ui/package-curation/audit

Do **not** use `/ui/curation/audit` (404 on current UI).

Optional override: `meta.curation_audit_ui_path` (default `/ui/package-curation/audit`).

Sidebar filters (Policy Name, Package Type, etc.) are **not** available via public API URL params; users filter manually in JFrog after opening the link.

---

## Data contract

| Field | Content |
|-------|---------|
| `curation.audit_events` | **All** `blocked` events in the report period only (no passed/approved rows) |
| `curation.audit_events_display` | Up to **50** rows for HTML (producer or template computes) |
| `curation.audit_events_display_meta` | `{ "cap": 50, "sort": "malicious_then_package_count_then_newest", "total_blocked": N }` |
| `curation.unique_users` | Distinct `username` or `user_mail` across **all** audit events in the window |
| `curation.top_users` | Top 10 users by event count (`events`, plus `blocked` / `approved` / `passed` breakdown) |

**API:** No separate “curation users” endpoint. Derive from paginated
`GET /xray/api/v1/curation/audit/packages` (`jf xr curl`), same source as totals.
Identity: `username` if set, else `user_mail`; omit rows with neither.

---


## Sort C+D (deterministic)

For each **blocked** event in the window:

1. `is_malicious` — true if any policy matches malicious heuristic (same as `by_reason.malicious` in collection doc).
2. `package_block_count` — count of blocked events for `(package_name, package_type)` in the window.

Sort keys (descending):

1. `is_malicious`
2. `package_block_count`
3. `created_at` (newest first)

Take first **50** → `audit_events_display`.

---

## Producer: Python (run in transform phase)

```python
import json
import re

CAP = 50
MAL = re.compile(r"malicious", re.I)

def is_malicious_event(ev):
    if ev.get("malicious") is True:
        return True
    for p in ev.get("policies") or []:
        blob = " ".join([
            p.get("condition_category") or "",
            p.get("condition_name") or "",
            p.get("policy_name") or "",
        ])
        if MAL.search(blob):
            return True
    pol = ev.get("policy") or ""
    if MAL.search(pol):
        return True
    return False

def row_from_api(ev):
    action = (ev.get("action") or ev.get("status") or "").lower()
    pols = ev.get("policies") or []
    return {
        "status": action,
        "package": ev.get("package_name") or "",
        "version": ev.get("package_version") or "",
        "type": ev.get("package_type") or "",
        "repo": ev.get("curated_repository_name") or "",
        "policy": (pols[0].get("policy_name") if pols else None) or "—",
        "requested_by": ev.get("username") or ev.get("user_mail") or "—",
        "date": (ev.get("created_at") or "")[:10],
        "timestamp": ev.get("created_at") or "",
        "malicious": is_malicious_event(ev),
    }

def build_display(blocked_rows):
    counts = {}
    for r in blocked_rows:
        k = (r["package"], r["type"])
        counts[k] = counts.get(k, 0) + 1
    def sort_key(r):
        k = (r["package"], r["type"])
        return (
            1 if r.get("malicious") else 0,
            counts.get(k, 0),
            r.get("timestamp") or "",
        )
    blocked_rows.sort(key=sort_key, reverse=True)
    return blocked_rows[:CAP]

# Usage: cur = json.load(open("/tmp/ciso-curation.json"))
# data = json.load(open("/tmp/ciso-data.json"))
# rows = [row_from_api(e) for e in cur.get("data") or [] if (e.get("action") or "").lower() == "blocked"]
# data["curation"]["audit_events"] = rows
# data["curation"]["audit_events_display"] = build_display(rows)
# data["curation"]["audit_events_display_meta"] = {"cap": CAP, "sort": "malicious_then_package_count_then_newest", "total_blocked": data["curation"]["blocked"]}
```

---

## Template footnote

> Showing 50 of {N} blocked events in this period (prioritized: malicious, then highest-volume packages, then newest). [View all in JFrog]({auditUrl}) — use date range {date_from}–{date_to} and the **Blocked** tab.

---

## Files to change (implementation checklist)

- [x] `Dashboard-ciso-report-skills/references/dashboard.html` — C+D helpers, `audit_events_display`, `/ui/package-curation/audit`
- [x] `Dashboard-ciso-report-skills/references/report-schema.md` — document new fields
- [x] `Dashboard-ciso-report-skills/references/report-data-collection.md` — blocked-only `audit_events` + transform module
- [x] `Dashboard-ciso-report-skills/references/report-data-collection.md` inline transform block — producer logic for transform phase
- [x] `Dashboard-ciso-report-skills/SKILL.md` — display sort and UI path notes
