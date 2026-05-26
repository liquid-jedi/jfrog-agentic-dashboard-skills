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

# Configure a server
jf config add solenglatest --url=https://solenglatest.jfrog.io --interactive
```

### Install the base `jfrog` skill

```bash
npx skills add jfrog -g -y
npx skills list   # must include "jfrog"
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

Your agent should list `jfrog-ciso-report` among available skills.

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

- [Running reports](RUNNING.md) — prompts, defaults, and artifact layout
- [CISO user manual](ciso-user-manual.md) — permissions, agents, and interpretation
- [Troubleshooting](TROUBLESHOOTING.md) — common fixes
