# shellcheck shell=bash
#
# Bash helper functions for working with arrays.

# Determine if an array is empty
function lib::data::array_is_empty() {
  local array=("${@:1}")

  if [ ${#array[@]} -eq 0 ]; then
    return 0
  else
    return 1
  fi
}

# Determine if an array contains a certain string
function lib::data::array_contains() {
  local needle=${1} array=("${@:2}")

  if [[ " ${array[*]} " =~ [[:space:]]${needle}[[:space:]] ]]; then
    return 0
  else
    return 1
  fi
}

#######################################
# Validate an ordinary scalar reference for the container primitives.
# Globals:
#   Referenced variable (attributes inspected, never logged).
# Arguments:
#   1 - Variable name; 2 - read or write
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
