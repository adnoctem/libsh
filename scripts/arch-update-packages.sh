#!/usr/bin/env bash
#
# Update the installed packages of an Arch Linux system.

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

# shellcheck source=lib/permissions.sh
. "$LIB_DIR"/permissions.sh

# shellcheck source=lib/ui.sh
. "$LIB_DIR"/ui.sh

# -------------------------
#   Flag spec
# -------------------------

OPTS=(
  ",--skip-aur:skip_aur:0:optional"
  "-y,--yes:assume_yes:0:optional"
  "-h,--help:help:0:optional"
  ",--dry-run:dry_run:0:optional"
  ",--check-prerequisites:check_prerequisites:0:optional"
)

declare -A OPTS_HELP=(
  [skip_aur]="Update only the official repositories, leaving AUR packages alone"
  [assume_yes]="Skip the confirmation prompt (required for unattended runs)"
  [dry_run]="List the pending updates and print the commands, without running them"
  [check_prerequisites]="Check that the required packages are installed, then exit"
  [help]="Show this help message and exit"
)

declare -A OPTS_VALUES=()

# Kernel packages whose upgrade means the running system is out of date
# until the machine is rebooted.
readonly KERNEL_PACKAGES='^linux(-lts|-zen|-hardened|-rt|-rt-lts)?[[:space:]]'

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
function arch_update_packages::prerequisites() {
  local prerequisites=('pacman')
  local optional=('yay' 'checkupdates')

  # Upgrading the official repositories needs root, which is 'sudo' unless
  # the script is already running as it.
  if [[ $EUID -ne 0 ]]; then
    prerequisites+=('sudo')
  fi

  for prerequisite in "${prerequisites[@]}"; do
    if ! lib::package::is_executable "${prerequisite}"; then
      lib::log::red "Could not find package '${prerequisite}' in system PATH. Please install '${prerequisite}' to proceed!"
      return 1
    fi

    lib::log::green "Found package '${prerequisite}' in system PATH."
  done

  for prerequisite in "${optional[@]}"; do
    if lib::package::is_executable "${prerequisite}"; then
      lib::log::green "Found optional package '${prerequisite}' in system PATH."
    else
      lib::log::yellow "Optional package '${prerequisite}' is missing: AUR updates need 'yay', and without 'checkupdates' (pacman-contrib) the pending list is read from a possibly stale sync database."
    fi
  done

  lib::log::green "Found all prerequisites: '${prerequisites[*]}' in system PATH. Ready to proceed!"
  return 0
}

#######################################
# List the packages that an upgrade would install.
#
# 'checkupdates' syncs into a temporary database, so it can answer this
# without a 'pacman -Sy' that would leave the real database half-synced --
# the partial-upgrade state Arch warns about.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   One "<name> <old> -> <new>" line per pending package to stdout.
#######################################
function arch_update_packages::pending() {
  if lib::package::is_executable checkupdates; then
    # Exits 2 when there is nothing to do, which is not an error here.
    checkupdates 2>/dev/null || true
  else
    pacman -Qu 2>/dev/null || true
  fi
}

#######################################
# Run the upgrade itself.
# Globals:
#   EUID (read)
# Arguments:
#   1 - "1" to skip AUR packages, "" otherwise
#   2 - "1" to answer pacman/yay prompts automatically, "" otherwise
#   3 - "1" for a dry run, "" otherwise
# Outputs:
#   pacman's and yay's output to stdout.
# Returns:
#   0 on success, otherwise the return value of 'pacman' or 'yay'.
#######################################
function arch_update_packages::exec() {
  local skip_aur=${1} assume_yes=${2} dry_run=${3}
  local -a pacman_cmd=(pacman -Syu)
  local -a yay_cmd=(yay -Syu)

  # -Syu, never -Su: upgrading against a stale sync database is how a
  # partial upgrade happens.
  if [[ $assume_yes == "1" ]]; then
    pacman_cmd+=(--noconfirm)
    yay_cmd+=(--noconfirm)
  fi

  if [[ $dry_run == "1" ]]; then
    lib::log::yellow "[dry-run] ${pacman_cmd[*]}"

    if [[ $skip_aur != "1" ]]; then
      lib::log::yellow "[dry-run] ${yay_cmd[*]}"
    fi

    return 0
  fi

  lib::log::timed_yellow "Updating official packages with 'pacman' ..."
  lib::permissions::run_as_root "${pacman_cmd[@]}"

  if [[ $skip_aur == "1" ]]; then
    lib::log::timed_green "Finished updating packages; AUR skipped on request."
    return 0
  fi

  if ! lib::package::is_executable yay; then
    lib::log::yellow "'yay' is not installed; AUR packages were left alone."
    return 0
  fi

  if [[ $EUID -eq 0 ]]; then
    lib::log::yellow "Running as root, so AUR packages were left alone: 'yay' builds packages and refuses to run as root."
    return 0
  fi

  lib::log::timed_yellow "Updating AUR packages with 'yay' ..."
  "${yay_cmd[@]}"

  lib::log::timed_green "Finished updating official and AUR packages."
}

# --------------------------------
#   MAIN
# --------------------------------

#######################################
# Parse the flags, list what is pending, confirm, then upgrade.
# Globals:
#   OPTS, OPTS_HELP (read)
#   OPTS_VALUES (written by lib::opts::parse)
#   KERNEL_PACKAGES (read)
# Arguments:
#   The script's original "$@"
# Returns:
#   0 on success, 1 on a usage or confirmation error.
#######################################
function main() {
  local arg skip_aur assume_yes dry_run pending count kernel=""

  # --check-prerequisites answers on its own, before the parser can reject
  # the run for the required flags a prerequisite check has no use for.
  for arg in "$@"; do
    if [[ $arg == "--check-prerequisites" ]]; then
      arch_update_packages::prerequisites
      return $?
    fi
  done

  lib::opts::parse "$@" || return 1

  skip_aur="${OPTS_VALUES[skip_aur]:-}"
  assume_yes="${OPTS_VALUES[assume_yes]:-}"
  dry_run="${OPTS_VALUES[dry_run]:-}"

  lib::log::timed_yellow "Checking for pending updates ..."
  pending=$(arch_update_packages::pending)

  if [[ -z $pending ]]; then
    lib::log::timed_green "Every official package is already up to date."

    if [[ $skip_aur == "1" ]]; then
      return 0
    fi

    lib::log::yellow "AUR packages are not covered by this check; 'yay' resolves them during the upgrade."
  else
    count=$(printf '%s\n' "$pending" | wc -l)
    lib::log::yellow "$count package(s) pending:"
    printf '%s\n' "$pending" | head -n 20

    if [[ $count -gt 20 ]]; then
      lib::log::yellow "  ... and $((count - 20)) more."
    fi

    if printf '%s\n' "$pending" | grep -qE "$KERNEL_PACKAGES"; then
      kernel="1"
    fi
  fi

  if [[ $dry_run != "1" && $assume_yes != "1" ]]; then
    # No default, so an unattended run without --yes stops here instead of
    # upgrading a machine nobody was watching.
    if ! lib::ui::confirm "Apply these updates?"; then
      lib::log::red "Aborted; nothing was upgraded."
      return 1
    fi
  fi

  arch_update_packages::exec "$skip_aur" "$assume_yes" "$dry_run"

  if [[ -n $kernel && $dry_run != "1" ]]; then
    lib::log::yellow "The kernel was among the updated packages; reboot to run it."
  fi
}

# ------------
# 'main' call
# ------------
main "$@"
