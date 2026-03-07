#!/usr/bin/env bash
set -euo pipefail

REAL_TASK_MASTER="/usr/local/share/npm-global/bin/task-master"

# ---------- helpers ----------

find_tasks_json() {
  local dir="${PWD}"
  while [[ "${dir}" != "/" ]]; do
    if [[ -f "${dir}/.taskmaster/tasks/tasks.json" ]]; then
      echo "${dir}/.taskmaster/tasks/tasks.json"
      return 0
    fi
    dir="$(dirname "${dir}")"
  done
  # fallback
  if [[ -f "/workspace/.taskmaster/tasks/tasks.json" ]]; then
    echo "/workspace/.taskmaster/tasks/tasks.json"
    return 0
  fi
  echo "ERROR: Could not find .taskmaster/tasks/tasks.json" >&2
  return 1
}

iso_now() {
  date -u +"%Y-%m-%dT%H:%M:%SZ"
}

# ---------- intercept logic ----------

do_update_task() {
  local task_id=""
  local prompt_text=""
  local title_text=""
  local description_text=""
  local details_text=""
  local replace_mode=false
  local file_override=""
  local positional_id=""

  # Parse arguments
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --id=*)
        task_id="${1#--id=}"
        shift
        ;;
      --id)
        shift
        task_id="${1:-}"
        shift
        ;;
      --prompt=*)
        prompt_text="${1#--prompt=}"
        shift
        ;;
      --prompt)
        shift
        prompt_text="${1:-}"
        shift
        ;;
      --description=*)
        description_text="${1#--description=}"
        shift
        ;;
      --description)
        shift
        description_text="${1:-}"
        shift
        ;;
      --title=*)
        title_text="${1#--title=}"
        shift
        ;;
      --title)
        shift
        title_text="${1:-}"
        shift
        ;;
      --details=*)
        details_text="${1#--details=}"
        shift
        ;;
      --details)
        shift
        details_text="${1:-}"
        shift
        ;;
      --replace)
        replace_mode=true
        shift
        ;;
      --file=*)
        file_override="${1#--file=}"
        shift
        ;;
      --file)
        shift
        file_override="${1:-}"
        shift
        ;;
      -*)
        # skip unknown flags (consume value if next arg is not a flag)
        shift
        if [[ $# -gt 0 && ! "$1" =~ ^- ]]; then
          shift
        fi
        ;;
      *)
        # positional arg -- could be numeric task ID for "update <id>" form
        if [[ -z "${positional_id}" && "$1" =~ ^[0-9]+$ ]]; then
          positional_id="$1"
        fi
        shift
        ;;
    esac
  done

  # Resolve task ID: explicit --id wins, then positional
  if [[ -z "${task_id}" ]]; then
    task_id="${positional_id}"
  fi

  if [[ -z "${task_id}" ]]; then
    echo "ERROR: No task ID provided. Use --id=<N> or pass ID as positional arg." >&2
    return 1
  fi

  # Resolve tasks.json path
  local tasks_file
  if [[ -n "${file_override}" ]]; then
    tasks_file="${file_override}"
  else
    tasks_file="$(find_tasks_json)"
  fi

  if [[ ! -f "${tasks_file}" ]]; then
    echo "ERROR: Tasks file not found: ${tasks_file}" >&2
    return 1
  fi

  # Detect the top-level key dynamically
  local top_key
  top_key="$(jq -r 'keys[0]' "${tasks_file}")"

  # Verify task exists
  local task_exists
  task_exists="$(jq -r --arg key "${top_key}" --arg id "${task_id}" \
    '.[$key].tasks[] | select(.id == $id or (.id | tonumber? // empty) == ($id | tonumber? // empty)) | .id' \
    "${tasks_file}" 2>/dev/null | head -1)"

  if [[ -z "${task_exists}" ]]; then
    echo "ERROR: Task ${task_id} not found in ${tasks_file}" >&2
    return 1
  fi

  # Treat --prompt as description if no explicit --description given
  if [[ -n "${prompt_text}" && -z "${description_text}" ]]; then
    description_text="${prompt_text}"
  fi

  # Nothing to update?
  if [[ -z "${description_text}" && -z "${title_text}" && -z "${details_text}" ]]; then
    echo "ERROR: Nothing to update. Provide --prompt, --description, --title, or --details." >&2
    return 1
  fi

  local now
  now="$(iso_now)"
  local tmp_file
  tmp_file="$(mktemp "${tasks_file}.XXXXXX")"

  # Build the jq filter dynamically
  local jq_filter=""
  local updated_fields=()

  # Helper: build append-or-replace expression for a field
  # $1 = field name, $2 = jq variable name
  build_field_expr() {
    local field="$1"
    local var="$2"
    if [[ "${replace_mode}" == true ]]; then
      echo ".${field} = \$${var}"
    else
      echo "if (.${field} // \"\") == \"\" then .${field} = \$${var} else .${field} = (.${field} + \"\\n\\n\" + \$${var}) end"
    fi
  }

  if [[ -n "${title_text}" ]]; then
    if [[ -n "${jq_filter}" ]]; then jq_filter="${jq_filter} | "; fi
    jq_filter="${jq_filter}.title = \$newtitle"
    updated_fields+=("title")
  fi

  if [[ -n "${description_text}" ]]; then
    if [[ -n "${jq_filter}" ]]; then jq_filter="${jq_filter} | "; fi
    jq_filter="${jq_filter}$(build_field_expr "description" "newdesc")"
    updated_fields+=("description")
  fi

  if [[ -n "${details_text}" ]]; then
    if [[ -n "${jq_filter}" ]]; then jq_filter="${jq_filter} | "; fi
    jq_filter="${jq_filter}$(build_field_expr "details" "newdetails")"
    updated_fields+=("details")
  fi

  # Always set updatedAt
  jq_filter="${jq_filter} | .updatedAt = \$now"

  # Full jq expression: walk into the correct task and apply updates
  local full_filter
  full_filter="(.${top_key}.tasks[] | select(.id == \$id or (.id | tonumber? // empty) == (\$id | tonumber? // empty))) |= (${jq_filter})"

  # Build jq args
  local -a jq_args=()
  jq_args+=(--arg id "${task_id}")
  jq_args+=(--arg now "${now}")
  if [[ -n "${title_text}" ]]; then
    jq_args+=(--arg newtitle "${title_text}")
  fi
  if [[ -n "${description_text}" ]]; then
    jq_args+=(--arg newdesc "${description_text}")
  fi
  if [[ -n "${details_text}" ]]; then
    jq_args+=(--arg newdetails "${details_text}")
  fi

  if jq "${jq_args[@]}" "${full_filter}" "${tasks_file}" > "${tmp_file}"; then
    mv "${tmp_file}" "${tasks_file}"
    local fields_str
    fields_str="$(printf '%s' "${updated_fields[0]}"; for f in "${updated_fields[@]:1}"; do printf ', %s' "$f"; done)"
    echo "Updated task ${task_id}: ${fields_str} updated"
  else
    rm -f "${tmp_file}"
    echo "ERROR: jq failed to update task ${task_id}" >&2
    return 1
  fi
}

# ---------- main dispatch ----------

if [[ $# -eq 0 ]]; then
  exec "${REAL_TASK_MASTER}" "$@"
fi

cmd="$1"

case "${cmd}" in
  update-task)
    shift
    do_update_task "$@"
    ;;
  update)
    # Only intercept if the next arg looks like a numeric task ID
    # (real "update" without a numeric ID is a bulk command -- pass through)
    if [[ $# -ge 2 && "$2" =~ ^[0-9]+$ ]]; then
      shift  # remove "update"
      do_update_task "$@"
    else
      exec "${REAL_TASK_MASTER}" "$@"
    fi
    ;;
  *)
    exec "${REAL_TASK_MASTER}" "$@"
    ;;
esac
