# Changelog

All notable changes to the `jfrog-ciso-report` skill. See [README.md](README.md) for
current usage and [docs/INSTALL.md](docs/INSTALL.md) for version-pinned install commands.

## v4.3.0 (August 2026)

*Curation audit windows*
- **Any range longer than 168 hours is chunked** — the Curation audit API rejects windows over seven days (`Maximum allowed duration is 168 hours`). Chunking previously ran for `monthly` only, so a custom or month-to-date window such as Aug 1–11 was refused and silently rendered as zero events and zero active users. Every report type now chunks at six-day windows, records the mode in diagnostics, and fails the run if a window comes back with an `errors` array instead of data
*Executive presentation*
- **Executive Summary rebuilt as the hero** — posture verdict, five decision tiles, and a prevented-vs-present flow replace the earlier two-column layout that buried the story
- **Sidebar PDF actions no longer overlap** — Executive PDF and Print current view sit in a stacked card with consistent spacing
- **Threat velocity table is full width** — Active Users is no longer clipped beside the prior-period comparison panel
- **Scan data retention removed from the report** — the panel and the default per-repository fan-out are gone; set `CISO_RETENTION_HEALTH=1` only when collecting that data for a separate workstream
*Active-user export*
- **Masked CSV for sharing** — `CISO_CURATION_USER_MASKED=1` writes a companion `*-masked.csv` with randomised names and emails
- **CSV metadata is a key/value block** — the export no longer opens with `#` comment lines that break spreadsheet import
*Metric correctness*
- **Xray pagination now uses page numbers** — `/api/v1/violations` defines `pagination.offset` as a one-based page number. The collector treated it as a row offset (`0`, `500`, `1000`), so large runs kept the API-reported total but built every severity, type, repository, and critical-issue breakdown from only the first 500 rows. It now drains pages `1..N`, records collection completeness, and fails before render unless the API total, fetched rows, severity sum, and type sum agree
- **One Curation coverage denominator** — supported-remotes, ecosystem gaps, and pass-through inventory now all derive support from Curation policy `supported_pkg_types`. The runner rejects a report unless the ecosystem gap sum and supported pass-through count equal `supported_not_connected`; unsupported remotes remain visible as a separate inventory count

- **Snapshots carry a collector version** — the first run after the pagination fix would otherwise compare a complete violation count against a prior snapshot built from one page, reporting the fix as a 27,000-violation increase in posture. Snapshots now record `collector_version`, and violation deltas, sparklines, and trend prose are withheld with a stated reason when the baseline predates the fix. Curation and coverage history, which the bug never touched, keeps trending

- **JAS applicability now parsed from violations** — critical rows already carry `applicability` / `applicability_details` from Contextual Analysis; the collector was only reading string `exploit_status` fields, so every issue showed NOT CAPTURED. It now rolls up applicable / not applicable / undetermined and only shows the Critical Issues column when data exists
- **New critical introductions gated like violation deltas** — withheld when the prior snapshot predates `collector_version` 2, with the trend context living under Trend & Comparison

*CISO decision signals*
- **Retention health** — read-only repository configuration collection reports indexed repositories on the 90-day default, custom retention, below-default settings, and unknowns. The report explicitly distinguishes retention expiry from a mandatory 90-day re-index cycle
- **Active-user adoption context** — period-based active users now trend through snapshots. Customers can optionally supply `CISO_CURATION_USER_BASELINE` to compare observed activity against their own planning number and see the headroom left. The report states plainly that this is an observed activity count, never a license count or contractual position
- **Waiver age and exploitability availability** — pending waivers are bucketed by age and the oldest backlog is surfaced; critical exploitability is always shown as captured or unavailable instead of disappearing silently
- **Normalized trend context** — trend history adds violations per indexed repository, Curation block rate, coverage gap, and active users alongside raw totals

*Report consolidation*
- **Repeated panels merged without dropping detail** — ecosystem coverage is one gap-first table, Curation policy outcomes use the richer protection table, Xray watch/policy hits carry trigger share in one table, the audit link sits with Curation activity, and prior-period comparison now lives beside multi-period trend
- **Pass-through labels reconciled** — the repository inventory states total ungated remotes, supported-but-not-enabled remotes, and unsupported ecosystems separately

*Terminology*
- **One name for the user count** — the same `curation.unique_users` figure was labelled three ways in one report: "Unique users" in the sidebar, "Active developers" on the KPI, and "Active users" on the panel below it, which read as three different measurements. Everything now says **Active users**, matching the executive PDF, the CSV export and the metric's own definition. The full PDF's user table header and its "additional developers" footnote follow, and "developer behavior change" on the upgrade-after-block panel becomes "user behavior change" — the report describes requester identities, which are not always developers

