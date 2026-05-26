# Troubleshooting

| Problem | Fix |
|---------|-----|
| Skill not detected by agent | Reinstall from GitHub: `npx skills add git@github.com:liquid-jedi/jfrog-agentic-dashboard-skills.git -g --skill jfrog-ciso-report` — see [Installation](INSTALL.md) |
| Agent generates its own HTML | Skill not registered or wrong skill active — verify with `npx skills list` |
| Curation shows "Not configured" | Enable curation on the JPD; ensure token has audit API permissions |
| CLI tools not found | Install `jf`, `jq`, `python3` and ensure they are on PATH |
| API calls return 403 | Token needs appropriate read access (security reader / platform read) |
| Report missing sections | Confirm reference files exist under the installed skill’s `references/` folder |
| Headless run stops for input | Include server name and `Local only` or `Save to Artifactory` in the prompt |
| Report path unclear | Check console for: `Local artifacts saved under: ...` |
| Trends always empty | Set a fixed `CISO_LOCAL_ROOT` — see [Running](RUNNING.md#stable-root-for-trends) |
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
- [Running reports](RUNNING.md)
- [CISO user manual](ciso-user-manual.md)
