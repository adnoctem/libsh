#!/usr/bin/env bash
#
# Update the installed packages of an Ubuntu/Debian system.

set -euo pipefail

# Mitigate potential path issues depending on where you're running the script from
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

# An explicit installation takes precedence; a checkout bootstraps itself.
LIB_DIR=${LIBSH_DIR:-"$(dirname "$SCRIPT_DIR")/lib"}
if [[ ! -r $LIB_DIR/lib.sh ]]; then
  printf 'Cannot read libsh at %s/lib.sh; set LIBSH_DIR or provide the local lib directory.\n' "$LIB_DIR" >&2
  exit 1
fi
LIB_DIR=$(cd -P -- "$LIB_DIR" && pwd)
# shellcheck source=lib/lib.sh
. "$LIB_DIR/lib.sh"
if ! declare -F lib::load >/dev/null || ! declare -F lib::load_extensions >/dev/null; then
  printf 'Incompatible libsh at %s: this script requires the core/extension loader. Update the installation, or set LIBSH_DIR to this checkout\047s lib directory.\n' "$LIB_DIR" >&2
  exit 1
fi
lib::load_extensions apt ui

# -------------------------
#   Flag spec
# -------------------------

# shellcheck disable=SC2034 # read by the dynamically loaded option parser
OPTS=(
  ",--full-upgrade:full_upgrade:0:optional"
  ",--autoremove:autoremove:0:optional"
  "-y,--yes:assume_yes:0:optional"
  "-h,--help:help:0:optional"
  ",--dry-run:dry_run:0:optional"
  ",--check-prerequisites:check_prerequisites:0:optional"
)

# shellcheck disable=SC2034 # read by the dynamically loaded option parser
declare -A OPTS_HELP=(
  [full_upgrade]="Use 'full-upgrade', which may add and remove packages to satisfy dependencies"
  [autoremove]="Remove packages that are no longer required once the upgrade is done"
  [assume_yes]="Skip the confirmation prompt (required for unattended runs)"
  [dry_run]="Simulate the upgrade with 'apt-get -s' and print what it would change"
  [check_prerequisites]="Check that the required packages are installed, then exit"
  [help]="Show this help message and exit"
)

declare -A OPTS_VALUES=()

#######################################
# Check if the prerequisites for the
# script are installed.
# Globals:
#   EUID (read)
# Arguments:
#   None
# Outputs:
#   One line per prerequisite to stdout.
# Returns:
#   0 if all prerequisites were found, 1 otherwise.
#######################################
function ubuntu_update_packages::prerequisites() {
  local prerequisites=('apt-get')

  # Everything below the simulation needs root, which is 'sudo' unless the
  # script is already running as it.
  if [[ $EUID -ne 0 ]]; then
    prerequisites+=('sudo')
  fi

  for prerequisite in "${prerequisites[@]}"; do
    if ! lib::os::is_executable "${prerequisite}"; then
      lib::log::red "Could not find package '${prerequisite}' in system PATH. Please install '${prerequisite}' to proceed!"
      return 1
    fi

    lib::log::green "Found package '${prerequisite}' in system PATH."
  done

  lib::log::green "Found all prerequisites: '${prerequisites[*]}' in system PATH. Ready to proceed!"
  return 0
}

#######################################
# Refresh the package lists and report what an upgrade would change.
# Globals:
#   None
# Arguments:
#   1 - Upgrade action: "upgrade" or "full-upgrade"
#   2 - "1" for a dry run, "" otherwise
# Outputs:
#   apt-get's own summary line to stdout.
# Returns:
#   0 if there is something to upgrade, 1 if the system is already current.
#######################################
function ubuntu_update_packages::plan() {
  local action=${1} dry_run=${2}
  local summary

  if [[ $dry_run == "1" ]]; then
    lib::log::yellow "[dry-run] skipping 'apt-get update'; simulating against the current package lists."
  else
    lib::log::timed_yellow "Refreshing package lists ..."
    lib::os::root_exec apt-get update
  fi

  # Simulating needs no privileges, so it is safe to run before asking the
  # operator to commit to anything.
  summary=$(ext::apt::simulate "$action" | ext::apt::summary_line || true)

  if [[ -z $summary ]]; then
    lib::log::yellow "Could not read an upgrade summary from apt-get; continuing anyway."
    return 0
  fi

  lib::log::green "$summary"

  if [[ $summary =~ ^0\ upgraded,\ 0\ newly\ installed ]]; then
    return 1
  fi

  return 0
}

