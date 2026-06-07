# Persona Interview

Ask the user the following 7 questions in a single message. Wait for
answers. If the user gives partial answers, follow up only on missing
items. Do not guess.

---

**1. Who is the persona and audience?**
- Persona name (e.g. CTO, Engineering Head, Compliance Officer, DevOps Lead)
- Audience level: executive / manager / individual contributor
- Will this report be shared externally (board, auditors, customers)?

**2. What are the top 5 questions this report must answer every cycle?**
Examples:
- "Are we blocking malicious packages effectively?"
- "Which teams have the highest open security debt?"
- "Where is delivery risk concentrated?"
- "Is our supply chain trust improving over time?"

**3. What decisions will this report drive?**
Examples:
- Budget allocation
- Hiring and team load balancing
- Policy tightening or loosening
- Release go/no-go
- Executive escalation

**4. What data sources are in scope?**
- JFrog products: Xray, Curation, Artifactory, Distribution, Evidence, etc.
- External (optional): Jira, GitHub, SonarQube, CI/CD telemetry
- Note any data that is NOT available so we can document gaps.

**5. What is the reporting cadence?**
- Daily / Weekly / Monthly / Quarterly / On-demand
- Should the report support period-over-period comparison?

**6. What output formats are required?**
- Self-contained HTML dashboard (default)
- Email summary
- Slack/Teams post
- PDF for archival
- JSON export for downstream tools

**7. What trust and governance requirements apply?**
- Source attribution per metric required?
- Human approval before publishing?
- Audit log of who generated the report?
- Redaction or masking rules?
- Retention policy for stored reports?

---

## Optional follow-up questions (only if needed)

- Preferred color theme / branding constraints
- Existing dashboards or reports this should replace or complement
- Top 3 KPIs the persona looks at first
- Known noise or false positives to suppress
- Specific repos, teams, or projects to focus on first
