#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
POLICY_FILE="${SCRIPT_DIR}/preflight.policy"

if ! command -v git >/dev/null 2>&1; then
  echo "ERROR: git is required"
  exit 1
fi

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || true)"
if [ -z "${REPO_ROOT}" ]; then
  echo "ERROR: run this inside the repository (or a linked worktree)"
  exit 1
fi

ORIGIN_URL="$(git remote get-url origin 2>/dev/null || true)"
GH_REPO=""
if [[ "${ORIGIN_URL}" =~ github\.com[:/]([^/]+)/([^/.]+)(\.git)?$ ]]; then
  GH_REPO="${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
fi

REQUIRED_MAIN_BRANCH="main"
WORKTREE_BRANCH_REGEX='^wt/[a-z0-9._-]+/[0-9]+-[a-z0-9._-]+$'
if [ -f "${POLICY_FILE}" ]; then
  # shellcheck source=/dev/null
  source "${POLICY_FILE}"
fi

WORKTREE_BASE_DIR_DEFAULT="$(cd "${REPO_ROOT}/.." && pwd -P)/worktrees"
WORKTREE_QUEUE_PLAN_FILES="${WORKTREE_QUEUE_PLAN_FILES:-ROADMAP.md}"

WT_PATHS=()
WT_HEADS=()
WT_BRANCHES=()
READY_ISSUE_NUMBERS=()
READY_ISSUE_TITLES=()
READY_ISSUE_CREATED=()
READY_ISSUE_LABELS=()
declare -A PLAN_ISSUE_ORDER=()

refresh_worktrees() {
  WT_PATHS=()
  WT_HEADS=()
  WT_BRANCHES=()

  local line=""
  local cur_path=""
  local cur_head=""
  local cur_branch="(detached)"

  while IFS= read -r line || [ -n "${line}" ]; do
    case "${line}" in
      "worktree "*)
        if [ -n "${cur_path}" ]; then
          WT_PATHS+=("${cur_path}")
          WT_HEADS+=("${cur_head}")
          WT_BRANCHES+=("${cur_branch}")
        fi
        cur_path="${line#worktree }"
        cur_head=""
        cur_branch="(detached)"
        ;;
      "HEAD "*)
        cur_head="${line#HEAD }"
        ;;
      "branch refs/heads/"*)
        cur_branch="${line#branch refs/heads/}"
        ;;
      "")
        if [ -n "${cur_path}" ]; then
          WT_PATHS+=("${cur_path}")
          WT_HEADS+=("${cur_head}")
          WT_BRANCHES+=("${cur_branch}")
          cur_path=""
          cur_head=""
          cur_branch="(detached)"
        fi
        ;;
    esac
  done < <(git worktree list --porcelain)

  if [ -n "${cur_path}" ]; then
    WT_PATHS+=("${cur_path}")
    WT_HEADS+=("${cur_head}")
    WT_BRANCHES+=("${cur_branch}")
  fi
}

primary_worktree_path() {
  refresh_worktrees
  if [ "${#WT_PATHS[@]}" -eq 0 ]; then
    echo "ERROR: no git worktrees found"
    exit 1
  fi
  printf '%s\n' "${WT_PATHS[0]}"
}

print_worktree_table() {
  refresh_worktrees
  local primary
  primary="$(primary_worktree_path)"

  echo
  echo "Registered worktrees:"
  local i
  for i in "${!WT_PATHS[@]}"; do
    local marker=" "
    if [ "${WT_PATHS[$i]}" = "${primary}" ]; then
      marker="*"
    fi
    printf "  [%d]%s %s\n" "$((i + 1))" "${marker}" "${WT_PATHS[$i]}"
    printf "      branch: %s\n" "${WT_BRANCHES[$i]}"
    printf "      head:   %s\n" "${WT_HEADS[$i]}"
  done
  echo
  echo "Legend: [*] primary worktree"
  echo
}

pause() {
  read -r -p "Press Enter to continue..." _
}

shell_quote() {
  printf '%q' "$1"
}

prompt_nonempty() {
  local prompt="$1"
  local value=""
  while :; do
    read -r -p "${prompt}" value
    if [ -n "${value}" ]; then
      printf '%s\n' "${value}"
      return 0
    fi
    echo "Value is required." >&2
  done
}

prompt_with_default() {
  local prompt="$1"
  local default_value="$2"
  local value=""
  read -r -p "${prompt} [${default_value}]: " value
  if [ -z "${value}" ]; then
    printf '%s\n' "${default_value}"
    return 0
  fi
  printf '%s\n' "${value}"
}

slugify_text() {
  local raw="$1"
  local lowered=""
  lowered="$(printf '%s' "${raw}" | tr '[:upper:]' '[:lower:]')"
  lowered="$(printf '%s' "${lowered}" | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//; s/-{2,}/-/g')"
  lowered="$(printf '%s' "${lowered}" | cut -c1-60)"
  if [ -z "${lowered}" ]; then
    lowered="task"
  fi
  printf '%s\n' "${lowered}"
}

