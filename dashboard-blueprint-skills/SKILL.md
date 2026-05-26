---
name: jfrog-dashboard-blueprint
description: >-
  Scaffold a new persona-specific JFrog dashboard/report skill from a guided
  interview. Use when the user asks to "create a new dashboard", "scaffold a
  report skill", "build a CTO/Eng/Compliance/DevOps dashboard pack", or
  "generate a starter blueprint for a custom report". This skill DOES NOT
  query JFrog APIs or generate a live report. It produces a new skill folder
  (SKILL.md, schema, data-collection mapping, HTML template, sample fixtures)
  that a persona-specific reporting skill can be built from.
metadata:
  role: workflow
  author: Avinash Giri
  version: 2.1.0
---

# JFrog Dashboard Blueprint Generator

## CRITICAL — READ THIS FIRST

You are NOT generating a live report. You are NOT calling JFrog APIs. You
are NOT producing HTML for a specific run. Your only job is to scaffold a
**new persona dashboard skill** by:

1. Running a short interview with the user.
2. Producing a new skill folder with the standard file layout.
3. Seeding each file from the templates in `references/`.
4. Replacing placeholders with the persona's answers.
5. Telling the user what to fill in next and how to register the skill.

If the user asks for an actual report run, hand off to the matching
persona skill (for example `jfrog-ciso-report`). Do NOT attempt to run a
report from this skill.

## When to use this skill

Use when the user wants a **starter blueprint** for a new dashboard pack:

- "Create a new dashboard for our CTO"
- "Scaffold an Engineering Head report"
- "Build a compliance pack"
- "I want a starter blueprint for a custom DevOps dashboard"
- "Generate a new persona skill"

Do NOT use for live report generation. Do NOT use for editing an existing
persona pack.

## Workflow

```
1. Run the persona interview (references/persona-interview.md)
2. Resolve output path (default: ./dashboard-report-skills-<persona-slug>)
3. Create the folder structure
4. Generate files from templates with placeholders substituted
5. Print a "next steps" summary for the user
```

## Step 1: Persona interview

Open `references/persona-interview.md` and ask the user the 7 core
questions in a single message. Wait for answers before continuing. Do not
guess answers. Do not skip questions. If the user gives partial answers,
ask only the missing items in a follow-up.

The answers MUST yield these variables:

| Variable | Source |
|----------|--------|
| `PERSONA_NAME` | Question 1 |
| `PERSONA_SLUG` | Lowercase, hyphenated form of `PERSONA_NAME` |
| `AUDIENCE` | Question 1 (exec / manager / IC) |
| `KEY_QUESTIONS[]` | Question 2 (up to 5) |
| `DECISIONS[]` | Question 3 |
| `DATA_SOURCES[]` | Question 4 |
| `CADENCE` | Question 5 (daily / weekly / monthly) |
| `OUTPUT_FORMATS[]` | Question 6 (html / email / slack / pdf) |
| `TRUST_REQS[]` | Question 7 (sources, approvals, audit) |

## Step 2: Resolve output path

Default: `./dashboard-report-skills-<PERSONA_SLUG>/`. Ask only if the
default conflicts with an existing folder. If conflict, offer:

1. Use a suffix (`-v2`)
2. Pick a different path
3. Abort

## Step 3: Create folder structure

```
dashboard-report-skills-<PERSONA_SLUG>/
├── SKILL.md
└── references/
    ├── report-schema.md
    ├── report-data-collection.md
    ├── dashboard.html
    └── sample-data.json
```

Use the templates in this skill's `references/` directory as the source
for each file. Substitute placeholders (see Step 4).

## Step 4: Placeholder substitution

Every template uses double-curly placeholders. Replace all of them. If a
value is missing, replace with `TODO: <description>` so the user knows
what to fill in.

| Placeholder | Replace with |
|-------------|--------------|
| `{{PERSONA_NAME}}` | e.g. "Engineering Head" |
| `{{PERSONA_SLUG}}` | e.g. "eng-head" |
| `{{AUDIENCE}}` | e.g. "engineering leadership" |
| `{{KEY_QUESTIONS}}` | Bullet list of the 5 questions |
| `{{DECISIONS}}` | Bullet list of decisions this report supports |
| `{{DATA_SOURCES}}` | Bullet list of JFrog products and any external sources |
| `{{CADENCE}}` | weekly / monthly / etc. |
| `{{OUTPUT_FORMATS}}` | html, email, etc. |
| `{{TRUST_REQS}}` | source attribution, approvals, audit log requirements |
| `{{GENERATED_DATE}}` | Today's ISO date |

## Step 5: Next-steps summary

After creating files, print a short message to the user with:

1. The folder path created.
2. A checklist of what to fill in:
   - Map each `KEY_QUESTION` to a schema section.
   - Implement API queries in `report-data-collection.md`.
   - Customize visuals in `dashboard.html`.
   - Add at least one golden fixture in `sample-data.json`.
3. How to register the skill globally:
   ```bash
   npx skills add ./dashboard-report-skills-<PERSONA_SLUG> -g -y
   ```
4. Reminder: keep the JSON-first contract. The agent must always produce
   JSON before injecting into the HTML template.

## Hard rules

- Do NOT call JFrog APIs from this skill.
- Do NOT write live data to the generated files.
- Do NOT skip the interview.
- Do NOT generate HTML or schema content that diverges from the templates
  in `references/`. Use them as the source of truth.
- Every generated `SKILL.md` MUST include the JSON-first execution
  contract (the template enforces this).
- Every generated `dashboard.html` MUST be self-rendering and consume a
  single `__DATA__` placeholder.
