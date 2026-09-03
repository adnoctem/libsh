# shellcheck shell=bash

# Block until a TCP endpoint accepts connections, or fail after a bounded
# number of retries -- the actual mechanism duplicated six times across
# shopware-main's docker/lib/libcheck.sh (database_connection_check,
# opensearch_connection_check, redis_connection_check,
# redis_cache_connection_check, redis_session_connection_check,
# rabbitmq_connection_check). All six were the identical loop
# (nc -z, sleep 1, bounded retries, fatal exit) around a different DSN var
# and a different human label. This collapses that into one primitive plus
# one thin convenience wrapper.

#######################################
# Block until 'host:port' accepts a TCP connection, retrying on a fixed
# interval, or exit 1 after the retry budget is exhausted.
# Globals:
#   None
# Arguments:
#   1 - Host to connect to
#   2 - Port to connect to
#   3 - Label to use in log output (optional, defaults to "host:port")
#   4 - Number of retries before giving up (optional, default 60)
#   5 - Per-attempt connect timeout in seconds (optional, default 5)
# Outputs:
#   Progress/result via lib::log::*.
# Returns:
#   0 once the connection succeeds. Exits 1 if it never does.
#######################################
function lib::networking::tcp() {
  local host=${1} port=${2} label=${3:-"${1}:${2}"} tries=${4:-60} timeout=${5:-5}
  local attempt=0

  lib::log::green "Checking for an active ${label} connection"

  until nc -z -w"${timeout}" "${host}" "${port}" 2>/dev/null; do
    attempt=$((attempt + 1))

    if [[ ${attempt} -ge ${tries} ]]; then
      lib::log::red "FATAL: could not reach ${label} (${host}:${port}) after ${tries} tries."
      exit 1
    fi

    lib::log::yellow "Waiting for ${label} (${host}:${port}) -- $((tries - attempt)) attempts left"
    sleep 1
  done

  lib::log::green "${label} connection established"
}

#######################################
# Convenience wrapper around lib::check::tcp: parse host/port out of a DSN
# with 'trurl' first. Kept separate from lib::check::tcp itself so this
# module carries no hard dependency on trurl being installed -- only callers
# of THIS function need it on PATH.
# Globals:
#   None
# Arguments:
#   1 - DSN/URL to parse (e.g. "mysql://user:pass@host:3306/db")
#   2 - Default port to use if the DSN doesn't specify one
#   3 - Label to use in log output (optional, defaults to the DSN's host)
#   4 - Number of retries before giving up (optional, default 60)
#   5 - Per-attempt connect timeout in seconds (optional, default 5)
# Outputs:
#   Same as lib::check::tcp.
# Returns:
#   Same as lib::check::tcp.
#######################################
function lib::networking::tcp_dsn() {
  local dsn=${1} default_port=${2} label=${3:-} tries=${4:-60} timeout=${5:-5}
  local host port

  if ! command -v trurl &>/dev/null; then
    lib::log::red "lib::networking::tcp_dsn requires 'trurl' on PATH to parse DSNs."
    exit 1
  fi

  host=$(trurl "${dsn}" --get '{host}')
  port=$(trurl "${dsn}" --get '{port}')
  port=${port:-${default_port}}

  lib::networking::tcp "${host}" "${port}" "${label:-${host}}" "${tries}" "${timeout}"
}
