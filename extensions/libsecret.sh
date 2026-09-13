# shellcheck shell=bash

# Read secrets from disk, so they never have to appear in argv where
# 'ps' and the shell history can see them.

#######################################
# Read a secret from the first line of a file.
#
# Only the first line is used: a trailing newline is an editor artifact,
# not part of the secret.
# Globals:
#   None
# Arguments:
#   1 - Path to the file holding the secret
# Outputs:
#   The secret to stdout. Warnings and errors go to stderr, so callers can
#   capture the value with a command substitution without catching them.
# Returns:
#   0 on success, 1 if the file is missing, unreadable or empty.
#######################################
function ext::secret::from_file() {
  local path=${1} mode secret

  if [[ ! -f $path ]]; then
    lib::log::red "Secret file '$path' does not exist."
    return 1
  fi

  if [[ ! -r $path ]]; then
    lib::log::red "Secret file '$path' is not readable."
    return 1
  fi

  # A secret every account on the box can read defeats the point of
  # keeping it off the command line in the first place. '-c' is GNU-only;
  # '-f' with a BSD-style format is the macOS/BSD stat equivalent.
  mode=$(stat -c '%a' "$path" 2>/dev/null || stat -f '%Lp' "$path" 2>/dev/null || true)

  if [[ -n $mode && ! $mode =~ ^[0-7]?[0-7]00$ ]]; then
    lib::log::yellow "Secret file '$path' is mode $mode; 600 is recommended." >&2
  fi

  IFS= read -r secret <"$path" || true

  if [[ -z $secret ]]; then
    lib::log::red "Secret file '$path' is empty."
    return 1
  fi

  printf '%s' "$secret"
}