derive_slug_from_issue_title() {
  local title="$1"
  local cleaned=""
  cleaned="$(printf '%s' "${title}" | sed -E 's/^[[:space:]]*[A-Za-z0-9._-]+:[[:space:]]*//')"
  slugify_text "${cleaned}"
}

infer_scope_from_issue() {
  local issue_title="${1:-}"
  local issue_labels="${2:-}"
  local haystack=""
  haystack="$(printf '%s|%s' "${issue_labels}" "${issue_title}" | tr '[:upper:]' '[:lower:]')"

  case "${haystack}" in
    *"|provider|"*|*"provider"*|*"novation"*)
      printf '%s\n' "provider"
      return 0
      ;;
    *"|docs|"*|*"readme"*|*"roadmap"*|*"changelog"*|*"runbook"*|*"adr"*)
      printf '%s\n' "docs"
      return 0
      ;;
    *"|runtime|"*|*"runtime"*|*"memory"*)
      printf '%s\n' "runtime"
      return 0
      ;;
    *"|foundation|"*|*"gateway"*|*"identity"*|*"observability"*)
      printf '%s\n' "foundation"
      return 0
      ;;
    *"|tools|"*|*"browser"*|*"code interpreter"*|*"tool registry"*|*"tool "*)
      printf '%s\n' "tools"
      return 0
      ;;
    *"|governance|"*|*"cedar"*|*"policy"*|*"evaluator"*)
      printf '%s\n' "governance"
      return 0
      ;;
    *"|ci|"*|*"workflow"*|*"pipeline"*|*"checkov"*|*"tflint"*|*"pre-commit"*|*"ci "*)
      printf '%s\n' "ci"
      return 0
      ;;
    *"|release|"*|*"release"*|*"tag"*|*"version"*)
      printf '%s\n' "release"
      return 0
      ;;
  esac

  printf '%s\n' "task"
}

choose_scope() {
  local suggested_scope="${1:-task}"
  local choice=""
  local custom_scope=""

  echo >&2
  echo "Choose branch scope namespace (used in wt/<scope>/<issue>-<slug>):" >&2
  echo "  1) use suggested: ${suggested_scope} (default)" >&2
  echo "  2) provider" >&2
  echo "  3) docs" >&2
  echo "  4) runtime" >&2
  echo "  5) foundation" >&2
  echo "  6) tools" >&2
  echo "  7) governance" >&2
  echo "  8) ci" >&2
  echo "  9) release" >&2
  echo "  10) custom" >&2
  echo >&2

  while :; do
    read -r -p "Choice [1]: " choice >&2
    choice="${choice:-1}"
    case "${choice}" in
      1) printf '%s\n' "${suggested_scope}"; return 0 ;;
      2|provider) printf '%s\n' "provider"; return 0 ;;
      3|docs) printf '%s\n' "docs"; return 0 ;;
      4|runtime) printf '%s\n' "runtime"; return 0 ;;
      5|foundation) printf '%s\n' "foundation"; return 0 ;;
      6|tools) printf '%s\n' "tools"; return 0 ;;
      7|governance) printf '%s\n' "governance"; return 0 ;;
      8|ci) printf '%s\n' "ci"; return 0 ;;
      9|release) printf '%s\n' "release"; return 0 ;;
      10|custom)
        custom_scope="$(prompt_nonempty "Custom scope (lowercase): ")"
        printf '%s\n' "${custom_scope}"
        return 0
        ;;
      *) echo "Invalid choice." >&2 ;;
    esac
  done
}

choose_issue_source() {
  local choice=""
  echo >&2
  echo "Choose issue source for new worktree:" >&2
  echo "  1) ready queue (next ready first, default)" >&2
  echo "  2) manual issue number + slug" >&2
  echo >&2
  while :; do
    read -r -p "Choice [1]: " choice >&2
    choice="${choice:-1}"
    case "${choice}" in
      1|queue|ready) printf '%s\n' "queue"; return 0 ;;
      2|manual) printf '%s\n' "manual"; return 0 ;;
      *) echo "Invalid choice." >&2 ;;
    esac
  done
}

