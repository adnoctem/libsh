#!/usr/bin/env bash
#
# List the installed packages of an Ubuntu/Debian system as a manifest.

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

# shellcheck source=lib/paths.sh
. "$LIB_DIR"/paths.sh

# -------------------------
#   Flag spec
# -------------------------

OPTS=(
  "-o,--output-file:output_file:1:optional"
  ",--all:all:0:optional"
  ",--with-versions:with_versions:0:optional"
  "-h,--help:help:0:optional"
  ",--check-prerequisites:check_prerequisites:0:optional"
)

declare -A OPTS_HELP=(
  [output_file]="Write the manifest here instead of stdout"
  [all]="List every installed package, not just the manually installed ones"
  [with_versions]="Emit 'package=version' lines, pinning the manifest to exact versions"
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
function ubuntu_list_packages::prerequisites() {
  local prerequisites=('apt-mark' 'dpkg-query')

  for prerequisite in "${prerequisites[@]}"; do
    if ! lib::package::is_executable "${prerequisite}"; then
      lib::log::red "Could not find package '${prerequisite}' in system PATH. Please install '${prerequisite}' to proceed!"
      return 1
    fi

    lib::log::green "Found package '${prerequisite}' in system PATH."
  done

  lib::log::green "Found all prerequisites: '${prerequisites[*]}' in system PATH. Ready to proceed!"
  lib::log::yellow "This script never needs root: it only reads the dpkg database."
  return 0
}

#######################################
# Print the manifest.
#
# The manually installed set is the useful one to carry to a new machine:
# everything else was pulled in as a dependency and will be again.
# Globals:
#   None
# Arguments:
#   1 - "1" to list every installed package, "" for manually installed only
#   2 - "1" to append '=<version>' to each name, "" otherwise
# Outputs:
#   One package per line, sorted, to stdout.
#######################################
function ubuntu_list_packages::exec() {
  local all=${1} with_versions=${2}
  local package version

  local -a names=()

  if [[ $all == "1" ]]; then
    while IFS= read -r package; do
      [[ -n $package ]] && names+=("$package")
    done < <(dpkg-query -W -f='${db:Status-Status} ${Package}\n' | awk '$1 == "installed" {print $2}' | sort)
  else
    while IFS= read -r package; do
      [[ -n $package ]] && names+=("$package")
    done < <(apt-mark showmanual | sort)
  fi

  if [[ ${#names[@]} -eq 0 ]]; then
    return 0
  fi

  if [[ $with_versions != "1" ]]; then
    printf '%s\n' "${names[@]}"
    return 0
  fi

  for package in "${names[@]}"; do
    version=$(dpkg-query -W -f='${Version}' -- "$package" 2>/dev/null || true)

    if [[ -z $version ]]; then
      printf '%s\n' "$package"
      continue
    fi

    printf '%s=%s\n' "$package" "$version"
  done
}

# --------------------------------
#   MAIN
# --------------------------------

#######################################
# Parse the flags, then write the package manifest.
#
# Status messages go to stderr throughout, so the manifest on stdout stays
# pipeable into a file or another command.
# Globals:
#   OPTS, OPTS_HELP (read)
#   OPTS_VALUES (written by lib::opts::parse)
# Arguments:
#   The script's original "$@"
# Returns:
#   0 on success, 1 on a usage error.
#######################################
function main() {
  local arg filename all with_versions count

  # --check-prerequisites answers on its own, before the parser can reject
  # the run for the required flags a prerequisite check has no use for.
  for arg in "$@"; do
    if [[ $arg == "--check-prerequisites" ]]; then
      ubuntu_list_packages::prerequisites
      return $?
    fi
  done

  lib::opts::parse "$@" || return 1

  filename="${OPTS_VALUES[output_file]:-}"
  all="${OPTS_VALUES[all]:-}"
  with_versions="${OPTS_VALUES[with_versions]:-}"

  if [[ -z $filename ]]; then
    ubuntu_list_packages::exec "$all" "$with_versions"
    return 0
  fi

  lib::paths::ensure_existence "$filename"
  ubuntu_list_packages::exec "$all" "$with_versions" >"$filename"

  count=$(grep -c . "$filename" || true)
  lib::log::timed_green "Wrote $count package(s) to '$filename'."
  lib::log::yellow "Install them elsewhere with: ./scripts/ubuntu-install-packages.sh --file $filename"
}

# ------------
# 'main' call
# ------------
main "$@"
