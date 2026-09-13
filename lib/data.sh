# shellcheck shell=bash
#######################################
#
# Array membership, scalar references and exact byte conversion.
# Determine if an array is empty
# Globals:
#   None
# Arguments:
#   1+ - Array elements (zero or more)
# Outputs:
#   None
# Returns:
#   0 if empty, 1 otherwise.
#######################################
function lib::data::array_is_empty() {
  local array=("${@:1}")

  if [ ${#array[@]} -eq 0 ]; then
    return 0
  else
    return 1
  fi
}

#######################################
# Test literal membership in the supplied array elements.
# Globals:
#   None
# Arguments:
#   1 - Needle
#   2+ - Array elements (zero or more)
# Outputs:
#   Errors on stderr.
# Returns:
#   0 found, 1 absent, 2 missing needle.
#######################################
function lib::data::array_contains() {
  if [[ $# == 0 ]]; then
    lib::log::red 'array_contains requires a needle.'
    return 2
  fi

  local needle=$1 element

  shift

  for element in ${1+"$@"}; do
    [[ $element != "$needle" ]] || return 0
  done

  return 1
}

#######################################
# Validate an ordinary scalar reference for the container primitives.
# Globals:
#   Referenced variable (attributes inspected, never logged).
# Arguments:
#   1 - Variable name
#   2 - Reference access: read or write
# Outputs:
#   Sanitized error on stderr.
# Returns:
#   0 if usable, 2 otherwise.
#######################################
function __libsh_data_scalar_reference() {
  local LC_ALL=C
  local __libsh_ref_decl __libsh_ref_flags

  if [[ ! ${1:-} =~ ^[a-zA-Z_][a-zA-Z_0-9]*$ ]]; then
    lib::log::red 'Expected an ordinary scalar variable name.'
    return 2
  fi

  # Shell-owned variables and implementation locals are not application storage.
  case $1 in
    __libsh_* | BASH* | COMP_* | DIRSTACK | EUID | UID | PPID | GROUPS | FUNCNAME | \
      IFS | PATH | CDPATH | ENV | SHELLOPTS | GLOBIGNORE | FIGNORE | LANG | LC_* | \
      HIST* | HOME | HOSTNAME | HOSTTYPE | MACHTYPE | OSTYPE | OPT* | POSIXLY_CORRECT | \
      PWD | OLDPWD | RANDOM | SRANDOM | SECONDS | EPOCH* | LINENO | PIPESTATUS | \
      SHLVL | REPLY | PROMPT_COMMAND | PROMPT_DIRTRIM | PS[0-4] | TIMEFORMAT | TMOUT | \
      MAIL | MAILCHECK | MAILPATH | GLOBSORT | COPROC | MAPFILE | _)
      lib::log::red 'Reserved variable reference.'
      return 2
      ;;
  esac

  if __libsh_ref_decl=$(declare -p "$1" 2>/dev/null); then
    __libsh_ref_flags=${__libsh_ref_decl#declare -}
    __libsh_ref_flags=${__libsh_ref_flags%% *}
    if [[ $__libsh_ref_flags == *[aAinlu]* ||
      (${2:-write} == write && $__libsh_ref_flags == *r*) ]]; then
      lib::log::red 'Variable must be an ordinary, non-transforming scalar (writable for output).'
      return 2
    fi
  fi

  return 0
}

#######################################
# Normalize a nonnegative decimal integer within signed 64-bit range.
# Globals:
#   None
# Arguments:
#   1 - Nonnegative decimal integer
# Outputs:
#   Normalized integer on stdout, no diagnostics.
# Returns:
#   0 valid, 2 invalid/out of range.
#######################################
function __libsh_data_uint() {
  local LC_ALL=C value=${1:-}

  [[ $value =~ ^[0-9]+$ ]] || return 2

  while [[ ${#value} -gt 1 && $value == 0* ]]; do
    value=${value#0}
  done

  # shellcheck disable=SC2071 # equal-length decimal strings, before arithmetic
  [[ ${#value} -lt 19 || (${#value} == 19 && ! $value > 9223372036854775807) ]] || return 2
  printf '%s' "$value"
}

#######################################
# Resolve explicit decimal or binary byte units, case sensitively.
# Globals:
#   None
# Arguments:
#   1 - Unit: B, KB..EB or KiB..EiB (case sensitive)
# Outputs:
#   Integer multiplier on stdout.
# Returns:
#   0 recognized, 2 unknown.
#######################################
function __libsh_data_byte_factor() {
  case ${1:-} in
    B) printf 1 ;;
    KB) printf 1000 ;;
    MB) printf 1000000 ;;
    GB) printf 1000000000 ;;
    TB) printf 1000000000000 ;;
    PB) printf 1000000000000000 ;;
    EB) printf 1000000000000000000 ;;
    KiB) printf 1024 ;;
    MiB) printf 1048576 ;;
    GiB) printf 1073741824 ;;
    TiB) printf 1099511627776 ;;
    PiB) printf 1125899906842624 ;;
    EiB) printf 1152921504606846976 ;;
    *) return 2 ;;
  esac
}

