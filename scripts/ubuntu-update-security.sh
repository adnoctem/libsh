#!/usr/bin/env bash
#
# Apply only the pending security updates of an Ubuntu/Debian system.

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

# shellcheck source=lib/apt.sh
. "$LIB_DIR"/apt.sh

# shellcheck source=lib/ui.sh
. "$LIB_DIR"/ui.sh

# -------------------------
#   Flag spec
# -------------------------

OPTS=(
  ",--skip-refresh:skip_refresh:0:optional"
  "-y,--yes:assume_yes:0:optional"
  "-h,--help:help:0:optional"
  ",--dry-run:dry_run:0:optional"
  ",--check-prerequisites:check_prerequisites:0:optional"
)

declare -A OPTS_HELP=(
  [skip_refresh]="Skip 'apt-get update' and work from the package lists as they are"
  [assume_yes]="Skip the confirmation prompt (required for unattended runs, e.g. from cron)"
  [dry_run]="Print the packages that would be upgraded, without changing anything"
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
function ubuntu_update_security::prerequisites() {
  local prerequisites=('apt-get' 'awk')

  # Installing packages needs root, which is 'sudo' unless the script is
  # already running as it.
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

  lib::log::green "Found all prerequisites: '${prerequisites[*]}' in system PATH. Ready to proceed!"
  return 0
}

#######################################
# Upgrade the named packages and nothing else.
#
# '--only-upgrade' keeps apt from pulling in packages that are not
# installed yet; dependencies of the upgraded packages are still resolved,
# which is the intended behaviour -- a security fix that needs a newer
# library is not much use without it.
# Globals:
#   None
# Arguments:
#   1 - "1" for a dry run, "" otherwise
#   2+ - Package names to upgrade
# Outputs:
#   apt-get's output to stdout.
# Returns:
#   0 on success, otherwise the return value of 'apt-get'.
#######################################
function ubuntu_update_security::exec() {
  local dry_run=${1}
  shift
  local -a packages=("$@")

  local -a upgrade_cmd=(apt-get -y --only-upgrade install "${packages[@]}")

  if [[ $dry_run == "1" ]]; then
    lib::log::yellow "[dry-run] ${upgrade_cmd[*]}"
    return 0
  fi

  lib::log::timed_yellow "Upgrading ${#packages[@]} package(s) from the security pocket ..."

  # DEBIAN_FRONTEND keeps a stray dpkg prompt from hanging an unattended
  # run, which is the point of this script existing separately.
  lib::permissions::run_as_root env DEBIAN_FRONTEND=noninteractive "${upgrade_cmd[@]}"

  lib::log::timed_green "Finished applying security updates."

  if lib::apt::reboot_required; then
    lib::log::yellow "A reboot is required to finish applying these updates (/var/run/reboot-required)."
  fi
}

# --------------------------------
#   MAIN
# --------------------------------

#######################################
# Parse the flags, find the pending security updates, confirm, then apply
# just those.
# Globals:
#   OPTS, OPTS_HELP (read)
#   OPTS_VALUES (written by lib::opts::parse)
# Arguments:
#   The script's original "$@"
# Returns:
#   0 on success or when nothing is pending, 1 on a usage or confirmation
#   error.
#######################################
function main() {
  local arg skip_refresh assume_yes dry_run simulation package
  local -a packages=()

  # --check-prerequisites answers on its own, before the parser can reject
  # the run for the required flags a prerequisite check has no use for.
  for arg in "$@"; do
    if [[ $arg == "--check-prerequisites" ]]; then
      ubuntu_update_security::prerequisites
      return $?
    fi
  done

  lib::opts::parse "$@" || return 1

  skip_refresh="${OPTS_VALUES[skip_refresh]:-}"
  assume_yes="${OPTS_VALUES[assume_yes]:-}"
  dry_run="${OPTS_VALUES[dry_run]:-}"

  if [[ $dry_run == "1" || $skip_refresh == "1" ]]; then
    lib::log::yellow "Working from the current package lists; they may be stale."
  else
    lib::log::timed_yellow "Refreshing package lists ..."
    lib::permissions::run_as_root apt-get update
  fi

  simulation=$(lib::apt::simulate upgrade || true)

  while IFS= read -r package; do
    [[ -z $package ]] && continue
    packages+=("$package")
  done < <(printf '%s\n' "$simulation" | lib::apt::security_packages)

  if [[ ${#packages[@]} -eq 0 ]]; then
    lib::log::timed_green "No pending security updates."
    return 0
  fi

  lib::log::yellow "${#packages[@]} package(s) with security updates pending:"
  for package in "${packages[@]}"; do
    lib::log::plain "  - $package"
  done

  if [[ $dry_run != "1" && $assume_yes != "1" ]]; then
    # No default, so an unattended run without --yes stops here instead of
    # upgrading a production machine nobody was watching.
    if ! lib::ui::confirm "Apply these security updates?"; then
      lib::log::red "Aborted; nothing was upgraded."
      return 1
    fi
  fi

  ubuntu_update_security::exec "$dry_run" "${packages[@]}"
}

# ------------
# 'main' call
# ------------
main "$@"