*Guardrails*
- **`/tmp` is no longer policed** — deletes were restricted to `/tmp/ciso-*`, so removing a scratch render or a test fixture from `/tmp` was refused mid-task. Everything under `/tmp` is scratch space and is now unrestricted, apart from the directory itself; `/private/tmp` is treated identically because on macOS it is the same place. Paths outside `/tmp` are unchanged, and `..` is resolved before the check so `/tmp/../<anything>` is still caught. Verified across all four agent hooks against 16 commands each
- **Scoped to the CISO skill, which is all they were ever meant to cover** — the hooks treated any command containing `jf rt` or `jf xr` as a report workflow, so the whole JFrog CLI was policed in every session: unrelated platform-skill queries, MCP-equivalent calls and ad-hoc admin work all hit CISO rules. They now engage only for commands naming CISO artifacts, plus anything issued while a run is in flight, which the runner signals with a `/tmp/ciso-report-run.active` marker that expires after four hours so a crashed run cannot arm them indefinitely
- **Read-only AQL is allowed** — `POST /api/search/aql` is a search that happens to use POST, and was being refused as a mutation alongside the already-allowed Xray violations POST

*Performance on large instances*
- **Audit pages are fetched concurrently** — collection paged the Curation audit API one request at a time, measured at ~500 events/sec, so an instance holding a million audit events spent over half an hour in that loop alone and ten million ran for hours. Four pages now go out at once, verified against a live instance to return the same 20,870 rows in the same order as the sequential drain, 3.2x faster. Tunable with `CISO_AUDIT_CONCURRENCY` (default `4`, clamped `1`–`8`); set it to `1` to restore the old one-at-a-time behaviour if a JPD rate-limits the endpoint
- **The agent-side collector was serial despite looking otherwise** — `report-data-collection.md` built waves of offsets and then fetched each one in a `for` loop, so `CISO_CURATION_CONCURRENCY` had no effect at all. It now uses a thread pool, and a wave that hits 403 or 404 is refused whole rather than committing the pages that happened to succeed
- **Scale documented** — [TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md#large-instances) records what actually drives runtime. User count is close to free: 10,000 users across a million events aggregate and export in under 5 seconds. Event volume is the cost, and memory is the harder ceiling at roughly 0.5 KB per audit row

*Curation active users*
- **Allowed-only user count** — `curation.unique_users_approved` counts identities with at least one allowed request, so users blocked on every attempt no longer read as package consumers. The dashboard surfaces it only when it differs from `unique_users`, which is the case worth reading. Tests `approved + passed` rather than `approved` alone, since an instance reporting only `passed` would otherwise report no active users
- **The export states what an Active User is** — `curation-user-package-activity.csv` opens with a commented definition of the metric, the reporting period and the user count. The number is routinely read as a licence count, and nothing in the file previously said what it counts: distinct requester identities as JFrog recorded them, offered as a yardstick for adoption and licence planning
- **Two tables instead of one** — the file now carries the per-user summary (table 1, every active user) followed by the underlying per-request detail (table 2), so the adoption question and the drill-down are both answerable from one attachment. Table 2 is capped at 50,000 rows and says so in its heading when the cap bites; table 1 is never capped
- **Curated repository named** — both tables report which curated remote served each request, which the export never carried, so a spike could not be traced to a repository without going back to the audit log. `distinct_packages` still counts packages: on live data one user's 318 packages arrived as 359 package/repo pairs, and counting pairs would have overstated their footprint by 13%
- **Comment lines are written unquoted** — routing them through the CSV writer would have quoted every line containing a comma, burying the definition inside a quoted field
- **A brief shape for large instances** — the per-package breakdown is the only part of the user export whose size is unbounded, and it is what puts a large instance at risk of exhausting memory. `brief` collects per-user counts and curated repositories and skips the package aggregation entirely; both shapes list every active user with identical counts, verified against a live instance. Curated repositories are kept in both, since a handful of repo names per user is bounded and it is the one field that says where the activity happened
- **The export tables are built from a per-user list, not the package cross-product** — table 1 previously derived its users from the package activity rows, which meant no packages implied no users. It now comes from `curation.user_summary`, so the user table is complete regardless of shape

*Prompt-driven output modes*
- **PDF and user-detail shape are chosen from the prompt** — both were environment variables only, so the shapes existed but nobody asked for them in the way the rest of the skill is driven. `executive pdf`, `full pdf`, `both pdfs`, `html only`, `brief users` and `with package detail` now resolve in Phase 0 alongside server and date range, and the resolved values are printed before collection starts
- **`CISO_PDF_MODE=none`** — every PDF consumer in the runner was already conditional, so HTML-only needed nothing but a case branch and a validation fix. The browser preflight is skipped in this mode, which is what makes the option worth having on WSL2 and bare CI images where installing a Linux browser is the whole difficulty
- **The volume question is asked before it costs anything** — a single request returns the period's exact event count in about three seconds and 1.1 KB, without downloading any events. Above 250,000 the skill reports the count and asks which shape you want; below it, it proceeds. User count cannot be known before collection, and it is not what drives the cost anyway

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
