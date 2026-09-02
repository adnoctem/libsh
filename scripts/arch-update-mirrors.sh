#!/usr/bin/env bash
#
# Refresh an Arch Linux system's pacman mirrorlist with 'reflector'.

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
  "-c,--countries:countries:1:optional"
  "-n,--latest:latest:1:optional"
  ",--protocol:protocol:1:optional"
  "-o,--output-file:output_file:1:optional"
  "-y,--yes:assume_yes:0:optional"
  "-h,--help:help:0:optional"
  ",--dry-run:dry_run:0:optional"
  ",--check-prerequisites:check_prerequisites:0:optional"
)

declare -A OPTS_HELP=(
  [countries]="Comma-separated countries to draw mirrors from (default: Germany,Netherlands,Sweden,Belgium,France,Austria)"
  [latest]="Keep only the N most recently synchronised mirrors (default: 10)"
  [protocol]="Mirror protocol: https, http, rsync or ftp (default: https)"
  [output_file]="Mirrorlist to write (default: /etc/pacman.d/mirrorlist)"
  [assume_yes]="Skip the confirmation prompt (required for unattended runs)"
  [dry_run]="Print the mirrorlist reflector would produce, without writing it"
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
function arch_update_mirrors::prerequisites() {
  local prerequisites=('reflector' 'diff')

  # Writing into /etc/pacman.d needs root, which is 'sudo' unless the
  # script is already running as it.
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
# Generate a mirrorlist and install it over the current one.
# Globals:
#   None
# Arguments:
#   1 - Comma-separated country list
#   2 - Number of mirrors to keep
#   3 - Mirror protocol
#   4 - Mirrorlist path to write
#   5 - "1" for a dry run, "" otherwise
#   6 - "1" to skip the confirmation, "" otherwise
# Outputs:
#   A unified diff of the change to stdout.
# Returns:
#   0 on success or when nothing needed changing, 1 on a reflector failure
#   or a declined confirmation.
#######################################
function arch_update_mirrors::exec() {
  local countries=${1} latest=${2} protocol=${3} filename=${4} dry_run=${5} assume_yes=${6}
  local generated backup rc=0

  generated=$(mktemp)
  # shellcheck disable=SC2064 # expanded now on purpose, so the trap holds this run's path
  trap "rm -f '$generated'" RETURN

  local -a reflector_cmd=(
    reflector
    --country "$countries"
    --protocol "$protocol"
    --latest "$latest"
    --save "$generated"
  )

  # reflector only needs root to write into /etc, so generating into a
  # temporary file first keeps the network query unprivileged -- and gives
  # us something to diff against.
  lib::log::timed_yellow "Querying mirrors from: $countries ..."
  "${reflector_cmd[@]}"

  if [[ ! -s $generated ]]; then
    lib::log::red "reflector returned no mirrors for '$countries' over $protocol."
    return 1
  fi

  lib::log::green "reflector returned $(grep -c '^Server' "$generated") mirror(s)."

  if [[ $dry_run == "1" ]]; then
    lib::log::yellow "[dry-run] the mirrorlist below would be written to '$filename':"
    cat "$generated"
    return 0
  fi

  if [[ -f $filename ]]; then
    # 'diff' exits 1 when the files differ, which is the interesting case
    # here rather than an error.
    diff -u -- "$filename" "$generated" >/dev/null 2>&1 || rc=$?

    if [[ $rc -eq 0 ]]; then
      lib::log::green "'$filename' is already identical to the generated list; nothing to change."
      return 0
    fi

    lib::log::yellow "Changes to '$filename':"
    diff -u -- "$filename" "$generated" || true
  else
    lib::log::yellow "'$filename' does not exist yet; it will be created."
  fi

  if [[ $assume_yes != "1" ]]; then
    # No default, so an unattended run without --yes stops here instead of
    # repointing a machine's mirrors unwatched.
    if ! lib::ui::confirm "Apply this mirrorlist to $filename?"; then
      lib::log::red "Aborted; '$filename' was left untouched."
      return 1
    fi
  fi

  if [[ -f $filename ]]; then
    backup="${filename}.libsh-$(date '+%d-%m-%Y+%H-%M-%S').bak"
    lib::permissions::run_as_root cp -- "$filename" "$backup"
    lib::log::green "Backed the original up to '$backup'."
  fi

  lib::permissions::run_as_root cp -- "$generated" "$filename"

  lib::log::timed_green "Wrote a fresh mirrorlist to '$filename'."
  lib::log::yellow "Run ./scripts/arch-update-packages.sh to refresh the package databases from the new mirrors."
}

# --------------------------------
#   MAIN
# --------------------------------

#######################################
# Parse the flags, validate them, then regenerate the mirrorlist.
# Globals:
#   OPTS, OPTS_HELP (read)
#   OPTS_VALUES (written by lib::opts::parse)
# Arguments:
#   The script's original "$@"
# Returns:
#   0 on success, 1 on a usage, reflector or confirmation error.
#######################################
function main() {
  local arg countries latest protocol filename dry_run assume_yes

  # --check-prerequisites answers on its own, before the parser can reject
  # the run for the required flags a prerequisite check has no use for.
  for arg in "$@"; do
    if [[ $arg == "--check-prerequisites" ]]; then
      arch_update_mirrors::prerequisites
      return $?
    fi
  done

  lib::opts::parse "$@" || return 1

  countries="${OPTS_VALUES[countries]:-Germany,Netherlands,Sweden,Belgium,France,Austria}"
  latest="${OPTS_VALUES[latest]:-10}"
  protocol="${OPTS_VALUES[protocol]:-https}"
  filename="${OPTS_VALUES[output_file]:-/etc/pacman.d/mirrorlist}"
  dry_run="${OPTS_VALUES[dry_run]:-}"
  assume_yes="${OPTS_VALUES[assume_yes]:-}"

  # Country names carry spaces and hyphens, but nothing that could turn
  # into another argument.
  if [[ ! $countries =~ ^[A-Za-z][A-Za-z,\ -]*$ ]]; then
    lib::log::red "Invalid --countries '$countries'; expected names or codes such as 'Germany,Austria'."
    return 1
  fi

  if [[ ! $latest =~ ^[0-9]+$ || $latest -eq 0 ]]; then
    lib::log::red "Invalid --latest '$latest'; expected a positive number."
    return 1
  fi

  case "$protocol" in
  https | http | rsync | ftp) ;;
  *)
    lib::log::red "Invalid --protocol '$protocol'; expected one of https, http, rsync, ftp."
    return 1
    ;;
  esac

  arch_update_mirrors::exec "$countries" "$latest" "$protocol" "$filename" "$dry_run" "$assume_yes"
}

# ------------
# 'main' call
# ------------
main "$@"
