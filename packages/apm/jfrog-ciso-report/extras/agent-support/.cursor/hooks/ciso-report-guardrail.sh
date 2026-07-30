#!/usr/bin/env bash
set -euo pipefail

HOOK_PAYLOAD="$(cat)" python3 - "$@" <<'PY'
import json
import os
import re
import shlex
import sys

try:
    payload = json.loads(os.environ.get("HOOK_PAYLOAD") or "{}")
except Exception:
    print(json.dumps({"permission": "allow"}))
    raise SystemExit(0)

def dig(obj, *keys):
    cur = obj
    for key in keys:
        if not isinstance(cur, dict):
            return ""
        cur = cur.get(key)
    return cur if isinstance(cur, str) else ""

command = (
    payload.get("command")
    or dig(payload, "tool_input", "command")
    or dig(payload, "input", "command")
    or dig(payload, "arguments", "command")
    or dig(payload, "params", "command")
    or ""
)

def respond(permission, user_message="", agent_message=""):
    out = {"permission": permission}
    if user_message:
        out["user_message"] = user_message
    if agent_message:
        out["agent_message"] = agent_message
    print(json.dumps(out))
    raise SystemExit(0)

if not command:
    respond("allow")

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
    respond("allow")

if re.search(r"\bjf\s+(rt|xr)\s+curl\b", lower):
    destructive = re.search(r"(^|\s)-x\s*(delete|put|patch)\b|(^|\s)-x(delete|put|patch)\b", lower)
    if destructive:
        respond(
            "deny",
            "Blocked a destructive JFrog curl method during a CISO report workflow.",
            "Use read-only JFrog API calls for CISO report generation. Destructive methods require explicit user approval outside this hook.",
        )
    post = re.search(r"(^|\s)-x\s*post\b|(^|\s)-xpost\b", lower)
    if post and "/api/v1/violations" not in lower:
        respond(
            "deny",
            "Blocked an unexpected JFrog POST during a CISO report workflow.",
            "Only Xray /api/v1/violations POST is treated as a read-style query for this report.",
        )

if re.search(r"\bjf\s+rt\s+(del|delete|rm|move|copy|set-props|sp|upload|u)\b", lower):
    if "upload" in lower or re.search(r"\bjf\s+rt\s+u\b", lower):
        if os.environ.get("CISO_ALLOW_REPORT_UPLOAD", "").lower() in {"1", "true", "yes", "on"}:
            respond("allow")
        respond(
            "ask",
            "This command uploads artifacts. Confirm publication for the CISO report.",
            "Set CISO_ALLOW_REPORT_UPLOAD=true only when the user explicitly asks to publish report artifacts.",
        )
    respond(
        "deny",
        "Blocked a mutating Artifactory command during a CISO report workflow.",
        "CISO report generation should use read-only JFrog commands unless the user explicitly requests publication.",
    )

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
        respond(
            "deny",
            "Blocked broad file deletion during a CISO report workflow.",
            "Cleanup should be scoped to /tmp/ciso-*, explicit report artifacts, or the versioned offline APM zip only.",
        )

respond("allow")
PY