#######################################
# Convert a whole number of explicit units to bytes without rounding.
# Globals:
#   None
# Arguments:
#   1 - Whole nonnegative amount
#   2 - Unit: B, KB..EB or KiB..EiB (case sensitive)
# Outputs:
#   Decimal bytes on stdout; errors on stderr.
# Returns:
#   0 success, 2 invalid arguments, fractions, or signed 64-bit overflow.
#######################################
function lib::data::bytes_from() {
  local amount factor

  if [[ $# != 2 ]] || ! amount=$(__libsh_data_uint "$1") \
    || ! factor=$(__libsh_data_byte_factor "$2"); then
    lib::log::red 'bytes_from requires a whole nonnegative amount and a supported byte unit.'
    return 2
  fi

  if ((amount > 9223372036854775807 / factor)); then
    lib::log::red 'Byte value exceeds the signed 64-bit range.'
    return 2
  fi

  printf '%s\n' "$((amount * factor))"
}

#######################################
# Render validated bytes with fixed decimal precision, truncating toward zero.
# Globals:
#   None
# Arguments:
#   1 - Validated bytes
#   2 - Positive unit multiplier
#   3 - Precision, 0..6
# Outputs:
#   Decimal number on stdout, without newline or unit label.
# Returns:
#   0 success.
#######################################
function __libsh_data_bytes_render() {
  local bytes=$1 factor=$2 precision=$3 remainder digit accum i j

  printf '%s' "$((bytes / factor))"
  remainder=$((bytes % factor))

  if ((precision > 0)); then
    printf '.'
  fi

  for ((i = 0; i < precision; i++)); do
    # Long division without computing remainder*10, which can overflow.
    digit=0 accum=0
    for ((j = 0; j < 10; j++)); do
      if ((accum >= factor - remainder)); then
        accum=$((accum - (factor - remainder)))
        digit=$((digit + 1))
      else
        accum=$((accum + remainder))
      fi
    done

    remainder=$accum
    printf '%s' "$digit"
  done
}

#######################################
# Convert bytes to a numeric display value in explicit units.
# Globals:
#   None
# Arguments:
#   1 - Bytes
#   2 - Unit: B, KB..EB or KiB..EiB (case sensitive)
#   3 - Precision, 0..6 (optional, default 2)
# Outputs:
#   Fixed-point value on stdout, truncated (never rounded up).
# Returns:
#   0 success, 2 invalid arguments or bytes outside signed 64-bit range.
#######################################
function lib::data::bytes_to() {
  local bytes factor precision=${3-2}

  if [[ $# -lt 2 || $# -gt 3 || ! $precision =~ ^[0-6]$ ]] \
    || ! bytes=$(__libsh_data_uint "$1") || ! factor=$(__libsh_data_byte_factor "$2"); then
    lib::log::red 'bytes_to requires bytes, a supported unit, and precision from 0 to 6.'
    return 2
  fi

  __libsh_data_bytes_render "$bytes" "$factor" "$precision"
  printf '\n'
}

#######################################
# Format bytes using the largest applicable SI or IEC unit.
# Globals:
#   None
# Arguments:
#   1 - Bytes
#   2 - System: iec or si (optional, default iec)
#   3 - Precision, 0..6 (optional, default 2)
# Outputs:
#   Fixed-point number, space, unit and newline. Fractions are truncated.
# Returns:
#   0 success, 2 invalid arguments or signed 64-bit overflow.
#######################################
function lib::data::bytes_format() {
  local bytes system=${2-iec} precision=${3-2} factor=1 base index=0
  local -a units

  if [[ $# -lt 1 || $# -gt 3 || ! $precision =~ ^[0-6]$ ]] \
    || ! bytes=$(__libsh_data_uint "$1"); then
    lib::log::red 'bytes_format requires bytes and precision from 0 to 6.'
    return 2
  fi

  case $system in
    iec)
      base=1024
      units=(B KiB MiB GiB TiB PiB EiB)
      ;;
    si)
      base=1000
      units=(B KB MB GB TB PB EB)
      ;;
    *)
      lib::log::red 'Byte display system must be si or iec.'
      return 2
      ;;
  esac

  while ((index < 6 && bytes / factor >= base)); do
    factor=$((factor * base))
    index=$((index + 1))
  done

  __libsh_data_bytes_render "$bytes" "$factor" "$precision"
  printf ' %s\n' "${units[$index]}"
}
