# CISO collection proof — solenglatest (2026-05-29)

Live tests against `SERVER_ID=solenglatest` using `jf xr curl` / `jf rt curl`.
Your current `weekly/2026-05-29/data.json` was built **without** platform merge or curation-audit-transform (fields missing below).

## Proof table

| Report field | Your `data.json` | Live API (retrievable) | API / mechanism |
|--------------|------------------|------------------------|-----------------|
| `platform.repos_indexed` | **0** | **545** | `GET /api/v1/binMgr/default/repos` → `indexed_repos[]` |
| `platform.watches_total` | **0** | **22** (14 active) | `GET /api/v2/watches` (not `/api/v2/xray/watches` — 404) |
| `platform.policies_total` | **0** | **28** | `GET /api/v2/policies` |
| `curation.unique_users` | **missing** | **17** | All paginated audit rows; `username` / `user_mail` |
| `policy_inventory.total_registered` | **missing** | **121** | `GET /api/v1/curation/policies` (paginate `meta.total_count`) |
| `policy_inventory.block_active` | **missing** | **90** | `policy_action != dry_run`, `enabled` |
| `policy_inventory.dry_run_active` | **missing** | **27** | `policy_action == dry_run` |
| `curation_state.connected` (all remotes) | **missing** | **190 / 249** | Per remote `GET /api/repositories/{key}` → `curated: true` |
| `supported_connected` / `supported_remote_total` | **missing** | **~190 / ~238** (UI) | Subset: remotes whose `packageType` is in policy `supported_pkg_types` |
| `package_types.total` | **missing** (UI shows 4) | **16** (UI) | Count supported package types with ≥1 remote |
| Blocking policies (not "Unknown") | **Unknown @ 213 hits** | Named policies | `policy_name` on blocked audit events, e.g. `jml-ai-catalog-demo-pypi` |
| Top block policy | missing | `block_malicious_package: 12`, … | `policies[].policy_name` on `action=blocked` |

## Sample API evidence

### Indexed repos (545)

```
GET /api/v1/binMgr/default/repos
→ len(indexed_repos) = 545
```

### Curation policies (121 total, 90 block, 27 dry-run)

```
GET /api/v1/curation/policies?num_of_rows=200&offset=0
→ meta.total_count = 121
→ enabled block policies = 90, dry_run = 27
→ sample block policy: ak-ide-immature-policy
```

### Curation users (17)

From audit window (7d), scanning paginated `GET /api/v1/curation/audit/packages`:

- `total_count` = 10091
- `unique_users` = 17 (e.g. `paulda`, `maharship`, `mikeho`, …)

### Blocking events per policy (top sample)

| Policy | Blocked events |
|--------|----------------|
| block_malicious_package | 12 |
| joern-curl-version | 7 |
| joern-block-malicious | 7 |
| jml-ai-catalog-demo-pypi | 6 |

Blocked event shape:

```json
{
  "policy_name": "jml-ai-catalog-demo-pypi",
  "policy_id": 1180,
  "dry_run": false,
  "condition_name": "AI-Catalog-block-in-ai-catalog-demo",
  "condition_category": "security"
}
```

### Remote repos connected (190/249)

```
GET /api/repositories?type=remote → 249 keys
GET /api/repositories/{key} → curated=true on 190 repos

Examples:
  Ohadz-test-curation-config: curated=True, packageType=npm
  agentic-development-lab-npm-remote: curated=True, packageType=npm

By package type (connected / total):
  npm: 56/58
  HuggingFaceML: 34/34
  Maven: 28/29
  Docker: 26/64
  PyPI: 21/26
```

### Why UI shows `0 / 175` for Conan connected repos

- **175** = blocked **events** in period for Conan (audit), not repo count.
- **0 / 175** in your report = `connected_repos` never merged from platform merge (`by_package_type` empty in JSON).
- Expected after merge: Conan **connected remotes** should reflect `curated=true` Conan remotes (not 175).

## Root cause in `data.json`

Checked `~/ciso-reports/solenglatest/weekly/2026-05-29/data.json`:

- No `curation.unique_users`, `policy_inventory`, `curation_state`, `blocking_events_per_policy`
- `platform.repos_indexed: 0`, `watches_total: 0`, `policies_total: 0`
- `governance.policy_effectiveness` = single row `Unknown` / `curation` (agent stub, not watch API)

**Conclusion:** Template/skill logic is fine; the **collection pipeline steps were skipped** on the last run.

## Required pipeline steps (must run in order)

1. Phase 1 platform track (correct watch/policy paths)
2. **Platform merge** → `/tmp/ciso-platform.json` → merge into `data.json` `platform`
3. Curation jq map + full audit pagination
4. **curation-audit-transform** → users, policies, blocking_events_per_policy, package_types
5. **collection-determinism-guards** (should fail if zeros remain)

Run proof script: `Dashboard-ciso-report-skills/internal/verify-ciso-collection-proof.sh solenglatest`