choose_ready_queue_stream_label() {
  local choice=""
  local custom_label=""
  local env_default="${WORKTREE_READY_STREAM_LABEL:-}"
  local stream_choice=""
  local roadmap_streams=("a" "b" "c" "d" "e")
  local stream_summary=""

  echo >&2
  echo "Ready queue stream filter (optional):" >&2
  if [ -n "${env_default}" ]; then
    echo "  1) use env default: ${env_default} (default)" >&2
    echo "  2) no stream filter (ready only)" >&2
    echo "  3) pick roadmap stream label" >&2
    echo "  4) enter custom label" >&2
    echo >&2
    while :; do
      read -r -p "Choice [1]: " choice >&2
      choice="${choice:-1}"
      case "${choice}" in
        1) printf '%s\n' "${env_default}"; return 0 ;;
        2) printf '%s\n' ""; return 0 ;;
        3|roadmap)
          echo >&2
          echo "Workstream labels:" >&2
          local i
          for i in "${!roadmap_streams[@]}"; do
            stream_summary="$(stream_label_summary "${roadmap_streams[$i]}")"
            if [ -n "${stream_summary}" ]; then
              printf "  %d) %s - %s\n" "$((i + 1))" "${roadmap_streams[$i]}" "${stream_summary}" >&2
            else
              printf "  %d) %s\n" "$((i + 1))" "${roadmap_streams[$i]}" >&2
            fi
          done
          echo >&2
          while :; do
            read -r -p "Pick roadmap stream [1]: " stream_choice >&2
            stream_choice="${stream_choice:-1}"
            if [[ "${stream_choice}" =~ ^[0-9]+$ ]] && [ "${stream_choice}" -ge 1 ] && [ "${stream_choice}" -le "${#roadmap_streams[@]}" ]; then
              printf '%s\n' "${roadmap_streams[$((stream_choice - 1))]}"
              return 0
            fi
            echo "Invalid choice." >&2
          done
          ;;
        4|custom)
          custom_label="$(prompt_nonempty "Stream label (e.g. a, a1, provider-matrix): ")"
          printf '%s\n' "${custom_label}"
          return 0
          ;;
        *) echo "Invalid choice." >&2 ;;
      esac
    done
  fi

  echo "  1) no stream filter (ready only) (default)" >&2
  echo "  2) pick roadmap stream label" >&2
  echo "  3) enter custom label (e.g. provider-matrix)" >&2
  echo >&2
  while :; do
    read -r -p "Choice [1]: " choice >&2
    choice="${choice:-1}"
    case "${choice}" in
      1) printf '%s\n' ""; return 0 ;;
      2|roadmap)
        echo >&2
        echo "Workstream labels:" >&2
        local i
        for i in "${!roadmap_streams[@]}"; do
          stream_summary="$(stream_label_summary "${roadmap_streams[$i]}")"
          if [ -n "${stream_summary}" ]; then
            printf "  %d) %s - %s\n" "$((i + 1))" "${roadmap_streams[$i]}" "${stream_summary}" >&2
          else
            printf "  %d) %s\n" "$((i + 1))" "${roadmap_streams[$i]}" >&2
          fi
        done
        echo >&2
        while :; do
          read -r -p "Pick roadmap stream [1]: " stream_choice >&2
          stream_choice="${stream_choice:-1}"
          if [[ "${stream_choice}" =~ ^[0-9]+$ ]] && [ "${stream_choice}" -ge 1 ] && [ "${stream_choice}" -le "${#roadmap_streams[@]}" ]; then
            printf '%s\n' "${roadmap_streams[$((stream_choice - 1))]}"
            return 0
          fi
          echo "Invalid choice." >&2
        done
        ;;
      3|custom)
        custom_label="$(prompt_nonempty "Stream label (e.g. a, a1, provider-matrix): ")"
        printf '%s\n' "${custom_label}"
        return 0
        ;;
      *) echo "Invalid choice." >&2 ;;
    esac
  done
}

stream_label_summary() {
  local stream_label="${1:-}"
  case "${stream_label}" in
    a*) printf '%s\n' "Workstream A: Terraform Provider Novation (CLI -> Native)" ;;
    b*) printf '%s\n' "Workstream B: Tag + Policy Consolidation" ;;
    c*) printf '%s\n' "Workstream C: Tenancy Portal/API Refinement" ;;
    d*) printf '%s\n' "Developer Experience (DX)" ;;
    e*) printf '%s\n' "Enterprise Features (Scale & Compliance)" ;;
    *) printf '%s\n' "" ;;
  esac
}

extract_stream_label_from_labels() {
  local labels="${1:-}"
  local label=""
  local normalized=""
  local lane_label=""
  IFS='|' read -r -a _label_arr <<< "${labels}"
  for label in "${_label_arr[@]}"; do
    normalized="$(printf '%s' "${label}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${normalized}" =~ ^[a-e]$ ]]; then
      lane_label="${normalized}"
      break
    fi
  done
  if [ -n "${lane_label}" ]; then
    printf '%s\n' "${lane_label}"
    return 0
  fi
  for label in "${_label_arr[@]}"; do
    normalized="$(printf '%s' "${label}" | tr '[:upper:]' '[:lower:]')"
    if [[ "${normalized}" =~ ^[a-z][0-9]+$ ]]; then
      printf '%s\n' "${normalized}"
      return 0
    fi
  done
  printf '%s\n' ""
}

fetch_issue_labels() {
  local issue_id="$1"
  if ! command -v gh >/dev/null 2>&1; then
    printf '%s\n' ""
    return 0
  fi
  if [ -z "${GH_REPO}" ]; then
    printf '%s\n' ""
    return 0
  fi
  gh issue view "${issue_id}" -R "${GH_REPO}" --json labels --jq '.labels | map(.name) | join("|")' 2>/dev/null || printf '%s\n' ""
}

