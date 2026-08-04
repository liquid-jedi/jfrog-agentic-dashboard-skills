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
    "curation_uninspected_label": "string — default: Passed without inspection",
    "curation_audit_ui_path": "string — optional UI path, default /ui/package-curation/audit",
    "date_from": "string — display format (e.g., Apr 1, 2026)",
    "date_to": "string — display format",
    "report_type": "string — Weekly | Monthly | Custom",
    "window_days": "number",
    "export_files": {
      "curation_user_package_activity_csv": "string — relative CSV path next to report.html"
    },
    "export_counts": {
      "curation_user_package_activity_rows": "number — one row per user in the CSV",
      "curation_user_package_pairs": "number — user/package pairs those rows aggregate"
    }
  },

  "// methodology": "RESERVED — no template reads this key; populating it has no effect on the report",
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
    "uncurated_types": ["string — package types without curation"],
    "pass_through_repos": [
      {
        "repo": "string — remote repository key not connected to Curation",
        "package_type": "string",
        "supported": "boolean — whether the package type is supported by Curation"
      }
    ],
    "repo_criticality": [
      {
        "repo": "string",
        "business_service": "string — optional application/service name",
        "criticality": "string — critical | high | medium | low | unknown",
        "environment": "string — e.g. production | build | development",
        "owner": "string — optional business or engineering owner"
      }
    ]
  },

  "curation": {
    "available": "boolean — false if API returned 404/403",
    "total": "number — total audit events",
    "blocked": "number",
    "approved": "number — packages allowed by Curation after policy evaluation",
    "clean_packages": "number — alias of approved; inspected packages allowed by Curation",
    "clean_rate": "number — clean_packages / (blocked + clean_packages) * 100",
    "passed": "number — legacy; prefer request_results.without_inspection",
    "request_results": {
      "blocked": "number",
      "approved": "number — packages allowed after Curation policy evaluation",
      "clean_packages": "number — alias of approved",
      "dry_run": "number — alert-only evaluations (dry_run=true stream)",
      "without_inspection": "number — downloads not policy-inspected (Curation UI Passed)"
    },
    "without_inspection": "number — alias of request_results.without_inspection",
    "policy_inventory": {
      "block_active": "number",
      "dry_run_active": "number",
      "total_registered": "number",
      "by_risk_type": [{ "type": "string", "count": "number" }],
      "block_by_risk_type": [{ "type": "string", "count": "number" }],
      "block_policies": [{ "name": "string", "risk_type": "string", "scope": "string", "condition": "string" }],
      "dry_run_policies": [
        { "name": "string", "scope": "string", "days_in_dry_run": "number|null" }
      ],
      "baseline_policy_posture": {
        "block_malicious_org_wide": "boolean",
        "matching_policies": ["string"]
      },
      "cached_package_enforcement": {
        "global_enabled": "boolean|null — null when the platform API does not expose the global setting",
        "policies_enforcing_cache": "number",
        "blocking_policies_total": "number",
        "policies_missing_cache_enforcement": ["string"]
      }
    },
    "waiver_requests": {
      "available": "boolean",
      "pending": "number",
      "approved": "number",
      "rejected": "number"
    },
    "curation_state": {
      "remote_total": "number",
      "connected": "number",
      "not_connected": "number",
      "connected_pct": "number",
      "supported_remote_total": "number — remotes in supported ecosystems",
      "supported_connected": "number",
      "supported_not_connected": "number",
      "supported_connected_pct": "number",
      "package_types_total": "number",
      "by_package_type": [
        {
          "package_type": "string",
          "remote_total": "number",
          "connected": "number",
          "blocked_period": "number"
        }
      ],
      "note": "string"
    },
    "top_policies": [
      { "name": "string", "audit_hits": "number", "blocked_hits": "number", "scope_label": "string", "action": "string" }
    ],
    "block_rate": "number — percentage",
    "by_reason": {
      "malicious": "number",
      "security": "number — CVE-based blocks",
      "license": "number",
      "operational": "number"
    },
    "policy_violations_by_type": {
      "malicious": "number",
      "security": "number",
      "license": "number",
      "operational": "number",
      "total_blocked": "number"
    },
    "blocking_events_per_policy": [
      {
        "name": "string",
        "scope_label": "string",
        "blocked_events": "number",
        "audit_events": "number",
        "action": "string"
      }
    ],
    "package_types": {
      "total": "number — package types in supported ecosystems (UI parity)",
      "top_by_blocked": [
        {
          "package_type": "string",
          "blocked": "number",
          "connected_repos": "number",
          "remote_total": "number"
        }
      ]
    },
    "top_blocked": [
      {
        "package": "string",
        "ecosystem": "string — npm, PyPI, Maven, etc.",
        "count": "number",
        "malicious": "boolean — true if flagged as malicious"
      }
    ],
    "policies_enforced": {
      "available": "boolean",
      "total_registered": "number — all curation policies returned by API",
      "enabled": "number",
      "enforcing": "number — enabled policies where policy_action is not dry_run",
      "dry_run_excluded": "number",
      "by_scope": [
        {
          "scope": "string — all_repos | specific_repos | user | …",
          "label": "string — display label",
          "registered": "number",
          "enforcing": "number — non-dry-run in this scope"
        }
      ],
      "by_policy": [
        {
          "name": "string",
          "scope": "string",
          "scope_label": "string",
          "action": "string — block | dry_run | …",
          "enabled": "boolean",
          "audit_hits": "number — non-dry-run policy evaluations in period",
          "blocked_hits": "number — blocked outcomes tied to policy",
          "clean_hits": "number — approved outcomes tied to policy",
          "blocked_pct": "number — blocked_hits / (blocked_hits + clean_hits) * 100",
          "clean_pct": "number — clean_hits / (blocked_hits + clean_hits) * 100"
        }
      ]
    },
    "by_type": [
      { "type": "string — npm, PyPI, etc.", "total": "number", "blocked": "number" }
    ],
    "unique_users": "number — distinct username or user_mail across all audit events in period",
    "unique_users_approved": "number — subset of unique_users with >=1 allowed request (approved + passed > 0), i.e. identities that actually received a package; <= unique_users",
    "top_users": [
      {
        "user": "string — username or user_mail",
        "events": "number — total audit events for this user",
        "events_pct": "number — percentage of all attributed user events",
        "blocked": "number",
        "approved": "number",
        "passed": "number",
        "packages": [
          {
            "package": "string",
            "ecosystem": "string",
            "requests": "number"
          }
        ],
        "distinct_packages": "number — distinct packages across the whole period, not capped by packages[]",
        "ecosystems": ["string — every ecosystem the user pulled from in the period"]
      }
    ],
    "user_package_activity": [
      {
        "user": "string",
        "user_events": "number",
        "user_events_pct": "number",
        "user_blocked": "number",
        "user_approved": "number",
        "package": "string",
        "ecosystem": "string",
        "requests": "number — full aggregated user/package export data"
      }
    ],
    "audit_events": [
      {
        "status": "string — blocked only (all blocked events in period)",
        "package": "string",
        "version": "string",
        "type": "string — package type",
        "repo": "string",
        "policy": "string",
        "requested_by": "string — user/email",
        "date": "string — display format",
        "timestamp": "string — ISO created_at (optional)",
        "malicious": "boolean — optional, used for display sort"
      }
    ],
    "audit_events_display": "array — same shape as audit_events, max 50, sort C+D for HTML table",
    "audit_events_display_meta": {
      "cap": "number — default 50",
      "sort": "string — malicious_then_package_count_then_newest",
      "total_blocked": "number"
    },
    "executive_insights": {
      "gate_coverage_gaps": [
        {
          "package_type": "string — supported Curation ecosystem only",
          "supported": "boolean — always true for rendered gaps",
          "unconnected": "number — supported remotes not connected to Curation",
          "connected": "number",
          "total": "number",
          "known_violations": "number — best-effort Xray violations mapped to this ecosystem",
          "priority": "string — P1 | P2"
        }
      ],
      "enforcement_opportunity": {
        "dry_run_policies": "number",
        "would_have_blocked": "number — best-effort dry-run audit events that would have blocked",
        "top_policies": [{ "policy": "string", "events": "number" }]
      },
      "malicious_package_defense": {
        "malicious_blocks": "number",
        "malicious_policies": "number",
        "top_packages": [{ "package": "string", "blocks": "number" }]
      }
    },
    "observation": "string — agent-generated insight about curation data"
  },

  "violations": {
    "total": "number",
    "unique_issue_count": "number — distinct Xray issue/CVE IDs",
    "unique_critical_issue_count": "number — distinct critical Xray issue/CVE IDs",
    "posture_signals": {
      "severity_mix": "number — 0-100 severity-weighted mix, not a composite risk score",
      "violation_volume": "number — raw Xray violation count",
      "coverage_gap": "number — percentage of repositories without Xray indexing"
    },
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
        "component": "string — best-effort affected component/package",
        "hits": "number",
        "repo_count": "number — distinct repositories in raw violation rows",
        "artifact_count": "number — distinct artifacts in raw violation rows",
        "first_seen": "string — YYYY-MM-DD",
        "days_open": "number",
        "fix_status": "string — available | none | unknown",
        "fix_available": "boolean",
        "fix_versions": ["string"],
        "exploit_status": "string — active | poc | none | unknown",
        "affected_environments": ["string — prod | build | dev | transitive"],
        "playbook_link": "string — optional URL to response runbook"
      }
    ],
    "top_repos": [
      {
        "repo": "string",
        "count": "number",
        "critical": "number",
        "business_service": "string — optional",
        "criticality": "string — from optional repo mapping",
        "environment": "string — optional",
        "owner": "string — optional"
      }
    ],
    "top_cves": [
      {
        "id": "string — CVE-YYYY-NNNN or XRAY id",
        "cvss": "number|string|null",
        "severity": "string",
        "packages": "number — unique affected components",
        "hits": "number — violation rows"
      }
    ],
    "top_watch_policies": [
      { "policy": "string", "type": "string", "hits": "number" }
    ],
    "executive_insights": {
      "sla_risk_backlog": {
        "buckets": [
          { "label": "string — 0-7 days | 8-30 days | 31-90 days | 90+ days", "issues": "number", "hits": "number" }
        ],
        "sla_breach_issues": "number — critical issues older than sla_days",
        "sla_days": "number — default 30"
      },
      "remediation_readiness": {
        "fix_available_issues": "number",
        "fix_available_hits": "number",
        "no_fix_issues": "number",
        "unknown_issues": "number"
      },
      "highest_impact_fixes": [
        { "component": "string", "critical_issues": "number", "hits": "number", "hit_share_pct": "number" }
      ],
      "new_critical_introductions": {
        "new_issues": "number",
        "new_hits": "number",
        "existing_issues": "number",
        "baseline_available": "boolean"
      },
      "watch_blind_spots": [
        { "repo": "string", "violation_count": "number", "critical_count": "number", "watch_count": "number", "watch_names": ["string"], "risk_level": "string" }
      ],
      "watch_blind_spots_meta": {
        "available": "boolean — false when the Xray watch payload lacks repo assignments",
        "reason": "string"
      },
      "blast_radius": [
        { "issue": "string", "repos": "number", "artifacts": "number", "component": "string", "hits": "number" }
      ]
    },
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
    "upgrade_rate_computed": "boolean — true only when derived from block-then-approved events",
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
    "xray_policy_effectiveness": "array — same shape as policy_effectiveness, rendered on the Xray tab",
    "curation_policy_effectiveness": "array — same shape as policy_effectiveness, rendered on the Curation tab",
    "repo_watch_coverage": [
      {
        "repo": "string",
        "indexed": "boolean",
        "watch_count": "number",
        "watch_names": ["string"],
        "violation_count": "number",
        "critical_count": "number",
        "risk_level": "string — critical | high | covered",
        "business_service": "string — optional",
        "criticality": "string — optional",
        "environment": "string — optional",
        "owner": "string — optional"
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