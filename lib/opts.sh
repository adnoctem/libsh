# shellcheck shell=bash

# lib::opts -- shared argument parser for all libsh scripts.
#
# Calling convention
# -------------------
# The calling script defines three globals *before* invoking
# lib::opts::parse, and reads results from a fourth populated by it:
#
#   OPTS=(
#     "-u,--username:username:1:required"
#     "-p,--password:password:1:optional"
#     "--dry-run:dry_run:0:optional"
#     "-h,--help:help:0:optional"
#   )
#   declare -A OPTS_HELP=(
#     [username]="Database username to connect with"
#     [password]="Database password (prefer MYSQL_PWD env var)"
#     [dry_run]="Print what would run without executing it"
#     [help]="Show this help message and exit"
#   )
#   declare -A OPTS_VALUES=()
#
#   lib::opts::parse "$@" || exit 1
#
# Spec entry format (colon-separated fields; first field is
# comma-separated short,long -- either may be omitted, not both):
#
#   "<short>,<long>:<key>:<takes_value: 0|1>:<required|optional>"
#
# After a successful parse:
#   - value flags:   OPTS_VALUES[<key>] holds the supplied string
#   - boolean flags: OPTS_VALUES[<key>] is "1" if passed, unset otherwise
#   - a spec entry whose <key> is literally "help" triggers
#     lib::opts::usage and `exit 0` immediately, before validation
#   - missing "required" entries print an error + usage and return 1
#
# Requires bash >= 4 (associative arrays). No nameref usage, so it also
# works on bash 4.0-4.2 where `local -n` is unavailable.

#######################################
# Print usage/help text derived entirely from OPTS + OPTS_HELP, so the
# help output can never drift out of sync with what's actually parsed.
# Globals:
#   OPTS, OPTS_HELP (read)
# Arguments:
#   None
# Outputs:
#   Writes usage to stdout
#######################################
function lib::opts::usage() {
  local script_name
  script_name=$(basename "${0}")
  echo "Usage: $script_name [OPTIONS]"
  echo

  local entry flags key takes_value required short long label
  for entry in "${OPTS[@]}"; do
    IFS=':' read -r flags key takes_value required <<<"$entry"
    IFS=',' read -r short long <<<"$flags"

    label=""
    [[ -n $short ]] && label="$short"
    if [[ -n $long ]]; then
      [[ -n $label ]] && label+=", "
      label+="$long"
    fi
    [[ $takes_value == "1" ]] && label+=" <value>"
    [[ $required == "required" ]] && label+=" (required)"

    printf "  %-32s %s\n" "$label" "${OPTS_HELP[$key]:-}"
  done
}

#######################################
# Parse "$@" against the OPTS spec into OPTS_VALUES.
# Globals:
#   OPTS       (read)  -- spec, defined by the calling script
#   OPTS_HELP  (read)  -- descriptions, defined by the calling script
#   OPTS_VALUES (write, reset at the start of every call)
# Arguments:
#   The script's original "$@"
# Returns:
#   0 on success. 1 on an unknown flag, a value flag missing its value,
#   or a required flag not supplied (each case prints an error first).
# Outputs:
#   Nothing on success. Errors to stderr via lib::log::red on failure.
#   Calls lib::opts::usage + exit 0 immediately if a "help" key is hit.
#######################################
function lib::opts::parse() {
  OPTS_VALUES=()

  while [[ $# -gt 0 ]]; do
    local matched=0
    local entry flags key takes_value required short long

    for entry in "${OPTS[@]}"; do
      IFS=':' read -r flags key takes_value required <<<"$entry"
      IFS=',' read -r short long <<<"$flags"

      if { [[ -n $short ]] && [[ $1 == "$short" ]]; } ||
        { [[ -n $long ]] && [[ $1 == "$long" ]]; }; then
        matched=1

        if [[ $key == "help" ]]; then
          lib::opts::usage
          exit 0
        fi

        if [[ $takes_value == "1" ]]; then
          if [[ $# -lt 2 ]]; then
            lib::log::red "Option '$1' requires a value."
            return 1
          fi
          OPTS_VALUES["$key"]="$2"
          shift 2
        else
          OPTS_VALUES["$key"]=1
          shift
        fi
        break
      fi
    done

    if [[ $matched -eq 0 ]]; then
      lib::log::red "Unknown option: $1"
      return 1
    fi
  done

  local missing=()
  local m_entry m_flags m_key m_takes_value m_required m_short m_long
  for m_entry in "${OPTS[@]}"; do
    # shellcheck disable=SC2034  # takes_value isn't needed for this pass
    IFS=':' read -r m_flags m_key m_takes_value m_required <<<"$m_entry"
    if [[ $m_required == "required" && -z ${OPTS_VALUES[$m_key]:-} ]]; then
      IFS=',' read -r m_short m_long <<<"$m_flags"
      missing+=("${m_long:-$m_short}")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    lib::log::red "Missing required option(s): ${missing[*]}"
    echo
    lib::opts::usage
    return 1
  fi

  return 0
}
