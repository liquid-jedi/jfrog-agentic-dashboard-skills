# Priority-modules report prototype (M1–M5)

Interactive **sample** of the CISO report layout agreed in discovery — not the shipping template.

Open [`report.html`](report.html) in a browser.

## What’s demonstrated

| Piece | Behavior |
|-------|----------|
| **Presets** | Full, Prevention-first, Exposure-first, Executive, Coverage audit — left rail switches modules |
| **M1 Prevention** | Gate, malicious, dry-run, gaps; **active user counts always**; brief user table only in Full |
| **M2 Exposure** | Occurrences vs unique, SLA aging, fixability, top issues |
| **M3 Coverage** | Indexing, watches, policy enforcement, ecosystem connectivity; **retention health** callout (conceptual) |
| **M4 Actions** | Ranked P1/P2 from live signals |
| **M5 Trend** | Period comparison + velocity |
| **Out** | SBOM (deferred); AI/MCP/Skills (later) |

## Data source

Compacted metrics from `solenglatest` monthly run ending **2026-07-31** (`rerun-154018`). User rows in the brief table are illustrative placeholders for layout; the active-user count `17` is from the real run.

## Not production

- Does not replace `Dashboard-ciso-report-skills/references/dashboard.html`
- Retention panel is labeled conceptual until Indexed Resources retention is collected
- No PDF / CSV / injection runner wiring
