# shellcheck shell=bash

# Read RPM installation state and DNF cached upgrade information.

#######################################
# Check whether one literal RPM package name is installed.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Package name, optionally with architecture; no globs or file paths
# Outputs:
#   None
# Returns:
#   0 installed, 1 absent/backend failure, 2 invalid invocation.
# Dependencies:
#   rpm, only at invocation.
#######################################
function ext::dnf::is_installed() {
  [[ $# == 1 && $1 =~ ^[a-zA-Z0-9][a-zA-Z0-9+_.-]*$ ]] || return 2
  rpm --query -- "$1" >/dev/null 2>&1 || return 1
}

#######################################
# List upgrades from existing DNF metadata without refreshing it.
# Missing metadata fails instead of refreshing. Uses the DNF 4/5 repoquery
# interface and preserves architecture suffixes; no transactions are performed.
# Globals:
#   PATH (read)
# Arguments:
#   None
# Outputs:
#   name.arch records, one per line; errors to stderr. No partial error output.
# Returns:
#   0 success (including no updates), 1 backend/parse failure, 2 invalid invocation.
# Dependencies:
#   dnf with repoquery support (DNF 4 or 5), only at invocation.
#######################################
function ext::dnf::pending_packages() {
  [[ $# == 0 ]] || return 2
  local data package output='' seen=$'\n'
  data=$(LC_ALL=C dnf --cacheonly --quiet repoquery --upgrades --queryformat '%{name}.%{arch}') || return 1

  while IFS= read -r package; do
    [[ -n $package ]] || continue
    [[ $package =~ ^[a-zA-Z0-9][a-zA-Z0-9+_.-]*\.[a-zA-Z0-9_]+$ ]] || return 1
    if [[ $seen != *$'\n'"$package"$'\n'* ]]; then
      output+="$package"$'\n'
      seen+="$package"$'\n'
    fi
  done <<<"$data"

  printf '%s' "$output"
}