refresh_plan_issue_order() {
  PLAN_ISSUE_ORDER=()
  local order=0
  local file=""
  local issue_num=""

  for file in ${WORKTREE_QUEUE_PLAN_FILES}; do
    if [ ! -f "${REPO_ROOT}/${file}" ]; then
      continue
    fi
    while IFS= read -r issue_num; do
      if [[ ! "${issue_num}" =~ ^[0-9]+$ ]]; then
        continue
      fi
      if [ -z "${PLAN_ISSUE_ORDER[${issue_num}]+x}" ]; then
        PLAN_ISSUE_ORDER["${issue_num}"]="${order}"
        order=$((order + 1))
      fi
    done < <(
      grep -hoE '#[0-9]+' "${REPO_ROOT}/${file}" 2>/dev/null \
        | sed 's/^#//' \
        | awk '!seen[$0]++'
    )
  done
}

plan_issue_rank() {
  local issue_id="$1"
  if [ -n "${PLAN_ISSUE_ORDER[${issue_id}]+x}" ]; then
    printf '%s\n' "${PLAN_ISSUE_ORDER[${issue_id}]}"
    return 0
  fi
  printf '999999\n'
}

priority_rank_from_labels() {
  local labels="$1"
  local lower=""
  lower="$(printf '%s' "${labels}" | tr '[:upper:]' '[:lower:]')"

  case "|${lower}|" in
    *"|p0|"*|*"|priority:p0|"*|*"|priority:high|"*|*"|priority:critical|"*|*"|urgent|"*)
      printf '0\n'
      return 0
      ;;
    *"|p1|"*|*"|priority:p1|"*|*"|priority:medium|"*|*"|high-priority|"*)
      printf '1\n'
      return 0
      ;;
    *"|p2|"*|*"|priority:p2|"*|*"|priority:low|"*)
      printf '2\n'
      return 0
      ;;
    *"|p3|"*|*"|priority:p3|"*|*"|nice-to-have|"*)
      printf '3\n'
      return 0
      ;;
  esac

  printf '50\n'
}

refresh_ready_issue_queue() {
  local stream_label="${1:-}"
  READY_ISSUE_NUMBERS=()
  READY_ISSUE_TITLES=()
  READY_ISSUE_CREATED=()
  READY_ISSUE_LABELS=()

  if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh CLI not found (required for ready issue queue)." >&2
    return 1
  fi
  if [ -z "${GH_REPO}" ]; then
    echo "ERROR: could not determine GitHub repo from origin remote." >&2
    return 1
  fi

  refresh_plan_issue_order

  local unsorted_lines=""
  local line=""
  local number=""
  local created_at=""
  local title=""
  local labels=""
  local roadmap_rank=""
  local priority_rank=""
  local sorted_line=""
  local -a gh_issue_args=()

  gh_issue_args=(
    issue list -R "${GH_REPO}" --state open --label ready --limit 50
    --json number,title,createdAt,labels
  )
  if [ -n "${stream_label}" ]; then
    gh_issue_args+=(--label "${stream_label}")
  fi

  while IFS= read -r line; do
    [ -z "${line}" ] && continue
    number="$(printf '%s' "${line}" | cut -f1)"
    created_at="$(printf '%s' "${line}" | cut -f2)"
    title="$(printf '%s' "${line}" | cut -f3)"
    labels="$(printf '%s' "${line}" | cut -f4)"
    roadmap_rank="$(plan_issue_rank "${number}")"
    priority_rank="$(priority_rank_from_labels "${labels}")"
    unsorted_lines+="${roadmap_rank}"$'\t'"${priority_rank}"$'\t'"${created_at}"$'\t'"${number}"$'\t'"${title}"$'\t'"${labels}"$'\n'
  done < <(
    gh "${gh_issue_args[@]}" \
      --jq '.[] | [.number, .createdAt, .title, (.labels | map(.name) | join("|"))] | @tsv'
  )

  while IFS= read -r sorted_line; do
    [ -z "${sorted_line}" ] && continue
    READY_ISSUE_NUMBERS+=("$(printf '%s' "${sorted_line}" | cut -f4)")
    READY_ISSUE_CREATED+=("$(printf '%s' "${sorted_line}" | cut -f3)")
    READY_ISSUE_TITLES+=("$(printf '%s' "${sorted_line}" | cut -f5-)")
    READY_ISSUE_LABELS+=("$(printf '%s' "${sorted_line}" | cut -f6-)")
  done < <(printf '%s' "${unsorted_lines}" | sort -t $'\t' -k1,1n -k2,2n -k3,3)

  if [ "${#READY_ISSUE_NUMBERS[@]}" -eq 0 ]; then
    if [ -n "${stream_label}" ]; then
      echo "No open issues labeled 'ready' and '${stream_label}' found in ${GH_REPO}." >&2
    else
      echo "No open issues labeled 'ready' found in ${GH_REPO}." >&2
    fi
    return 1
  fi
  return 0
}

