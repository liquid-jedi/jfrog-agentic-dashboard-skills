#!/usr/bin/env bash
# Refresh APM package skill bundles from the canonical root skill folders.
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

sync_skill() {
  local source_dir="$1"
  local package_dir="$2"
  local skill_name="$3"
  local target_dir="${package_dir}/.apm/skills/${skill_name}"

  if [[ ! -d "${REPO_ROOT}/${source_dir}" ]]; then
    echo "ERROR: missing source skill folder: ${source_dir}" >&2
    exit 1
  fi

  mkdir -p "${REPO_ROOT}/${package_dir}/.apm/skills"
  rm -rf "${REPO_ROOT}/${target_dir}"
  cp -R "${REPO_ROOT}/${source_dir}" "${REPO_ROOT}/${target_dir}"
  echo "synced ${source_dir} -> ${target_dir}"
}

sync_skill "Dashboard-ciso-report-skills" "packages/apm/jfrog-ciso-report" "jfrog-ciso-report"
sync_skill "Dashboard-blueprint-skills" "packages/apm/jfrog-dashboard-blueprint" "jfrog-dashboard-blueprint"
