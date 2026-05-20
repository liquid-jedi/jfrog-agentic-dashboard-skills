#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CISO_SKILL_PATH="$REPO_ROOT/dashboard-report-skills"
AUTO_FIX=false
ASSUME_YES=false

while [ "$#" -gt 0 ]; do
  case "$1" in
    --fix)
      AUTO_FIX=true
      ;;
    --yes)
      ASSUME_YES=true
      ;;
    --skill-path)
      shift
      CISO_SKILL_PATH="${1:-}"
      if [ -z "$CISO_SKILL_PATH" ]; then
        echo "ERROR: --skill-path requires a value"
        exit 2
      fi
      ;;
    -h|--help)
      cat <<'EOF'
Usage: agentic-dashboard-prechecks.sh [--fix] [--yes] [--skill-path <path>]

Options:
  --fix                Install missing required skills (jfrog, jfrog-ciso-report)
  --yes                Non-interactive mode for --fix
  --skill-path <path>  Override local source path for jfrog-ciso-report install
  -h, --help           Show help
EOF
      exit 0
      ;;
    *)
      echo "ERROR: Unknown argument: $1"
      exit 2
      ;;
  esac
  shift
done

failures=0
warnings=0
need_fix_jfrog=false
need_fix_ciso=false

ok() { printf "[OK] %s\n" "$1"; }
warn() { printf "[WARN] %s\n" "$1"; warnings=$((warnings+1)); }
err() { printf "[FAIL] %s\n" "$1"; failures=$((failures+1)); }

check_cmd() {
  local c="$1"
  if command -v "$c" >/dev/null 2>&1; then
    ok "Tool on PATH: $c"
  else
    err "Missing required tool on PATH: $c"
  fi
}

printf "=== CISO Runtime Readiness Check ===\n"
printf "Repo root: %s\n" "$REPO_ROOT"
printf "Expected skill source: %s\n\n" "$CISO_SKILL_PATH"

check_cmd jf
check_cmd jq
check_cmd python3
check_cmd npx

printf "\n=== Skills Installation ===\n"
SKILLS_OUT_RAW="$(npx skills list -g 2>/dev/null || true)"
SKILLS_OUT="$(printf "%s\n" "$SKILLS_OUT_RAW" | sed -E 's/\x1B\[[0-9;]*[A-Za-z]//g')"
if printf "%s\n" "$SKILLS_OUT" | awk '$1=="jfrog"{found=1} END{exit(found?0:1)}'; then
  ok "Base skill installed globally: jfrog"
else
  err "Base skill 'jfrog' is not installed globally"
  need_fix_jfrog=true
fi

if printf "%s\n" "$SKILLS_OUT" | awk '$1=="jfrog-ciso-report"{found=1} END{exit(found?0:1)}'; then
  ok "Persona skill installed globally: jfrog-ciso-report"
else
  err "Persona skill 'jfrog-ciso-report' is not installed globally"
  need_fix_ciso=true
fi

if ! printf "%s\n" "$SKILLS_OUT" | grep -q '^jfrog-ciso-report '; then
  printf "Install with:\n"
  printf "  npx skills add \"%s\" -g -y\n" "$CISO_SKILL_PATH"
fi

printf "\n=== JFrog CLI Configuration ===\n"
CFG="$(jf config show 2>/dev/null || true)"
if [ -z "$CFG" ]; then
  err "No JFrog CLI configuration found (jf config show returned empty)"
else
  SERVERS=()
  while IFS= read -r sid; do
    [ -n "$sid" ] && SERVERS+=("$sid")
  done <<EOF
$(printf "%s\n" "$CFG" | awk '/^Server ID:/{print $3}')
EOF
  SERVER_COUNT="${#SERVERS[@]}"

  if [ "$SERVER_COUNT" -eq 0 ]; then
    err "No JFrog servers configured"
  elif [ "$SERVER_COUNT" -eq 1 ]; then
    ok "Exactly one JFrog server configured: ${SERVERS[0]}"
  else
    warn "Multiple JFrog servers configured (${SERVER_COUNT}): ${SERVERS[*]}"
    warn "Good behavior: report agent must ask for server choice when prompt does not name one"
  fi
fi

printf "\n=== Skill Source Path ===\n"
if [ -f "$CISO_SKILL_PATH/SKILL.md" ]; then
  ok "Skill source path is valid"
else
  err "Skill source path invalid: $CISO_SKILL_PATH/SKILL.md not found"
fi

printf "\n=== Good State Summary ===\n"
printf "1. jf, jq, python3, npx available on PATH\n"
printf "2. Global skills include: jfrog and jfrog-ciso-report\n"
printf "3. At least one JFrog CLI server configured\n"
printf "4. If multiple servers are configured, runtime must ask server choice\n"
printf "5. Runtime must echo resolved local output root before collection\n"

printf "\n=== Result ===\n"
if [ "$failures" -gt 0 ]; then
  printf "Readiness check failed with %s blocking issue(s) and %s warning(s).\n" "$failures" "$warnings"

  if [ "$AUTO_FIX" = true ]; then
    printf "\n=== Auto-fix mode ===\n"

    if [ "$need_fix_jfrog" = true ]; then
      if [ "$ASSUME_YES" = true ]; then
        do_install_jfrog="y"
      else
        printf "Install missing base skill 'jfrog'? [y/N]: "
        read -r do_install_jfrog
      fi
      if [[ "${do_install_jfrog:-n}" =~ ^[Yy]$ ]]; then
        npx skills add jfrog -g -y
      fi
    fi

    if [ "$need_fix_ciso" = true ]; then
      if [ "$ASSUME_YES" = true ]; then
        do_install_ciso="y"
      else
        printf "Install missing persona skill 'jfrog-ciso-report' from %s ? [y/N]: " "$CISO_SKILL_PATH"
        read -r do_install_ciso
      fi
      if [[ "${do_install_ciso:-n}" =~ ^[Yy]$ ]]; then
        npx skills add "$CISO_SKILL_PATH" -g -y
      fi
    fi

    printf "\nRe-run precheck to verify final state:\n"
    printf "  %s --skill-path \"%s\"\n" "$0" "$CISO_SKILL_PATH"
  fi

  exit 1
fi

printf "Readiness check passed with %s warning(s).\n" "$warnings"
exit 0