choose_ready_issue_from_queue() {
  local stream_label="${1:-}"
  if ! refresh_ready_issue_queue "${stream_label}"; then
    return 1
  fi

  echo >&2
  if [ -n "${stream_label}" ]; then
    echo "Ready issue queue (filter: ready + ${stream_label}; plan order -> priority labels -> createdAt):" >&2
  else
    echo "Ready issue queue (filter: ready; plan order -> priority labels -> createdAt):" >&2
  fi
  local i
  for i in "${!READY_ISSUE_NUMBERS[@]}"; do
    if [ -n "${READY_ISSUE_LABELS[$i]}" ]; then
      printf "  %d) #%s %s [%s]\n" "$((i + 1))" "${READY_ISSUE_NUMBERS[$i]}" "${READY_ISSUE_TITLES[$i]}" "${READY_ISSUE_LABELS[$i]}" >&2
    else
      printf "  %d) #%s %s\n" "$((i + 1))" "${READY_ISSUE_NUMBERS[$i]}" "${READY_ISSUE_TITLES[$i]}" >&2
    fi
  done
  echo >&2

  local choice=""
  while :; do
    read -r -p "Pick issue [1]: " choice >&2
    choice="${choice:-1}"
    if [[ "${choice}" =~ ^[0-9]+$ ]] && [ "${choice}" -ge 1 ] && [ "${choice}" -le "${#READY_ISSUE_NUMBERS[@]}" ]; then
      local idx=$((choice - 1))
      printf '%s\t%s\t%s\n' "${READY_ISSUE_NUMBERS[$idx]}" "${READY_ISSUE_TITLES[$idx]}" "${READY_ISSUE_LABELS[$idx]}"
      return 0
    fi
    echo "Invalid choice." >&2
  done
}

choose_auto_claim() {
  local choice=""
  echo >&2
  echo "Auto-claim selected ready issue?" >&2
  echo "  1) yes (default) - move labels: ready -> in-progress" >&2
  echo "  2) no" >&2
  echo >&2
  while :; do
    read -r -p "Choice [1]: " choice >&2
    choice="${choice:-1}"
    case "${choice}" in
      1|yes|y) printf '%s\n' "yes"; return 0 ;;
      2|no|n) printf '%s\n' "no"; return 0 ;;
      *) echo "Invalid choice." >&2 ;;
    esac
  done
}

claim_issue_in_progress() {
  local issue_id="$1"

  if ! command -v gh >/dev/null 2>&1; then
    echo "WARNING: gh CLI not found; skipped auto-claim for issue #${issue_id}" >&2
    return 1
  fi
  if [ -z "${GH_REPO}" ]; then
    echo "WARNING: could not determine GitHub repo from origin; skipped auto-claim for issue #${issue_id}" >&2
    return 1
  fi

  if gh issue edit "${issue_id}" -R "${GH_REPO}" --add-label in-progress --remove-label ready >/dev/null 2>&1; then
    echo "Auto-claim: issue #${issue_id} moved to in-progress (removed ready)."
    return 0
  fi

  echo "WARNING: auto-claim failed for issue #${issue_id}; update labels manually (ready -> in-progress)." >&2
  return 1
}

suggest_next_worktree_name() {
  refresh_worktrees
  local max_num=1
  local i
  for i in "${!WT_PATHS[@]}"; do
    local base
    base="$(basename "${WT_PATHS[$i]}")"
    if [[ "${base}" =~ ^wt([0-9]+)$ ]]; then
      local n="${BASH_REMATCH[1]}"
      if [ "${n}" -ge "${max_num}" ]; then
        max_num=$((n + 1))
      fi
    fi
  done
  printf 'wt%d\n' "${max_num}"
}

validate_branch_parts() {
  local scope="$1"
  local issue_id="$2"
  local slug="$3"

  if [[ ! "${scope}" =~ ^[a-z0-9._-]+$ ]]; then
    echo "ERROR: scope must match [a-z0-9._-]+"
    return 1
  fi
  if [[ ! "${issue_id}" =~ ^[0-9]+$ ]]; then
    echo "ERROR: issue id must be numeric"
    return 1
  fi
  if [[ ! "${slug}" =~ ^[a-z0-9._-]+$ ]]; then
    echo "ERROR: slug must match [a-z0-9._-]+"
    return 1
  fi
  return 0
}

choose_worktree_path() {
  local include_primary="$1"
  refresh_worktrees
  local primary
  primary="$(primary_worktree_path)"

  local options=()
  local idx_map=()
  local i
  for i in "${!WT_PATHS[@]}"; do
    if [ "${include_primary}" = "false" ] && [ "${WT_PATHS[$i]}" = "${primary}" ]; then
      continue
    fi
    options+=("${WT_PATHS[$i]} | ${WT_BRANCHES[$i]}")
    idx_map+=("${i}")
  done

  if [ "${#options[@]}" -eq 0 ]; then
    echo "No eligible worktrees found." >&2
    return 1
  fi

  echo >&2
  echo "Select a worktree:" >&2
  local n=1
  for n in "${!options[@]}"; do
    printf "  %d) %s\n" "$((n + 1))" "${options[$n]}" >&2
  done
  echo >&2

  local selection=""
  while :; do
    read -r -p "Choice: " selection >&2
    if [[ "${selection}" =~ ^[0-9]+$ ]] && [ "${selection}" -ge 1 ] && [ "${selection}" -le "${#options[@]}" ]; then
      local mapped="${idx_map[$((selection - 1))]}"
      printf '%s\n' "${WT_PATHS[$mapped]}"
      return 0
    fi
    echo "Invalid choice." >&2
  done
}

run_preflight_in_worktree() {
  local wt_path="$1"
  echo
  echo "Running preflight in ${wt_path} ..."
  (cd "${wt_path}" && make preflight-session)
}

