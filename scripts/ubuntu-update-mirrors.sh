#!/usr/bin/env bash
#
# Point an Ubuntu system's apt sources at a different archive mirror.

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
  "-c,--country:country:1:optional"
  "-m,--mirror:mirror:1:optional"
  "-f,--sources-file:sources_file:1:optional"
  "-y,--yes:assume_yes:0:optional"
  "-h,--help:help:0:optional"
  ",--dry-run:dry_run:0:optional"
  ",--check-prerequisites:check_prerequisites:0:optional"
)

declare -A OPTS_HELP=(
  [country]="Two-letter country code for a country mirror, e.g. 'de' (default: de)"
  [mirror]="Full mirror base URI, e.g. 'https://mirror.hetzner.com/ubuntu/packages'. Overrides --country."
  [sources_file]="apt sources file to rewrite (default: the deb822 file if present, else /etc/apt/sources.list)"
  [assume_yes]="Skip the confirmation prompt (required for unattended runs)"
  [dry_run]="Print the diff that would be applied, without writing anything"
  [check_prerequisites]="Check that the required packages are installed, then exit"
  [help]="Show this help message and exit"
)

declare -A OPTS_VALUES=()

# The security pocket deliberately stays on security.ubuntu.com: it is
# served from Canonical's own infrastructure and country mirrors lag it.
readonly ARCHIVE_PATTERN='https?://([a-z]{2}\.)?archive\.ubuntu\.com/ubuntu'

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
function ubuntu_update_mirrors::prerequisites() {
  local prerequisites=('apt-get' 'sed' 'diff')

  # Writing into /etc/apt needs root, which is 'sudo' unless the script is
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
# Resolve which apt sources file to rewrite.
#
# Ubuntu 24.04 and newer ship the deb822 file and leave sources.list as an
# empty stub, so the newer format wins when both are present.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   The sources file path to stdout, empty if none was found.
#######################################
function ubuntu_update_mirrors::sources_file() {
  local candidate

  for candidate in /etc/apt/sources.list.d/ubuntu.sources /etc/apt/sources.list; do
    if [[ -s $candidate ]]; then
      printf '%s' "$candidate"
      return 0
    fi
  done

  printf ''
}

#######################################
# Rewrite the archive URIs in one apt sources file.
# Globals:
#   ARCHIVE_PATTERN (read)
# Arguments:
#   1 - Sources file path
#   2 - New mirror base URI
#   3 - "1" for a dry run, "" otherwise
#   4 - "1" to skip the confirmation, "" otherwise
# Outputs:
#   A unified diff of the change to stdout.
# Returns:
#   0 on success or when nothing needed changing, 1 on a write failure or
#   a declined confirmation.
#######################################
function ubuntu_update_mirrors::exec() {
  local filename=${1} mirror=${2} dry_run=${3} assume_yes=${4}
  local rewritten backup rc=0

  rewritten=$(mktemp)
  # shellcheck disable=SC2064 # the path is expanded now on purpose, the variable is reused below
  trap "rm -f '$rewritten'" RETURN

  sed -E "s#${ARCHIVE_PATTERN}#${mirror}#g" -- "$filename" >"$rewritten"

  # 'diff' exits 1 when the files differ, which is the interesting case
  # here rather than an error.
  diff -u -- "$filename" "$rewritten" >/dev/null 2>&1 || rc=$?

  if [[ $rc -eq 0 ]]; then
    lib::log::green "'$filename' already points at $mirror; nothing to change."
    return 0
  fi

  if [[ $rc -gt 1 ]]; then
    lib::log::red "Could not compare '$filename' with the rewritten version."
    return 1
  fi

  lib::log::yellow "Changes to '$filename':"
  diff -u -- "$filename" "$rewritten" || true

  if [[ $dry_run == "1" ]]; then
    lib::log::yellow "[dry-run] nothing was written."
    return 0
  fi

  if [[ $assume_yes != "1" ]]; then
    # No default, so an unattended run without --yes stops here instead of
    # repointing a production machine's apt sources unwatched.
    if ! lib::ui::confirm "Apply this change to $filename?"; then
      lib::log::red "Aborted; '$filename' was left untouched."
      return 1
    fi
  fi

  backup="${filename}.libsh-$(date '+%d-%m-%Y+%H-%M-%S').bak"
  lib::permissions::run_as_root cp -- "$filename" "$backup"
  lib::log::green "Backed the original up to '$backup'."

  # 'cp' onto the existing file keeps its owner and mode, which matters
  # for anything under /etc/apt.
  lib::permissions::run_as_root cp -- "$rewritten" "$filename"

  lib::log::timed_green "Repointed '$filename' at $mirror."
  lib::log::yellow "Run ./scripts/ubuntu-update-packages.sh to refresh the package lists from the new mirror."
}

# --------------------------------
#   MAIN
# --------------------------------

#######################################
# Parse the flags, resolve the mirror and sources file, then rewrite it.
# Globals:
#   OPTS, OPTS_HELP (read)
#   OPTS_VALUES (written by lib::opts::parse)
# Arguments:
#   The script's original "$@"
# Returns:
#   0 on success, 1 on a usage, sources-file or confirmation error.
#######################################
function main() {
  local arg country mirror filename dry_run assume_yes

  # --check-prerequisites answers on its own, before the parser can reject
  # the run for the required flags a prerequisite check has no use for.
  for arg in "$@"; do
    if [[ $arg == "--check-prerequisites" ]]; then
      ubuntu_update_mirrors::prerequisites
      return $?
    fi
  done

  lib::opts::parse "$@" || return 1

  country="${OPTS_VALUES[country]:-de}"
  mirror="${OPTS_VALUES[mirror]:-}"
  dry_run="${OPTS_VALUES[dry_run]:-}"
  assume_yes="${OPTS_VALUES[assume_yes]:-}"

  if [[ -n ${OPTS_VALUES[country]:-} && -n $mirror ]]; then
    lib::log::red "--country and --mirror are mutually exclusive; pass only one of them."
    return 1
  fi

  if [[ -z $mirror ]]; then
    if [[ ! $country =~ ^[a-z]{2}$ ]]; then
      lib::log::red "Invalid country '$country'; expected a two-letter code such as 'de'."
      return 1
    fi

    mirror="http://${country}.archive.ubuntu.com/ubuntu"
  fi

  # The value is interpolated into a sed replacement, so anything that
  # could end the expression or inject a shell character is refused.
  if [[ ! $mirror =~ ^https?://[A-Za-z0-9._~:/?#@!$\&\'()*+,\;=%-]+$ ]]; then
    lib::log::red "Invalid mirror '$mirror'; expected an http(s) URI."
    return 1
  fi

  filename="${OPTS_VALUES[sources_file]:-$(ubuntu_update_mirrors::sources_file)}"

  if [[ -z $filename ]]; then
    lib::log::red "Found no apt sources file to rewrite; pass one with --sources-file."
    return 1
  fi

  if [[ ! -r $filename ]]; then
    lib::log::red "Sources file '$filename' does not exist or is not readable."
    return 1
  fi

  lib::log::green "Using apt sources file '$filename'."

  ubuntu_update_mirrors::exec "$filename" "$mirror" "$dry_run" "$assume_yes"
}

# ------------
# 'main' call
# ------------
main "$@"
