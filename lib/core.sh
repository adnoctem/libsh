# shellcheck shell=bash

# Shared version, retry and operation-result helpers.

#######################################
# Validate one complete SemVer 2.0.0 string, without numeric coercion.
# Specification: https://semver.org/spec/v2.0.0.html
# Globals:
#   None
# Arguments:
#   1 - Version (no leading v or surrounding whitespace)
# Outputs:
#   Invocation errors on stderr; otherwise none.
# Returns:
#   0 valid, 1 invalid version, 2 incorrect argument count.
#######################################
function lib::core::semver_validate() {
  if [[ $# != 1 ]]; then
    lib::log::red 'semver_validate requires one version.'
    return 2
  fi

  local LC_ALL=C version=$1 main identifiers item
  local -a parts

  main=${version%%+*}
  if [[ $version == *+* ]]; then
    identifiers=${version#*+}
    [[ $identifiers =~ ^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*$ ]] || return 1
  fi

  if [[ $main == *-* ]]; then
    identifiers=${main#*-}
    main=${main%%-*}
    [[ $identifiers =~ ^[a-zA-Z0-9-]+(\.[a-zA-Z0-9-]+)*$ ]] || return 1

    IFS=. read -r -a parts <<<"$identifiers"
    for item in "${parts[@]}"; do
      [[ ! $item =~ ^[0-9]+$ || $item == 0 || $item != 0* ]] || return 1
    done
  fi

  [[ $main =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

#######################################
# Extract a field from a complete, validated SemVer string.
# Globals:
#   None
# Arguments:
#   1 - Complete version
#   2 - Field: major, minor, patch, prerelease or build
# Outputs:
#   Field and newline on stdout; absent prerelease/build prints an empty
#   line. Original numeric strings are preserved without integer-size limits.
# Returns:
#   0 success, 2 invalid version, field, or argument count.
#######################################
function lib::core::semver_parse() {
  if [[ $# != 2 ]] || ! lib::core::semver_validate "$1"; then
    lib::log::red 'semver_parse requires a valid complete version and field.'
    return 2
  fi

  local version=$1 field=$2 main prerelease='' build='' value

  main=${version%%+*}
  [[ $version != *+* ]] || build=${version#*+}

  if [[ $main == *-* ]]; then
    prerelease=${main#*-}
    main=${main%%-*}
  fi

  case $field in
    major) value=${main%%.*} ;;
    minor)
      value=${main#*.}
      value=${value%%.*}
      ;;
    patch) value=${main##*.} ;;
    prerelease) value=$prerelease ;;
    build) value=$build ;;
    *)
      lib::log::red 'Unknown SemVer field.'
      return 2
      ;;
  esac

  printf '%s\n' "$value"
}

#######################################
# Retry an argv command with a fixed interval and bounded number of attempts.
# Interval is whole nonnegative seconds; attempts is a positive integer.
# This is not a deadline and does not terminate a hung command. Check command
# failures explicitly inside shell functions: invocation is in an if context.
# Globals:
#   None; each command runs in a subshell to isolate its shell changes.
# Arguments:
#   1 - Interval in whole nonnegative seconds
#   2 - Positive attempt count
#   3 - Literal -- separator
#   4 - Command to run
#   5+ - Command arguments (optional)
# Outputs:
#   Command stdout/stderr unchanged; library diagnostics on stderr.
# Returns:
#   0 command succeeded, 1 all attempts failed or sleep failed,
#   2 invalid invocation. No sleep after success or the final failed attempt.
#######################################
function lib::core::retry() {
  local __libsh_core_interval __libsh_core_attempts __libsh_core_attempt

  if [[ $# -lt 4 || ${3:-} != -- || -z ${4:-} ]] \
    || ! __libsh_core_interval=$(__libsh_data_uint "$1") \
    || ! __libsh_core_attempts=$(__libsh_data_uint "$2") \
    || [[ $__libsh_core_attempts == 0 ]]; then
    lib::log::red 'retry requires INTERVAL ATTEMPTS -- COMMAND [ARG...].'
    return 2
  fi

  shift 3

  for ((__libsh_core_attempt = 1; ; __libsh_core_attempt++)); do
    if ("$@"); then
      return 0
    fi

    ((__libsh_core_attempt < __libsh_core_attempts)) || break

    if ((__libsh_core_interval > 0)); then
      if ! sleep "$__libsh_core_interval"; then
        lib::log::red 'Retry interval sleep failed.'
        return 1
      fi
    fi
  done

  lib::log::red 'Command failed on every retry attempt.'
  return 1
}

#######################################
# Read and validate an opaque caller-owned result store.
# Globals:
#   Named scalar store (read), never modified.
# Arguments:
#   1 - Caller-owned scalar store name
#   2 - Reference access: read or write
# Outputs:
#   Validated store contents on stdout; sanitized errors on stderr.
# Returns:
#   0 valid (unset/empty is an empty store), 2 invalid reference/content.
#######################################
function __libsh_core_results_read() {
  __libsh_data_scalar_reference "$1" "$2" || return 2

  local __libsh_core_name=$1 __libsh_core_value __libsh_core_line
  local __libsh_core_id __libsh_core_status
  local -A __libsh_core_seen=()

  __libsh_core_value=${!__libsh_core_name-}
  if [[ -n $__libsh_core_value ]]; then
    while IFS= read -r __libsh_core_line; do
      __libsh_core_id=${__libsh_core_line%%$'\t'*}
      __libsh_core_status=${__libsh_core_line#*$'\t'}

      if [[ $__libsh_core_line != *$'\t'* ||
        ! $__libsh_core_id =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.:-]*$ ||
        ! $__libsh_core_status =~ ^(pending|success|failure)$ ||
        ${__libsh_core_seen[$__libsh_core_id]+set} ]]; then
        lib::log::red 'Invalid result store contents.'
        return 2
      fi
      __libsh_core_seen[$__libsh_core_id]=1
    done <<<"$__libsh_core_value"
  fi

  printf '%s' "$__libsh_core_value"
}

#######################################
# Add or update one operation in a caller-owned result store.
# Declare a local scalar first to keep the store local. Treat its
# serialization
# as opaque; results_list supplies stable tab-separated output. IDs contain
# ASCII letters/digits/underscore, then optionally dot, colon or hyphen.
# Globals:
#   Named ordinary scalar STORE (written on success); no hidden store.
# Arguments:
#   1 - Caller-owned scalar store name
#   2 - Operation ID
#   3 - Status: pending, success or failure
# Outputs:
#   None on success; errors on stderr.
# Returns:
#   0 added/updated, 2 invalid input/store. Failures preserve the store.
#######################################
function lib::core::results_add() {
  local LC_ALL=C
  local __libsh_core_name=${1:-} __libsh_core_id=${2:-} __libsh_core_status=${3:-}
  local __libsh_core_state __libsh_core_line __libsh_core_next=''

  if [[ $# != 3 || ! $__libsh_core_id =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.:-]*$ ||
    ! $__libsh_core_status =~ ^(pending|success|failure)$ ]]; then
    lib::log::red 'results_add requires STORE ID and pending, success, or failure.'
    return 2
  fi

  __libsh_core_state=$(__libsh_core_results_read "$__libsh_core_name" write) || return 2

  if [[ -n $__libsh_core_state ]]; then
    while IFS= read -r __libsh_core_line; do
      [[ ${__libsh_core_line%%$'\t'*} != "$__libsh_core_id" ]] || continue
      __libsh_core_next+="${__libsh_core_next:+$'\n'}$__libsh_core_line"
    done <<<"$__libsh_core_state"
  fi

  __libsh_core_next+="${__libsh_core_next:+$'\n'}$__libsh_core_id"$'\t'"$__libsh_core_status"
  printf -v "$__libsh_core_name" '%s' "$__libsh_core_next"
}

#######################################
# Remove an operation from a caller-owned result store; absent IDs are a
# no-op.
# Globals:
#   Named scalar STORE (written on success).
# Arguments:
#   1 - Caller-owned scalar store name
#   2 - Operation ID
# Outputs:
#   Errors on stderr only.
# Returns:
#   0 removed/absent, 2 invalid input/store. Failures preserve the store.
#######################################
function lib::core::results_remove() {
  local LC_ALL=C
  local __libsh_core_name=${1:-} __libsh_core_id=${2:-}
  local __libsh_core_state __libsh_core_line __libsh_core_next=''

  if [[ $# != 2 || ! $__libsh_core_id =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.:-]*$ ]]; then
    lib::log::red 'results_remove requires STORE and a valid operation ID.'
    return 2
  fi

  __libsh_core_state=$(__libsh_core_results_read "$__libsh_core_name" write) || return 2
  [[ -n $__libsh_core_state ]] || return 0

  while IFS= read -r __libsh_core_line; do
    [[ ${__libsh_core_line%%$'\t'*} != "$__libsh_core_id" ]] || continue
    __libsh_core_next+="${__libsh_core_next:+$'\n'}$__libsh_core_line"
  done <<<"$__libsh_core_state"

  printf -v "$__libsh_core_name" '%s' "$__libsh_core_next"
}

#######################################
# List operations sorted by ID in ASCII order, optionally filtered by status.
# Globals:
#   Named scalar STORE (read only).
# Arguments:
#   1 - Caller-owned scalar store name
#   2 - Status filter: pending, success or failure (optional)
# Outputs:
#   ID<TAB>STATUS per line. Empty stores/selections produce no stdout.
# Returns:
#   0 success, 1 sort failure, 2 invalid reference/content/filter.
# Dependencies:
#   sort, only for nonempty output.
#######################################
function lib::core::results_list() {
  local LC_ALL=C
  local __libsh_core_state __libsh_core_line __libsh_core_next='' __libsh_core_sorted

  if [[ $# -lt 1 || $# -gt 2 || ($# == 2 && ! $2 =~ ^(pending|success|failure)$) ]]; then
    lib::log::red 'results_list requires STORE and an optional result status.'
    return 2
  fi

  __libsh_core_state=$(__libsh_core_results_read "$1" read) || return 2
  [[ -n $__libsh_core_state ]] || return 0

  while IFS= read -r __libsh_core_line; do
    [[ $# == 1 || ${__libsh_core_line#*$'\t'} == "$2" ]] || continue
    __libsh_core_next+="${__libsh_core_next:+$'\n'}$__libsh_core_line"
  done <<<"$__libsh_core_state"

  [[ -n $__libsh_core_next ]] || return 0

  if ! __libsh_core_sorted=$(printf '%s\n' "$__libsh_core_next" | LC_ALL=C sort); then
    lib::log::red 'Could not sort operation results.'
    return 1
  fi

  printf '%s\n' "$__libsh_core_sorted"
}