worktree_branch_name() {
  local wt_path="$1"
  git -C "${wt_path}" branch --show-current 2>/dev/null || true
}

worktree_issue_id() {
  local wt_path="$1"
  local branch_name=""
  branch_name="$(worktree_branch_name "${wt_path}")"
  if [[ "${branch_name}" =~ ^wt/[^/]*/([0-9]+)- ]]; then
    printf '%s\n' "${BASH_REMATCH[1]}"
    return 0
  fi
  printf 'UNKNOWN\n'
}

echo_agent_prompt_for_worktree() {
  local wt_path="$1"
  local issue_type="$2"
  local closure_condition="$3"
  local issue_id=""
  local branch_name=""
  local issue_labels=""
  local stream_label=""
  local stream_summary=""
  local stream_sentence=""
  local finish_rule=""
  local issue_type_note=""
  issue_id="$(worktree_issue_id "${wt_path}")"
  branch_name="$(worktree_branch_name "${wt_path}")"
  if [ "${issue_id}" != "UNKNOWN" ]; then
    issue_labels="$(fetch_issue_labels "${issue_id}")"
    stream_label="$(extract_stream_label_from_labels "${issue_labels}")"
    stream_summary="$(stream_label_summary "${stream_label}")"
    if [ -n "${stream_label}" ] && [ -n "${stream_summary}" ]; then
      stream_sentence=" Stream: ${stream_label} (${stream_summary})."
    elif [ -n "${stream_label}" ]; then
      stream_sentence=" Stream label: ${stream_label}."
    else
      stream_sentence=""
    fi
  fi
  if [ "${issue_type}" = "tracker" ]; then
    finish_rule="Rule 12.9"
    issue_type_note="Treat this as a tracker issue (coordination/planning unless explicitly docs/planning implementation)."
  else
    finish_rule="Rule 12.8"
    issue_type_note="Treat this as an execution issue (implement in this worktree only)."
  fi
  # Final line before the prompt is a copy/paste-ready agent prompt boilerplate.
  printf '%s\n' "You are a pragmatic, rigorous, concise coding agent working issue #${issue_id} on branch ${branch_name} in worktree ${wt_path}.${stream_sentence} ${issue_type_note} Read first: AGENTS.md (focus on Rules 7.7-7.8 and 12.3-12.11), DEVELOPER_GUIDE.md (workflow), README.md (entrypoints), docs/architecture.md (module boundaries), and ADRs 0009/0010/0011 in docs/adr/. Then execute in a loop until the closure condition is met: inspect -> state plan + expected touched paths -> implement -> validate -> update docs/tests as required -> rerun checks -> continue. Work only in this worktree and keep changes scoped to issue #${issue_id}. Run make preflight-session now and again before commit/push. Follow existing repo patterns before introducing new files or scripts. Do not stop at the first blocker: if an approach conflicts with a repo rule, choose another compliant approach and continue; escalate only if no compliant path exists. Closure condition for this task: ${closure_condition}. Finish using ${finish_rule} and include validation evidence in the issue/PR."
}

build_agent_command() {
  local agent="$1"
  local mode="$2"
  local prompt="$3"
  local quoted_prompt=""
  quoted_prompt="$(shell_quote "${prompt}")"

  case "${agent}" in
    gemini)
      if [ "${mode}" = "yolo" ]; then
        printf 'gemini --yolo %s\n' "${quoted_prompt}"
      else
        printf 'gemini %s\n' "${quoted_prompt}"
      fi
      ;;
    claude|clause)
      if [ "${mode}" = "yolo" ]; then
        printf 'claude --dangerously-skip-permissions %s\n' "${quoted_prompt}"
      else
        printf 'claude %s\n' "${quoted_prompt}"
      fi
      ;;
    codex)
      if [ "${mode}" = "yolo" ]; then
        printf 'codex --yolo %s\n' "${quoted_prompt}"
      else
        printf 'codex %s\n' "${quoted_prompt}"
      fi
      ;;
    *)
      printf 'echo %s\n' "$(shell_quote "Unsupported agent '${agent}'")"
      ;;
  esac
}

choose_agent() {
  local choice=""
  echo >&2
  echo "Choose agent:" >&2
  echo "  1) gemini" >&2
  echo "  2) claude" >&2
  echo "  3) codex" >&2
  echo >&2
  while :; do
    read -r -p "Choice [3]: " choice >&2
    choice="${choice:-3}"
    case "${choice}" in
      1|gemini) printf '%s\n' "gemini"; return 0 ;;
      2|claude|clause) printf '%s\n' "claude"; return 0 ;;
      3|codex) printf '%s\n' "codex"; return 0 ;;
      *) echo "Invalid choice." >&2 ;;
    esac
  done
}

choose_agent_mode() {
  local agent="$1"
  local choice=""
  echo >&2
  echo "Choose launch mode for ${agent}:" >&2
  echo "  1) normal" >&2
  echo "  2) yolo / equivalent" >&2
  echo >&2
  while :; do
    read -r -p "Choice [2]: " choice >&2
    choice="${choice:-2}"
    case "${choice}" in
      1|normal) printf '%s\n' "normal"; return 0 ;;
      2|yolo) printf '%s\n' "yolo"; return 0 ;;
      *) echo "Invalid choice." >&2 ;;
    esac
  done
}

