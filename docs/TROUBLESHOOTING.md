# Troubleshooting

| Problem | Fix |
|---------|-----|
| Skill not detected by agent | Reinstall with APM or the generic Skills command from [Installation](INSTALL.md), then verify the deployed skill exists |
| Agent generates its own HTML | Skill not registered or wrong skill active — verify with `npx skills list -g` |
| Curation shows "Not configured" | Enable curation on the JPD; ensure token has audit API permissions |
| CLI tools not found | Install `jf`, `jq`, `python3` and ensure they are on PATH |
| API calls return 403 | Token needs appropriate read access (security reader / platform read) |
| Report missing sections | Confirm reference files exist under the installed skill’s `references/` folder |
| Headless run stops for input | Include server name and `Local only` or `Save to Artifactory` in the prompt |
| Report path unclear | Check console for: `Local artifacts saved under: ...` |
| Trends always empty | Set a fixed `CISO_LOCAL_ROOT` or let the first run bootstrap it — see [Installation](INSTALL.md) |
| Precheck failures | Run `scripts/agentic-dashboard-prechecks.sh` and fix reported blockers |

---

## Compatibility

| | Supported |
|---|:---:|
| JFrog SaaS | Yes |
| JFrog Self-Hosted | Yes |
| JFrog Xray | Required |
| JFrog Curation | Optional |
| macOS | Yes |
| Linux | Yes (date command may need adjustment) |

---

## Related docs

- [Installation](INSTALL.md)
- [CISO user manual](ciso-user-manual.md)
