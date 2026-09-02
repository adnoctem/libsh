#!/usr/bin/env bash
#
# Extract compressed tarballs (archives) into a target directory.

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

# shellcheck source=lib/ui.sh
. "$LIB_DIR"/ui.sh

# -------------------------
#   Flag spec
# -------------------------

OPTS=(
  "-f,--files:files:1:required"
  "-o,--output-dir:output_dir:1:required"
  ",--strip-components:strip_components:1:optional"
  "-y,--yes:assume_yes:0:optional"
  "-h,--help:help:0:optional"
  ",--dry-run:dry_run:0:optional"
  ",--check-prerequisites:check_prerequisites:0:optional"
)

declare -A OPTS_HELP=(
  [files]="Comma-separated list of archives to extract, in the given order"
  [output_dir]="Directory to extract into. Required: archives from archive-create.sh hold paths relative to '/', so there is no safe default."
  [strip_components]="Strip this many leading path components from every member"
  [assume_yes]="Skip the confirmation prompt (required for unattended runs)"
  [dry_run]="List what the archives hold, without extracting anything"
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
function archive_extract::prerequisites() {
  local prerequisites=('tar' 'pv' 'numfmt' 'gzip')

  for prerequisite in "${prerequisites[@]}"; do
    if ! lib::package::is_executable "${prerequisite}"; then
      lib::log::red "Could not find package '${prerequisite}' in system PATH. Please install '${prerequisite}' to proceed!"
      return 1
    fi

    lib::log::green "Found package '${prerequisite}' in system PATH."
  done

  lib::log::green "Found all prerequisites: '${prerequisites[*]}' in system PATH. Ready to proceed!"
  lib::log::yellow "The 'zstd', 'xz' and 'bzip2' decompressors are only needed for archives in those formats."
  return 0
}

#######################################
# Extract a single archive.
# Globals:
#   None
# Arguments:
#   1 - Archive file path
#   2 - Directory to extract into
#   3 - Number of leading components to strip, or ""
#   4 - "1" for a dry run, "" otherwise
# Outputs:
#   Progress to stdout, or the archive's first entries on a dry run.
# Returns:
#   0 on success, otherwise the return value of 'tar'.
#######################################
function archive_extract::exec() {
  local filename=${1} destination=${2} strip=${3} dry_run=${4}
  local file_size size listing decompressor
  local -a tar_cmd=(tar --extract --directory "$destination")
  local -a decompress_cmd=()

  if [[ -n $strip ]]; then
    tar_cmd+=("--strip-components=$strip")
  fi

  # GNU tar only auto-detects compression when it opens the archive
  # itself, not when the bytes arrive on stdin from pv, so the
  # decompressor is named explicitly here.
  case "$filename" in
  *.tar.gz | *.tgz) decompress_cmd=(gzip -dc) ;;
  *.tar.zst | *.tzst) decompress_cmd=(zstd -dc) ;;
  *.tar.xz | *.txz) decompress_cmd=(xz -dc) ;;
  *.tar.bz2 | *.tbz2) decompress_cmd=(bzip2 -dc) ;;
  *.tar) decompress_cmd=(cat) ;;
  esac

  if [[ $dry_run == "1" ]]; then
    if [[ ${#decompress_cmd[@]} -eq 0 ]]; then
      lib::log::yellow "[dry-run] ${tar_cmd[*]} --file $filename"
    else
      lib::log::yellow "[dry-run] pv $filename | ${decompress_cmd[*]} | ${tar_cmd[*]}"
    fi

    # 'head' closing the pipe early makes tar exit on SIGPIPE, which
    # pipefail would otherwise turn into a failed dry run.
    listing=$({ tar --list --file "$filename" | head -n 20; } 2>/dev/null || true)
    lib::log::yellow "[dry-run] first entries of '$filename':"
    echo "$listing"
    return 0
  fi

  file_size=$(wc -c <"$filename")
  size=$(numfmt --to=iec-i --suffix=B "$file_size")

  lib::log::timed_yellow "Extracting '$filename' ($size) into $destination ..."

  if [[ ${#decompress_cmd[@]} -eq 0 ]]; then
    # Unknown extension: let tar open the archive and work the format out
    # on its own, at the cost of the progress bar.
    lib::log::yellow "Unrecognised archive extension; extracting without a progress bar."
    "${tar_cmd[@]}" --file "$filename"
  else
    decompressor="${decompress_cmd[0]}"

    if ! lib::package::is_executable "$decompressor"; then
      lib::log::red "Extracting '$filename' needs '$decompressor', which is not in the system PATH."
      return 1
    fi

    pv --size "$file_size" -- "$filename" | "${decompress_cmd[@]}" | "${tar_cmd[@]}"
  fi

  lib::log::timed_green "Finished extraction of archive: $filename"
}

# --------------------------------
#   MAIN
# --------------------------------

#######################################
# Parse the flags, vet the archives, confirm, then extract every archive
# named by --files.
# Globals:
#   OPTS, OPTS_HELP (read)
#   OPTS_VALUES (written by lib::opts::parse)
# Arguments:
#   The script's original "$@"
# Returns:
#   0 on success, 1 on a usage, archive or confirmation error.
#######################################
function main() {
  local arg destination strip dry_run assume_yes file
  local -a archives valid_archives=()

  # --check-prerequisites answers on its own, before the parser can reject
  # the run for the required flags a prerequisite check has no use for.
  for arg in "$@"; do
    if [[ $arg == "--check-prerequisites" ]]; then
      archive_extract::prerequisites
      return $?
    fi
  done

  lib::opts::parse "$@" || return 1

  destination="${OPTS_VALUES[output_dir]}"
  strip="${OPTS_VALUES[strip_components]:-}"
  dry_run="${OPTS_VALUES[dry_run]:-}"
  assume_yes="${OPTS_VALUES[assume_yes]:-}"

  if [[ -n $strip && ! $strip =~ ^[0-9]+$ ]]; then
    lib::log::red "Invalid --strip-components '$strip'; expected a number."
    return 1
  fi

  IFS=',' read -ra archives <<<"${OPTS_VALUES[files]}"

  # Vet every archive up front: finding an unreadable one halfway through
  # leaves the target half-extracted.
  for file in "${archives[@]}"; do
    if [[ -z $file ]]; then
      lib::log::yellow "Skipping an empty file name in --files."
      continue
    fi

    if [[ ! -f $file || ! -r $file ]]; then
      lib::log::red "Archive '$file' does not exist or is not readable."
      return 1
    fi

    valid_archives+=("$file")
  done

  if [[ ${#valid_archives[@]} -eq 0 ]]; then
    lib::log::red "No archives given in --files."
    return 1
  fi

  if [[ $dry_run != "1" && $assume_yes != "1" ]]; then
    lib::log::yellow "About to extract ${#valid_archives[@]} archive(s) into $destination:"
    for file in "${valid_archives[@]}"; do
      lib::log::yellow "  - $file"
    done
    lib::log::yellow "Existing files with the same paths are overwritten without a prompt from tar."

    # No default, so an unattended run without --yes stops here instead of
    # overwriting a tree nobody was watching.
    if ! lib::ui::confirm "Continue?"; then
      lib::log::red "Aborted; nothing was extracted."
      return 1
    fi
  fi

  if [[ $dry_run != "1" ]]; then
    lib::paths::ensure_directory "$destination"
  fi

  for file in "${valid_archives[@]}"; do
    archive_extract::exec "$file" "$destination" "$strip" "$dry_run"
  done
}

# ------------
# 'main' call
# ------------
main "$@"
