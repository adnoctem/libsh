#!/usr/bin/env bash
#
# Migrate the charset of MySQL-compatible databases (MySQL, Aurora MySQL).
#
# ref: https://stackoverflow.com/questions/6115612/how-to-convert-an-entire-mysql-database-characterset-and-collation-to-utf-8

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

# shellcheck source=lib/secret.sh
. "$LIB_DIR"/secret.sh

# shellcheck source=lib/history.sh
. "$LIB_DIR"/history.sh

# shellcheck source=lib/ui.sh
. "$LIB_DIR"/ui.sh

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
  "-c,--charset:charset:1:optional"
  ",--collation:collation:1:optional"
  "-y,--yes:assume_yes:0:optional"
  ",--force:force:0:optional"
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
  [databases]="Comma-separated list of database names to migrate"
  [charset]="Target character set (default: utf8mb4)"
  [collation]="Target collation (default: the server's default collation for the charset)"
  [assume_yes]="Skip the confirmation prompt (required for unattended runs)"
  [force]="Convert every table, including ones already reporting the target charset"
  [dry_run]="Print the ALTER statements that would run, without executing them"
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
function mysql_migrate_charset::prerequisites() {
  local prerequisites=('mysql')

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
# Convert a single database and every base table in it to the target
# charset.
#
# Tables already reporting the target are skipped unless --force is given.
# Views are left alone: 'ALTER TABLE' cannot convert them, they carry the
# charset of their definition and have to be recreated to change it.
# Globals:
#   MYSQL_PWD (read, by mysql itself)
# Arguments:
#   1 - Database host
#   2 - Database port
#   3 - Database user
#   4 - Database name
#   5 - Target charset
#   6 - Target collation, or "" for the charset default
#   7 - "1" for a dry run, "" otherwise
#   8 - "1" to convert already-matching tables, "" otherwise
# Outputs:
#   One line per table to stdout.
# Returns:
#   0 on success, otherwise the return value of 'mysql'.
#######################################
function mysql_migrate_charset::exec() {
  local host=${1} port=${2} user=${3} db_name=${4} charset=${5} collation=${6} dry_run=${7} force=${8}
  local collate_clause="" table table_collation statement escaped
  local total=0 converted=0 skipped=0 index=0 views=0
  local -a tables=() collations=()

  if [[ -n $collation ]]; then
    collate_clause=" COLLATE $collation"
  fi

  local -a mysql_cmd=(
    mysql
    -h "$host" -P "$port" -u "$user"
    --batch --skip-column-names
    -D "$db_name"
  )

  # information_schema rather than 'SHOW TABLES': it filters views out and
  # hands back the current collation, which is what decides the skips.
  while IFS=$'\t' read -r table table_collation; do
    [[ -z $table ]] && continue
    tables+=("$table")
    collations+=("$table_collation")
  done < <(
    "${mysql_cmd[@]}" -e "SELECT TABLE_NAME, TABLE_COLLATION \
      FROM information_schema.TABLES \
      WHERE TABLE_SCHEMA='$db_name' AND TABLE_TYPE='BASE TABLE' \
      ORDER BY TABLE_NAME;"
  )

  views=$(
    "${mysql_cmd[@]}" -e "SELECT COUNT(*) FROM information_schema.TABLES \
      WHERE TABLE_SCHEMA='$db_name' AND TABLE_TYPE='VIEW';"
  )

  total=${#tables[@]}
  lib::log::timed_yellow "Database '$db_name': $total base table(s) to consider, target $charset${collate_clause}."

  if [[ $views != "0" ]]; then
    lib::log::yellow "Skipping $views view(s): a view carries the charset of its definition and has to be recreated to change it."
  fi

  # The database default only affects objects created from here on, so it
  # runs first -- an interrupted migration then at least creates new
  # tables correctly.
  # shellcheck disable=SC2016 # the backticks quote a MySQL identifier, they are not a subshell
  statement=$(printf 'ALTER DATABASE `%s` CHARACTER SET %s%s;' "${db_name//\`/\`\`}" "$charset" "$collate_clause")
  if [[ $dry_run == "1" ]]; then
    lib::log::yellow "[dry-run] $statement"
  else
    "${mysql_cmd[@]}" -e "$statement"
  fi

  for index in "${!tables[@]}"; do
    table="${tables[index]}"
    table_collation="${collations[index]}"

    # TABLE_COLLATION is the table default; a column can still carry an
    # explicit charset of its own, which is what --force is for.
    if [[ $force != "1" ]] && mysql_migrate_charset::matches "$table_collation" "$charset" "$collation"; then
      skipped=$((skipped + 1))
      continue
    fi

    escaped="${table//\`/\`\`}"
    # shellcheck disable=SC2016 # the backticks quote a MySQL identifier, they are not a subshell
    statement=$(printf 'ALTER TABLE `%s` CONVERT TO CHARACTER SET %s%s;' "$escaped" "$charset" "$collate_clause")

    if [[ $dry_run == "1" ]]; then
      lib::log::yellow "[dry-run] $statement"
      converted=$((converted + 1))
      continue
    fi

    # One statement per connection rather than one piped session: an
    # ALTER TABLE rewrites the whole table, so the connection overhead is
    # noise, and a failure names the table it happened on.
    lib::log::timed_yellow "[$((index + 1))/$total] Converting table '$table' (currently ${table_collation:-unknown}) ..."
    "${mysql_cmd[@]}" -e "$statement"
    converted=$((converted + 1))
  done

  lib::log::timed_green "Finished migration of MySQL database '$db_name' to charset $charset: $converted converted, $skipped already on target."
}

#######################################
# Decide whether a table is already on the target charset/collation.
# Globals:
#   None
# Arguments:
#   1 - The table's current collation (information_schema.TABLE_COLLATION)
#   2 - Target charset
#   3 - Target collation, or "" for the charset default
# Returns:
#   0 if the table already matches, 1 if it needs converting.
#######################################
function mysql_migrate_charset::matches() {
  local table_collation=${1} charset=${2} collation=${3}

  if [[ -z $table_collation ]]; then
    return 1
  fi

  # A specific collation was asked for, so only that exact one counts.
  if [[ -n $collation ]]; then
    [[ $table_collation == "$collation" ]]
    return $?
  fi

  # Otherwise any collation belonging to the target charset is fine.
  [[ $table_collation == "${charset}_"* ]]
}

# --------------------------------
#   MAIN
# --------------------------------

#######################################
# Parse the flags, resolve credentials and target, confirm, then migrate
# every database named by --databases.
# Globals:
#   OPTS, OPTS_HELP (read)
#   OPTS_VALUES (written by lib::opts::parse)
#   MYSQL_PWD (read as a fallback, exported for mysql)
# Arguments:
#   The script's original "$@"
# Returns:
#   0 on success, 1 on a usage, credential or confirmation error.
#######################################
function main() {
  local arg password password_file host port user charset collation dry_run assume_yes force db_name
  local -a db_names valid_names=()

  # --check-prerequisites answers on its own, before the parser can reject
  # the run for the required flags a prerequisite check has no use for.
  for arg in "$@"; do
    if [[ $arg == "--check-prerequisites" ]]; then
      mysql_migrate_charset::prerequisites
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
  # typed whether or not the migration below succeeds.
  if [[ ${OPTS_VALUES[scrub_history]:-} == "1" ]]; then
    trap 'lib::history::scrub "${MYSQL_PWD:-}" || true' EXIT
  fi

  host="${OPTS_VALUES[host]}"
  port="${OPTS_VALUES[port]:-3306}"
  user="${OPTS_VALUES[username]}"
  charset="${OPTS_VALUES[charset]:-utf8mb4}"
  collation="${OPTS_VALUES[collation]:-}"
  dry_run="${OPTS_VALUES[dry_run]:-}"
  assume_yes="${OPTS_VALUES[assume_yes]:-}"
  force="${OPTS_VALUES[force]:-}"

  # These two are interpolated into SQL unquoted, so they are checked
  # rather than escaped.
  if [[ ! $charset =~ ^[A-Za-z0-9_]+$ ]]; then
    lib::log::red "Invalid charset '$charset'; expected something like 'utf8mb4'."
    return 1
  fi

  if [[ -n $collation && ! $collation =~ ^[A-Za-z0-9_]+$ ]]; then
    lib::log::red "Invalid collation '$collation'; expected something like 'utf8mb4_unicode_ci'."
    return 1
  fi

  if [[ -n $collation && $collation != "${charset}_"* ]]; then
    lib::log::red "Collation '$collation' does not belong to charset '$charset'."
    return 1
  fi

  IFS=',' read -ra db_names <<<"${OPTS_VALUES[databases]}"

  for db_name in "${db_names[@]}"; do
    if [[ -z $db_name ]]; then
      lib::log::yellow "Skipping an empty database name in --databases."
      continue
    fi

    # The name goes into a WHERE clause as a string literal and into
    # ALTER DATABASE as an identifier; quoting characters have no business
    # in either.
    if [[ $db_name == *'`'* || $db_name == *"'"* || $db_name == *"\\"* ]]; then
      lib::log::red "Refusing database name '$db_name': quotes and backslashes are not supported."
      return 1
    fi

    valid_names+=("$db_name")
  done

  if [[ ${#valid_names[@]} -eq 0 ]]; then
    lib::log::red "No database names given in --databases."
    return 1
  fi

  if [[ $dry_run != "1" && $assume_yes != "1" ]]; then
    lib::log::yellow "About to rewrite every table in ${#valid_names[@]} database(s) on $host:$port as '$user':"
    for db_name in "${valid_names[@]}"; do
      lib::log::yellow "  - $db_name"
    done
    lib::log::yellow "A charset conversion rewrites table data in place and cannot be rolled back."
    lib::log::yellow "Take a dump with mysql-backup.sh first if you have not already."

    # No default, so an unattended run without --yes stops here instead of
    # rewriting a live database nobody was watching.
    if ! lib::ui::confirm "Continue?"; then
      lib::log::red "Aborted; nothing was migrated."
      return 1
    fi
  fi

  for db_name in "${valid_names[@]}"; do
    mysql_migrate_charset::exec "$host" "$port" "$user" "$db_name" \
      "$charset" "$collation" "$dry_run" "$force"
  done
}

# ------------
# 'main' call
# ------------
main "$@"
