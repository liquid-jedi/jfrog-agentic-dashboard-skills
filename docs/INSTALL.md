# Installation

Get the dashboard skills installed, verified, and ready to run against your JFrog Platform.

## Before you start

| Requirement | Notes |
|-------------|--------|
| **JFrog Platform** | SaaS or self-hosted |
| **JFrog Xray** | Required for vulnerability and violation data |
| **JFrog Curation** | Optional — dashboard shows "Not configured" when absent |
| **JFrog CLI** (`jf`) | Installed and authenticated |
| **Tools on PATH** | `jf`, `jq`, `python3`; `apm` for APM installs or `npx` for generic Skills installs |
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

- `jfrog-ciso-report` — `2.3.0`
- `jfrog-dashboard-blueprint` — `2.1.1`

Previous release:

- `jfrog-ciso-report` — `2.2.0`
- `jfrog-dashboard-blueprint` — `2.1.0`

### Install the base `jfrog` skill

```bash
npx skills add jfrog -g -y
npx skills list -g   # must include "jfrog"
```

---

## Install dashboard skills

### What is APM?

[Microsoft APM](https://microsoft.github.io/apm/) is an Agent Package Manager: a package manager for agent context. It lets a project declare skills, prompts, instructions, plugins, and MCP servers in `apm.yml`, then reproduce the same agent setup with `apm install`.

For these JFrog dashboard skills, APM installs the skill into the current project, for example:

```text
~/ciso-reporting/
├── apm.yml
├── apm.lock.yaml
├── .agents/skills/jfrog-ciso-report/
└── .claude/skills/jfrog-ciso-report/
```

That project-local model is different from a global Skills install.

### Which install should you choose?

| Install path | Best for | Runtime behavior |
|--------------|----------|------------------|
| **Option 1: APM install** | Teams that want reproducible, project-local agent context with `apm.yml` and `apm.lock.yaml` | Run the agent from the APM project folder where the skill was installed. |
| **Option 2: Generic Skills install** | Users who want the skill available globally from any terminal folder or UI-based agent session | Installs into the user's global skills directory. |

APM is intentionally project-based, similar to how `npm install` works for application dependencies. If you install the skill into `~/ciso-reporting`, start Claude/Codex/Cursor from `~/ciso-reporting` so the runtime can see that project's `.agents/skills/` and `.claude/skills/` folders.

If your operators expect to open Claude/Codex from any folder and simply ask for a CISO report, use the generic global Skills install instead.

APM tradeoffs:

- **Pros:** reproducible installs, lockfile, project-local isolation, easier team onboarding, safer than relying on each user's global state.
- **Cons:** users must run the agent from the APM project folder, or open that folder as the active workspace in UI-based agents.

Generic Skills tradeoffs:

- **Pros:** available globally from any terminal folder or UI session after one install.
- **Cons:** less reproducible across users and machines; updates depend on each user's global skill state.

### Option 1: APM install

Use this path when you want a reproducible agent package install across supported agent runtimes.

Install APM:

```bash
curl -sSL https://aka.ms/apm-unix | sh
apm --version
```

Install the CISO report package from the published repository:

```bash
mkdir -p ~/ciso-reporting
cd ~/ciso-reporting
apm init -y --target claude,codex,cursor
apm install liquid-jedi/jfrog-agentic-dashboard-skills/packages/apm/jfrog-ciso-report#v2.3.0
```

Optional: install the persona scaffolder package:

```bash
apm install liquid-jedi/jfrog-agentic-dashboard-skills/packages/apm/jfrog-dashboard-blueprint#v2.3.0
```

Run project-local APM skills from the same folder:

```bash
cd ~/ciso-reporting
claude
```

For Codex or Cursor, open/use the `~/ciso-reporting` folder as the active project/workspace.

Do not use `#v2.2.0` for APM installs because that release predates APM packaging.

### Option 2: Generic Skills install

Use this path when your agent runtime already uses the Skills CLI flow.

```bash
npx skills add git@github.com:liquid-jedi/jfrog-agentic-dashboard-skills.git -g --skill jfrog-ciso-report
```

Optional skills from the same repository:

```bash
npx skills add git@github.com:liquid-jedi/jfrog-agentic-dashboard-skills.git -g --skill jfrog-dashboard-blueprint
```

### Local clone install (development)

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

For generic Skills installs, check the globally installed skills directly:

```bash
npx skills list -g
```

Expected result: the global skills list includes `jfrog` and `jfrog-ciso-report`.

If you also installed the scaffolder, the list should include `jfrog-dashboard-blueprint`.

For APM installs, inspect the deployed skills in the target project:

```bash
cd ~/ciso-reporting
find .agents/skills -maxdepth 2 -type f | sort
```

## Update installed skills

For APM installs, rerun the same `apm install ...` command or update the dependency in `apm.yml` and run `apm install`.

For generic Skills installs, rerun the same `npx skills add ... -g --skill ...` command you used for install, then verify again with `npx skills list -g`.

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

For an APM install, start the agent from the APM project folder:

```bash
cd ~/ciso-reporting
claude
```

For a generic global Skills install, start the agent from any folder where you want to work.

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
- `Example Reports/ciso-reports/weekly/report-1.html`
- `Example Reports/ciso-reports/Monthly/report-1.html`

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
