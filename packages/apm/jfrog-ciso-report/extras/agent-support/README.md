# Optional Agent Support Files

These files are optional helpers for teams running the CISO report skill from an
agent-enabled IDE or CLI.

- `.boost/filters.toml` reduces noisy CISO report and JFrog CLI output.
- `.cursor/` contains the Cursor guardrail hook configuration and script.
- `.claude/` contains the Claude Code guardrail hook configuration and script.
- `.codex/` contains the Codex hook configuration and script.
- `.agents/` contains the Antigravity hook configuration and script.

Copy only the folder that matches the customer's agent runtime into the root of
the customer's report workspace. The CISO report skill itself can run without
these files as long as the runtime requirements in the package README are met.
