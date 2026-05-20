# Blueprint Output Structure

This describes what the blueprint generator produces and the
responsibility of each file. Every persona pack follows this exact
structure so the agent ecosystem can reason about it consistently.

```
dashboard-report-skills-<PERSONA_SLUG>/
├── SKILL.md                       # Persona workflow + JSON-first contract
└── references/
    ├── report-schema.md           # JSON schema the agent must produce
    ├── report-data-collection.md  # API mapping per schema field
    ├── dashboard.html             # Self-rendering HTML template
    └── sample-data.json           # Golden fixture for evals + smoke render
```

## File responsibilities

| File | Owns |
|------|------|
| `SKILL.md` | Workflow orchestration, hard rules, runtime checkpoints, JSON-first contract |
| `report-schema.md` | The contract: every required field, type, semantics |
| `report-data-collection.md` | How to derive each schema field from JFrog APIs |
| `dashboard.html` | All presentation: layout, components, styling, rendering logic |
| `sample-data.json` | Golden DATA payload used for smoke tests and evals |

## Shared design rules (apply to every pack)

1. **JSON-first.** The agent must produce JSON before any rendering.
2. **Single placeholder.** `dashboard.html` consumes `__DATA__` (or
   the persona-specific equivalent) exactly once.
3. **No freeform HTML.** The agent never authors HTML at run time.
4. **Schema gates.** Required fields must be validated before injection.
5. **Methodology in DATA.** Severity, scoring, and risk-band definitions
   are configurable via a top-level `methodology` block in the JSON.
6. **Recommendations metadata.** Every recommendation carries `priority`
   and `score`; optional: `effort`, `owner`, `due_date`, `dependencies`.
7. **Source attribution (optional but recommended).** Each metric may
   carry `source`, `endpoint`, `timestamp`, `confidence`.
8. **Graceful degradation.** Missing optional fields render defaults,
   not errors.

## Why this structure

- Reusability: every pack swaps logic, not layout primitives.
- Testability: JSON-first lets us run offline evals.
- Portability: any skill-capable agent can run the pack.
- Governance: schema gates and methodology config are inspectable.
