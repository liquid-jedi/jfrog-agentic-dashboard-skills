# Running Reports

How to generate CISO (and other persona) dashboards from your AI agent.

## Interactive (recommended)

Open your agent and ask naturally:

```
Generate a weekly CISO report
Generate a monthly CISO report for solenglatest
Generate a CISO dashboard for the last 30 days
```

### Server selection

| Situation | Behavior |
|-----------|----------|
| Server named in prompt | That server is used |
| Exactly one `jf` server configured | Used silently |
| Multiple servers, none named | Skill **asks** — no silent CLI default |

### Local output path

| Priority | Source |
|----------|--------|
| 1 | Path in your prompt |
| 2 | `CISO_LOCAL_ROOT` environment variable |
| 3 | One-time bootstrap prompt for a stable local root |

The skill should state the resolved server, local root, and storage mode **before** data collection.

---

## Headless / CI

**Claude Code:**

```bash
claude -p "Generate a weekly CISO report for solenglatest. Local only." \
  --allowedTools "Bash(jf *)" "Bash(jq *)" "Bash(eval *)" \
  "Bash(cat *)" "Bash(echo *)" "Bash(date *)" "Bash(sed *)" \
  "Bash(cp *)" "Bash(mkdir *)" "Bash(python3 *)" "Bash(wc *)" \
  "Bash(grep *)" "Bash(find *)" "Read" "Write" \
  2>&1 | tee /tmp/ciso-run.log
```

**Any agent:** prompt with `"Generate a weekly CISO report. Local only."` and ensure `jf`, `jq`, `python3`, and file read/write are available.

### Storage mode

- **Local only** — include `Local only` in the prompt (or rely on default local-only behavior).
- **Artifactory** — include `Save to Artifactory` for remote storage and historical comparison.

---

## Sample prompts

```
Generate a weekly CISO report.
Generate a monthly CISO report. Local only.
Generate a CISO security dashboard for March 2026.
Generate a weekly CISO report for solenglatest. Save to Artifactory.
Generate a weekly CISO report. Local only. Save local artifacts under /Users/me/security-reports.
```

---

## Default runtime behavior

When the prompt omits server, path, or storage mode:

| Setting | Default |
|---------|---------|
| **Server** | Single configured server → auto; multiple → ask |
| **Local root** | Prompt path → `CISO_LOCAL_ROOT` → one-time bootstrap prompt |
| **Pre-run** | Echo resolved server, output root, storage mode |
| **Artifactory** | Local-only unless prompt requests Artifactory; create repo if missing; on `403` continue local-only |

---

## Local artifact storage

Every run writes a deterministic bundle under your local root.

### Stable root for trends

If you run from different directories, prior snapshots may not be found and period-over-period comparison stays empty. The runtime can bootstrap this once interactively, or you can pin a fixed root yourself:

```bash
echo 'export CISO_LOCAL_ROOT=~/ciso-reports' >> ~/.zprofile
echo 'export CISO_LOCAL_ROOT=~/ciso-reports' >> ~/.zshrc
```

### Directory layout

```text
<LOCAL_ROOT>/
└── <instance-slug>/
    └── <report-type>/
        └── <YYYY-MM-DD>/
            ├── report.html
            ├── data.json          # optional; default on
            ├── snapshot.json
            └── run-meta.json
```

### Controls

| Variable / behavior | Effect |
|---------------------|--------|
| `CISO_SAVE_DATA_JSON` | `true` / `false` (default `true`) |
| `run-meta.json` | Includes `token_usage` from `CISO_TOTAL_TOKENS` or `/tmp/ciso-token-usage.json` |
| Same-day rerun | Stored under `rerun-HHMMSS/` — never overwrites |

```text
<LOCAL_ROOT>/<instance-slug>/<report-type>/<YYYY-MM-DD>/rerun-HHMMSS/
```

Checked-in examples live under `samples/`. Generated artifacts are gitignored.

---

## Artifactory storage (optional)

```
ciso-reports-local/
├── solenglatest/
│   ├── weekly/2026-04-24/snapshot.json, report.html
│   ├── monthly/2026-04/snapshot.json, report.html
│   └── manifest.json
└── LiquidJedi/
    └── weekly/...
```

---

## Related docs

- [Installation](INSTALL.md)
- [Architecture](ARCHITECTURE.md) — execution contract and data flow
- [CISO user manual](ciso-user-manual.md) — interpretation and tuning
