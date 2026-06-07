# JFrog CISO Report APM Package

This APM package ships the `jfrog-ciso-report` skill as a standalone installable package.

The skill generates a branded CISO Security and Curation HTML dashboard from a JFrog Platform instance. It includes the deterministic report runner, dashboard template, schema, collection mapping, and validation helpers.

## Install

```bash
apm install liquid-jedi/jfrog-agentic-dashboard-skills/packages/apm/jfrog-ciso-report#main
```

For local testing from this repository:

```bash
cd packages/apm/jfrog-ciso-report
apm pack --dry-run --verbose
```

## Runtime Requirements

- JFrog CLI configured with a server ID.
- `python3`, `jq`, and shell access available to the agent runtime.
- Network access to the target JFrog Platform APIs.
