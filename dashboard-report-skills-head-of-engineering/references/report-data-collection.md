# Report Data Collection — Head of Engineering

Generated: 2026-05-19
Schema: `1.0-head-of-engineering`

## Execution order

Collect in this order to minimize latency. **Blocking** sources must complete
before JSON assembly. Non-blocking sources can run in parallel after step 1.

| Step | Source | Blocking? | Maps to sections |
|------|--------|-----------|-----------------|
| 1 | Xray — violations by project/team | yes | `cve-by-team`, `dep-trend`, `delivery-risk`, `k-cve-critical`, `k-dep-health-score` |
| 2 | Curation — decision log | yes | `curation-summary`, `k-curation-block-rate` |
| 3 | Artifactory — build records | yes | `build-health`, `k-build-reproducibility` |
| 4 | Evidence — attestations | yes | `build-health` |
| 5 | Distribution — release bundles | no | `delivery-risk`, `k-delivery-risk` |
| 6 | GitHub — PR/commit activity | no | `gh-activity`, `k-gh-throughput` |
| 7 | Xray + Artifactory — user group mapping | no | `user-group-breakdown` |

---

## Source 1: JFrog Xray — violations by project and team

**Purpose:** `cve-by-team`, `dep-trend`, `delivery-risk`, KPIs `k-cve-critical` and `k-dep-health-score`

```bash
# List all violations in period, paginated (replace dates with actual period)
jf xr curl -s "GET" "/api/v1/violations" \
  --data '{
    "filters": {
      "start_date": "{{PERIOD_START}}",
      "end_date": "{{PERIOD_END}}",
      "type": ["security","license"],
      "min_severity": "Low"
    },
    "pagination": { "order_by": "created", "direction": "asc", "limit": 100, "offset": 0 }
  }'
```

```bash
# Get violations grouped by Xray watch/project (use project_key filter per project)
# Repeat for each project in scope
jf xr curl -s "GET" "/api/v1/violations?filters=%7B%22project_key%22%3A%22{{PROJECT_KEY}}%22%7D"
```

**Expected fields per violation:**
`issue_id`, `type`, `severity`, `component_id`, `package_name`, `version`,
`watch_name`, `project_key`, `created`, `summary`

**Aggregation logic:**
- Group by `project_key` → map to team (use team-lookup table)
- Count `critical`, `high`, `medium`, `low` per group
- Compute score: `(critical × 100 + high × 20 + medium × 5 + low × 1)`, normalize 0–100
- For trend: store current score alongside prior-period score

**Error handling:** If Xray returns 0 violations, add warning to `meta.warnings`.
Do not fail the report — render zeros with a "No violations found" note in the section.

---

## Source 2: JFrog Curation — decision log

**Purpose:** `curation-summary`, KPI `k-curation-block-rate`

```bash
# TODO: confirm exact endpoint for your Curation version
# Curation audit log — paginated
jf curl -s "GET" "/api/v2/curation/auditLog?from={{PERIOD_START}}&to={{PERIOD_END}}&limit=500"
```

**Expected fields per record:**
`package_name`, `version`, `package_type`, `repo`, `action` (`"blocked"` | `"allowed"`),
`policy_name`, `condition_name`, `timestamp`, `requested_by`

**Aggregation logic:**
- `block_count` = count where `action == "blocked"`
- `allow_count` = count where `action == "allowed"`
- `block_rate` = `block_count / (block_count + allow_count) × 100`
- Group by `policy_name` for the bar chart breakdown

**KPI assembly:**
```json
{ "id": "k-curation-block-rate", "value": 12, "unit": "%" }
```

**Known gap:** Curation API path may differ between SaaS and self-hosted.
Check `/api/v2/curation/` vs `/xray/api/v2/curation/` for your deployment.

---

## Source 3: JFrog Artifactory — build records

**Purpose:** `build-health`, KPI `k-build-reproducibility`

```bash
# List all builds in the platform
jf rt curl -s "GET" "/api/build"

# Get build details (repeat per build name/number)
jf rt curl -s "GET" "/api/build/{{BUILD_NAME}}/{{BUILD_NUMBER}}"
```

**Expected fields:**
`name`, `number`, `started`, `version`, `buildAgent.name`, `buildAgent.version`,
`modules[].id`, `modules[].artifacts[].name`, `modules[].artifacts[].sha256`,
`properties`, `statuses`

**Reproducibility heuristic:**
A build is considered reproducible if:
1. It has at least one artifact with a recorded `sha256`
2. The same artifact sha256 appears in two or more builds of the same name

```
reproducibility_rate = reproducible_builds / total_builds × 100
```

**Error handling:** If build API returns empty, add warning. Render 0% with note.

---

## Source 4: JFrog Evidence — attestations

**Purpose:** Augment `build-health` with provenance and compliance signals

