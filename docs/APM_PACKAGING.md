# APM Packaging

This repository ships two separate Agent Package Manager (APM) packages:

- `packages/apm/jfrog-ciso-report`
- `packages/apm/jfrog-dashboard-blueprint`

The packages are intentionally separate because the skills have different jobs:

- `jfrog-ciso-report` generates live CISO Security and Curation reports.
- `jfrog-dashboard-blueprint` scaffolds new persona dashboard skills.

## Package Layout

Each package follows the APM package shape:

```text
apm.yml
.apm/
  skills/
    <skill-name>/
      SKILL.md
      references/
      bin/
      internal/
```

The canonical skill sources remain at the repository root:

```text
Dashboard-ciso-report-skills/
Dashboard-blueprint-skills/
```

Before publishing APM package changes, refresh the package copies:

```bash
bash scripts/sync-apm-packages.sh
```

## Local Development Test

Install APM first:

```bash
curl -sSL https://aka.ms/apm-unix | sh
```

Then test each package from a scratch directory:

```bash
mkdir -p /tmp/jfrog-apm-test
cd /tmp/jfrog-apm-test
apm init -y --target cursor
apm install /path/to/jfrog-ciso-dashboard/packages/apm/jfrog-ciso-report --target cursor
apm install /path/to/jfrog-ciso-dashboard/packages/apm/jfrog-dashboard-blueprint --target cursor
find .agents/skills -maxdepth 3 -type f | sort
```

Package author checks:

```bash
cd packages/apm/jfrog-ciso-report
apm pack --dry-run --verbose

cd ../jfrog-dashboard-blueprint
apm pack --dry-run --verbose
```

`apm preview` previews named scripts and these packages do not define scripts.
`apm view` expects an installed or remote package argument. For these skill-only
packages, local path install plus `apm pack --dry-run` are the primary checks.

## Install From GitHub

After these package folders are merged to `main`, consumers can install from the monorepo subdirectories:

```bash
apm install liquid-jedi/jfrog-agentic-dashboard-skills/packages/apm/jfrog-ciso-report#main
apm install liquid-jedi/jfrog-agentic-dashboard-skills/packages/apm/jfrog-dashboard-blueprint#main
```

Use a version tag only after the tag contains the `packages/apm/` folders, for example a future release:

```bash
apm install liquid-jedi/jfrog-agentic-dashboard-skills/packages/apm/jfrog-ciso-report#v2.3.0
apm install liquid-jedi/jfrog-agentic-dashboard-skills/packages/apm/jfrog-dashboard-blueprint#v2.3.0
```

Do not use `#v2.2.0` for APM installs because that tag was created before APM package folders were added.
