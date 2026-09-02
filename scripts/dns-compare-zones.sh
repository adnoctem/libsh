#!/usr/bin/env bash
#
# Compare the records of a DNS zone across two nameservers.

set -euo pipefail

# Mitigate potential path issues depending on where you're running the script from
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# shellcheck source=lib/log.sh
. "$LIB_DIR"/log.sh

# shellcheck source=lib/opts.sh
. "$LIB_DIR"/opts.sh

# shellcheck source=lib/package.sh
. "$LIB_DIR"/package.sh

# shellcheck source=lib/array.sh
. "$LIB_DIR"/array.sh

# -------------------------
#   Flag spec
# -------------------------

OPTS=(
  "-z,--zone:zone:1:required"
  "-n,--nameservers:nameservers:1:optional"
  "-t,--types:types:1:optional"
  "-w,--warn-types:warn_types:1:optional"
  "-h,--help:help:0:optional"
  ",--check-prerequisites:check_prerequisites:0:optional"
)

declare -A OPTS_HELP=(
  [zone]="DNS zone to compare, e.g. 'adnoctem.co'"
  [nameservers]="The two nameservers to compare, comma-separated (default: 8.8.8.8,1.1.1.1)"
  [types]="Comma-separated record types to compare (default: A,AAAA,CNAME,MX,TXT,NS,SOA)"
  [warn_types]="Types whose differences count as warnings rather than errors (default: NS,SOA)"
  [check_prerequisites]="Check that the required packages are installed, then exit"
  [help]="Show this help message and exit"
)

declare -A OPTS_VALUES=()

#######################################
# Check if the prerequisites for the
# script are installed.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   One line per prerequisite to stdout.
# Returns:
#   0 if all prerequisites were found, 1 otherwise.
#######################################
function dns_compare_zones::prerequisites() {
  local prerequisites=('dig')

  for prerequisite in "${prerequisites[@]}"; do
    if ! lib::package::is_executable "${prerequisite}"; then
      lib::log::red "Could not find package '${prerequisite}' in system PATH. Please install '${prerequisite}' to proceed!"
      return 1
    fi

    lib::log::green "Found package '${prerequisite}' in system PATH."
  done

  lib::log::green "Found all prerequisites: '${prerequisites[*]}' in system PATH. Ready to proceed!"
  return 0
}

#######################################
# Compare one record type across two nameservers.
# Globals:
#   None
# Arguments:
#   1 - Zone to query
#   2 - First nameserver
#   3 - Second nameserver
#   4 - Record type
# Outputs:
#   A verdict line, plus both answers when they differ.
# Returns:
#   0 when the answers match, 1 when they differ, 2 when a query failed.
#######################################
function dns_compare_zones::exec() {
  local zone=${1} nameserver_a=${2} nameserver_b=${3} type=${4}
  local answer_a answer_b

  if ! answer_a=$(dig +short "$type" "@${nameserver_a}" "$zone" 2>/dev/null | sort); then
    lib::log::red "Querying $type for '$zone' from '$nameserver_a' failed."
    return 2
  fi

  if ! answer_b=$(dig +short "$type" "@${nameserver_b}" "$zone" 2>/dev/null | sort); then
    lib::log::red "Querying $type for '$zone' from '$nameserver_b' failed."
    return 2
  fi

  if [[ $answer_a == "$answer_b" ]]; then
    lib::log::green "$type matches across '$nameserver_a' and '$nameserver_b'."
    return 0
  fi

  lib::log::yellow "$type differs across nameservers, please examine the values:"
  lib::log::cyan "  $nameserver_a:"
  lib::log::plain "${answer_a:-    (empty)}"
  lib::log::cyan "  $nameserver_b:"
  lib::log::plain "${answer_b:-    (empty)}"

  return 1
}

# --------------------------------
#   MAIN
# --------------------------------

#######################################
# Parse the flags, then compare every requested record type across the two
# nameservers.
# Globals:
#   OPTS, OPTS_HELP (read)
#   OPTS_VALUES (written by lib::opts::parse)
# Arguments:
#   The script's original "$@"
# Returns:
#   0 when every type matched or only warned, 1 on a usage error or a
#   differing error-level type, 2 when a query failed.
#######################################
function main() {
  local arg zone type rc failures=0 warnings=0 queries=0
  local -a nameservers types warn_types

  # --check-prerequisites answers on its own, before the parser can reject
  # the run for the required flags a prerequisite check has no use for.
  for arg in "$@"; do
    if [[ $arg == "--check-prerequisites" ]]; then
      dns_compare_zones::prerequisites
      return $?
    fi
  done

  lib::opts::parse "$@" || return 1

  zone="${OPTS_VALUES[zone]}"

  IFS=',' read -ra nameservers <<<"${OPTS_VALUES[nameservers]:-8.8.8.8,1.1.1.1}"
  # 'ANY' is deliberately not a default: RFC 8482 lets a resolver answer it
  # with a minimal synthesised record, so a difference means nothing.
  IFS=',' read -ra types <<<"${OPTS_VALUES[types]:-A,AAAA,CNAME,MX,TXT,NS,SOA}"
  IFS=',' read -ra warn_types <<<"${OPTS_VALUES[warn_types]:-NS,SOA}"

  if [[ ${#nameservers[@]} -ne 2 ]]; then
    lib::log::red "Expected exactly two --nameservers, got ${#nameservers[@]}."
    return 1
  fi

  lib::log::timed_yellow "Comparing zone '$zone' across '${nameservers[0]}' and '${nameservers[1]}' ..."

  for type in "${types[@]}"; do
    if [[ -z $type ]]; then
      continue
    fi

    queries=$((queries + 1))
    rc=0
    dns_compare_zones::exec "$zone" "${nameservers[0]}" "${nameservers[1]}" "$type" || rc=$?

    if [[ $rc -eq 2 ]]; then
      return 2
    fi

    if [[ $rc -eq 1 ]]; then
      # NS and SOA differ legitimately between a hidden primary and its
      # secondaries, so they warn instead of failing the run.
      if lib::array::contains "$type" "${warn_types[@]}"; then
        warnings=$((warnings + 1))
      else
        failures=$((failures + 1))
      fi
    fi
  done

  lib::log::timed_cyan "Compared $queries record type(s) for '$zone': $failures error(s), $warnings warning(s)."

  # A non-zero exit makes this usable as a monitoring or CI check.
  if [[ $failures -gt 0 ]]; then
    return 1
  fi

  return 0
}

# ------------
# 'main' call
# ------------
main "$@"
