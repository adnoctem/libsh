#!/usr/bin/env bash
#
# Create a GNU-zipped tarball (archive) of local files and directories.

# Mitigate potential path issues depending on where you're running the script from
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# shellcheck source=lib/log.sh
. "$LIB_DIR"/log.sh

# shellcheck source=lib/package.sh
. "$LIB_DIR"/package.sh

# shellcheck source=lib/paths.sh
. "$LIB_DIR"/paths.sh

# -------------------------
#   GLOBAL defaults
# -------------------------

SOURCE=""
DESTINATION="${HOME}/.libsh"

#######################################
# Print the usage output for the script.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Writes usage to stdout
#######################################
function backup::usage() {
  local script_name

  script_name=$(basename "${0}")

  echo "$script_name"
  echo
  echo "Create a GNU-zipped tarball of local files and directories."
  echo
  echo "Usage: ./scripts/$script_name <SOURCE> [NAME] [DESTINATION]"
  echo
  echo "help    - Print this usage information"
  echo "deps    - Show the required dependencies to run this script"
  echo
  echo "Examples:"
  echo "  ./scripts/$script_name /var/www/html"
  echo "  ./scripts/$script_name /var/www/myhtml htmlroot /tmp/destination"
}

#######################################
# Check if the required dependencies for
# the scripts are installed.
# Arguments:
#   None
# Returns:
#   0 if all dependencies were found, 1 otherwise.
#######################################
function backup::deps() {
  local deps=('tar')

  package::is_executable "${deps[0]}"
  rc=$?

  if [ $rc -ne 0 ]; then
    log::red "Could not find package '${deps[0]}' in system PATH. Please install '${deps[0]}' to proceed!"
    return 1
  fi

  log::green "Found package '${deps[0]}' in system PATH. Ready to proceed!"
  return 0
}

#######################################
# Run the TAR backup.
# Globals:
#   SOURCE
#   DESTINATION
# Arguments:
#   A source file path from which to backup.
#   A name for the backup (to name the tarball).
#   A destination file path to backup to.
# Returns:
#   0 if the source path does not exist.
#   Otherwise the parent return value of 'tar'.
#######################################
function backup::run() {
  local source_path backup_name destination_path curdate
  source_path=${1:-"$SOURCE"}
  backup_name=${2:-$(basename "$SOURCE")}
  destination_path=${3:-"$DESTINATION"}
  curdate=$(date '+%d-%m-%Y+%T')

  if [ ! -e "$source_path" ]; then
    log::red "Cannot backup directory $source_path. No such file or directory."
    return 1
  fi

  paths::ensure_existence "$destination_path"
  # ref: https://unix.stackexchange.com/questions/59243/tar-removing-leading-from-member-names
  tar -vczf "$destination_path/$backup_name-$curdate.tar.gz" -C / "${source_path#/}"
}

# --------------------------------
#   MAIN
# --------------------------------
function main() {
  local cmd=${1}

  case "${cmd}" in
  help)
    backup::usage
    ;;
  deps)
    backup::deps
    return $?
    ;;
  *)
    backup::run "$@"
    return $?
    ;;
  esac
}

# ------------
# 'main' call
# ------------
main "$@"
