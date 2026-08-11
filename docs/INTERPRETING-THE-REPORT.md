# Interpreting the report

This guide is for the person **reading** a CISO report — presenting it to a
security leader, or acting on it. It walks the dashboard in the order the report
itself is laid out, so you can read with the report open beside you.

If you are the person **running** the report, see the
[CISO user manual](ciso-user-manual.md) for permissions, runtime behaviour and
tuning.

---

## Three things to know before you start

**There is no single risk score.** The report deliberately refuses to blend
signals into one number, because a composite score hides which lever to pull. You
get independent measures and you read them together.

**Occurrences are not unique issues.** Wherever the report says *occurrences*, it
is counting instances — the same CVE in forty artifacts is forty occurrences.
Unique issue counts are reported alongside so you can tell "one bad dependency,
widely used" from "forty separate problems". The first is one upgrade; the second
is a programme of work.

**Prevention and exposure are separate stories.** Curation is the gate at the
front door — what was stopped on the way in. Xray is what already lives inside
your repositories. A clean gate says nothing about your existing inventory, and
that is usually the most important sentence in the whole report.

---

## Executive Summary

The briefing strip holds the Xray posture headline (critical occurrences,
total occurrences, indexing gap). The Overview KPI row then focuses on
gate and adoption decisions:

| KPI | What it means | What to watch |
|-----|---------------|---------------|
| **Blocked at gate** | Requests Curation denied by policy, and what share of all requests that is | A rising block count is usually prevention working, not a problem |
| **Without inspection** | Requests that reached the client without policy evaluation | Any non-trivial number here is a real gap — see [Curation Activity](#curation-activity) |
| **Remotes gated** | Supported remotes connected to Curation | Coverage, not risk. Low coverage means unknown risk at the gate |
| **Active Curation users** | Distinct requester identities this period, with prior-period delta when available | Adoption trend, and usage against a customer-supplied planning baseline when one is configured. This is observed activity, not a license count |
| **Pending waivers** | Open waiver workflow backlog | Aging backlog means risk accepted without a decision |

Below the strip, insight cards summarise the findings that most often drive a
decision: how long critical findings have been open past SLA, how much of your
exposure actually has a fix available, which repositories have no watch covering
them, and which supported ecosystems are not behind the gate.

**Reading it out loud.** The honest one-sentence summary is usually of the shape:
"the gate stopped *N* risky packages this period, while *M* violation occurrences
already live inside our repositories, and *X%* of repositories are not indexed at
all." Prevention, exposure, and blind spot — in that order.

---

## Curation Activity

What the supply-chain gate did during the period.

- **Block rate** is blocked divided by total evaluated. Read it next to volume: a
  2% block rate on 20,000 requests is a very different conversation from 2% on 40.
- **High blocked volume is ambiguous on its own.** It can mean stronger policy,
  higher incoming threat pressure, or a single noisy dependency being retried in
  CI. The *Why packages were blocked* and *Top blocked packages* panels are what
  disambiguate it.
- **Gate coverage by supported ecosystem** is one gap-first table: of the remotes
  Curation *could* protect, how many are connected and where the remaining gap
  sits. Unconnected remotes are a silent bypass — packages flow through them
  without evaluation.
- **Remote repositories not protected by Curation** lists every ungated remote,
  split into supported-but-not-enabled (configuration wins) and unsupported
  ecosystems (product coverage, not a missed toggle).
- **Waiver governance** shows pending/approved/rejected counts and pending-age
  buckets. Oldest pending days is the decision-latency signal.
- The **Curation Audit** link opens the live trail for blocked downloads; the
  report no longer keeps a separate Audit Events section that only duplicated
  that CTA.

A package already in a remote repository cache can be served without a fresh
policy evaluation, depending on configuration. That is what **Without inspection**
counts. *Cached-package enforcement* shows per-policy coverage and the global
setting where the API exposes it — when it reports "not exposed by collected API",
the setting exists but is not readable, so treat it as unknown rather than off.

---

## Policy Inventory

What is actually enforced, as opposed to what exists.

The distinction that matters is **block mode versus dry-run**. A dry-run policy
evaluates and logs but does not stop anything. *Policies still in dry-run* is
therefore a list of protection you have already designed and are not yet getting
— usually the highest-value, lowest-effort change available.

*Protection by policy*, *Recommended policy baseline*, and *Curation policies by
risk category* show outcomes and gaps against a sensible default, so you can see
which categories are unpoliced rather than just counting policies.

---

## Active Users

Who is pulling packages, ranked by request volume, with the full list exported to
`curation-user-package-activity.csv` beside the report.

Sort the CSV by **`block_rate_pct`**, not by request count. The heaviest requester
is usually a CI service account behaving normally. A low-volume user with a high
block rate is the more interesting signal — either they are reaching for risky
dependencies, or they are fighting a policy that needs review. `curated_repos`
tells you which remotes they pulled through, which is where a spike gets traced
back to a team.

The `rank` column is ordered by volume, so the last row's rank is also your active
user count for the period.

If the report was generated with package detail (the default), two more columns
add breadth: `distinct_packages` and `ecosystems`, which separate "one build
pulling the same dependency repeatedly" from genuinely broad consumption. A
second table then lists every user, repository and package. Reports generated in
brief mode stop after `curated_repos` and say so in the file header; the user
list itself is complete either way.

---

## Xray Posture

What already exists inside the repositories.

**Severity distribution** — the mix of critical, high, medium and low:

- **Critical** — exploit likely, or a high-impact compromise path.
- **High** — serious weakness needing near-term remediation.
- **Medium** — meaningful exposure, lower immediate blast radius.
- **Low** — limited immediate impact, suited to batched remediation.

**Posture signals** are three independent measures, shown separately and never
combined:

| Signal | Meaning |
|--------|---------|
| `severity_mix` | 0–100 severity-weighted mix of current violations |
| `violation_volume` | Raw violation count |
| `coverage_gap` | Share of repositories Xray has not indexed |

The interpretation rules that matter:

- Rising `severity_mix` or `violation_volume` is bad — watch the trend, not the
  snapshot.
- A high `coverage_gap` means exposure may be going undetected. This is invisible
  risk, not absent risk, and it is the one signal where a good-looking number can
  be the most dangerous.
- **The signals move in tension, and this trips people up.** Indexing more
  repositories shrinks `coverage_gap` and *raises* `severity_mix` and
  `violation_volume`, because you are surfacing violations that were always there
  but unseen. Posture improved; two of three numbers got worse. Say this out loud
  before someone else reads it as a regression.

*SLA risk backlog* ages findings against your remediation targets. *Remediation
readiness* and *Highest-impact fixes* answer the question executives actually ask
— how much of this can we fix now — by separating findings with an available fix
from those without. *License compliance* and *Operational risk* cover
policy-backed licence exposure and stale or end-of-life components.

---

## Critical Issues

The list you work from, not just count.

Each row carries the issue ID, how many occurrences it accounts for, how many
repositories and artifacts it touches, how long it has been open, and whether a
fix version exists. Optional columns — exploit status, affected environments,
playbook links — appear only when the APIs actually return them, so an absent
column means "not available", not "none".

*New critical introductions* is the leading indicator: it separates newly arrived
criticals from long-standing ones. Rising new introductions while the total holds
steady means you are remediating and re-acquiring at the same rate.

*Blast radius* and *Repositories with the most exposure* re-frame the same findings
by reach, which is how you decide what to fix first when everything is critical.

---

## Watches & Effectiveness

Whether your detection is actually pointed at your repositories.

**Watch blind spots** is the one to read first. A repository with no watch
covering it generates no violations — which looks identical to a clean repository
in every other number in this report. Blind spots are why `coverage_gap` deserves
the weight it gets.

*Watch-to-repository coverage* and *Watch & policy hits* show where detection is
concentrated, including each watch/policy share of events. Heavy triggering on
one watch alongside broad blind spots usually means policy was tuned for a subset
of the estate and never extended.

*Scan data retention* reports indexed repositories on the default retention
window versus custom or below-default settings. Retention expiry removes
historical scan data; it is not a mandatory 90-day re-index cycle.

*Exploitability context* is explicit: when the violations response did not carry
exploitability/applicability data, the report says so instead of hiding the
column or treating unknown as not exploitable.

---

## Recommended Actions

P1/P2/P3 actions generated from this period's data, each with an impact
statement, a next step, an effort rating, a suggested owner and a due date.

These are derived, not editorial — they follow from the numbers above, which means
you can trace any action back to the panel that produced it. Priority reflects
impact against effort, so P1 is not simply "most critical"; a low-effort
configuration change that closes a whole ecosystem bypass can outrank a large
remediation programme.

---

## Trend & Comparison

One section holds both prior-period deltas and multi-period velocity.

- **Compared with previous report** — current vs previous for critical
  occurrences, total violations, indexing gap, gate blocks, and active users.
- **Threat velocity** — sparklines across validated prior runs, including
  normalized signals such as violations per indexed repository, Curation block
  rate, and active users.

Trend needs history. With one report there is nothing to compare and the section
says so rather than inventing a baseline. Comparisons appear once prior snapshots
exist, and the sparklines fill in as runs accumulate.

Read velocity as the answer to "are we getting better?" — the level answers "how
bad is it?", and those are different questions with frequently different answers.

---

## The other outputs

- **`executive-report.pdf`** — the shareable version. Deliberately narrower than
  the HTML: headline posture, the decisions, and the trend, without the long
  operational tables. This is the one you forward.
- **`full-report.pdf`** — the same run with the detail retained, for internal
  review. Produced only under `CISO_PDF_MODE=full` or `both`.
- **`curation-user-package-activity.csv`** — every active Curation user, one row
  each. The dashboard shows the top 20; this is the complete list.

Comparing the HTML dashboard against the executive PDF is the fastest way to see
what the executive mode intentionally leaves out.

---

## Common misreadings

| Reading | Why it is wrong |
|---------|-----------------|
| "Blocks went up, we got worse" | Blocks are prevention succeeding. Look at what was blocked and why |
| "Zero violations in that repo, it is clean" | Check whether a watch covers it. No watch means no findings by construction |
| "500 critical issues" | Usually 500 *occurrences*. Read the unique count beside it before escalating |
| "Coverage improved but severity rose, so we regressed" | Expected. Indexing more repositories surfaces pre-existing violations |
| "The gate is clean, so we are fine" | The gate only governs new arrivals. Existing inventory is the Xray sections |
| "No fix available on most findings" | Check whether the column is populated at all — absent data is not the same as no fix |

---

## Related docs

- [CISO user manual](ciso-user-manual.md) — running and tuning the skill
- [Installation](INSTALL.md)
- [Troubleshooting](TROUBLESHOOTING.md)