choose_handoff_action() {
  local choice=""
  echo >&2
  echo "Choose handoff behavior:" >&2
  echo "  1) execute-now (default)" >&2
  echo "  2) print-only (open shell, do not launch agent)" >&2
  echo >&2
  while :; do
    read -r -p "Choice [1]: " choice >&2
    choice="${choice:-1}"
    case "${choice}" in
      1|execute-now|execute) printf '%s\n' "execute-now"; return 0 ;;
      2|print-only|print) printf '%s\n' "print-only"; return 0 ;;
      *) echo "Invalid choice." >&2 ;;
    esac
  done
}

choose_issue_type() {
  local choice=""
  echo >&2
  echo "Choose issue type:" >&2
  echo "  1) execution (default)" >&2
  echo "  2) tracker" >&2
  echo >&2
  while :; do
    read -r -p "Choice [1]: " choice >&2
    choice="${choice:-1}"
    case "${choice}" in
      1|execution|exec) printf '%s\n' "execution"; return 0 ;;
      2|tracker) printf '%s\n' "tracker"; return 0 ;;
      *) echo "Invalid choice." >&2 ;;
    esac
  done
}

choose_closure_condition() {
  local issue_type="$1"
  local choice=""
  echo >&2
  echo "Choose closure condition for ${issue_type} issue:" >&2
  if [ "${issue_type}" = "tracker" ]; then
    echo "  1) child issues allocated / tracker updated (default)" >&2
    echo "  2) PR merged (docs/planning task)" >&2
    echo "  3) custom (type free-form)" >&2
  else
    echo "  1) PR merged (default)" >&2
    echo "  2) PR opened" >&2
    echo "  3) release tag" >&2
    echo "  4) custom (type free-form)" >&2
  fi
  echo >&2
  while :; do
    read -r -p "Choice [1]: " choice >&2
    choice="${choice:-1}"
    if [ "${issue_type}" = "tracker" ]; then
      case "${choice}" in
        1) printf '%s\n' "child issues allocated and tracker status updated"; return 0 ;;
        2) printf '%s\n' "PR merged to main"; return 0 ;;
        3|custom)
          prompt_nonempty "Custom closure condition: "
          return 0
          ;;
        *) echo "Invalid choice." >&2 ;;
      esac
    else
      case "${choice}" in
        1) printf '%s\n' "PR merged to main"; return 0 ;;
        2) printf '%s\n' "PR opened and issue moved to review"; return 0 ;;
        3) printf '%s\n' "release tag created"; return 0 ;;
        4|custom)
          prompt_nonempty "Custom closure condition: "
          return 0
          ;;
        *) echo "Invalid choice." >&2 ;;
      esac
    fi
  done
}

open_shell_in_worktree() {
  local wt_path="$1"
  local agent=""
  local agent_mode=""
  local issue_type=""
  local closure_condition=""
  local handoff_action=""
  local agent_prompt=""
  local agent_command=""

  agent="$(choose_agent)"
  agent_mode="$(choose_agent_mode "${agent}")"
  issue_type="$(choose_issue_type)"
  closure_condition="$(choose_closure_condition "${issue_type}")"
  handoff_action="$(choose_handoff_action)"
  agent_prompt="$(echo_agent_prompt_for_worktree "${wt_path}" "${issue_type}" "${closure_condition}")"
  agent_command="$(build_agent_command "${agent}" "${agent_mode}" "${agent_prompt}")"

  echo
  echo "Opening shell in ${wt_path}"
  echo "Boilerplate prompt (copy/edit if needed):"
  echo "${agent_prompt}"
  if [ "${handoff_action}" = "execute-now" ]; then
    echo "Final line below is the ${agent} launch command (${agent_mode}); it will be executed immediately."
  else
    echo "Final line below is the ${agent} launch command (${agent_mode}); print-only mode will open a shell without executing it."
  fi
  cd "${wt_path}"
  echo "${agent_command}"
  if [ "${handoff_action}" = "execute-now" ]; then
    exec bash -lc "${agent_command}"
  fi
  exec "${SHELL:-bash}" -l
}

run_command_in_worktree() {
  local wt_path="$1"
  local command_str=""
  read -r -p "Command to run in ${wt_path} (blank to cancel): " command_str
  if [ -z "${command_str}" ]; then
    echo "No command entered."
    return 0
  fi
  echo
  echo "Running command in ${wt_path}: ${command_str}"
  (cd "${wt_path}" && bash -lc "${command_str}")
}