#######################################
# Run the upgrade itself.
# Globals:
#   None
# Arguments:
#   1 - Upgrade action: "upgrade" or "full-upgrade"
#   2 - "1" to also run 'autoremove', "" otherwise
#   3 - "1" for a dry run, "" otherwise
# Outputs:
#   apt-get's output to stdout.
# Returns:
#   0 on success, otherwise the return value of 'apt-get'.
#######################################
function ubuntu_update_packages::exec() {
  local action=${1} autoremove=${2} dry_run=${3}

  if [[ $dry_run == "1" ]]; then
    lib::log::yellow "[dry-run] apt-get -s $action"
    apt-get -s "$action"

    if [[ $autoremove == "1" ]]; then
      lib::log::yellow "[dry-run] apt-get -s autoremove"
      apt-get -s autoremove
    fi

    return 0
  fi

  # The operator already confirmed, so apt gets '-y' rather than asking a
  # second time. DEBIAN_FRONTEND keeps a stray dpkg prompt from hanging an
  # unattended run.
  lib::log::timed_yellow "Running 'apt-get $action' ..."
  lib::os::root_exec env DEBIAN_FRONTEND=noninteractive apt-get -y "$action"

  if [[ $autoremove == "1" ]]; then
    lib::log::timed_yellow "Removing packages that are no longer required ..."
    lib::os::root_exec env DEBIAN_FRONTEND=noninteractive apt-get -y autoremove
  fi

  lib::log::timed_green "Finished updating packages with 'apt-get $action'."

  # Worth surfacing because an unattended fleet upgrade otherwise hides it.
  if ext::apt::reboot_required; then
    lib::log::yellow "A reboot is required to finish applying these updates (/var/run/reboot-required)."
  fi
}

# --------------------------------
#   MAIN
# --------------------------------

#######################################
# Parse the flags, plan the upgrade, confirm, then run it.
# Globals:
#   OPTS, OPTS_HELP (read)
#   OPTS_VALUES (written by lib::opt::parse)
# Arguments:
#   The script's original "$@"
# Returns:
#   0 on success, 1 on a usage or confirmation error.
#######################################
function main() {
  local arg action autoremove dry_run assume_yes

  # --check-prerequisites answers on its own, before the parser can reject
  # the run for the required flags a prerequisite check has no use for.
  for arg in "$@"; do
    if [[ $arg == "--check-prerequisites" ]]; then
      ubuntu_update_packages::prerequisites
      return $?
    fi
  done

  lib::opt::parse "$@" || return 1
  [[ ${OPTS_VALUES[help]:-} != 1 ]] || return 0

  autoremove="${OPTS_VALUES[autoremove]:-}"
  dry_run="${OPTS_VALUES[dry_run]:-}"
  assume_yes="${OPTS_VALUES[assume_yes]:-}"
  action="upgrade"

  if [[ ${OPTS_VALUES[full_upgrade]:-} == "1" ]]; then
    action="full-upgrade"
  fi

  if ! ubuntu_update_packages::plan "$action" "$dry_run"; then
    lib::log::timed_green "Every package is already up to date; nothing to do."
    return 0
  fi

  if [[ $dry_run != "1" && $assume_yes != "1" ]]; then
    if [[ $action == "full-upgrade" ]]; then
      lib::log::yellow "'full-upgrade' may remove packages to satisfy new dependencies."
    fi

    # No default, so an unattended run without --yes stops here instead of
    # upgrading a production machine nobody was watching.
    if ! ext::ui::confirm "Apply these updates?"; then
      lib::log::red "Aborted; nothing was upgraded."
      return 1
    fi
  fi

  ubuntu_update_packages::exec "$action" "$autoremove" "$dry_run"
}

# ------------
# 'main' call
# ------------
main "$@"
