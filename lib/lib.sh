# shellcheck shell=bash

# Single entrypoint for the whole library.
#
# Source this one file to get every lib:: function, instead of naming each
# module in every script:
#
#   . "$LIB_DIR"/lib.sh
#
# Modules are discovered rather than listed, so adding lib/<module>.sh needs
# no edit here. They only define functions, so load order does not matter.
# Sourcing twice is harmless: the second pass just redefines the same
# functions, and LIBSH_LOADED lets a caller skip it entirely.

# shellcheck disable=SC2034 # exported for callers that want to test it, not used here
LIBSH_LIB_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"

#######################################
# Source every module next to this file.
# Globals:
#   LIBSH_LIB_DIR (read)
#   LIBSH_LOADED (written)
# Arguments:
#   None
# Returns:
#   0 on success, 1 if no modules were found.
#######################################
function lib::lib::load() {
  local module found=0

  for module in "$LIBSH_LIB_DIR"/*.sh; do
    [[ -f $module ]] || continue
    [[ "$(basename "$module")" == "lib.sh" ]] && continue

    # shellcheck disable=SC1090 # the path is only known at runtime
    . "$module"
    found=$((found + 1))
  done

  if [[ $found -eq 0 ]]; then
    printf 'lib.sh: no modules found in %s\n' "$LIBSH_LIB_DIR" >&2
    return 1
  fi

  LIBSH_LOADED="$found"
  return 0
}

lib::lib::load
