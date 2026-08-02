# JFrog Dashboard Blueprint APM Package

This APM package ships the `jfrog-dashboard-blueprint` skill as a standalone installable package.

The skill scaffolds new persona-specific JFrog dashboard/report skills from a guided interview. It does not query JFrog APIs or generate a live report.

## Install

```bash
apm install liquid-jedi/jfrog-agentic-dashboard-skills/packages/apm/jfrog-dashboard-blueprint#v4.0.1
```

For local testing from this repository:

```bash
cd packages/apm/jfrog-dashboard-blueprint
apm pack --dry-run --verbose
```
