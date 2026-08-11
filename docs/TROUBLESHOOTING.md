# Troubleshooting

| Problem | Fix |
|---------|-----|
| Skill not detected by agent | Reinstall with APM or the generic Skills command from [Installation](INSTALL.md), then verify the deployed skill exists |
| Agent generates its own HTML | Skill not registered or wrong skill active — verify with `npx skills list -g` |
| Curation shows "Not configured" | Enable curation on the JPD; ensure token has audit API permissions |
| CLI tools not found | Install `jf`, `jq`, `python3`, `node` and ensure they are on PATH |
| API calls return 403 | Token needs appropriate read access (security reader / platform read) |
| Report missing sections | Confirm reference files exist under the installed skill’s `references/` folder |
| `No PDF browser found` | Install Google Chrome, Chromium or Edge, or install Puppeteer. If the browser is in a non-standard location, set `CISO_CHROME_BIN` to its executable |
| `CISO_PDF_MODE must be executive, full, or both` | PDF export cannot be skipped. Use one of those three values; any other value stops the run |
| `rendered PDF is missing or unexpectedly small` | The browser launched but produced no usable output — check it runs headless (`"$CISO_CHROME_BIN" --headless --version`) |
| `No harness detected` on install | You are installing into a folder with no agent markers. Add `--target claude,cursor,codex` or declare `targets:` in `apm.yml` |
| Headless run stops for input | Include server name and `Local only` or `Save to Artifactory` in the prompt |
| Report path unclear | Check console for: `Local artifacts saved under: ...` |
| Trends always empty | Set a fixed `CISO_LOCAL_ROOT` or let the first run bootstrap it — see [Installation](INSTALL.md) |
| Precheck failures | Run `scripts/agentic-dashboard-prechecks.sh` and fix reported blockers |
| Run takes far longer than 5 minutes | Almost always Curation audit volume, not user count. Check `pages_fetched` in `/tmp/ciso-curation-diagnostics.json`: each page is 2,000 events. See [Large instances](#large-instances) |
| Run is killed, or the machine swaps, during the curation transform | The per-user package breakdown outgrew available memory. Re-run with `brief users`. See [Large instances](#large-instances) |

---

## Large instances

Runtime scales with the number of **Curation audit events** in the window, not
with how many users you have. Ten thousand users aggregate in a few seconds; it
is fetching their events that costs time.

Collection pages the audit API 2,000 events at a time, fetching four pages
concurrently. Measured against a live instance that is roughly 2,000 events per
second, so:

| Events in window | Approximate audit collection time |
|------------------|-----------------------------------|
| 100,000 | under 1 minute |
| 500,000 | ~4 minutes |
| 1,000,000 | ~7 minutes |
| 10,000,000 | over an hour |

Monthly reports cover roughly four times the events of a weekly report over the
same instance, because they chunk the month into 6-day windows and fetch them all.

Tuning:

- `CISO_AUDIT_CONCURRENCY` (default `4`, clamped to `1`–`8`) sets how many audit
  pages are fetched at once. Raising it shortens collection on a large instance;
  lower it to `1` if your JPD rate-limits the audit API. Results are identical at
  any setting — only the elapsed time changes.
- `CISO_CURATION_CONCURRENCY` is the equivalent knob for the agent-driven
  collector in `report-data-collection.md`.

Memory is the other limit, and it comes from two places:

- **Raw audit rows**, held in memory before aggregation at roughly 0.5 KB per
  row — about 2 GB at one million events. Narrow the window and run weekly
  rather than monthly reports.
- **The per-user package breakdown**, which grows with distinct user-package
  pairs rather than with users. This is the part that has no ceiling: at the
  breadth measured on a live instance, 10,000 users need roughly 700 MB for this
  alone, against under 3 MB without it.

The second is avoidable. Ask for `brief users`, or set
`CISO_CURATION_USER_DETAIL=brief`, and the package aggregation is skipped
entirely. You still get every active user with their request, block and approval
counts and the curated repositories they pulled through — only the per-package
columns and the CSV's detail table are dropped. Above 250,000 events in the
window the skill reports the count and asks which you want.

---

## Compatibility

This table is the canonical platform reference; other docs link here.

| | Supported |
|---|:---:|
| JFrog SaaS | Yes |
| JFrog Self-Hosted | Yes |
| JFrog Xray | Required |
| JFrog Curation | Required — see below |
| macOS | Yes — primary tested platform |
| Linux | Yes |
| Windows via WSL2 | Yes — see the note below about the browser |
| Windows via Git Bash | Untested; use WSL2 if you have the choice |
| Windows native (CMD/PowerShell) | No — the runner is a bash script |
| Chrome / Chromium / Edge | Required — see below |

**Curation is not optional.** Every run finishes with a live collection proof
that fails when the instance has no Curation policies registered and no
package-gate audit activity in the last seven days. On an Xray-only instance the
report and PDFs are still written, but the runner exits non-zero at that gate, so
treat Xray plus Curation as the supported baseline.

**PDF export is not optional.** `CISO_PDF_MODE` accepts `executive`, `full`, or
`both`; there is no way to skip it. The runner probes for a browser *before* it
collects any data, so a missing browser aborts the whole run rather than
falling back to HTML only. Install Chrome, Chromium or Edge, or install
Puppeteer, or point `CISO_CHROME_BIN` at a browser executable.

**On WSL2, install a browser inside WSL** (for example
`sudo apt install chromium-browser`), or install Puppeteer. Pointing
`CISO_CHROME_BIN` at the Windows Chrome under `/mnt/c/...` launches it
successfully but it cannot write the PDF back to a Linux output path.

---

## Related docs

- [Installation](INSTALL.md)
- [CISO user manual](ciso-user-manual.md)
- [Interpreting the report](INTERPRETING-THE-REPORT.md)
