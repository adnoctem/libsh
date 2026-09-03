#!/usr/bin/env bash
#
# Prepare a libsh release: sync the Makefile's VERSION, rebuild dist/, and
# write dist/CHECKSUMS_SHA256.txt. Invoked by @semantic-release/exec's
# prepareCmd (see .releaserc) with the version it resolved from Conventional
# Commits, before the release commit and GitHub release are created.

set -euo pipefail

# Mitigate potential path issues depending on where you're running the script from
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

ROOT_DIR="$(dirname "$SCRIPT_DIR")"
LIB_DIR="$ROOT_DIR/lib"
MAKEFILE="$ROOT_DIR/Makefile"
DIST_DIR="$ROOT_DIR/dist"
CHECKSUMS_FILE="$DIST_DIR/CHECKSUMS_SHA256.txt"

# shellcheck source=lib/log.sh
. "$LIB_DIR"/log.sh

# shellcheck source=lib/opts.sh
. "$LIB_DIR"/opts.sh

# shellcheck source=lib/package.sh
. "$LIB_DIR"/package.sh

# -------------------------
#   Flag spec
# -------------------------

OPTS=(
  ",--version:version:1:required"
  "-h,--help:help:0:optional"
  ",--dry-run:dry_run:0:optional"
  ",--check-prerequisites:check_prerequisites:0:optional"
)

declare -A OPTS_HELP=(
  [version]="Semantic version to release, e.g. '1.2.3' (matches \${nextRelease.version})"
  [dry_run]="Print the steps that would run, without touching the Makefile or dist/"
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
function release_prepare::prerequisites() {
  local prerequisites=('sed' 'make' 'sha256sum' 'tar')

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
# Validate a version is a bare semver core, matching what
# @semantic-release/commit-analyzer hands to exec's prepareCmd.
# Globals:
#   None
# Arguments:
#   1 - Version string to validate
# Returns:
#   0 if valid, 1 otherwise (with an error on stderr).
#######################################
function release_prepare::validate_version() {
  local version=${1}

  if [[ ! $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    lib::log::red "Invalid version '$version'; expected a bare semver core, e.g. '1.2.3'."
    return 1
  fi

  return 0
}

#######################################
# Rewrite the Makefile's VERSION variable in place.
# Globals:
#   MAKEFILE (read)
# Arguments:
#   1 - New version string
#   2 - "1" for a dry run, "" otherwise
# Returns:
#   0 on success, 1 if the VERSION line could not be found.
#######################################
function release_prepare::set_makefile_version() {
  local version=${1} dry_run=${2}

  if ! grep -qE '^VERSION := ' "$MAKEFILE"; then
    lib::log::red "Could not find a 'VERSION := ...' line in $MAKEFILE."
    return 1
  fi

  if [[ $dry_run == "1" ]]; then
    lib::log::yellow "[dry-run] Would set 'VERSION := $version' in $MAKEFILE"
    return 0
  fi

  sed -i.bak -E "s/^VERSION := .*/VERSION := $version/" "$MAKEFILE"
  rm -f "$MAKEFILE.bak"
  lib::log::green "Set 'VERSION := $version' in $MAKEFILE"
}

#######################################
# Rebuild dist/ via 'make clean build'.
# Globals:
#   ROOT_DIR (read)
# Arguments:
#   1 - "1" for a dry run, "" otherwise
# Returns:
#   0 on success, otherwise the return value of 'make'.
#######################################
function release_prepare::build() {
  local dry_run=${1}

  if [[ $dry_run == "1" ]]; then
    lib::log::yellow "[dry-run] Would run 'make clean build' in $ROOT_DIR"
    return 0
  fi

  lib::log::timed_yellow "Rebuilding dist/ ..."
  make -C "$ROOT_DIR" clean build
  lib::log::timed_green "Finished rebuilding dist/"
}

#######################################
# Write dist/CHECKSUMS_SHA256.txt for every archive in dist/.
# Globals:
#   DIST_DIR, CHECKSUMS_FILE (read)
# Arguments:
#   1 - "1" for a dry run, "" otherwise
# Returns:
#   0 on success, 1 if dist/ or its archives are missing.
#######################################
function release_prepare::write_checksums() {
  local dry_run=${1}
  local -a archives=()

  if [[ ! -d $DIST_DIR ]]; then
    lib::log::red "dist/ directory not found at $DIST_DIR."
    return 1
  fi

  while IFS= read -r -d '' archive; do
    archives+=("$archive")
  done < <(find "$DIST_DIR" -maxdepth 1 -name '*.tar.gz' -print0 | sort -z)

  if [[ ${#archives[@]} -eq 0 ]]; then
    lib::log::red "No *.tar.gz archives found in $DIST_DIR."
    return 1
  fi

  if [[ $dry_run == "1" ]]; then
    lib::log::yellow "[dry-run] Would write SHA256 checksums for ${#archives[@]} archive(s) -> $CHECKSUMS_FILE"
    return 0
  fi

  (
    cd "$DIST_DIR"
    sha256sum -- "${archives[@]##*/}"
  ) >"$CHECKSUMS_FILE"

  lib::log::green "Checksums written: $CHECKSUMS_FILE"
}

# --------------------------------
#   MAIN
# --------------------------------

#######################################
# Parse the flags, then sync the Makefile version, rebuild dist/, and
# write the checksum file.
# Globals:
#   OPTS, OPTS_HELP (read)
#   OPTS_VALUES (written by lib::opts::parse)
# Arguments:
#   The script's original "$@"
# Returns:
#   0 on success, 1 on a usage or version error.
#######################################
function main() {
  local arg version dry_run

  # --check-prerequisites answers on its own, before the parser can reject
  # the run for the required flags a prerequisite check has no use for.
  for arg in "$@"; do
    if [[ $arg == "--check-prerequisites" ]]; then
      release_prepare::prerequisites
      return $?
    fi
  done

  lib::opts::parse "$@" || return 1

  version="${OPTS_VALUES[version]}"
  dry_run="${OPTS_VALUES[dry_run]:-}"

  release_prepare::validate_version "$version" || return 1
  release_prepare::set_makefile_version "$version" "$dry_run" || return 1
  release_prepare::build "$dry_run" || return 1
  release_prepare::write_checksums "$dry_run" || return 1

  lib::log::green "Release prepare complete for version $version."
}

# ------------
# 'main' call
# ------------
main "$@"
