# shellcheck shell=bash

# Query APT without changing anything.
#
# Every function here is read-only and unprivileged: 'apt-get -s' simulates
# without touching the system, which is what lets a script show an operator
# what would happen before asking them to commit to it. The parsers read a
# simulation on stdin, so one simulation can answer several questions.

#######################################
# Simulate an apt-get action.
# Globals:
#   None
# Arguments:
#   1 - The action to simulate (default: upgrade)
# Outputs:
#   apt-get's simulation output to stdout.
# Returns:
#   The return value of 'apt-get'.
#######################################
function lib::apt::simulate() {
  local action=${1:-upgrade}

  apt-get -s "$action" 2>/dev/null
}

#######################################
# List the packages a simulation would install or upgrade.
# Globals:
#   None
# Arguments:
#   None
# Inputs:
#   An apt-get simulation on stdin.
# Outputs:
#   One package name per line.
#######################################
function lib::apt::pending_packages() {
  awk '/^Inst /{print $2}'
}

#######################################
# List the packages a simulation would take from a security pocket.
#
# apt names the origin in parentheses, e.g.
#   Inst libssl3 [3.0.13] (3.0.14 Ubuntu:24.04/noble-security [amd64])
# so the suite suffix is what identifies a security update, independent of
# the release codename.
# Globals:
#   None
# Arguments:
#   None
# Inputs:
#   An apt-get simulation on stdin.
# Outputs:
#   One package name per line.
#######################################
function lib::apt::security_packages() {
  awk '$0 ~ /^Inst / && $0 ~ /-security[ ,)]/ {print $2}'
}

#######################################
# Extract apt-get's own one-line summary from a simulation.
# Globals:
#   None
# Arguments:
#   None
# Inputs:
#   An apt-get simulation on stdin.
# Outputs:
#   The "N upgraded, N newly installed, ..." line, if there is one.
#######################################
function lib::apt::summary_line() {
  awk '/^[0-9]+ upgraded/{print; exit}'
}

#######################################
# Report how long ago the package lists were refreshed.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   The age in whole days to stdout, or "-1" when it cannot be determined.
# Returns:
#   0 on success, 1 when no timestamp was found.
#######################################
function lib::apt::lists_age_days() {
  local candidate stamp=""

  # apt touches the stamp file only on a successful update; the lists
  # directory is the fallback when periodic updates are not configured.
  for candidate in /var/lib/apt/periodic/update-success-stamp /var/lib/apt/lists; do
    if [[ -e $candidate ]]; then
      stamp="$candidate"
      break
    fi
  done

  if [[ -z $stamp ]]; then
    printf '%s' "-1"
    return 1
  fi

  # '-c' is GNU-only; '-f' with a BSD-style format is the macOS/BSD stat
  # equivalent (this module is Debian/APT-focused, but the timestamp read
  # itself costs nothing to keep portable).
  local mtime
  mtime=$(stat -c %Y "$stamp" 2>/dev/null || stat -f %m "$stamp" 2>/dev/null)
  printf '%s' "$((($(date +%s) - mtime) / 86400))"
}

#######################################
# Check whether a package is installed.
# Globals:
#   None
# Arguments:
#   1 - Package name
# Returns:
#   0 if the package is installed, 1 otherwise.
#######################################
function lib::apt::is_installed() {
  local package=${1}

  [[ "$(dpkg-query -W -f='${db:Status-Status}' -- "$package" 2>/dev/null)" == "installed" ]]
}

#######################################
# Check whether the system wants a reboot.
#
# The file is written by the kernel and libc packages themselves.
# Globals:
#   None
# Arguments:
#   None
# Returns:
#   0 if a reboot is required, 1 otherwise.
#######################################
function lib::apt::reboot_required() {
  [[ -f /var/run/reboot-required ]]
}
