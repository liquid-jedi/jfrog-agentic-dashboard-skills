# Changelog

All notable changes to the `jfrog-ciso-report` skill. See [README.md](README.md) for
current usage and [docs/INSTALL.md](docs/INSTALL.md) for version-pinned install commands.

## Unreleased

*Guardrails*
- **Scoped to the CISO skill, which is all they were ever meant to cover** — the hooks treated any command containing `jf rt` or `jf xr` as a report workflow, so the whole JFrog CLI was policed in every session: unrelated platform-skill queries, MCP-equivalent calls and ad-hoc admin work all hit CISO rules. They now engage only for commands naming CISO artifacts, plus anything issued while a run is in flight, which the runner signals with a `/tmp/ciso-report-run.active` marker that expires after four hours so a crashed run cannot arm them indefinitely
- **Read-only AQL is allowed** — `POST /api/search/aql` is a search that happens to use POST, and was being refused as a mutation alongside the already-allowed Xray violations POST

*Curation active users*
- **Allowed-only user count** — `curation.unique_users_approved` counts identities with at least one allowed request, so users blocked on every attempt no longer read as package consumers. The dashboard surfaces it only when it differs from `unique_users`, which is the case worth reading. Tests `approved + passed` rather than `approved` alone, since an instance reporting only `passed` would otherwise report no active users

