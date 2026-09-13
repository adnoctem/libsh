# shellcheck shell=bash

# Source this entrypoint for core; request installed addons separately.
LIBSH_LIB_DIR="$(cd -P -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)" || return 1

#######################################
# Load core modules from this physically resolved library directory.
# Globals:
#   LIBSH_LIB_DIR (read), LIBSH_LOADED, LIBSH_LOADED_VERSION (written)
#   __libsh_lib_core_dir, __libsh_lib_extensions (internal load state)
# Arguments:
#   1 - None. Use lib::load_extensions for addons.
# Outputs:
#   Errors on stderr.
# Returns:
#   0 success, 1 missing/unreadable sources, 2 unexpected arguments.
#   Source failures propagate their status. Successfully loaded core is reused.
#######################################
# shellcheck disable=SC2120 # arguments are explicitly rejected
function lib::load() {
  local __libsh_lib_module __libsh_lib_found=0
  local __libsh_lib_version=development

  if [[ $# != 0 ]]; then
    printf 'libsh: lib::load takes no arguments; use lib::load_extensions for addons.\n' >&2
    return 2
  fi

  if [[ ${__libsh_lib_core_dir:-} != "$LIBSH_LIB_DIR" ]]; then
    if [[ -f $LIBSH_LIB_DIR/.libsh-version ]]; then
      IFS= read -r __libsh_lib_version <"$LIBSH_LIB_DIR/.libsh-version" || return 1
    fi
    for __libsh_lib_module in "$LIBSH_LIB_DIR"/*.sh; do
      [[ -f $__libsh_lib_module ]] || continue
      [[ ${__libsh_lib_module##*/} == lib.sh ]] && continue
      # shellcheck disable=SC1090 # physically resolved module path
      . "$__libsh_lib_module" || return $?
      __libsh_lib_found=$((__libsh_lib_found + 1))
    done
    if [[ $__libsh_lib_found == 0 ]]; then
      printf 'libsh: no core modules found in %s\n' "$LIBSH_LIB_DIR" >&2
      return 1
    fi
    # shellcheck disable=SC2034 # public loader metadata
    LIBSH_LOADED=$__libsh_lib_found
    # shellcheck disable=SC2034 # public release metadata
    LIBSH_LOADED_VERSION=$__libsh_lib_version
    __libsh_lib_extensions=' '
    __libsh_lib_core_dir=$LIBSH_LIB_DIR
  fi

  return 0
}

#######################################
# Load explicitly requested installed addons after ensuring core is loaded.
# Globals:
#   LIBSH_LIB_DIR, __libsh_lib_extensions (read/write via loader)
# Arguments:
#   1+ - Zero or more extension names, e.g. secret git apt.
# Outputs:
#   Errors on stderr. Never installs or downloads extensions.
# Returns:
#   0 success, 1 unavailable source, 2 invalid name; source failures propagate.
#   Repeated loads are harmless. Failed sources may have partial shell effects
#   and are never marked loaded. Preflight checks every requested addon first.
#######################################
function lib::load_extensions() {
  local __libsh_lib_name

  # Preflight the entire request before sourcing any requested addon.
  for __libsh_lib_name in ${1+"$@"}; do
    if [[ ! $__libsh_lib_name =~ ^[a-z][a-z0-9_]*$ ]]; then
      printf 'libsh: invalid extension name: %s\n' "$__libsh_lib_name" >&2
      return 2
    fi
    if [[ ! -f $LIBSH_LIB_DIR/../extensions/lib$__libsh_lib_name.sh ||
      ! -r $LIBSH_LIB_DIR/../extensions/lib$__libsh_lib_name.sh ]]; then
      printf 'libsh: extension %s is unavailable; install it for this core release.\n' "$__libsh_lib_name" >&2
      return 1
    fi
  done

  # shellcheck disable=SC2119 # core takes no arguments
  lib::load || return $?

  for __libsh_lib_name in ${1+"$@"}; do
    [[ $__libsh_lib_extensions == *" $__libsh_lib_name "* ]] && continue
    # shellcheck disable=SC1090 # name validated above; same release as core
    . "$LIBSH_LIB_DIR/../extensions/lib$__libsh_lib_name.sh" || return $?
    __libsh_lib_extensions+="$__libsh_lib_name "
  done

  return 0
}

# Sourcing always loads core, independently of consumer positional arguments.
# shellcheck disable=SC2119
lib::load
