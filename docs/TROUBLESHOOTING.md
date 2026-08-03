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

---

## Compatibility

This table is the canonical platform reference; other docs link here.

| | Supported |
|---|:---:|
| JFrog SaaS | Yes |
| JFrog Self-Hosted | Yes |
| JFrog Xray | Required |
| JFrog Curation | Optional |
| macOS | Yes — primary tested platform |
| Linux | Yes |
| Windows via WSL2 | Yes — see the note below about the browser |
| Windows via Git Bash | Untested; use WSL2 if you have the choice |
| Windows native (CMD/PowerShell) | No — the runner is a bash script |
| Chrome / Chromium / Edge | Required — see below |

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
