#!/usr/bin/env bash
set -euo pipefail

HOOK_PAYLOAD="$(cat)" python3 - "$@" <<'PY'
import json
import os
import re
import shlex
import sys
import time

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

# These guardrails cover the CISO report skill only. They must not police
# unrelated JFrog work — the platform skill, the MCP server, or ad-hoc CLI use.
# Matching any "jf rt"/"jf xr" command would do exactly that, so scope instead to
# commands that name CISO artifacts, plus anything issued while a report run is
# in flight (the runner touches RUN_MARKER for its lifetime).
RUN_MARKER = "/tmp/ciso-report-run.active"
MARKER_MAX_AGE_SECONDS = 4 * 3600

CISO_TOKENS = (
    "generate-ciso-report.sh",
    "enrich-ciso-datajson.sh",
    "verify-ciso-collection-proof.sh",
    "repair-ciso-report.sh",
    "ciso-report",
    "ciso-reports",
    "/tmp/ciso-",
    "ciso_pdf_mode",
    "ciso_local_root",
    "ciso_chrome_bin",
)

def ciso_run_active():
    # A crashed run would otherwise leave the marker behind and keep the
    # guardrails armed for every later command, so ignore a stale marker.
    try:
        age = time.time() - os.path.getmtime(RUN_MARKER)
    except OSError:
        return False
    return 0 <= age <= MARKER_MAX_AGE_SECONDS

if not any(token in lower for token in CISO_TOKENS) and not ciso_run_active():
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
    # POST is the transport for two read-only queries: the Xray violations
    # search and AQL. Neither mutates state, so both are read-style here.
    read_style_post = ("/api/v1/violations" in lower) or ("/api/search/aql" in lower)
    if post and not read_style_post:
        respond(
            "deny",
            "Blocked an unexpected JFrog POST during a CISO report workflow.",
            "Only Xray /api/v1/violations and Artifactory /api/search/aql POSTs are treated as read-style queries for this report.",
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
        # "git rm" only stages the removal of an already-tracked file and is
        # recoverable via "git checkout --" / "git reset". It is a version
        # control operation, not a filesystem wipe, so it is not restricted.
        if idx > 0 and tokens[idx - 1] == "git":
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
