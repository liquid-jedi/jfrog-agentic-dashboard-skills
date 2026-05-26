# CISO Report — JSON Schema

This is the contract between the data collector (agent) and the dashboard
renderer (HTML/JS). The agent fills every field. The dashboard reads every
field. Neither changes the other's job.

## Rules

- Every field MUST be present. Use `0`, `[]`, `""`, or `null` if unavailable.
- The dashboard handles missing/zero data gracefully — shows "Not configured".
- Never omit a section. If curation is unavailable, set `curation.available: false`.
- Strings should be pre-formatted for display (e.g., dates as "Apr 16").

## Schema

```json
{
  "meta": {
    "schema_version": "string — e.g., 2.0-beta",
    "server_id": "string — jf config server ID",
    "url": "string — full platform URL with https",
    "host": "string — hostname only (e.g., <server-id>.jfrog.io)",
    "generated": "string — YYYY-MM-DD",
    "date_from": "string — display format (e.g., Apr 1, 2026)",
    "date_to": "string — display format",
    "report_type": "string — Weekly | Monthly | Custom",
    "window_days": "number"
  },

  "methodology": {
    "severity_levels": {
      "critical": { "meaning": "string", "signal": "string" },
      "high": { "meaning": "string", "signal": "string" },
      "medium": { "meaning": "string", "signal": "string" },
      "low": { "meaning": "string", "signal": "string" }
    },
    "risk_score": {
      "weights": {
        "critical": "number",
        "high": "number",
        "medium": "number",
        "low": "number"
      },
      "bands": [
        {
          "min": "number",
          "max": "number|null",
          "label": "string",
          "signal": "string"
        }
      ]
    },
    "curation_actions": {
      "blocked": "string",
      "approved": "string",
      "passed": "string"
    },
    "repo_watch_risk_levels": [
      { "level": "string — critical|high|medium|low", "rule": "string" }
    ]
  },

  "platform": {
    "watches_total": "number",
    "watches_active": "number",
    "policies_total": "number",
    "policies_security": "number",
    "policies_operational": "number",
    "policies_license": "number",
    "repos_total": "number",
    "repos_indexed": "number",
    "repos_unindexed": "number",
    "repo_types": ["string — list of all package types"],
    "curation_enabled": "boolean",
    "curation_repos_count": "number — remote repos with curation",
    "curation_policies_global": "number",
    "curation_policies_repo": "number",
    "curation_policies_user": "number",
    "curated_types": ["string — package types with curation events"],
    "uncurated_types": ["string — package types without curation"]
  },

  "curation": {
    "available": "boolean — false if API returned 404/403",
    "total": "number — total audit events",
    "blocked": "number",
    "approved": "number — explicitly approved/override outcomes",
    "passed": "number — evaluated with no blocking policy match",
    "block_rate": "number — percentage",
    "by_reason": {
      "malicious": "number",
      "security": "number — CVE-based blocks",
      "license": "number",
      "operational": "number"
    },
    "top_blocked": [
      {
        "package": "string",
        "ecosystem": "string — npm, PyPI, Maven, etc.",
        "count": "number",
        "policies": "string — comma-separated policy names",
        "malicious": "boolean — true if flagged as malicious"
      }
    ],
    "by_type": [
      { "type": "string — npm, PyPI, etc.", "total": "number", "blocked": "number" }
    ],
    "audit_events": [
      {
        "status": "string — blocked | approved",
        "package": "string",
        "version": "string",
        "type": "string — package type",
        "repo": "string",
        "policy": "string",
        "requested_by": "string — user/email",
        "date": "string — display format"
      }
    ],
    "observation": "string — agent-generated insight about curation data"
  },

  "violations": {
    "total": "number",
    "risk_score": "number — normalized weighted risk score (0-100)",
    "risk_score_previous": "number — previous period weighted score",
    "by_type": {
      "security": "number",
      "operational": "number",
      "license": "number"
    },
    "by_severity": {
      "critical": "number",
      "high": "number",
      "medium": "number",
      "low": "number"
    },
    "severity_pct": {
      "critical": "number — percentage of security violations",
      "high": "number",
      "medium": "number",
      "low": "number"
    },
    "critical_issues": [
      {
        "id": "string — XRAY-NNNNNN",
        "description": "string",
        "hits": "number",
        "first_seen": "string — YYYY-MM-DD",
        "days_open": "number",
        "exploit_status": "string — active | poc | none | unknown",
        "affected_environments": ["string — prod | build | dev | transitive"],
        "playbook_link": "string — optional URL to response runbook"
      }
    ],
    "top_repos": [
      { "repo": "string", "count": "number" }
    ],
    "observation": "string — agent-generated key finding"
  },

  "license": {
    "total": "number",
    "licenses": [
      {
        "spdx": "string — e.g., GPL-3.0",
        "name": "string — full name",
        "count": "number",
        "severity": "string — High, Medium, etc."
      }
    ],
    "observation": "string"
  },

  "operational": {
    "total": "number",
    "severity": "string — e.g., all High",
    "top_components": [
      {
        "component": "string",
        "hits": "number",
        "current_version": "string — optional",
        "latest_version": "string — optional",
        "days_behind": "number — optional"
      }
    ],
    "top_locations": [
      { "location": "string — repo/path", "hits": "number" }
    ]
  },

  "benefit": {
    "curation_headline": "string — e.g., Stopped 82 packages at the gate",
    "xray_headline": "string — e.g., Surfaced 21,433 violations across 88 components",
    "compare_line": "string — Curation stopped N at the gate. Xray found M inside.",
    "cves_prevented": "number",
    "upgrade_rate": "number — percentage",
    "xray_coverage": "number — percentage of repos indexed",
    "roi_estimate": {
      "cost_avoided_usd": "number",
      "calculation_basis": "string",
      "confidence": "string — low | medium | high"
    }
  },

  "governance": {
    "policy_effectiveness": [
      {
        "policy": "string",
        "type": "string — security | operational | license | curation",
        "hits": "number",
        "pct_of_events": "number",
        "delta_pct": "number"
      }
    ],
    "repo_watch_coverage": [
      {
        "repo": "string",
        "indexed": "boolean",
        "watch_count": "number",
        "risk_level": "string — critical | high | medium | low"
      }
    ]
  },

  "threat_velocity": {
    "available": "boolean",
    "periods": [
      {
        "label": "string — e.g., 2026-W19",
        "blocked": "number",
        "violations": "number",
        "critical": "number"
      }
    ],
    "trend_summary": "string"
  },

  "comparison": {
    "available": "boolean — true if previous snapshot exists",
    "previous_date": "string — date of previous snapshot",
    "metrics": [
      {
        "label": "string — e.g., Packages Blocked",
        "previous": "number",
        "current": "number",
        "change_pct": "number — signed percentage",
        "direction": "string — up | down | flat",
        "good": "boolean — true if this direction is positive"
      }
    ]
  },

  "recommendations": [
    {
      "priority": "string — P1 | P2 | P3",
      "title": "string — bold title",
      "detail": "string — explanation with specific IDs, names, versions",
      "effort": "string — low | medium | high",
      "owner": "string — optional team or person",
      "due_date": "string — optional YYYY-MM-DD",
      "dependencies": ["string — optional recommendation IDs/titles"],
      "score": "number — required ranking score in beta"
    }
  ]
}
```

