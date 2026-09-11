# shellcheck shell=bash
#
# Bash general utility functions.

# shellcheck disable=SC1090,SC1091 # the sourced paths only exist at runtime

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
__libsh_utils_scalar_reference() {
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
# Reload the rc files for Bash (and/or Zsh).
# Globals:
#   HOME (read)
# Arguments:
#   None
# Returns:
#   0, whether or not either file exists.
#######################################
function lib::utils::rc() {
  if [ -e "${HOME}/.bashrc" ]; then source "${HOME}/.bashrc"; fi
  if [ -e "${HOME}/.zshrc" ]; then source "${HOME}/.zshrc"; fi

  return 0
}

#######################################
# Activate the Python venv in the current directory, creating it first if
# it does not exist yet.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Whatever 'python -m venv' writes, when it has to create the venv.
# Returns:
#   0 on success, otherwise the return value of 'python -m venv'.
#######################################
function lib::utils::venv() {
  local venv activate python

  venv="$(pwd)/.venv"
  activate="$venv/bin/activate"

  if [[ ! -e $activate ]]; then
    # Ubuntu and Debian ship 'python3' with no unversioned 'python'.
    python=python3
    command -v python3 >/dev/null 2>&1 || python=python

    "$python" -m venv "$venv" || return $?
  fi

  source "$activate"
}
