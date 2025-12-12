#!/usr/bin/env bash
#
# Create dumps of MySQL databases.

# Mitigate potential path issues depending on where you're running the script from
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# shellcheck source=lib/log.sh
. "$LIB_DIR"/log.sh

# shellcheck source=lib/package.sh
. "$LIB_DIR"/package.sh

# shellcheck source=lib/paths.sh
. "$LIB_DIR"/paths.sh

# shellcheck source=lib/array.sh
. "$LIB_DIR"/array.sh

# -------------------------
#   GLOBAL defaults
# -------------------------

DESTINATION="${HOME}/.libsh"
DB_HOST=""
DB_PORT=""
DB_USER=""
DB_PASSWORD=""
DB_NAMES=()

#######################################
# Print the usage output for the script.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Writes usage to stdout
#######################################
function mysql_dump::usage() {
  local script_name

  script_name=$(basename "${0}")

  echo "$script_name"
  echo
  echo "Create dumps of MySQL databases."
  echo
  echo "Usage: ./scripts/$script_name <DB_URL> [DESTINATION]"
  echo
  echo "help    - Print this usage information"
  echo "deps    - Show the required dependencies to run this script"
  echo
  echo "Examples:"
  echo "  ./scripts/$script_name (with configured Globals)"
  echo "  ./scripts/$script_name mysql://db_user:db_password@127.0.0.1:3306/db_name"
  echo "  ./scripts/$script_name mysql://db_user:db_password@127.0.0.1:3306/db_name ./Backups"
}

#######################################
# Check if the required dependencies for
# the scripts are installed.
# Arguments:
#   None
# Returns:
#   0 if all dependencies were found, 1 otherwise.
#######################################
function mysql_dump::deps() {
  local deps=('mysql' 'mysqldump' 'trurl' 'pv')

  for dep in "${deps[@]}"; do
    package::is_executable "${dep}"
    rc=$?

    if [ $rc -ne 0 ]; then
      log::red "Could not find package '${dep}' in system PATH. Please install '${dep}' to proceed!"
      return 1
    fi

    log::green "Found package '${dep}' in system PATH."
  done

  log::green "Found all dependant packages: '${deps[*]}' in system PATH. Ready to proceed!"
  return 0
}

#######################################
# Run MySQL dump.
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
function mysql_dump::run() {
  local db_url, db_host, db_port, db_user, db_password, db_name, destination_path
  db_url=${1}
  db_host=${DB_HOST:-"$(trurl "$db_url" --get '{host}')"}
  db_port=${DB_PORT:-"$(trurl "$db_url" --get '{port}')"}
  db_user=${DB_USER:-"$(trurl "$db_url" --get '{user}')"}
  db_password=${DB_PASSWORD:-"$(trurl "$db_url" --get '{password}')"}
  path=$(trurl "$db_url" --get '{path}')
  db_name=${path#/}

  destination_path=${2:-"$DESTINATION"}
  paths::ensure_existence "$destination_path"

  curdate=$(date '+%d-%m-%Y+%T')
  file="$destination_path/dump_$db_name-$curdate.sql"

  array::is_empty "${DB_NAMES[@]}"
  rc=$?

  if [ $rc -eq 0 ]; then
    mysql_dump::exec "$db_host" "$db_port" "$db_user" "$db_password" "$db_name" "$file"
  else
    for db in "${DB_NAMES[@]}"; do
      mysql_dump::exec "$db_host" "$db_port" "$db_user" "$db_password" "$db" "$file"
    done
  fi
}

function mysql_dump::exec() {
  local db_host, db_port, db_user, db_password, db_name, filename

  db_host=${1}
  db_port=${2}
  db_user=${3}
  db_password=${4}
  db_name=${5}
  filename=${6}

  db_size=$(
    mysql \
      -h "$db_host" \
      -P "$db_port" \
      -u "$db_user" \
      "-p$db_password" \
      --silent \
      --skip-column-names \
      -e "SELECT ROUND(SUM(data_length) * 1.09) AS \"size_bytes\" \
      FROM information_schema.TABLES \
      WHERE table_schema='$db_name';"
  )

  size=$(numfmt --to=iec-i --suffix=B "$db_size")
  log_time::yellow "Dumping database '$db_name' (≈$size) into $file ..."

  mysqldump \
    -h "$db_host" \
    -P "$db_port" \
    -u "$db_user" \
    "-p$db_password" \
    --compact \
    --dump-date \
    --hex-blob \
    --databases \
    --no-tablespaces \
    --order-by-primary \
    --quick \
    "$db_name" |
    pv --size "$db_size" \
      >"$filename"

  log_time::green "Finished backup of MySQL database: $db_name"
}

# --------------------------------
#   MAIN
# --------------------------------
function main() {
  local cmd=${1}

  case "${cmd}" in
  help)
    mysql_dump::usage
    ;;
  deps)
    mysql_dump::deps
    return $?
    ;;
  *)
    mysql_dump::run "$@"
    return $?
    ;;
  esac
}

# ------------
# 'main' call
# ------------
main "$@"