## Recommendation scoring (beta)

Use a deterministic, data-driven score for recommendation ranking. Suggested
formula:

```text
score =
  (critical_hits * 10) +
  (high_hits * 4) +
  (medium_hits * 2) +
  (exploit_active ? 30 : exploit_poc ? 10 : 0) +
  (in_prod ? 20 : 0) +
  (coverage_gap ? 15 : 0)
```

Priority mapping:
- `P1`: `score >= 80`
- `P2`: `score >= 40 and < 80`
- `P3`: `score < 40`

If upstream data is incomplete, compute the score with available values and
assume missing booleans are false.

Beta enforcement rule:
- Every recommendation MUST include both `priority` and `score`.
- If either is missing, treat it as a producer validation failure.

## Example values for unavailable features

```json
"curation": {
  "available": false,
  "total": 0, "blocked": 0, "approved": 0, "passed": 0, "block_rate": 0,
  "by_reason": { "malicious": 0, "security": 0, "license": 0, "operational": 0 },
  "top_blocked": [],
  "by_type": [],
  "audit_events": [],
  "observation": "Curation audit data unavailable. Curation may not be configured or the token lacks VIEW_POLICIES permission."
}
```

```json
"comparison": {
  "available": false,
  "previous_date": "",
  "metrics": []
}
```

```json
"threat_velocity": {
  "available": false,
  "periods": [],
  "trend_summary": ""
}
```