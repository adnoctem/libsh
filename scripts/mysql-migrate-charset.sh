#!/usr/bin/env bash
#
# Migrate the charset of MySQL databases.
#
# shellcheck disable=SC2016

# Mitigate potential path issues depending on where you're running the script from
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# shellcheck source=lib/log.sh
. "$LIB_DIR"/log.sh

# -------------------------
#   GLOBAL defaults
# -------------------------

CHARSET="utf8mb4"
DB_HOST="localhost"
DB_PORT="3306"
DB_USER=""
DB_PASSWORD=""

#######################################
# Print the usage output for the script.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Writes usage to stdout
#######################################
function mysql_migrate_charset::usage() {
  local script_name

  script_name=$(basename "${0}")

  echo "$script_name"
  echo
  echo "Migrate the charset of MySQL databases."
  echo
  echo "Usage: ./scripts/$script_name <DB_URL> [CHARSET]"
  echo
  echo "help    - Print this usage information"
  echo "deps    - Show the required dependencies to run this script"
  echo
  echo "Examples:"
  echo "  ./scripts/$script_name (with configured Globals)"
  echo "  ./scripts/$script_name mysql://db_user:db_password@127.0.0.1:3306/db_name utf8mb4"
  echo "  ./scripts/$script_name mysql://db_user:db_password@127.0.0.1:3306/db_name"
}

#######################################
# Check if the required dependencies for
# the scripts are installed.
# Arguments:
#   None
# Returns:
#   0 if all dependencies were found, 1 otherwise.
#######################################
function mysql_migrate_charset::deps() {
  local deps=('mysql' 'mysqldump' 'trurl' 'pv' 'xargs')

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

# ref: https://stackoverflow.com/questions/6115612/how-to-convert-an-entire-mysql-database-characterset-and-collation-to-utf-8
#######################################
# Run the MySQL migration.
# Globals:
#   URL
#   CHARSET
# Arguments:
#   The database URL to use for the migration.
#   A valid MySQL charset.
# Returns:
#   The exit code of the called 'mysql' executable.
#######################################
function mysql_migrate_charset::run() {
  local db_url, db_host, db_port, db_user, db_password, db_name
  db_url=${1}
  db_charset=${2:-"$CHARSET"}

  db_host=${DB_HOST:-"$(trurl "$db_url" --get '{host}')"}
  db_port=${DB_PORT:-"$(trurl "$db_url" --get '{port}')"}
  db_user=${DB_USER:-"$(trurl "$db_url" --get '{user}')"}
  db_password=${DB_PASSWORD:-"$(trurl "$db_url" --get '{password}')"}
  path=$(trurl "$db_url" --get '{path}')
  db_name=${path#/}

  echo 'ALTER DATABASE `'"$db_name"'` CHARACTER SET utf8 COLLATE `'"$db_charset"'`;'
  mysql "$db_name" -u"$db_user" -p"$db_password" -e "SHOW TABLES" --batch --skip-column-names |
    xargs -I{} echo 'ALTER TABLE `'{}'` CONVERT TO CHARACTER SET utf8 COLLATE `'"$db_charset"'`;' |
    mysql "$db_name" -u"$db_user" -p"$db_password" -h"$db_host" -P"$db_port"

  log_time::green "Finished migration of MySQL database: $db_name to charset $db_charset"
}

# --------------------------------
#   MAIN
# --------------------------------
function main() {
  local cmd=${1}

  case "${cmd}" in
  help)
    mysql_migrate_charset::usage
    ;;
  deps)
    mysql_migrate_charset::deps
    return $?
    ;;
  *)
    mysql_migrate_charset::run "$@"
    return $?
    ;;
  esac
}

# ------------
# 'main' call
# ------------
main "$@"