```bash
# TODO: implement Evidence attestation query
# Evidence API — list attestations for build subjects
jf evd curl -s "GET" "/api/v1/subjects?type=build&from={{PERIOD_START}}&to={{PERIOD_END}}"
```

**Expected fields:**
`subject_id`, `subject_type`, `predicate_type` (e.g. `"https://slsa.dev/provenance/v1"`),
`verified`, `signer`, `created_at`, `package_ref`

**Assembly logic:**
- For each build in Source 3, look up matching Evidence subject by `subject_id`
- Mark `has_attestation: true/false` on each build row
- Surface unsigned or unverified attestations as warnings

**Known gap:** Evidence module must be licensed and enabled on your platform.
If unavailable, set `has_attestation: null` and emit a warning.

---

## Source 5: JFrog Distribution — release bundle status

**Purpose:** `delivery-risk` section and KPI `k-delivery-risk`

```bash
# TODO: confirm Distribution API version for your deployment
# List release bundles in period
jf ds curl -s "GET" "/api/v1/release_bundle?order_by=created_at&direction=desc"
```

**Expected fields:**
`name`, `version`, `state` (`"OPEN"` | `"CLOSED"` | `"SIGNED"` | `"DISTRIBUTED"`),
`created_at`, `distribution_rules[].site_name`, `artifacts_count`

**Risk signal:**
- Bundles in `"OPEN"` state past expected close date → elevated delivery risk
- Bundles with 0 artifacts → gap in pipeline
- Failed distributions (check distribution log) → risk flag

---

## Source 6: GitHub — PR and commit activity

**Purpose:** `gh-activity`, KPI `k-gh-throughput`

```bash
# List merged PRs in period (requires gh CLI + auth)
# TODO: replace {{ORG}} with your GitHub org
gh api "/orgs/{{ORG}}/repos" --paginate | jq '.[].name' | while read repo; do
  gh api "/repos/{{ORG}}/$repo/pulls?state=closed&base=main&per_page=100" --paginate \
    | jq --arg repo "$repo" '[.[] | select(.merged_at != null) | {
        repo: $repo,
        number: .number,
        title: .title,
        merged_at: .merged_at,
        author: .user.login,
        labels: [.labels[].name]
      }]'
done
```

**Aggregation logic:**
- `prs_merged` = total merged PRs in period
- Group by repo → map to team via CODEOWNERS or Artifactory user groups
- `cycle_time` = average (merged_at − created_at) in hours — optional

**Known gap:** Team mapping from GitHub logins to engineering teams requires
either a lookup table or GitHub Teams API (`/orgs/{{ORG}}/teams`).

---

## Source 7: Xray + Artifactory — violations by user group

**Purpose:** `user-group-breakdown` section

```bash
# Step A: get all Artifactory user groups
jf rt curl -s "GET" "/api/security/groups"

# Step B: get group members for each group
jf rt curl -s "GET" "/api/security/groups/{{GROUP_NAME}}?includeUsers=true"

# Step C: get per-user artifact download activity
# jf rt curl -s "GET" "/api/storage?path=/&list&deep=1" — too broad
# Better: use Artifactory Access Log or Xray violations filtered by requester identity
# TODO: implement user-group to violation cross-reference
```

**Assembly logic:**
- Build a `user → group` lookup from Step B
- For each Xray violation (from Source 1), identify the requesting user from the artifact's
  download log (requires Audit Log enabled in Artifactory)
- Aggregate violation counts per group

**Known gap:** User-to-violation attribution requires Audit Log.
If unavailable, this section should render as "Data not available — Audit Log required"
and emit a warning to `meta.warnings`.

---

## Period-over-period comparison

To populate `comparison`, re-run all queries for the prior period:

| Cadence | Prior period offset |
|---------|-------------------|
| Daily | −1 day |
| Weekly | −7 days |
| Monthly | −30 days |

Store prior KPI values then compute:
```
kpi_deltas[id] = current_value − prior_value
```

A negative delta for a `down_is_good` KPI is an improvement (render green).
A positive delta for a `down_is_good` KPI is a regression (render red).

---

## Known gaps and TODOs

- [ ] **Curation** — confirm API path for your deployment (SaaS vs self-hosted)
- [ ] **Evidence** — verify Evidence module is licensed and enabled
- [ ] **GitHub integration** — configure org list; store PAT in environment variable `GITHUB_TOKEN`
- [ ] **User group → team mapping** — build a static lookup table or use GitHub Teams API
- [ ] **Audit Log** — enable Artifactory Access Log for user-group violation attribution
- [ ] **Distribution** — confirm API path for your Distribution version
- [ ] **Retention policy** — define and implement report file retention (delete after N days)
- [ ] **Approval workflow** — implement notification to approver when `approval_status == "pending"`