#######################################
# Read a text secret into an ordinary caller variable.
# Globals:
#   Named output variable (written only on success).
# Arguments:
#   1 - Output variable name
#   2 - File path
#   3+ - Optional --mode text|first-line and --allow-empty
# Outputs:
#   Sanitized errors on stderr; no stdout.
# Returns:
#   0 success, 1 I/O/dependency failure, 2 invalid input.
#######################################
function ext::secret::read_file() {
  [[ $# -ge 2 ]] || {
    lib::log::red 'read_file requires OUT and PATH.'
    return 2
  }
  __libsh_data_scalar_reference "$1" write || return 2
  local __libsh_read_out=$1 __libsh_read_path=$2
  local __libsh_read_mode=text __libsh_read_empty=0 __libsh_read_seen=0

  shift 2

  while [[ $# -gt 0 ]]; do
    case $1 in
      --mode)
        [[ $# -ge 2 && $__libsh_read_seen == 0 && ($2 == text || $2 == first-line) ]] || {
          lib::log::red 'Invalid or duplicate secret read mode.'
          return 2
        }
        __libsh_read_mode=$2 __libsh_read_seen=1
        shift 2
        ;;
      --allow-empty)
        [[ $__libsh_read_empty == 0 ]] || {
          lib::log::red 'Duplicate empty-value policy.'
          return 2
        }
        __libsh_read_empty=1
        shift
        ;;
      *)
        lib::log::red 'Unknown secret read option.'
        return 2
        ;;
    esac
  done

  __libsh_ext_secret_read_text "$__libsh_read_out" "$__libsh_read_path" "$__libsh_read_mode" "$__libsh_read_empty"
}

#######################################
# Read once through od, validating status and every byte before assignment.
# Globals:
#   Named output variable (may be an internal destination).
# Arguments:
#   1 - Output variable name
#   2 - File path
#   3 - Mode (already validated)
#   4 - Allow-empty flag (already validated)
# Outputs:
#   Sanitized errors on stderr.
# Returns:
#   0 success, 1 I/O/dependency failure, 2 invalid text/empty selection.
#######################################
function __libsh_ext_secret_read_text() {
  local __libsh_bytes_dump __libsh_bytes_line __libsh_bytes_byte
  local __libsh_bytes_escape='' __libsh_bytes_done=0
  local -a __libsh_bytes_row=()

  if [[ ! -f $2 || ! -r $2 ]]; then
    lib::log::red 'Secret input must be a readable regular file.'
    return 1
  fi

  command -v od >/dev/null 2>&1 || {
    lib::log::red "Secret reading requires 'od'."
    return 1
  }

  # Only the octal representation enters command substitution. Its formatting
  # newlines are disposable; the original bytes (including NUL) are preserved.
  # Redirection opens the selected inode once, including projected symlinks.
  if ! __libsh_bytes_dump=$({ LC_ALL=C od -An -v -t o1 <"$2"; } 2>/dev/null); then
    lib::log::red 'Failed to read secret input.'
    return 1
  fi

  while IFS= read -r __libsh_bytes_line; do
    IFS=' ' read -r -a __libsh_bytes_row <<<"$__libsh_bytes_line"
    for __libsh_bytes_byte in ${__libsh_bytes_row[@]+"${__libsh_bytes_row[@]}"}; do
      if [[ ! $__libsh_bytes_byte =~ ^[0-3][0-7][0-7]$ || $__libsh_bytes_byte == 000 ]]; then
        lib::log::red 'Secret input contains NUL or invalid byte data.'
        return 2
      fi
      if [[ $3 == first-line && $__libsh_bytes_byte == 012 ]]; then
        __libsh_bytes_done=1
      fi
      if [[ $__libsh_bytes_done == 0 ]]; then
        __libsh_bytes_escape+="\\0$__libsh_bytes_byte"
      fi
    done
  done <<<"$__libsh_bytes_dump"

  if [[ -z $__libsh_bytes_escape && $4 != 1 ]]; then
    lib::log::red 'Selected secret value is empty.'
    return 2
  fi

  printf -v "$1" '%b' "$__libsh_bytes_escape"
}

#######################################
# Resolve explicitly named direct/file variables without exporting the result.
# Globals:
#   Named input variables (read) and output variable (written/unset on success).
# Arguments:
#   1 - Output variable name
#   2+ - --value-var NAME and --file-var NAME; optional --mode
#        text|first-line, --allow-empty and --precedence presence|nonempty
# Outputs:
#   Sanitized errors on stderr; no stdout.
# Returns:
#   0 success (including absence), 1 I/O/dependency failure, 2 invalid input.
#######################################
function ext::secret::resolve() {
  [[ $# -ge 1 ]] || {
    lib::log::red 'resolve requires an output variable.'
    return 2
  }
  __libsh_data_scalar_reference "$1" write || return 2
  local __libsh_res_out=$1 __libsh_res_value='' __libsh_res_file=''
  local __libsh_res_mode=text __libsh_res_empty=0 __libsh_res_precedence=presence
  local __libsh_res_seen=' ' __libsh_res_selected __libsh_res_has=0

  shift

  while [[ $# -gt 0 ]]; do
    if [[ $__libsh_res_seen == *" $1 "* ]]; then
      lib::log::red 'Duplicate resolver option.'
      return 2
    fi
    __libsh_res_seen+="$1 "
    case $1 in
      --allow-empty)
        __libsh_res_empty=1
        shift
        ;;
      --value-var | --file-var | --mode | --precedence)
        [[ $# -ge 2 ]] || {
          lib::log::red 'Missing resolver option argument.'
          return 2
        }
        case $1 in
          --value-var) __libsh_res_value=$2 ;;
          --file-var) __libsh_res_file=$2 ;;
          --mode) __libsh_res_mode=$2 ;;
          --precedence) __libsh_res_precedence=$2 ;;
        esac
        shift 2
        ;;
      *)
        lib::log::red 'Unknown resolver option.'
        return 2
        ;;
    esac
  done

  __libsh_data_scalar_reference "$__libsh_res_value" read || return 2
  __libsh_data_scalar_reference "$__libsh_res_file" read || return 2

  if [[ $__libsh_res_out == "$__libsh_res_file" ||
    ($__libsh_res_mode != text && $__libsh_res_mode != first-line) ||
    ($__libsh_res_precedence != presence && $__libsh_res_precedence != nonempty) ]]; then
    lib::log::red 'Invalid resolver policy or aliased file reference.'
    return 2
  fi

  # ${!name+x} distinguishes absence from an explicitly empty scalar on Bash 4.0.
  if [[ ${!__libsh_res_value+x} ]]; then
    __libsh_res_selected=${!__libsh_res_value}
    if [[ $__libsh_res_precedence == presence || -n $__libsh_res_selected ]]; then
      __libsh_res_has=1
    fi
  fi

  if [[ $__libsh_res_has == 0 && ${!__libsh_res_file+x} ]]; then
    [[ -n ${!__libsh_res_file} ]] || {
      lib::log::red 'Selected secret file path is empty.'
      return 2
    }
    __libsh_ext_secret_read_text __libsh_res_selected "${!__libsh_res_file}" "$__libsh_res_mode" "$__libsh_res_empty" || return $?
    __libsh_res_has=1
  fi

  if [[ $__libsh_res_has == 0 ]]; then
    unset -v "$__libsh_res_out"
    return 0
  fi

  if [[ -z $__libsh_res_selected && $__libsh_res_empty == 0 ]]; then
    lib::log::red 'Selected secret value is empty.'
    return 2
  fi

  printf -v "$__libsh_res_out" '%s' "$__libsh_res_selected"
}
