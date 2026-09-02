#!/usr/bin/env bash
#
# Report the pending updates of an Ubuntu/Debian system, changing nothing.

set -euo pipefail

# Mitigate potential path issues depending on where you're running the script from
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# shellcheck source=lib/log.sh
. "$LIB_DIR"/log.sh

# shellcheck source=lib/opts.sh
. "$LIB_DIR"/opts.sh

# shellcheck source=lib/package.sh
. "$LIB_DIR"/package.sh

# shellcheck source=lib/apt.sh
. "$LIB_DIR"/apt.sh

# -------------------------
#   Flag spec
# -------------------------

OPTS=(
  ",--fail-on:fail_on:1:optional"
  ",--max-list-age:max_list_age:1:optional"
  "-h,--help:help:0:optional"
  ",--check-prerequisites:check_prerequisites:0:optional"
)

declare -A OPTS_HELP=(
  [fail_on]="What makes the exit code non-zero: any, security, reboot or never (default: any)"
  [max_list_age]="Warn when the package lists are older than this many days (default: 7)"
  [check_prerequisites]="Check that the required packages are installed, then exit"
  [help]="Show this help message and exit"
)

declare -A OPTS_VALUES=()

#######################################
# Check if the prerequisites for the
# script are installed.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   One line per prerequisite to stdout.
# Returns:
#   0 if all prerequisites were found, 1 otherwise.
#######################################
function ubuntu_test_updates::prerequisites() {
  local prerequisites=('apt-get' 'awk' 'stat')

  for prerequisite in "${prerequisites[@]}"; do
    if ! lib::package::is_executable "${prerequisite}"; then
      lib::log::red "Could not find package '${prerequisite}' in system PATH. Please install '${prerequisite}' to proceed!"
      return 1
    fi

    lib::log::green "Found package '${prerequisite}' in system PATH."
  done

  lib::log::green "Found all prerequisites: '${prerequisites[*]}' in system PATH. Ready to proceed!"
  lib::log::yellow "This script never needs root: it only simulates, and 'apt-get -s' is unprivileged."
  return 0
}

# --------------------------------
#   MAIN
# --------------------------------

#######################################
# Report pending updates, pending security updates, the age of the package
# lists and whether a reboot is due.
#
# Nothing here writes: the package lists are read as they are, so a stale
# list is reported rather than silently refreshed. Refreshing needs root and
# would make this a different verb.
# Globals:
#   OPTS, OPTS_HELP (read)
#   OPTS_VALUES (written by lib::opts::parse)
# Arguments:
#   The script's original "$@"
# Returns:
#   0 when nothing --fail-on names is outstanding, 1 when something is,
#   2 on a usage error.
#######################################
function main() {
  local arg fail_on max_list_age simulation age reboot="" summary
  local total=0 security=0

  # --check-prerequisites answers on its own, before the parser can reject
  # the run for the required flags a prerequisite check has no use for.
  for arg in "$@"; do
    if [[ $arg == "--check-prerequisites" ]]; then
      ubuntu_test_updates::prerequisites
      return $?
    fi
  done

  lib::opts::parse "$@" || return 2

  fail_on="${OPTS_VALUES[fail_on]:-any}"
  max_list_age="${OPTS_VALUES[max_list_age]:-7}"

  case "$fail_on" in
  any | security | reboot | never) ;;
  *)
    lib::log::red "Invalid --fail-on '$fail_on'; expected one of any, security, reboot, never."
    return 2
    ;;
  esac

  if [[ ! $max_list_age =~ ^[0-9]+$ ]]; then
    lib::log::red "Invalid --max-list-age '$max_list_age'; expected a number of days."
    return 2
  fi

  simulation=$(lib::apt::simulate upgrade || true)
  total=$(printf '%s\n' "$simulation" | lib::apt::pending_packages | grep -c . || true)
  security=$(printf '%s\n' "$simulation" | lib::apt::security_packages | grep -c . || true)
  summary=$(printf '%s\n' "$simulation" | lib::apt::summary_line)

  age=$(lib::apt::lists_age_days || true)

  if [[ $age == "-1" ]]; then
    lib::log::yellow "Could not determine when the package lists were last refreshed."
  elif [[ $age -gt $max_list_age ]]; then
    lib::log::yellow "Package lists are $age day(s) old (limit: $max_list_age); the counts below may understate reality."
  else
    lib::log::green "Package lists are $age day(s) old."
  fi

  if [[ $total -eq 0 ]]; then
    lib::log::green "No pending updates."
  else
    lib::log::yellow "$total pending update(s), $security of them from a security pocket."

    if [[ -n $summary ]]; then
      lib::log::plain "  $summary"
    fi

    if [[ $security -gt 0 ]]; then
      lib::log::yellow "Security updates pending:"
      printf '%s\n' "$simulation" | lib::apt::security_packages | sed 's/^/  - /'
    fi
  fi

  if lib::apt::reboot_required; then
    reboot="1"
    lib::log::yellow "A reboot is required to finish applying earlier updates."
  else
    lib::log::green "No reboot required."
  fi

  case "$fail_on" in
  any)
    [[ $total -gt 0 || -n $reboot ]] && return 1
    ;;
  security)
    [[ $security -gt 0 ]] && return 1
    ;;
  reboot)
    [[ -n $reboot ]] && return 1
    ;;
  never) ;;
  esac

  return 0
}

# ------------
# 'main' call
# ------------
main "$@"