*Documentation and repository*
- **Interpreting the report** — the interpretation material was ~60 lines buried at the end of a 515-line operator manual, mixed in with permissions and agent-compliance detail. It is now [its own guide](docs/INTERPRETING-THE-REPORT.md) aimed at whoever reads the finished report, ordered to match the dashboard, and extended to cover the v4 panels the old section never described
- **Project site** — [GitHub Pages](https://liquid-jedi.github.io/jfrog-agentic-dashboard-skills/) serves the example dashboards rendered. GitHub shows an HTML file from the repository view as source, so the example `report.html` links were effectively unreadable; the examples moved to `docs/examples/` so a single copy is both browsable and published
- **Blueprint retired** — the persona scaffolder (`Dashboard-blueprint-skills/` and `packages/apm/jfrog-dashboard-blueprint`) is removed along with its documentation. Existing installs that pin a tag up to `v4.2.0` are unaffected
- **Install paths and platforms surfaced earlier** — `INSTALL.md` presented a two-row "which install should you choose?" table while documenting four paths, so the offline zip and local-clone options sat below the table meant to enumerate them; all four are now listed and linked. Platform support moved from the bottom of the document to the prerequisites, since a Windows reader previously got through the whole install before learning the runner needs WSL2, and it now covers where to install tooling and why the WSL2 browser has to be a Linux one
- **The right release asset is named** — GitHub attaches "Source code" archives to every release automatically, and nothing distinguished them from the skill bundle. The docs, the site and the v4.2.0 release notes now name `jfrog-ciso-report-v4.2.0.zip` and say why the 3.6 MB source archive is not installable
- **Reserved schema flagged at the source** — the `methodology` block is read by no template, and the warning about that lived only in the user manual. It now sits on the module itself in `report-data-collection.md` and in `report-schema.md`, where someone would actually hit it

## v4.2.0 (August 2026)

*Sidebar navigation*
- **Last section could never be selected** — the scroll indicator marked a section active once its heading rose past a line 120px below the viewport top, which the final section can never reach: at maximum scroll its heading still sits several hundred pixels lower. "Threat Velocity & Trend" therefore stayed unhighlighted no matter how far you scrolled, and clicking it looked broken — the jump did work, but the scroll handler immediately reset the highlight to Recommendations. The indicator now falls back to the last visible section once the page is scrolled to the end, and re-syncs on window resize

*Active-user export*
- **Users are numbered** — `curation-user-package-activity.csv` leads with a `rank` column ordered by request volume, so the last row's rank doubles as the active user count

*Examples*
- **Rebuilt against the current template** — the shipped examples were rendered before v4.1.0 and still carried the pre-v4.1.0 cross-product CSV export, so they misrepresented what a run produces. Both are re-rendered from their existing data through the current template; the underlying report data is unchanged

## v4.1.0 (August 2026)

*Active-user export, rebuilt*
- **One row per user** — `curation-user-package-activity.csv` was a user x package cross-product that repeated each user's totals on every package row; a 10-user week produced 3,356 rows. It is now one row per user, with the package detail kept inline as a ranked `top_packages` summary
- **New signal columns** — `block_rate_pct` surfaces users whose requests are mostly being denied regardless of their volume, which raw request counts hide; `distinct_packages` and `ecosystems` give consumption breadth
- **In-dashboard export fixed** — the "Download full CSV" fallback built its rows from a payload the runner deliberately empties, so it produced a header-only file. It now builds from the embedded top users and matches the on-disk column layout

*Windows*
- **PDF renderer** — added Windows Chrome, Chromium and Edge install locations, fixed `CISO_CHROME_BIN` so backslash paths are recognised, and switched to `pathToFileURL()` so a drive path no longer produces a malformed `file://C:\...` URL. macOS and Linux output is unchanged
- **Accurate platform docs** — [Troubleshooting](docs/TROUBLESHOOTING.md#compatibility) is now the single compatibility reference: WSL2 for Windows, Git Bash marked untested, and the two facts that actually decide success — PDF export cannot be skipped and is checked before collection, and WSL2 needs a browser installed inside it

*Docs*
- **Dead links removed** — the user manual linked to two files that are gitignored, so they 404'd for everyone reading it on GitHub
- **Stale platform claims dropped** — guidance about BSD versus GNU `date` and `sed -i` no longer applies; the runner delegates date arithmetic to `python3` and shells out to neither

## v4.0.1 (August 2026)

*Fixes on top of v4.0.0 — upgrade if you installed that release*
- **Claude guardrail** — both `.claude/settings.json` and the hook script had been written twice. The duplicated settings made the file invalid JSON so Claude Code never registered the hook, and the duplicated script block emitted two conflicting decisions per invocation. Both now contain a single copy, and all four agent hooks stopped treating `git rm` as a destructive delete
- **Template weight** — removed 55 unused `@font-face` subsets (Cyrillic, Greek, Hebrew, Vietnamese, symbols) that the report never renders, cutting `dashboard.html` from 1.8MB to 724KB
- **Packaging integrity** — `sync-apm-packages.sh` now asserts version parity between the canonical `SKILL.md` and `apm.yml` before syncing, and uses `rsync` with exclusions so `.DS_Store` and other OS cruft cannot leak into the shipped package
- **Docs** — the user manual pointed at `#v2.5.0`, two majors behind; PDF prerequisites and failure modes are now covered in [Troubleshooting](docs/TROUBLESHOOTING.md), including Windows support via WSL or Git Bash
- **Examples** — the monthly example is now complete, so its in-dashboard PDF and CSV links resolve

## v4.0.0 (July 2026)

*Two-audience PDF export*
- **Executive and full PDFs** — every run renders `executive-report.pdf`, a concise board-shareable summary, and optionally `full-report.pdf` for internal review; controlled by `CISO_PDF_MODE`
- **New print templates** — `dashboard-pdf.html` and `dashboard-pdf-full.html` rendered by `bin/generate-ciso-pdf.js`, using Puppeteer or an already-installed Chrome/Chromium/Edge (nothing downloaded mid-run)
- **In-dashboard export links** — the HTML report links directly to whichever PDFs the run produced

*Clearer metrics*
- **Occurrences vs unique issues** — "Critical instances" and "Violation hits" are now "Critical occurrences" and "Total violation occurrences", with a unique-CVE count reported alongside so volume is no longer mistaken for distinct findings
- **Honest empty states** — optional columns (Environment, Playbook, Exploit, Business Service, Criticality) are hidden when the APIs return no data, instead of showing walls of "unknown"
- **Renamed panels** — "Curation policy effectiveness" is now "Blocks by Curation policy", reflecting that it measures block counts rather than effectiveness; watch coverage only renders when watch-to-repo mapping is meaningfully exposed
- **Coverage wording fix** — remote repos whose package type Curation supports but which are not connected are no longer mislabelled as a "Supported gap"

*Visual refresh*
- **Threat velocity trend cards** — movement is shown with sparklines and directional indicators rather than bare deltas
- **Distinct severity colors** with clear separation across the distribution bar
- **Consistent widget styling** — recommended actions and PDF export controls now match the card system used across the rest of the page
- **Package type icons** and a decluttered sidebar with redundant run metadata removed

*Scale and correctness*
- **Active users at scale** — the Curation tab shows the top 20 active users with a total count; the complete export lands in `curation-user-package-activity.csv` next to the report, so instances with thousands of users stay responsive
- **Month-to-date support** — "this month" now reports the current month through today rather than projecting to a future end date; "monthly" reports the last *completed* calendar month
- **Faster runs** — collection and enrichment reworked after report times regressed past ten minutes

*Operations*
- **Agent guardrails** — project-level hooks for Cursor, Claude Code, Codex, and Antigravity block destructive JFrog HTTP methods, require explicit opt-in before publishing reports, and keep cleanup scoped to report artifacts and `/tmp/ciso-*`
- **Boost filters** — `.boost/filters.toml` trims noisy runner and JFrog CLI output
- **Token metadata** — `run-meta.json` records best-effort agent and token usage, marked `unavailable` when no source exists
- **Offline distribution** — the whole APM package ships as a zip for restricted networks, with agent-support files bundled under `extras/agent-support/`

## v3.0.0 (June 2026)
- **Release alignment** — skill frontmatter, APM package metadata, and plugin metadata now publish the CISO report skill as version 3.0.0
- **Versioned install guidance** — install examples now default to `#v3.0.0`, with explicit fallback instructions for teams that still need `#v2.3.0`
- **Git tag continuity** — the repository keeps older tagged installs available, so operators can pin either release as needed

## v2.6.0 (June 2026)
- **Independent posture signals** — critical/high finding movement, violation volume, and coverage gap are shown separately; no composite risk weighting is applied
- **Executive insight panels** — SLA risk backlog, remediation readiness, highest-impact fixes, new critical introductions, watch blind spots, blast radius, gate coverage gaps, enforcement opportunity, and malicious package defense
- **4-tab dashboard** — Overview, Curation, Xray, Recommendations; policy and coverage evidence is folded into the operational tabs where it drives action
- **Data-driven recommendations** — P1/P2/P3 generated from live data after enrichment, including executive insight fields where available
- **Period-over-period comparison** — runner scans prior snapshots and computes curation/violation deltas automatically
- **Show all / fewer toggle** — fixed on long tables in Curation and Xray tabs

## v2.3.0 and earlier
- Installable from the repository tag `v2.3.0`
- Instance-aware filenames and safe same-day reruns (`rerun-HHMMSS/`)
- Structured local artifacts: `report.html`, `snapshot.json`, `run-meta.json`
- Stable local-root bootstrap on first run (or set `CISO_LOCAL_ROOT` up front)
- Severity panel concentration metrics