create_worktree() {
  local base_dir
  local suggested_name
  local worktree_name
  local scope=""
  local scope_suggestion="task"
  local issue_source
  local issue_id
  local issue_title=""
  local issue_labels=""
  local queue_pick=""
  local auto_claim="no"
  local ready_stream_label=""
  local derived_slug=""
  local slug
  local branch_name
  local wt_path
  local start_ref

  base_dir="$(prompt_with_default "Base directory for linked worktrees" "${WORKTREE_BASE_DIR_DEFAULT}")"
  suggested_name="$(suggest_next_worktree_name)"
  worktree_name="$(prompt_with_default "Worktree folder name" "${suggested_name}")"
  issue_source="$(choose_issue_source)"

  if [ "${issue_source}" = "queue" ]; then
    ready_stream_label="$(choose_ready_queue_stream_label)"
    if queue_pick="$(choose_ready_issue_from_queue "${ready_stream_label}")"; then
      issue_id="$(printf '%s' "${queue_pick}" | cut -f1)"
      issue_title="$(printf '%s' "${queue_pick}" | cut -f2-)"
      issue_labels="$(printf '%s' "${queue_pick}" | cut -f3-)"
      scope_suggestion="$(infer_scope_from_issue "${issue_title}" "${issue_labels}")"
      derived_slug="$(derive_slug_from_issue_title "${issue_title}")"
      auto_claim="$(choose_auto_claim)"
      echo
      echo "Selected ready issue: #${issue_id} ${issue_title}"
      scope="$(choose_scope "${scope_suggestion}")"
      slug="$(prompt_with_default "Slug (derived from issue title)" "${derived_slug}")"
    else
      echo "Falling back to manual issue entry."
      issue_id="$(prompt_nonempty "GitHub issue number: ")"
      scope="$(choose_scope "task")"
      slug="$(prompt_nonempty "Slug (lowercase, hyphenated): ")"
    fi
  else
    issue_id="$(prompt_nonempty "GitHub issue number: ")"
    scope="$(choose_scope "task")"
    slug="$(prompt_nonempty "Slug (lowercase, hyphenated): ")"
  fi

  if ! validate_branch_parts "${scope}" "${issue_id}" "${slug}"; then
    return 1
  fi

  branch_name="wt/${scope}/${issue_id}-${slug}"
  if [[ ! "${branch_name}" =~ ${WORKTREE_BRANCH_REGEX} ]]; then
    echo "ERROR: branch '${branch_name}' does not match policy regex ${WORKTREE_BRANCH_REGEX}"
    return 1
  fi

  wt_path="${base_dir%/}/${worktree_name}"
  if [ -e "${wt_path}" ]; then
    echo "ERROR: path already exists: ${wt_path}"
    return 1
  fi

  if git show-ref --verify --quiet refs/remotes/origin/main; then
    start_ref="origin/main"
  else
    start_ref="${REQUIRED_MAIN_BRANCH}"
  fi
  start_ref="$(prompt_with_default "Start ref" "${start_ref}")"

  if git show-ref --verify --quiet "refs/heads/${branch_name}"; then
    echo "ERROR: local branch already exists: ${branch_name}"
    return 1
  fi

  mkdir -p "${base_dir}"

  echo
  echo "Creating worktree:"
  echo "  path:   ${wt_path}"
  echo "  branch: ${branch_name}"
  echo "  from:   ${start_ref}"
  echo

  git worktree add "${wt_path}" -b "${branch_name}" "${start_ref}"

  run_preflight_in_worktree "${wt_path}"

  if [ "${auto_claim}" = "yes" ]; then
    claim_issue_in_progress "${issue_id}" || true
  fi

  local next_action=""
  echo
  echo "Next action:"
  echo "  1) Open shell in new worktree"
  echo "  2) Run a command in new worktree"
  echo "  3) Return to menu"
  read -r -p "Choice [1]: " next_action
  next_action="${next_action:-1}"

  case "${next_action}" in
    1) open_shell_in_worktree "${wt_path}" ;;
    2) run_command_in_worktree "${wt_path}" ;;
    3) ;;
    *) echo "Unknown choice; returning to menu." ;;
  esac
}

resume_worktree_open_shell() {
  local wt_path=""
  if ! wt_path="$(choose_worktree_path false)"; then
    return 0
  fi
  run_preflight_in_worktree "${wt_path}"
  open_shell_in_worktree "${wt_path}"
}

resume_worktree_run_command() {
  local wt_path=""
  if ! wt_path="$(choose_worktree_path false)"; then
    return 0
  fi
  run_preflight_in_worktree "${wt_path}"
  run_command_in_worktree "${wt_path}"
}

main_menu() {
  while :; do
    echo "Worktree Session Menu"
    echo "  1) List worktrees"
    echo "  2) Create new worktree"
    echo "  3) Resume worktree (preflight + shell)"
    echo "  4) Resume worktree (preflight + command)"
    echo "  5) Preflight current worktree"
    echo "  6) Exit"
    echo

    local choice=""
    read -r -p "Choice: " choice
    echo

    case "${choice}" in
      1)
        print_worktree_table
        pause
        ;;
      2)
        create_worktree || true
        echo
        ;;
      3)
        resume_worktree_open_shell
        ;;
      4)
        resume_worktree_run_command
        pause
        ;;
      5)
        run_preflight_in_worktree "$(pwd -P)"
        pause
        ;;
      6)
        exit 0
        ;;
      *)
        echo "Invalid choice."
        echo
        ;;
    esac
  done
}

main_menu
