#!/usr/bin/env bash
#
# Create a compressed tarball (archive) of local files and directories.

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
  "-s,--sources:sources:1:required"
  "-n,--name:name:1:optional"
  "-o,--output-dir:output_dir:1:optional"
  "-e,--exclude:exclude:1:optional"
  "-c,--compression:compression:1:optional"
  "-h,--help:help:0:optional"
  ",--dry-run:dry_run:0:optional"
  ",--check-prerequisites:check_prerequisites:0:optional"
)

declare -A OPTS_HELP=(
  [sources]="Comma-separated list of files/directories to archive"
  [name]="Base name for the archive (default: the first source's basename)"
  [output_dir]='Directory to write the archive into (default: $HOME/.libsh)'
  [exclude]="Comma-separated tar exclude patterns, e.g. 'node_modules,*.log'"
  [compression]="One of gzip, zstd, xz, none (default: gzip)"
  [dry_run]="Print the pipeline that would run, without executing it"
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
function archive_create::prerequisites() {
  local prerequisites=('tar' 'pv' 'du' 'numfmt' 'gzip' 'realpath')

  for prerequisite in "${prerequisites[@]}"; do
    if ! lib::package::is_executable "${prerequisite}"; then
      lib::log::red "Could not find package '${prerequisite}' in system PATH. Please install '${prerequisite}' to proceed!"
      return 1
    fi

    lib::log::green "Found package '${prerequisite}' in system PATH."
  done

  lib::log::green "Found all prerequisites: '${prerequisites[*]}' in system PATH. Ready to proceed!"
  lib::log::yellow "The 'zstd' and 'xz' compressors are only needed when --compression asks for them."
  return 0
}

#######################################
# Create one archive from the given sources.
#
# Paths are stored relative to '/' (tar runs with '-C /'), so an archive
# of /var/www/html holds 'var/www/html/...' and can be unpacked under any
# root instead of only the original one.
# Globals:
#   None
# Arguments:
#   1 - Base name for the archive
#   2 - Directory to write the archive into
#   3 - Compression: gzip, zstd, xz or none
#   4 - Comma-separated exclude patterns, or ""
#   5 - "1" for a dry run, "" otherwise
#   6+ - Absolute source paths to archive
# Outputs:
#   Progress to stdout, the archive to the output directory.
# Returns:
#   0 on success, otherwise the return value of 'tar' or the compressor.
#######################################
function archive_create::exec() {
  local name=${1} destination=${2} compression=${3} exclude=${4} dry_run=${5}
  shift 5
  local -a sources=("$@")

  local extension compressor curdate archive total size source pattern
  local -a compress_cmd=() exclude_args=() members=() patterns=()

  case "$compression" in
  gzip)
    extension="tar.gz"
    compress_cmd=(gzip -c)
    compressor="gzip"
    ;;
  zstd)
    extension="tar.zst"
    compress_cmd=(zstd -c -T0)
    compressor="zstd"
    ;;
  xz)
    extension="tar.xz"
    compress_cmd=(xz -c -T0)
    compressor="xz"
    ;;
  none)
    extension="tar"
    compress_cmd=(cat)
    compressor=""
    ;;
  esac

  if [[ -n $compressor ]] && ! lib::package::is_executable "$compressor"; then
    lib::log::red "Compression '$compression' needs '$compressor', which is not in the system PATH."
    return 1
  fi

  if [[ -n $exclude ]]; then
    IFS=',' read -ra patterns <<<"$exclude"
    for pattern in "${patterns[@]}"; do
      [[ -z $pattern ]] && continue
      exclude_args+=("--exclude=$pattern")
    done
  fi

  # tar members are the sources with their leading '/' removed, to match
  # the '-C /' above.
  for source in "${sources[@]}"; do
    members+=("${source#/}")
  done

  curdate=$(date '+%d-%m-%Y+%H-%M-%S')
  archive="$destination/${name}-${curdate}.${extension}"

  local -a tar_cmd=(
    tar
    --create
    --file -
    --directory /
    "${exclude_args[@]}"
    --
    "${members[@]}"
  )

  if [[ $dry_run == "1" ]]; then
    lib::log::yellow "[dry-run] ${tar_cmd[*]} | pv | ${compress_cmd[*]} > $archive"
    return 0
  fi

  # Only an ETA input for pv, so unreadable paths are not worth failing
  # over -- and --exclude patterns make it an over-estimate anyway.
  total=$(du -scb -- "${sources[@]}" 2>/dev/null | tail -n 1 | cut -f 1)
  if [[ ! $total =~ ^[0-9]+$ ]]; then
    total=0
  fi

  size=$(numfmt --to=iec-i --suffix=B "$total")
  lib::log::timed_yellow "Archiving ${#sources[@]} source(s) (≈$size before compression) into $archive ..."

  lib::paths::ensure_existence "$archive"

  # pv sits between tar and the compressor on purpose: it then measures
  # the uncompressed byte count the estimate above is based on.
  "${tar_cmd[@]}" | pv --size "$total" | "${compress_cmd[@]}" >"$archive"

  size=$(numfmt --to=iec-i --suffix=B "$(wc -c <"$archive")")
  lib::log::timed_green "Finished archive: $archive ($size)"
}

# --------------------------------
#   MAIN
# --------------------------------

#######################################
# Parse the flags, resolve the sources, then create the archive.
# Globals:
#   OPTS, OPTS_HELP (read)
#   OPTS_VALUES (written by lib::opts::parse)
# Arguments:
#   The script's original "$@"
# Returns:
#   0 on success, 1 on a usage or source error.
#######################################
function main() {
  local arg name destination compression exclude dry_run source resolved
  local -a raw_sources sources=()

  # --check-prerequisites answers on its own, before the parser can reject
  # the run for the required flags a prerequisite check has no use for.
  for arg in "$@"; do
    if [[ $arg == "--check-prerequisites" ]]; then
      archive_create::prerequisites
      return $?
    fi
  done

  lib::opts::parse "$@" || return 1

  destination="${OPTS_VALUES[output_dir]:-${HOME}/.libsh}"
  compression="${OPTS_VALUES[compression]:-gzip}"
  exclude="${OPTS_VALUES[exclude]:-}"
  dry_run="${OPTS_VALUES[dry_run]:-}"

  case "$compression" in
  gzip | zstd | xz | none) ;;
  *)
    lib::log::red "Invalid compression '$compression'; expected one of gzip, zstd, xz, none."
    return 1
    ;;
  esac

  IFS=',' read -ra raw_sources <<<"${OPTS_VALUES[sources]}"

  for source in "${raw_sources[@]}"; do
    if [[ -z $source ]]; then
      lib::log::yellow "Skipping an empty path in --sources."
      continue
    fi

    if [[ ! -e $source ]]; then
      lib::log::red "Cannot archive '$source': no such file or directory."
      return 1
    fi

    # Stored relative to '/', so a relative argument has to be resolved
    # before tar ever sees it.
    resolved=$(realpath -- "$source")
    sources+=("$resolved")
  done

  if [[ ${#sources[@]} -eq 0 ]]; then
    lib::log::red "No sources given in --sources."
    return 1
  fi

  name="${OPTS_VALUES[name]:-$(basename -- "${sources[0]}")}"

  if [[ $name == */* || -z $name ]]; then
    lib::log::red "Invalid archive name '$name': it becomes a filename, so it cannot contain '/'."
    return 1
  fi

  archive_create::exec "$name" "$destination" "$compression" "$exclude" "$dry_run" "${sources[@]}"
}

# ------------
# 'main' call
# ------------
main "$@"
