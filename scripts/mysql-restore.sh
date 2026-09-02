#!/usr/bin/env bash
#
# Restore dumps into MySQL-compatible databases (MySQL, Aurora MySQL).

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
  "-f,--files:files:1:required"
  "-d,--database:database:1:optional"
  "-y,--yes:assume_yes:0:optional"
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
  [files]="Comma-separated list of dump files to restore, in the given order"
  [database]="Database to restore into. Dumps taken by mysql-backup.sh name their own database, so this is only needed for dumps written without --databases."
  [assume_yes]="Skip the confirmation prompt (required for unattended runs)"
  [dry_run]="Print the mysql command(s) that would run, without executing them"
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
function restore_mysql::prerequisites() {
  local prerequisites=('mysql' 'pv' 'numfmt')

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
# Restore a single dump file.
# Globals:
#   MYSQL_PWD (read, by mysql itself)
# Arguments:
#   1 - Database host
#   2 - Database port
#   3 - Database user
#   4 - Database to restore into, or "" to let the dump decide
#   5 - Dump file path
#   6 - "1" for a dry run, "" otherwise
# Outputs:
#   Progress to stdout.
# Returns:
#   0 on success, otherwise the return value of 'mysql'.
#######################################
function restore_mysql::exec() {
  local host=${1} port=${2} user=${3} database=${4} filename=${5} dry_run=${6}
  local file_size size target

  local -a restore_cmd=(
    mysql
    -h "$host" -P "$port" -u "$user"
  )

  if [[ -n $database ]]; then
    restore_cmd+=(--database "$database")
  fi

  if [[ $dry_run == "1" ]]; then
    lib::log::yellow "[dry-run] MYSQL_PWD=**** pv $filename | ${restore_cmd[*]}"
    return 0
  fi

  file_size=$(wc -c <"$filename")
  size=$(numfmt --to=iec-i --suffix=B "$file_size")
  target=${database:-"the database named in the dump"}

  lib::log::timed_yellow "Restoring '$filename' (${size}) into $target on $host ..."

  pv --size "$file_size" -- "$filename" | "${restore_cmd[@]}"

  lib::log::timed_green "Finished restore of dump: $filename"
}

# --------------------------------
#   MAIN
# --------------------------------

#######################################
# Parse the flags, resolve credentials and target, confirm, then restore
# every dump named by --files.
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
  local arg password password_file host port user database dry_run assume_yes file
  local -a dump_files valid_files=()

  # --check-prerequisites answers on its own, before the parser can reject
  # the run for the required flags a prerequisite check has no use for.
  for arg in "$@"; do
    if [[ $arg == "--check-prerequisites" ]]; then
      restore_mysql::prerequisites
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
  # typed whether or not the restore below succeeds.
  if [[ ${OPTS_VALUES[scrub_history]:-} == "1" ]]; then
    trap 'lib::history::scrub "${MYSQL_PWD:-}" || true' EXIT
  fi

  host="${OPTS_VALUES[host]}"
  port="${OPTS_VALUES[port]:-3306}"
  user="${OPTS_VALUES[username]}"
  database="${OPTS_VALUES[database]:-}"
  dry_run="${OPTS_VALUES[dry_run]:-}"
  assume_yes="${OPTS_VALUES[assume_yes]:-}"

  IFS=',' read -ra dump_files <<<"${OPTS_VALUES[files]}"

  # Vet every dump up front: finding an unreadable file halfway through
  # leaves the target half-restored.
  for file in "${dump_files[@]}"; do
    if [[ -z $file ]]; then
      lib::log::yellow "Skipping an empty file name in --files."
      continue
    fi

    if [[ ! -f $file || ! -r $file ]]; then
      lib::log::red "Dump file '$file' does not exist or is not readable."
      return 1
    fi

    valid_files+=("$file")
  done

  if [[ ${#valid_files[@]} -eq 0 ]]; then
    lib::log::red "No dump files given in --files."
    return 1
  fi

  if [[ $dry_run != "1" && $assume_yes != "1" ]]; then
    lib::log::yellow "About to restore ${#valid_files[@]} dump file(s) into $host:$port as '$user':"
    for file in "${valid_files[@]}"; do
      lib::log::yellow "  - $file"
    done

    # No default, so an unattended run without --yes stops here instead of
    # overwriting a live database nobody was watching.
    if ! lib::ui::confirm "This overwrites existing data. Continue?"; then
      lib::log::red "Aborted; nothing was restored."
      return 1
    fi
  fi

  for file in "${valid_files[@]}"; do
    restore_mysql::exec "$host" "$port" "$user" "$database" "$file" "$dry_run"
  done
}

# ------------
# 'main' call
# ------------
main "$@"
