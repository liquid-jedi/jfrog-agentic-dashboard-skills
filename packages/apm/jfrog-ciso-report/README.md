# JFrog CISO Report APM Package

This APM package ships the `jfrog-ciso-report` skill as a standalone installable package.

The skill generates a branded CISO Security and Curation HTML dashboard from a JFrog Platform instance. It includes the deterministic report runner, dashboard template, executive and full PDF templates, schema, collection mapping, and validation helpers.

## Install

```bash
apm install liquid-jedi/jfrog-agentic-dashboard-skills/packages/apm/jfrog-ciso-report#v4.1.0
```

To install an older repository release instead, use `#v3.0.0` rather than
`#v4.0.0` — the Claude guardrail in v4.0.0 shipped with an invalid
`settings.json` and never loaded, which is what v4.0.1 fixes.

```bash
apm install liquid-jedi/jfrog-agentic-dashboard-skills/packages/apm/jfrog-ciso-report#v3.0.0
```

For local testing from this repository:

```bash
cd packages/apm/jfrog-ciso-report
apm pack --dry-run --verbose
```

## Offline Package

The bundle is a build artifact, so it is not committed to the repository.
Download it from the [GitHub Release](https://github.com/liquid-jedi/jfrog-agentic-dashboard-skills/releases),
or rebuild it locally:

```bash
cd packages/apm
zip -r jfrog-ciso-report-v4.1.0.zip jfrog-ciso-report -x '*.DS_Store'
```

On the customer side, unzip and install from the local directory:

```bash
unzip jfrog-ciso-report-v4.1.0.zip
apm install ./jfrog-ciso-report --target claude,cursor,codex
```

To validate the bundle without installing it:

```bash
cd jfrog-ciso-report
apm pack --dry-run --verbose
```

## Runtime Requirements

- JFrog CLI configured with a server ID.
- `python3`, `jq`, and shell access available to the agent runtime.
- Network access to the target JFrog Platform APIs.
- `node` plus Puppeteer or a Chrome/Chromium-compatible browser for PDF generation.

## PDF Export Modes

`CISO_PDF_MODE` controls the generated PDF artifact:

| Mode | Output |
|-|-|
| unset or `executive` | `executive-report.pdf` is a concise CISO-shareable PDF |
| `full` | `full-report.pdf` is the detailed internal PDF |
| `both` | `executive-report.pdf` and `full-report.pdf` |

The runner also writes `curation-user-package-activity.csv` next to
`report.html` for the full active-user/package export. The dashboard embeds only
the top active users so large customer runs stay lightweight.

## Token Metadata, Boost, And Guardrails

`run-meta.json` includes best-effort agent and token metadata. The runner reads
token values from `CISO_TOTAL_TOKENS`, detailed token env vars,
`CISO_TOKEN_USAGE_PATH`, `/tmp/ciso-token-usage.json`, or a supplied Claude
transcript path. If no source is available, token usage is marked unavailable.

This APM also includes optional Boost filters and guardrail hook examples under
`extras/agent-support/` for Cursor, Claude Code, Codex, and Antigravity. Boost
reduces noisy terminal output; the guardrails block destructive JFrog commands
during report generation. Copy only the files for the agent runtime the customer
uses.
