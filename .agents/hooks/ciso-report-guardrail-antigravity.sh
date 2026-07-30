#!/usr/bin/env bash
set -euo pipefail

HOOK_PAYLOAD="$(cat)" python3 - "$@" <<'PY'
import json
import os
import re
import shlex

try:
    payload = json.loads(os.environ.get("HOOK_PAYLOAD") or "{}")
except Exception:
    payload = {}

def dig(obj, *keys):
    cur = obj
    for key in keys:
        if not isinstance(cur, dict):
            return ""
        cur = cur.get(key)
    return cur if isinstance(cur, str) else ""

command = (
    payload.get("command")
    or dig(payload, "tool_input", "CommandLine")
    or dig(payload, "tool_input", "command")
    or dig(payload, "args", "CommandLine")
    or dig(payload, "args", "command")
    or dig(payload, "arguments", "CommandLine")
    or dig(payload, "arguments", "command")
    or ""
)

def allow():
    print(json.dumps({"decision": "allow", "allow_tool": True}))
    raise SystemExit(0)

def deny(reason):
    print(json.dumps({
        "decision": "deny",
        "allow_tool": False,
        "reason": reason,
        "deny_reason": reason,
    }))
    raise SystemExit(0)

if not command:
    allow()

lower = command.lower()
is_ciso_related = any(token in lower for token in (
    "generate-ciso-report.sh",
    "ciso-report",
    "ciso-reports",
    "/tmp/ciso-",
    "jf rt ",
    "jf xr ",
))

if not is_ciso_related:
    allow()

if re.search(r"\bjf\s+(rt|xr)\s+curl\b", lower):
    if re.search(r"(^|\s)-x\s*(delete|put|patch)\b|(^|\s)-x(delete|put|patch)\b", lower):
        deny("Blocked destructive JFrog curl method during CISO report workflow.")
    post = re.search(r"(^|\s)-x\s*post\b|(^|\s)-xpost\b", lower)
    if post and "/api/v1/violations" not in lower:
        deny("Blocked unexpected JFrog POST. Only Xray /api/v1/violations is allowed as a read-style query.")

if re.search(r"\bjf\s+rt\s+(del|delete|rm|move|copy|set-props|sp|upload|u)\b", lower):
    if ("upload" in lower or re.search(r"\bjf\s+rt\s+u\b", lower)) and os.environ.get("CISO_ALLOW_REPORT_UPLOAD", "").lower() in {"1", "true", "yes", "on"}:
        allow()
    deny("Blocked mutating Artifactory command during CISO report workflow. Set CISO_ALLOW_REPORT_UPLOAD=true only for explicit report publication.")

def safe_rm_target(arg):
    if "*" in arg or "?" in arg or "[" in arg:
        return False
    base = os.path.basename(arg)
    if arg.startswith("/tmp/ciso-"):
        return True
    if base in {"executive-report.pdf", "full-report.pdf"}:
        return True
    return bool(re.fullmatch(r"jfrog-ciso-report-v\d+(?:\.\d+){1,2}(?:[-.\w]*)?\.zip", base))

def rm_is_scoped(command_text):
    try:
        tokens = shlex.split(command_text)
    except Exception:
        return False
    for idx, token in enumerate(tokens):
        if token != "rm":
            continue
        targets = []
        recursive = False
        for part in tokens[idx + 1:]:
            if part in {"&&", "||", ";"}:
                break
            if part.startswith("-"):
                recursive = recursive or "r" in part.lower()
                continue
            targets.append(part)
        if not targets:
            return False
        if recursive and not all(t.startswith("/tmp/ciso-") for t in targets):
            return False
        if not all(safe_rm_target(t) for t in targets):
            return False
    return True

if re.search(r"\brm\s+-", lower):
    if not rm_is_scoped(command):
        deny("Blocked broad file deletion. Cleanup must be scoped to /tmp/ciso-*, explicit report artifacts, or the versioned offline APM zip only.")

allow()
PY
