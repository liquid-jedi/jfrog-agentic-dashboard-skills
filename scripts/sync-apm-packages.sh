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
  mkdir -p "${REPO_ROOT}/${target_dir}"

  # rsync (not cp -R) so OS cruft never reaches a shipped package.
  rsync -a \
    --exclude '.DS_Store' \
    --exclude '__pycache__/' \
    --exclude '*.pyc' \
    --exclude '*.log' \
    "${REPO_ROOT}/${source_dir}/" "${REPO_ROOT}/${target_dir}/"

  echo "synced ${source_dir} -> ${target_dir}"
}

# The packaged skill version must match the canonical source. A mismatch means
# a release bump was applied to the package only, and syncing would revert it.
assert_version_match() {
  local source_dir="$1"
  local package_dir="$2"
  local skill_version apm_version

  skill_version="$(sed -n 's/^[[:space:]]*version:[[:space:]]*\(.*\)$/\1/p' \
    "${REPO_ROOT}/${source_dir}/SKILL.md" | head -1)"
  apm_version="$(sed -n 's/^version:[[:space:]]*\(.*\)$/\1/p' \
    "${REPO_ROOT}/${package_dir}/apm.yml" | head -1)"

  if [[ "$skill_version" != "$apm_version" ]]; then
    echo "ERROR: version mismatch for ${package_dir}" >&2
    echo "  ${source_dir}/SKILL.md : ${skill_version}" >&2
    echo "  ${package_dir}/apm.yml : ${apm_version}" >&2
    echo "Bump the canonical SKILL.md before syncing, or the sync will" >&2
    echo "overwrite the packaged version with the older source value." >&2
    exit 1
  fi
  echo "version check ok: ${package_dir} = ${apm_version}"
}

assert_version_match "Dashboard-ciso-report-skills" "packages/apm/jfrog-ciso-report"

sync_skill "Dashboard-ciso-report-skills" "packages/apm/jfrog-ciso-report" "jfrog-ciso-report"
