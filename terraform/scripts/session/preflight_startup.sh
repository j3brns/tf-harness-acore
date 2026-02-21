#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_FILE="${SCRIPT_DIR}/preflight.policy"

if [ ! -f "${POLICY_FILE}" ]; then
  echo "ERROR: policy file not found: ${POLICY_FILE}"
  exit 1
fi

# shellcheck source=/dev/null
source "${POLICY_FILE}"

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required for preflight checks"
  exit 1
fi

ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
GH_REPO=""
if [[ "${ORIGIN_URL}" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
  GH_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "${REPO_ROOT}" ]; then
  echo "ERROR: not inside a git repository"
  exit 1
fi

CURRENT_PATH="$(pwd -P)"
CURRENT_BRANCH="$(git branch --show-current 2>/dev/null || true)"
if [ -z "${CURRENT_BRANCH}" ]; then
  echo "ERROR: detached HEAD is not allowed for session work"
  exit 1
fi

PRIMARY_WORKTREE_RAW="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
PRIMARY_WORKTREE="$(cd "${PRIMARY_WORKTREE_RAW}" && pwd -P)"

CURRENT_WORKTREE=""
while IFS= read -r worktree_path; do
  canonical_path="$(cd "${worktree_path}" && pwd -P)"
  if [[ "${CURRENT_PATH}" == "${canonical_path}"* ]]; then
    CURRENT_WORKTREE="${canonical_path}"
    break
  fi
done < <(git worktree list --porcelain | awk '/^worktree /{print $2}')

if [ -z "${CURRENT_WORKTREE}" ]; then
  echo "ERROR: current path is not a registered git worktree path"
  exit 1
fi

ERRORS=()
WARNINGS=()

if [ "${CURRENT_WORKTREE}" = "${PRIMARY_WORKTREE}" ]; then
  if [ "${CURRENT_BRANCH}" != "${REQUIRED_MAIN_BRANCH}" ]; then
    ERRORS+=("primary worktree must stay on '${REQUIRED_MAIN_BRANCH}', found '${CURRENT_BRANCH}'")
  fi
else
  if [[ ! "${CURRENT_BRANCH}" =~ ${WORKTREE_BRANCH_REGEX} ]]; then
    ERRORS+=("linked worktree branch '${CURRENT_BRANCH}' does not match regex ${WORKTREE_BRANCH_REGEX}")
  fi

  if [[ "${CURRENT_BRANCH}" =~ ^wt/[^/]*/([0-9]+)- ]]; then
    ISSUE_ID="${BASH_REMATCH[1]}"
    if [ "${ENFORCE_GH_ISSUE_LOOKUP}" = "true" ]; then
      if command -v gh >/dev/null 2>&1; then
        if [ -n "${GH_REPO}" ]; then
          if ! gh api "repos/${GH_REPO}/issues/${ISSUE_ID}" >/dev/null 2>&1; then
            ERRORS+=("branch issue id '${ISSUE_ID}' does not resolve via gh api for repo '${GH_REPO}'")
          fi
        else
          ERRORS+=("cannot resolve GitHub repo from origin URL; issue lookup could not be validated")
        fi
      else
        WARNINGS+=("gh CLI not found; skipped issue lookup for #${ISSUE_ID}")
      fi
    fi
  else
    ERRORS+=("cannot extract issue id from worktree branch '${CURRENT_BRANCH}'")
  fi
fi

if [ "${REQUIRE_CLEAN_WORKTREE}" = "true" ]; then
  if [ -n "$(git status --porcelain)" ]; then
    ERRORS+=("working tree is not clean")
  fi
fi

echo "Preflight context:"
echo "  repo:       ${REPO_ROOT}"
echo "  path:       ${CURRENT_PATH}"
echo "  worktree:   ${CURRENT_WORKTREE}"
echo "  primary:    ${PRIMARY_WORKTREE}"
echo "  branch:     ${CURRENT_BRANCH}"

if [ "${#WARNINGS[@]}" -gt 0 ]; then
  echo "Warnings:"
  for warning in "${WARNINGS[@]}"; do
    echo "  - ${warning}"
  done
fi

if [ "${#ERRORS[@]}" -gt 0 ]; then
  echo "Preflight result: FAILED"
  for err in "${ERRORS[@]}"; do
    echo "  - ${err}"
  done
  exit 1
fi

echo "Preflight result: PASS"
