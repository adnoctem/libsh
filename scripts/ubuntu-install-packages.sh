#!/usr/bin/env bash
#
# Install a set of packages on an Ubuntu/Debian system, idempotently.

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
  "-p,--packages:packages:1:optional"
  "-f,--file:file:1:optional"
  ",--skip-refresh:skip_refresh:0:optional"
  "-y,--yes:assume_yes:0:optional"
  "-h,--help:help:0:optional"
  ",--dry-run:dry_run:0:optional"
  ",--check-prerequisites:check_prerequisites:0:optional"
)

declare -A OPTS_HELP=(
  [packages]="Comma-separated package names to install"
  [file]="Manifest file with one package per line, as written by ubuntu-list-packages.sh ('#' comments and blank lines are ignored)"
  [skip_refresh]="Skip 'apt-get update' and install from the package lists as they are"
  [assume_yes]="Skip the confirmation prompt (required for unattended runs)"
  [dry_run]="Print what would be installed, without changing anything"
  [check_prerequisites]="Check that the required packages are installed, then exit"
  [help]="Show this help message and exit"
)

declare -A OPTS_VALUES=()

# A Debian package name, optionally pinned to a version by the manifest.
readonly PACKAGE_PATTERN='^[a-z0-9][a-z0-9+.-]*(:[a-z0-9]+)?(=[A-Za-z0-9+.:~-]+)?$'

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
function ubuntu_install_packages::prerequisites() {
  local prerequisites=('apt-get' 'dpkg-query')

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
# Read a package manifest.
#
# Comments and blank lines are skipped so a manifest can be annotated, and
# inline comments are trimmed so 'nginx # web server' works.
# Globals:
#   None
# Arguments:
#   1 - Manifest file path
# Outputs:
#   One package name per line to stdout.
#######################################
function ubuntu_install_packages::from_manifest() {
  local filename=${1} line

  while IFS= read -r line || [[ -n $line ]]; do
    line="${line%%#*}"
    line="${line#"${line%%[![:space:]]*}"}"
    line="${line%"${line##*[![:space:]]}"}"

    [[ -z $line ]] && continue

    printf '%s\n' "$line"
  done <"$filename"
}

#######################################
# Install the named packages.
# Globals:
#   None
# Arguments:
#   1 - "1" for a dry run, "" otherwise
#   2+ - Package names to install
# Outputs:
#   apt-get's output to stdout.
# Returns:
#   0 on success, otherwise the return value of 'apt-get'.
#######################################
function ubuntu_install_packages::exec() {
  local dry_run=${1}
  shift
  local -a packages=("$@")

  local -a install_cmd=(apt-get -y install "${packages[@]}")

  if [[ $dry_run == "1" ]]; then
    lib::log::yellow "[dry-run] ${install_cmd[*]}"
    return 0
  fi

  lib::log::timed_yellow "Installing ${#packages[@]} package(s) ..."

  lib::permissions::run_as_root env DEBIAN_FRONTEND=noninteractive "${install_cmd[@]}"

  lib::log::timed_green "Finished installing ${#packages[@]} package(s)."
}

# --------------------------------
#   MAIN
# --------------------------------

#######################################
# Parse the flags, work out which of the requested packages are missing,
# confirm, then install those.
# Globals:
#   OPTS, OPTS_HELP (read)
#   OPTS_VALUES (written by lib::opts::parse)
#   PACKAGE_PATTERN (read)
# Arguments:
#   The script's original "$@"
# Returns:
#   0 on success or when everything is already installed, 1 on a usage,
#   manifest or confirmation error.
#######################################
function main() {
  local arg filename skip_refresh assume_yes dry_run package name
  local -a requested=() missing=()
  local present=0

  # --check-prerequisites answers on its own, before the parser can reject
  # the run for the required flags a prerequisite check has no use for.
  for arg in "$@"; do
    if [[ $arg == "--check-prerequisites" ]]; then
      ubuntu_install_packages::prerequisites
      return $?
    fi
  done

  lib::opts::parse "$@" || return 1

  filename="${OPTS_VALUES[file]:-}"
  skip_refresh="${OPTS_VALUES[skip_refresh]:-}"
  assume_yes="${OPTS_VALUES[assume_yes]:-}"
  dry_run="${OPTS_VALUES[dry_run]:-}"

  # Neither flag can be 'required' on its own, so the pair is checked here.
  if [[ -z ${OPTS_VALUES[packages]:-} && -z $filename ]]; then
    lib::log::red "Nothing to install: pass --packages, --file, or both."
    return 1
  fi

  if [[ -n ${OPTS_VALUES[packages]:-} ]]; then
    IFS=',' read -ra requested <<<"${OPTS_VALUES[packages]}"
  fi

  if [[ -n $filename ]]; then
    if [[ ! -r $filename ]]; then
      lib::log::red "Manifest '$filename' does not exist or is not readable."
      return 1
    fi

    while IFS= read -r package; do
      requested+=("$package")
    done < <(ubuntu_install_packages::from_manifest "$filename")
  fi

  if [[ ${#requested[@]} -eq 0 ]]; then
    lib::log::red "No package names were given."
    return 1
  fi

  for package in "${requested[@]}"; do
    if [[ -z $package ]]; then
      continue
    fi

    # The names reach apt as arguments, so anything that is not a package
    # name is refused rather than passed along.
    if [[ ! $package =~ $PACKAGE_PATTERN ]]; then
      lib::log::red "Refusing '$package': that is not a valid package name."
      return 1
    fi

    # A pinned 'name=version' is checked by name; apt decides whether the
    # exact version is the installed one.
    name="${package%%=*}"

    if lib::apt::is_installed "$name"; then
      present=$((present + 1))
      continue
    fi

    missing+=("$package")
  done

  lib::log::green "$present of ${#requested[@]} requested package(s) already installed."

  if [[ ${#missing[@]} -eq 0 ]]; then
    lib::log::timed_green "Nothing to do."
    return 0
  fi

  lib::log::yellow "${#missing[@]} package(s) to install:"
  for package in "${missing[@]}"; do
    lib::log::plain "  - $package"
  done

  if [[ $dry_run == "1" || $skip_refresh == "1" ]]; then
    lib::log::yellow "Working from the current package lists; they may be stale."
  else
    lib::log::timed_yellow "Refreshing package lists ..."
    lib::permissions::run_as_root apt-get update
  fi

  if [[ $dry_run != "1" && $assume_yes != "1" ]]; then
    # No default, so an unattended run without --yes stops here instead of
    # installing onto a machine nobody was watching.
    if ! lib::ui::confirm "Install these packages?"; then
      lib::log::red "Aborted; nothing was installed."
      return 1
    fi
  fi

  ubuntu_install_packages::exec "$dry_run" "${missing[@]}"
}

# ------------
# 'main' call
# ------------
main "$@"
