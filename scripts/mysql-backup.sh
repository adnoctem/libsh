#!/usr/bin/env bash
#
# Create dumps of MySQL-compatible databases (MySQL, Aurora MySQL).

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

# shellcheck source=lib/secret.sh
. "$LIB_DIR"/secret.sh

# shellcheck source=lib/history.sh
. "$LIB_DIR"/history.sh

# -------------------------
#   Flag spec
# -------------------------

OPTS=(
  "-u,--username:username:1:required"
  ",--password:password:1:optional"
  ",--password-file:password_file:1:optional"
  "-H,--host:host:1:required"
  "-P,--port:port:1:optional"
  "-d,--databases:databases:1:required"
  "-o,--output-dir:output_dir:1:optional"
  "-h,--help:help:0:optional"
  ",--dry-run:dry_run:0:optional"
  ",--scrub-history:scrub_history:0:optional"
  ",--check-prerequisites:check_prerequisites:0:optional"
)

declare -A OPTS_HELP=(
  [username]="Database user to connect as"
  [password]="Database password. Prefer --password-file or the MYSQL_PWD env var -- passing it here is visible to other local users via 'ps'."
  [password_file]="Read the database password from the first line of this file"
  [host]="Database host (e.g. an RDS endpoint)"
  [port]="Database port (default: 3306)"
  [databases]="Comma-separated list of database names to dump"
  [output_dir]='Directory to write dump files into (default: $HOME/.libsh)'
  [dry_run]="Print the mysqldump command(s) that would run, without executing them"
  [scrub_history]="Remove lines containing the password from the shell history file afterwards"
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
function backup_mysql::prerequisites() {
  local prerequisites=('mysql' 'mysqldump' 'pv' 'numfmt')

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
# Dump a single database.
# Globals:
#   MYSQL_PWD (read, by mysql/mysqldump themselves)
# Arguments:
#   1 - Database host
#   2 - Database port
#   3 - Database user
#   4 - Database name
#   5 - Destination file path
#   6 - "1" for a dry run, "" otherwise
# Outputs:
#   Progress to stdout, the dump itself to the destination file.
# Returns:
#   0 on success, otherwise the return value of 'mysql' or 'mysqldump'.
#######################################
function backup_mysql::exec() {
  local host=${1} port=${2} user=${3} db_name=${4} filename=${5} dry_run=${6}
  local db_size size

  local -a dump_cmd=(
    mysqldump
    -h "$host" -P "$port" -u "$user"
    --single-transaction
    --set-gtid-purged=OFF
    --no-tablespaces
    --routines --triggers --events
    --hex-blob
    --quick
    --databases "$db_name"
  )

  if [[ $dry_run == "1" ]]; then
    lib::log::yellow "[dry-run] MYSQL_PWD=**** ${dump_cmd[*]} > $filename"
    return 0
  fi

  # Estimate the dump size up front so 'pv' can render a real progress bar.
  db_size=$(
    mysql \
      -h "$host" \
      -P "$port" \
      -u "$user" \
      --silent \
      --skip-column-names \
      -e "SELECT ROUND(SUM(data_length) * 1.09) AS \"size_bytes\" \
      FROM information_schema.TABLES \
      WHERE table_schema='$db_name';"
  )

  # An unknown/empty schema answers 'NULL', which is not a size.
  if [[ ! $db_size =~ ^[0-9]+$ ]]; then
    lib::log::yellow "Could not determine the size of database '$db_name'; progress will be shown without a total."
    db_size=0
  fi

  size=$(numfmt --to=iec-i --suffix=B "$db_size")
  lib::log::timed_yellow "Dumping database '$db_name' (≈$size) into $filename ..."

  "${dump_cmd[@]}" | pv --size "$db_size" >"$filename"

  lib::log::timed_green "Finished backup of MySQL database: $db_name"
}

# --------------------------------
#   MAIN
# --------------------------------

#######################################
# Parse the flags, resolve credentials and target, then dump every
# database named by --databases.
# Globals:
#   OPTS, OPTS_HELP (read)
#   OPTS_VALUES (written by lib::opts::parse)
#   MYSQL_PWD (read as a fallback, exported for mysql/mysqldump)
# Arguments:
#   The script's original "$@"
# Returns:
#   0 on success, 1 on a usage or credential error.
#######################################
function main() {
  local arg password password_file host port user dry_run destination curdate db_name file
  local -a db_names

  # --check-prerequisites answers on its own, before the parser can reject
  # the run for the required flags a prerequisite check has no use for.
  for arg in "$@"; do
    if [[ $arg == "--check-prerequisites" ]]; then
      backup_mysql::prerequisites
      return $?
    fi
  done

  lib::opts::parse "$@" || return 1

  password="${OPTS_VALUES[password]:-}"
  password_file="${OPTS_VALUES[password_file]:-}"
  unset 'OPTS_VALUES[password]'

  if [[ -n $password && -n $password_file ]]; then
    lib::log::red "--password and --password-file are mutually exclusive; pass only one of them."
    return 1
  fi

  if [[ -n $password_file ]]; then
    password=$(lib::secret::from_file "$password_file") || return 1
  fi

  export MYSQL_PWD="${password:-${MYSQL_PWD:-}}"
  unset password

  if [[ -z $MYSQL_PWD ]]; then
    lib::log::red "No password supplied. Use --password-file, --password, or set the MYSQL_PWD environment variable."
    return 1
  fi

  # Registered as a trap rather than a closing line: the credentials were
  # typed whether or not the dump below succeeds.
  if [[ ${OPTS_VALUES[scrub_history]:-} == "1" ]]; then
    trap 'lib::history::scrub "${MYSQL_PWD:-}" || true' EXIT
  fi

  host="${OPTS_VALUES[host]}"
  port="${OPTS_VALUES[port]:-3306}"
  user="${OPTS_VALUES[username]}"
  dry_run="${OPTS_VALUES[dry_run]:-}"
  destination="${OPTS_VALUES[output_dir]:-${HOME}/.libsh}"

  IFS=',' read -ra db_names <<<"${OPTS_VALUES[databases]}"

  curdate=$(date '+%d-%m-%Y+%H-%M-%S')

  for db_name in "${db_names[@]}"; do
    if [[ -z $db_name ]]; then
      lib::log::yellow "Skipping an empty database name in --databases."
      continue
    fi

    # Built per database: computing this once outside the loop made every
    # database dump into the same file, silently overwriting the last one.
    file="$destination/mysqldump_${db_name}-${curdate}.sql"

    # 'lib::paths::ensure_existence' creates the *parent* of the path it's given,
    # so hand it the dump file to get the destination directory.
    if [[ $dry_run != "1" ]]; then
      lib::paths::ensure_existence "$file"
    fi

    backup_mysql::exec "$host" "$port" "$user" "$db_name" "$file" "$dry_run"
  done
}

# ------------
# 'main' call
# ------------
main "$@"
