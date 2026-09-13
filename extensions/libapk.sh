# shellcheck shell=bash

# Read installed Alpine packages and locally cached upgrade information.

#######################################
# Check whether one literal Alpine package name is installed.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Package name, without version constraints or globs
# Outputs:
#   None
# Returns:
#   0 installed, 1 absent/backend failure, 2 invalid invocation.
# Dependencies:
#   apk, only at invocation.
#######################################
function ext::apk::is_installed() {
  [[ $# == 1 && $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9+_.-]*$ ]] || return 2
  apk info --exists -- "$1" >/dev/null 2>&1 || return 1
}

#######################################
# List installed packages older than their locally cached repository versions.
# Does not refresh indexes or modify packages; stale indexes give stale results.
# Globals:
#   PATH (read)
# Arguments:
#   None
# Outputs:
#   Package names, one per line; errors to stderr. No partial output on failure.
# Returns:
#   0 success (including no updates), 1 backend/parse failure, 2 invalid invocation.
# Dependencies:
#   apk, only at invocation.
#######################################
function ext::apk::pending_packages() {
  [[ $# == 0 ]] || return 2
  local data installed relation available extra name output=''
  data=$(LC_ALL=C apk version --limit '<') || return 1

  while read -r installed relation available extra; do
    [[ -n $installed ]] || continue
    [[ $installed != Installed && $installed != Installed: ]] || continue
    [[ $relation == '<' && -n $available && -z $extra ]] || return 1
    # Alpine versions start with a digit; choose the last such delimiter so
    # digits and hyphens in a package name remain intact.
    name=${installed%-[0-9]*}
    [[ $name != "$installed" && $name =~ ^[a-zA-Z0-9][a-zA-Z0-9+_.-]*$ ]] || return 1
    output+="$name"$'\n'
  done <<<"$data"

  printf '%s' "$output"
}
