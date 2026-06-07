# Installation

Get the dashboard skills installed, verified, and ready to run against your JFrog Platform.

## Before you start

| Requirement | Notes |
|-------------|--------|
| **JFrog Platform** | SaaS or self-hosted |
| **JFrog Xray** | Required for vulnerability and violation data |
| **JFrog Curation** | Optional — dashboard shows "Not configured" when absent |
| **JFrog CLI** (`jf`) | Installed and authenticated |
| **Tools on PATH** | `jf`, `jq`, `python3`, `npx` |
| **Base skill** | [`jfrog`](https://github.com/jfrog/jfrog-skills) from JFrog Platform Skills |

### Install JFrog CLI

```bash
# macOS
brew install jfrog-cli

# Linux
curl -fL https://install-cli.jfrog.io | sh

# Configure a server interactively with your own JFrog Platform URL
jf config add --interactive
```

### Current skill versions in this repository

- `jfrog-ciso-report` — `2.2.0`
- `jfrog-dashboard-blueprint` — `2.1.1`

Previous release:

- `jfrog-ciso-report` — `2.1.1`
- `jfrog-dashboard-blueprint` — `2.1.0`

### Install the base `jfrog` skill

```bash
npx skills add jfrog -g -y
npx skills list -g   # must include "jfrog"
```

---

## Install dashboard skills

### From GitHub (consumers)

```bash
npx skills add git@github.com:liquid-jedi/jfrog-agentic-dashboard-skills.git -g --skill jfrog-ciso-report
```

Optional skills from the same repository:

```bash
npx skills add git@github.com:liquid-jedi/jfrog-agentic-dashboard-skills.git -g --skill jfrog-dashboard-blueprint
```

### From a local clone (development)

Use this when you are editing skills in this repository — changes take effect immediately without copying stale folders.

```bash
REPO_ROOT="$(pwd)"
npx skills add "$REPO_ROOT" -g --skill jfrog-ciso-report
```

Other skills in the same clone:

```bash
npx skills add "$REPO_ROOT" -g --skill jfrog-dashboard-blueprint
```

> **Tip:** Prefer local-clone installs for authoring. Create a frozen distribution copy only when you need a handoff to another machine or team.

---

## Verify installation

Check the globally installed skills directly:

```bash
npx skills list -g
```

Expected result: the global skills list includes `jfrog` and `jfrog-ciso-report`.

If you also installed the scaffolder, the list should include `jfrog-dashboard-blueprint`.

## Update installed skills

There is no separate update command documented in this repo today. To refresh an installed skill, rerun the same `npx skills add ... -g --skill ...` command you used for install, then verify again with `npx skills list -g`.

Update from GitHub:

```bash
npx skills add git@github.com:liquid-jedi/jfrog-agentic-dashboard-skills.git -g --skill jfrog-ciso-report
```

Update from a local clone:

```bash
REPO_ROOT="$(pwd)"
npx skills add "$REPO_ROOT" -g --skill jfrog-ciso-report
```

## First report run

Ask your agent with a direct prompt such as:

```text
Generate a weekly CISO report.
Generate a monthly CISO report. Local only.
Generate a weekly CISO report for <your-server-id>. Save to Artifactory.
```

Runtime defaults:

- Server: single configured server is used automatically; multiple servers require a user choice.
- Local output root: prompt path, then `CISO_LOCAL_ROOT`, then a one-time bootstrap prompt for a stable local root.
- Storage: local-only unless you explicitly ask for Artifactory.
- Same-day reruns: written under `rerun-HHMMSS/` and never overwrite an earlier run.

## Example reports

If you want to see the output format before running the skill against your own instance, open one of the shipped sample reports from the repository:

- `samples/ciso-report-2026-04-26.html`
- `samples/` (additional sample outputs)
- `Example Reports/ciso-reports/liquidjedi/weekly/2026-05-20/report.html`
- `Example Reports/ciso-reports/liquidjedi/weekly/2026-05-26/report.html`

These files are static reference artifacts. They are useful for reviewing the generated dashboard layout and narrative style, but they are not live data and are not updated automatically.

**Claude Code example:**

```bash
claude -p "What skills do you have?" --allowedTools "Read" "Write"
```

---

## Runtime readiness check

Run the precheck script from any directory (replace the path with your clone):

```bash
REPO_ROOT="/path/to/your/jfrog-ciso-dashboard-clone"
bash "$REPO_ROOT/scripts/agentic-dashboard-prechecks.sh"
```

**Optional auto-fix:**

```bash
bash "$REPO_ROOT/scripts/agentic-dashboard-prechecks.sh" --fix
bash "$REPO_ROOT/scripts/agentic-dashboard-prechecks.sh" --fix --yes   # non-interactive / CI
```

### What “good” looks like

- `jf`, `jq`, `python3`, and `npx` on PATH
- Global skills include `jfrog` and `jfrog-ciso-report`
- At least one JFrog CLI server configured
- Multiple servers → runtime asks which server to use (no silent default)
- If no local output root is configured, runtime asks once for a stable `CISO_LOCAL_ROOT`
- Resolved local output root echoed before collection starts

Fix any reported blockers before generating reports.

### Platform support

| Environment | Supported |
|-------------|-----------|
| macOS | Yes |
| Linux | Yes |
| Windows (WSL) | Recommended |
| Native CMD/PowerShell | Not the primary path for prechecks |

### Cursor sandbox

If Cursor runs in sandbox auto-run mode, outbound network may be blocked. Allow egress to your JFrog endpoints for live API collection. Blocked network should fail fast — the skill must not reuse stale payloads.

### Runtime cleanup

Cleanup is agent-driven (part of the skill workflow), not an external script. Transient payloads under `/tmp` are removed at the end of each run. Interrupted runs must overwrite stale runtime data on the next run.

---

## Next steps

- [CISO user manual](ciso-user-manual.md) — permissions, agents, and interpretation
- [Troubleshooting](TROUBLESHOOTING.md) — common fixes
