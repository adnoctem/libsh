# shellcheck shell=bash

# Network inspection, address validation, URI parsing and connection probes.

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
function lib::net::tcp_probe() {
  local host=${1} port=${2} label=${3:-"${1}:${2}"} tries=${4:-60} timeout=${5:-5}

  if lib::net::tcp_wait "$host" "$port" --label "$label" --attempts "$tries" --timeout "$timeout"; then
    return 0
  fi

  lib::log::print_error "FATAL: could not reach ${label} (${host}:${port}) after ${tries} tries."
  exit 1
}

#######################################
# Convenience wrapper around lib::net::tcp_probe: parse host/port out
# of a DSN with 'trurl' first. Kept separate from lib::net::tcp_probe
# itself so this module carries no hard dependency on trurl being installed
# -- only callers of THIS function need it on PATH.
# Deprecated: credentials reach trurl argv. New callers should use
# endpoint_from_uri (variable reference) followed by tcp_wait instead.
# Globals:
#   None
# Arguments:
#   1 - DSN/URL to parse (e.g. "mysql://user:pass@host:3306/db")
#   2 - Default port to use if the DSN doesn't specify one
#   3 - Label to use in log output (optional, defaults to the DSN's host)
#   4 - Number of retries before giving up (optional, default 60)
#   5 - Per-attempt connect timeout in seconds (optional, default 5)
# Outputs:
#   Same as lib::net::tcp_probe.
# Returns:
#   Same as lib::net::tcp_probe.
#######################################
function lib::net::tcp_dsn_probe() {
  local dsn=${1} default_port=${2} label=${3:-} tries=${4:-60} timeout=${5:-5}
  local host port

  if ! command -v trurl &>/dev/null; then
    lib::log::print_error "lib::net::tcp_dsn_probe requires 'trurl' on PATH to parse DSNs."
    exit 1
  fi

  host=$(trurl "${dsn}" --get '{host}')
  port=$(trurl "${dsn}" --get '{port}')
  port=${port:-${default_port}}

  lib::net::tcp_probe "${host}" "${port}" "${label:-${host}}" "${tries}" "${timeout}"
}

#######################################
# Normalize a bounded decimal without evaluating caller-controlled arithmetic.
# Globals:
#   None
# Arguments:
#   1 - Decimal; 2 - maximum (trusted integer); 3 - minimum (trusted integer)
# Outputs:
#   Normalized decimal on stdout.
# Returns:
#   0 valid, 2 invalid.
#######################################
function __libsh_net_decimal() {
  local LC_ALL=C
  local __libsh_dec=${1:-}

  [[ $__libsh_dec =~ ^[0-9]+$ ]] || return 2

  while [[ ${#__libsh_dec} -gt 1 && $__libsh_dec == 0* ]]; do
    __libsh_dec=${__libsh_dec#0}
  done

  [[ ${#__libsh_dec} -le 9 ]] || return 2
  [[ $__libsh_dec -ge $3 && $__libsh_dec -le $2 ]] || return 2
  printf '%s' "$__libsh_dec"
}

#######################################
# Validate an unbracketed IPv6 address using Bash only, including IPv4 tails.
# Globals:
#   None
# Arguments:
#   1 - Address (no scope/zone identifier)
# Outputs:
#   None
# Returns:
#   0 valid, 2 invalid.
#######################################
function __libsh_net_endpoint_ipv6() {
  local LC_ALL=C
  local __libsh_ip=$1 __libsh_ip_tail __libsh_ip_side __libsh_ip_group
  local __libsh_ip_count=0 __libsh_ip_compressed=0
  local -a __libsh_ip_groups=()

  [[ $__libsh_ip =~ ^[a-fA-F0-9:.]+$ && $__libsh_ip == *:* && $__libsh_ip != *:::* ]] || return 2

  if [[ $__libsh_ip == *.* ]]; then
    __libsh_ip_tail=${__libsh_ip##*:}
    lib::net::ipv4_validate "$__libsh_ip_tail" || return 2
    __libsh_ip=${__libsh_ip%:*}:0:0
  fi

  if [[ $__libsh_ip == *::* ]]; then
    __libsh_ip_compressed=1
    __libsh_ip_tail=${__libsh_ip#*::}
    [[ $__libsh_ip_tail != *::* ]] || return 2
  elif [[ $__libsh_ip == :* || $__libsh_ip == *: ]]; then
    return 2
  fi

  # Split each side independently so empty groups only occur at '::'.
  for __libsh_ip_side in "${__libsh_ip%%::*}" "${__libsh_ip_tail:-}"; do
    [[ -n $__libsh_ip_side ]] || continue
    [[ $__libsh_ip_side != :* && $__libsh_ip_side != *: ]] || return 2
    IFS=: read -r -a __libsh_ip_groups <<<"$__libsh_ip_side"
    for __libsh_ip_group in "${__libsh_ip_groups[@]}"; do
      [[ $__libsh_ip_group =~ ^[a-fA-F0-9]{1,4}$ ]] || return 2
      __libsh_ip_count=$((__libsh_ip_count + 1))
    done
    [[ $__libsh_ip_compressed == 1 ]] || break
  done

  if [[ $__libsh_ip_compressed == 1 ]]; then
    [[ $__libsh_ip_count -lt 8 ]] || return 2
  else
    [[ $__libsh_ip_count == 8 ]] || return 2
  fi

  return 0
}

#######################################
# Validate a TCP host (DNS, IPv4, or unbracketed IPv6).
# Globals:
#   None
# Arguments:
#   1 - Host
# Outputs:
#   None
# Returns:
#   0 valid, 2 invalid.
#######################################
function __libsh_net_endpoint_host() {
  local LC_ALL=C
  local __libsh_host=$1 __libsh_host_label
  local -a __libsh_host_labels=()

  if [[ $__libsh_host == *:* ]]; then
    __libsh_net_endpoint_ipv6 "$__libsh_host"
    return $?
  fi

  if [[ $__libsh_host =~ ^[0-9.]+$ && $__libsh_host == *.* ]]; then
    lib::net::ipv4_validate "$__libsh_host" || return 2
    return 0
  fi

  [[ $__libsh_host != *.. ]] || return 2
  __libsh_host=${__libsh_host%.}
  [[ -n $__libsh_host && ${#__libsh_host} -le 253 && $__libsh_host != *..* ]] || return 2
  IFS=. read -r -a __libsh_host_labels <<<"$__libsh_host"

  for __libsh_host_label in "${__libsh_host_labels[@]}"; do
    [[ ${#__libsh_host_label} -le 63 && $__libsh_host_label =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]] || return 2
  done

  return 0
}

#######################################
# Extract a TCP endpoint from a restricted single-host database URI.
# Globals:
#   URI variable (read), host/port output variables (written on success).
# Arguments:
#   1 - URI input variable name
#   2 - Host output variable name
#   3 - Port output variable name
#   4+ - Optional --default-port PORT
# Outputs:
#   Sanitized errors on stderr; no stdout. See docs/API.md.
# Returns:
#   0 success, 2 invalid reference/URI/port. Never exits.
#######################################
function lib::net::endpoint_from_uri() {
  local LC_ALL=C

  [[ $# == 3 || ($# == 5 && ${4:-} == --default-port) ]] || {
    lib::log::print_error 'Expected URI_VAR HOST_OUT PORT_OUT and optional --default-port.'
    return 2
  }
  __libsh_data_scalar_reference "$1" read || return 2
  __libsh_data_scalar_reference "$2" write || return 2
  __libsh_data_scalar_reference "$3" write || return 2
  [[ $1 != "$2" && $1 != "$3" && $2 != "$3" ]] || {
    lib::log::print_error 'Endpoint variable references must be distinct.'
    return 2
  }
  local __libsh_uri=${!1-} __libsh_uri_default='' __libsh_uri_host __libsh_uri_port=''
  local __libsh_uri_authority __libsh_uri_user __libsh_uri_check __libsh_uri_rest

  if [[ $# == 5 ]]; then
    __libsh_uri_default=$(__libsh_net_decimal "$5" 65535 1) || {
      lib::log::print_error 'Invalid default port.'
      return 2
    }
  fi

  if [[ ! $__libsh_uri =~ ^[a-zA-Z][a-zA-Z0-9+.-]*:// || $__libsh_uri == *[[:space:][:cntrl:]]* ]]; then
    lib::log::print_error 'Invalid endpoint URI scheme or whitespace.'
    return 2
  fi

  __libsh_uri_rest=${__libsh_uri#*://}
  __libsh_uri_authority=${__libsh_uri_rest%%[/?#]*}
  # Validate percent escapes everywhere; do not decode any component.
  __libsh_uri_check=$__libsh_uri_rest

  while [[ $__libsh_uri_check == *%* ]]; do
    __libsh_uri_check=${__libsh_uri_check#*%}
    [[ $__libsh_uri_check =~ ^[a-fA-F0-9]{2} ]] || {
      lib::log::print_error 'Invalid endpoint URI escape.'
      return 2
    }
    __libsh_uri_check=${__libsh_uri_check:2}
  done

  if [[ $__libsh_uri_authority == *@* ]]; then
    __libsh_uri_user=${__libsh_uri_authority%%@*}
    __libsh_uri_authority=${__libsh_uri_authority#*@}
    # RFC userinfo characters: unreserved, sub-delimiters, colon, escapes.
    __libsh_uri_check="^[a-zA-Z0-9._~!\$&'()*+,;=:%-]+$"
    [[ $__libsh_uri_user =~ $__libsh_uri_check && $__libsh_uri_authority != *@* ]] || {
      lib::log::print_error 'Invalid endpoint URI user information.'
      return 2
    }
  fi

  if [[ $__libsh_uri_authority == \[* ]]; then
    [[ $__libsh_uri_authority == *\]* ]] || {
      lib::log::print_error 'Invalid endpoint brackets.'
      return 2
    }
    __libsh_uri_host=${__libsh_uri_authority#\[}
    __libsh_uri_host=${__libsh_uri_host%%\]*}
    __libsh_uri_rest=${__libsh_uri_authority#*\]}
    __libsh_net_endpoint_ipv6 "$__libsh_uri_host" || {
      lib::log::print_error 'Invalid IPv6 endpoint.'
      return 2
    }
  else
    __libsh_uri_host=${__libsh_uri_authority%%:*}
    __libsh_uri_rest=${__libsh_uri_authority#"$__libsh_uri_host"}
    __libsh_net_endpoint_host "$__libsh_uri_host" || {
      lib::log::print_error 'Invalid endpoint host.'
      return 2
    }
  fi

  if [[ -n $__libsh_uri_rest ]]; then
    [[ $__libsh_uri_rest == :* ]] || {
      lib::log::print_error 'Invalid endpoint authority.'
      return 2
    }
    __libsh_uri_port=$(__libsh_net_decimal "${__libsh_uri_rest#:}" 65535 1) || {
      lib::log::print_error 'Invalid explicit endpoint port.'
      return 2
    }
  else
    __libsh_uri_port=$__libsh_uri_default
    [[ -n $__libsh_uri_port ]] || {
      lib::log::print_error 'Endpoint requires a port or default port.'
      return 2
    }
  fi

  printf -v "$2" '%s' "$__libsh_uri_host"
  printf -v "$3" '%s' "$__libsh_uri_port"
}

#######################################
# Wait for TCP acceptance, returning control to the caller on failure.
# Globals:
#   None
# Arguments:
#   1 - Host
#   2 - Port
#   3+ - Optional --attempts N, --timeout SECONDS, --interval SECONDS,
#        and --label LABEL
# Outputs:
#   Progress on stdout, sanitized errors on stderr. Labels must contain no
#   secrets.
# Returns:
#   0 connected, 1 dependency/connection/sleep failure, 2 invalid arguments.
#   Budget: attempts*timeout + (attempts-1)*interval, excluding DNS and
#   overhead.
#######################################
function lib::net::tcp_wait() {
  [[ $# -ge 2 ]] || {
    lib::log::print_error 'tcp_wait requires HOST and PORT.'
    return 2
  }
  local __libsh_wait_host=$1 __libsh_wait_port __libsh_wait_label="${1}:${2}"
  local __libsh_wait_attempts=60 __libsh_wait_timeout=5 __libsh_wait_interval=1
  local __libsh_wait_seen=' ' __libsh_wait_attempt=1 __libsh_wait_platform
  local -a __libsh_wait_nc_flags

  __libsh_net_endpoint_host "$1" || {
    lib::log::print_error 'Invalid TCP host.'
    return 2
  }
  __libsh_wait_port=$(__libsh_net_decimal "$2" 65535 1) || {
    lib::log::print_error 'Invalid TCP port.'
    return 2
  }
  shift 2

  while [[ $# -gt 0 ]]; do
    [[ $# -ge 2 && $__libsh_wait_seen != *" $1 "* ]] || {
      lib::log::print_error 'Missing or duplicate TCP wait option.'
      return 2
    }
    __libsh_wait_seen+="$1 "
    case $1 in
      --attempts) __libsh_wait_attempts=$2 ;;
      --timeout) __libsh_wait_timeout=$2 ;;
      --interval) __libsh_wait_interval=$2 ;;
      --label) __libsh_wait_label=$2 ;;
      *)
        lib::log::print_error 'Unknown TCP wait option.'
        return 2
        ;;
    esac
    shift 2
  done

  if ! __libsh_wait_attempts=$(__libsh_net_decimal "$__libsh_wait_attempts" 999999999 1) \
    || ! __libsh_wait_timeout=$(__libsh_net_decimal "$__libsh_wait_timeout" 999999999 1) \
    || ! __libsh_wait_interval=$(__libsh_net_decimal "$__libsh_wait_interval" 999999999 0); then
    lib::log::print_error 'Invalid TCP retry budget.'
    return 2
  fi

  if ! command -v nc >/dev/null 2>&1 || ! command -v sleep >/dev/null 2>&1 || ! command -v uname >/dev/null 2>&1; then
    lib::log::print_error "TCP waiting requires OpenBSD-compatible 'nc', 'sleep', and 'uname'."
    return 1
  fi

  __libsh_wait_nc_flags=(-z "-w$__libsh_wait_timeout")
  # Apple's -w is the idle timeout; -G bounds TCP connection establishment.
  __libsh_wait_platform=$(uname -s 2>/dev/null) || {
    lib::log::print_error 'Could not determine the TCP client platform.'
    return 1
  }

  if [[ $__libsh_wait_platform == Darwin ]]; then
    __libsh_wait_nc_flags+=(-G "$__libsh_wait_timeout")
  fi

  lib::log::print_info "Checking for an active ${__libsh_wait_label} connection"

  while :; do
    if nc "${__libsh_wait_nc_flags[@]}" "$__libsh_wait_host" "$__libsh_wait_port" >/dev/null 2>&1; then
      lib::log::print_success "${__libsh_wait_label} connection established"
      return 0
    fi
    if [[ $__libsh_wait_attempt -ge $__libsh_wait_attempts ]]; then
      lib::log::print_error "TCP connection unavailable after ${__libsh_wait_attempts} attempts."
      return 1
    fi
    lib::log::print_info "Waiting for ${__libsh_wait_label} (${__libsh_wait_host}:${__libsh_wait_port}) -- $((__libsh_wait_attempts - __libsh_wait_attempt)) attempts left"
    if [[ $__libsh_wait_interval != 0 ]]; then
      sleep "$__libsh_wait_interval" || {
        lib::log::print_error 'TCP retry sleep failed.'
        return 1
      }
    fi
    __libsh_wait_attempt=$((__libsh_wait_attempt + 1))
  done
}

# Default-adapter discovery and IP/gateway/DNS/MAC/prefix/broadcast/multicast
# address resolution -- a port of PSFoundation's networking.ps1, redesigned
# around Linux's 'ip' (iproute2, not the often-absent-on-containers net-tools
# 'ifconfig'/'route') and macOS's BSD-native 'ifconfig'/'route'/'ipconfig'
# instead of Windows' CIM/Get-NetAdapter/[System.Net.IPAddress]. PSFoundation
# threads a resolved adapter object through every function to avoid
# re-resolving it; here that's just an optional interface-name string, since
# re-running 'ip'/'ifconfig' is cheap and bash has no structured objects.
# Every function logs an ERROR intent and returns 1 on failure, matching the
# rest of this library -- PSFoundation's separate -Required
# throw-vs-return-$null split has no equivalent here.

#######################################
# Resolve the interface name of the default network adapter, via the
# lowest-metric IPv4 default route.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   The interface name to stdout. An error to stderr on failure.
# Returns:
#   0 on success, 1 if no default route/adapter was found.
#######################################
function lib::net::default_adapter() {
  local iface

  if [[ $(uname) == "Darwin" ]]; then
    iface=$(route -n get default 2>/dev/null | awk '/interface:/{print $2}')
  else
    iface=$(ip -4 route show default 2>/dev/null | awk '
      { dev=""; metric=0
        for (i = 1; i <= NF; i++) {
          if ($i == "dev") dev = $(i + 1)
          if ($i == "metric") metric = $(i + 1)
        }
        if (dev != "") print metric, dev
      }' | sort -n | head -1 | awk '{print $2}')
  fi

  if [[ -z $iface ]]; then
    lib::log::print_error "No default network adapter found."
    return 1
  fi

  printf '%s' "$iface"
}

#######################################
# Resolve the IP address of an adapter. For IPv6, a global/unique-local
# address is preferred over link-local; falls back to link-local if no
# routable address is assigned.
# Globals:
#   None
# Arguments:
#   1 - Address family: ipv4 or ipv6 (optional, default ipv4)
#   2 - Interface name (optional; resolved via default_adapter if omitted)
# Outputs:
#   The address to stdout. An error to stderr on failure.
# Returns:
#   0 on success, 1 if no address of that family was found.
#######################################
function lib::net::ip_address() {
  local family=${1:-ipv4} iface=${2:-} ip

  if [[ -z $iface ]]; then
    iface=$(lib::net::default_adapter) || return 1
  fi

  if [[ $(uname) == "Darwin" ]]; then
    if [[ $family == "ipv4" ]]; then
      ip=$(ipconfig getifaddr "$iface" 2>/dev/null)
    else
      ip=$(ifconfig "$iface" 2>/dev/null | awk '/inet6 / && !/fe80/{print $2; exit}')
      [[ -z $ip ]] && ip=$(ifconfig "$iface" 2>/dev/null | awk '/inet6 /{print $2; exit}')
      ip=${ip%%\%*}
    fi
  elif [[ $family == "ipv4" ]]; then
    ip=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
  else
    ip=$(ip -6 -o addr show dev "$iface" scope global 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
    [[ -z $ip ]] && ip=$(ip -6 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -1)
  fi

  if [[ -z $ip ]]; then
    lib::log::print_error "No $family address found on adapter '$iface'."
    return 1
  fi

  printf '%s' "$ip"
}

#######################################
# Resolve the IPv4 subnet mask of an adapter, in dotted-decimal form.
# Globals:
#   None
# Arguments:
#   1 - Interface name (optional; resolved via default_adapter if omitted)
# Outputs:
#   The mask to stdout. An error to stderr on failure.
# Returns:
#   0 on success, 1 if no IPv4 mask was found.
#######################################
function lib::net::subnet_mask() {
  local iface=${1:-} cidr hex

  if [[ -z $iface ]]; then
    iface=$(lib::net::default_adapter) || return 1
  fi

  if [[ $(uname) == "Darwin" ]]; then
    hex=$(ifconfig "$iface" 2>/dev/null | awk '/inet /{print $4; exit}')
    if [[ -z $hex ]]; then
      lib::log::print_error "No IPv4 subnet mask found on adapter '$iface'."
      return 1
    fi
    __libsh_net_hex_mask_to_dotted "$hex"
    return 0
  fi

  cidr=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f2 | head -1)

  if [[ -z $cidr ]]; then
    lib::log::print_error "No IPv4 subnet mask found on adapter '$iface'."
    return 1
  fi

  __libsh_net_cidr_to_dotted_mask "$cidr"
}

#######################################
# Resolve the default gateway of an adapter.
# Globals:
#   None
# Arguments:
#   1 - Address family: ipv4 or ipv6 (optional, default ipv4)
#   2 - Interface name (optional; resolved via default_adapter if omitted)
# Outputs:
#   The gateway address to stdout. An error to stderr on failure.
# Returns:
#   0 on success, 1 if no gateway of that family was found.
#######################################
function lib::net::default_gateway() {
  local family=${1:-ipv4} iface=${2:-} flag=-4 gateway

  if [[ -z $iface ]]; then
    iface=$(lib::net::default_adapter) || return 1
  fi

  [[ $family == "ipv6" ]] && flag=-6

  if [[ $(uname) == "Darwin" ]]; then
    if [[ $family == "ipv6" ]]; then
      gateway=$(route -n get -inet6 default 2>/dev/null | awk '/gateway:/{print $2}')
    else
      gateway=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
    fi
  else
    gateway=$(ip $flag route show default dev "$iface" 2>/dev/null \
      | awk '{for (i = 1; i <= NF; i++) if ($i == "via") print $(i + 1)}' | head -1)
  fi

  if [[ -z $gateway ]]; then
    lib::log::print_error "No $family default gateway found on adapter '$iface'."
    return 1
  fi

  printf '%s' "$gateway"
}

#######################################
# List the configured DNS servers, read from /etc/resolv.conf -- this isn't
# adapter-scoped the way PSFoundation's CimConfig.DNSServerSearchOrder is,
# so unlike the other functions here there is no interface-name argument.
# Globals:
#   None
# Arguments:
#   1 - Address family to filter by: ipv4 or ipv6 (optional, default both)
# Outputs:
#   One server per line to stdout. An error to stderr on failure.
# Returns:
#   0 on success, 1 if no matching DNS servers were found.
#######################################
function lib::net::dns_servers() {
  local family=${1:-} servers

  case "$family" in
    ipv4) servers=$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | grep -v ':') ;;
    ipv6) servers=$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | grep ':') ;;
    *) servers=$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null) ;;
  esac

  if [[ -z $servers ]]; then
    lib::log::print_error "No ${family:-} DNS servers found in /etc/resolv.conf."
    return 1
  fi

  printf '%s\n' "$servers"
}

#######################################
# Resolve the MAC address of an adapter.
# Globals:
#   None
# Arguments:
#   1 - Interface name (optional; resolved via default_adapter if omitted)
# Outputs:
#   The MAC address to stdout. An error to stderr on failure.
# Returns:
#   0 on success, 1 if no MAC address was found.
#######################################
function lib::net::mac_address() {
  local iface=${1:-} mac

  if [[ -z $iface ]]; then
    iface=$(lib::net::default_adapter) || return 1
  fi

  if [[ $(uname) == "Darwin" ]]; then
    mac=$(ifconfig "$iface" 2>/dev/null | awk '/ether /{print $2; exit}')
  else
    mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null)
  fi

  if [[ -z $mac ]]; then
    lib::log::print_error "No MAC address found on adapter '$iface'."
    return 1
  fi

  printf '%s' "$mac"
}

#######################################
# Resolve the network address (IPv4) or network prefix (IPv6) of an
# adapter.
# Globals:
#   None
# Arguments:
#   1 - Address family: ipv4 or ipv6 (optional, default ipv4)
#   2 - Interface name (optional; resolved via default_adapter if omitted)
# Outputs:
#   The network address to stdout. An error to stderr on failure.
# Returns:
#   0 on success, 1 on failure.
#######################################
function lib::net::network_prefix() {
  local family=${1:-ipv4} iface=${2:-} ip mask data address prefix_length expanded masked

  if [[ -z $iface ]]; then
    iface=$(lib::net::default_adapter) || return 1
  fi

  if [[ $family == "ipv4" ]]; then
    ip=$(lib::net::ip_address ipv4 "$iface") || return 1
    mask=$(lib::net::subnet_mask "$iface") || return 1
    __libsh_net_ipv4_and "$ip" "$mask"
    return 0
  fi

  data=$(__libsh_net_ipv6_prefix_data "$iface") || return 1
  address="${data%/*}"
  prefix_length="${data#*/}"
  expanded=$(__libsh_net_ipv6_expand "$address")
  masked=$(__libsh_net_ipv6_apply_prefix "$expanded" "$prefix_length")
  __libsh_net_ipv6_hex_to_string "$masked"
}

#######################################
# Resolve the network prefix of an adapter in CIDR notation.
# Globals:
#   None
# Arguments:
#   1 - Address family: ipv4 or ipv6 (optional, default ipv4)
#   2 - Interface name (optional; resolved via default_adapter if omitted)
# Outputs:
#   The CIDR-notation prefix to stdout. An error to stderr on failure.
# Returns:
#   0 on success, 1 on failure.
#######################################
function lib::net::network_prefix_cidr() {
  local family=${1:-ipv4} iface=${2:-} prefix mask cidr data prefix_length

  if [[ -z $iface ]]; then
    iface=$(lib::net::default_adapter) || return 1
  fi

  if [[ $family == "ipv4" ]]; then
    prefix=$(lib::net::network_prefix ipv4 "$iface") || return 1
    mask=$(lib::net::subnet_mask "$iface") || return 1
    cidr=$(__libsh_net_dotted_mask_to_cidr "$mask")
    printf '%s/%s' "$prefix" "$cidr"
    return 0
  fi

  data=$(__libsh_net_ipv6_prefix_data "$iface") || return 1
  prefix_length="${data#*/}"
  prefix=$(lib::net::network_prefix ipv6 "$iface") || return 1
  printf '%s/%s' "$prefix" "$prefix_length"
}

#######################################
# Resolve the IPv4 broadcast address of an adapter.
# Globals:
#   None
# Arguments:
#   1 - Interface name (optional; resolved via default_adapter if omitted)
# Outputs:
#   The broadcast address to stdout. An error to stderr on failure.
# Returns:
#   0 on success, 1 on failure.
#######################################
function lib::net::broadcast_address() {
  local iface=${1:-} ip mask

  if [[ -z $iface ]]; then
    iface=$(lib::net::default_adapter) || return 1
  fi

  ip=$(lib::net::ip_address ipv4 "$iface") || return 1
  mask=$(lib::net::subnet_mask "$iface") || return 1
  __libsh_net_ipv4_broadcast "$ip" "$mask"
}

#######################################
# Resolve the solicited-node multicast address for an adapter's IPv6
# address, per RFC 4291 section 2.7.1 (the ff02::1:ff00:0/104 prefix
# combined with the address's lower 24 bits). Used by Neighbor Discovery as
# the IPv6 replacement for ARP.
# Globals:
#   None
# Arguments:
#   1 - Interface name (optional; resolved via default_adapter if omitted)
# Outputs:
#   The multicast address to stdout. An error to stderr on failure.
# Returns:
#   0 on success, 1 on failure.
#######################################
function lib::net::multicast_address() {
  local iface=${1:-} ip expanded multicast

  if [[ -z $iface ]]; then
    iface=$(lib::net::default_adapter) || return 1
  fi

  ip=$(lib::net::ip_address ipv6 "$iface") || return 1
  expanded=$(__libsh_net_ipv6_expand "$ip")
  multicast=$(__libsh_net_ipv6_multicast "$expanded")
  __libsh_net_ipv6_hex_to_string "$multicast"
}

#######################################
# Check whether a string is a valid IPv4 address per RFC 791: four
# dot-separated decimal octets, each 0-255, no leading zeros. Arithmetic
# decomposition with bounded decimal octets.
# Globals:
#   None
# Arguments:
#   1 - The string to validate
# Outputs:
#   None
# Returns:
#   0 valid, 1 invalid, 2 incorrect argument count.
#######################################
function lib::net::ipv4_validate() {
  [[ $# == 1 ]] || return 2

  local LC_ALL=C address=$1
  local -a octets
  local octet

  [[ $address =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 1
  [[ $address == .* || $address == *. ]] && return 1

  IFS='.' read -ra octets <<<"$address"
  [[ ${#octets[@]} -eq 4 ]] || return 1

  for octet in "${octets[@]}"; do
    [[ ${#octet} -le 3 ]] || return 1
    [[ $octet =~ ^[0-9]+$ ]] || return 1
    if [[ ${#octet} -gt 1 && ${octet:0:1} == "0" ]]; then
      return 1
    fi
    ((octet >= 0 && octet <= 255)) || return 1
  done

  return 0
}

#######################################
# Validate an unbracketed IPv6 address, including embedded IPv4 tails.
# Zone identifiers and CIDR suffixes are not accepted.
# Globals:
#   None
# Arguments:
#   1 - Address
# Outputs:
#   None
# Returns:
#   0 valid, 1 invalid, 2 incorrect argument count.
#######################################
function lib::net::ipv6_validate() {
  [[ $# == 1 ]] || return 2
  __libsh_net_endpoint_ipv6 "$1" || return 1
}

#######################################
# Validate either an IPv4 or an unbracketed IPv6 address.
# Globals:
#   None
# Arguments:
#   1 - Address, without CIDR suffix or zone identifier
# Outputs:
#   None
# Returns:
#   0 valid, 1 invalid, 2 incorrect argument count.
#######################################
function lib::net::ip_validate() {
  [[ $# == 1 ]] || return 2
  lib::net::ipv4_validate "$1" || lib::net::ipv6_validate "$1"
}

#######################################
# Validate a decimal remote service port; leading zeros are accepted.
# Port zero is reserved for local automatic allocation and is rejected here.
# Globals:
#   None
# Arguments:
#   1 - Port in the range 1 through 65535
# Outputs:
#   None
# Returns:
#   0 valid, 1 invalid, 2 incorrect argument count.
#######################################
function lib::net::port_validate() {
  [[ $# == 1 ]] || return 2
  __libsh_net_decimal "$1" 65535 1 >/dev/null || return 1
}

# --- Internal helpers ---------------------------------------------------
# Private implementation details use __libsh_net_ and are called by
# the public functions above. They are not supported consumer APIs.

#######################################
# Resolve the global (falling back to link-local) IPv6 address and prefix
# length of an adapter, as used by network_prefix/network_prefix_cidr's
# IPv6 branch. A port of PSFoundation's Resolve-IPv6PrefixData, simplified
# since the prefix length always arrives here as a clean CIDR integer
# (from 'ip'/'ifconfig' output) rather than CIM's either-integer-or-mask
# IPSubnet field PSFoundation had to handle.
# Globals:
#   None
# Arguments:
#   1 - Interface name (optional; resolved via default_adapter if omitted)
# Outputs:
#   "<address>/<prefix-length>" to stdout. An error to stderr on failure.
# Returns:
#   0 on success, 1 if no IPv6 address was found.
#######################################
function __libsh_net_ipv6_prefix_data() {
  local iface=${1:-} line address prefix_length

  if [[ -z $iface ]]; then
    iface=$(lib::net::default_adapter) || return 1
  fi

  if [[ $(uname) == "Darwin" ]]; then
    line=$(ifconfig "$iface" 2>/dev/null | awk '/inet6 / && !/fe80/{print $2, $4; exit}')
    if [[ -z $line ]]; then
      line=$(ifconfig "$iface" 2>/dev/null | awk '/inet6 /{print $2, $4; exit}')
    fi
    address=$(awk '{print $1}' <<<"$line")
    address=${address%%\%*}
    prefix_length=$(awk '{print $2}' <<<"$line")
  else
    line=$(ip -6 -o addr show dev "$iface" scope global 2>/dev/null | awk '{print $4}' | head -1)
    [[ -z $line ]] && line=$(ip -6 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | head -1)
    address="${line%/*}"
    prefix_length="${line#*/}"
  fi

  if [[ -z $address || -z $prefix_length ]]; then
    lib::log::print_error "No IPv6 address with a valid prefix length found on adapter '$iface'."
    return 1
  fi

  printf '%s/%s' "$address" "$prefix_length"
}

#######################################
# Convert an IPv4 CIDR prefix length to a dotted-decimal subnet mask.
# Globals:
#   None
# Arguments:
#   1 - Prefix length, 0-32
# Outputs:
#   The dotted-decimal mask to stdout.
# Returns:
#   The final printf status; callers must supply valid input.
#######################################
function __libsh_net_cidr_to_dotted_mask() {
  local prefix=${1} i octet
  local -a mask_octets=()

  for ((i = 0; i < 4; i++)); do
    if ((prefix >= 8)); then
      octet=255
      prefix=$((prefix - 8))
    elif ((prefix > 0)); then
      octet=$(((255 << (8 - prefix)) & 255))
      prefix=0
    else
      octet=0
    fi
    mask_octets+=("$octet")
  done

  printf '%s.%s.%s.%s' "${mask_octets[@]}"
}

#######################################
# Convert a dotted-decimal IPv4 subnet mask to its CIDR prefix length.
# Globals:
#   None
# Arguments:
#   1 - Dotted-decimal mask, e.g. "255.255.255.0"
# Outputs:
#   The prefix length to stdout.
# Returns:
#   The final printf status; callers must supply valid input.
#######################################
function __libsh_net_dotted_mask_to_cidr() {
  local mask=${1} octet bits=0
  local -a octets

  IFS='.' read -ra octets <<<"$mask"

  for octet in "${octets[@]}"; do
    while ((octet > 0)); do
      bits=$((bits + (octet & 1)))
      octet=$((octet >> 1))
    done
  done

  printf '%d' "$bits"
}

#######################################
# Convert a macOS/BSD ifconfig-style hex subnet mask (e.g. "0xffffff00")
# to dotted-decimal form.
# Globals:
#   None
# Arguments:
#   1 - Hex mask, with or without a leading "0x"
# Outputs:
#   The dotted-decimal mask to stdout.
# Returns:
#   The final printf status; callers must supply valid input.
#######################################
function __libsh_net_hex_mask_to_dotted() {
  local hex=${1#0x}

  printf '%d.%d.%d.%d' "0x${hex:0:2}" "0x${hex:2:2}" "0x${hex:4:2}" "0x${hex:6:2}"
}

#######################################
# Bitwise-AND two dotted-decimal IPv4 addresses, octet by octet.
# Globals:
#   None
# Arguments:
#   1 - First address
#   2 - Second address (typically a subnet mask)
# Outputs:
#   The result, in dotted-decimal form, to stdout.
# Returns:
#   The final printf status; callers must supply valid input.
#######################################
function __libsh_net_ipv4_and() {
  local ip=${1} mask=${2}
  local -a ip_o mask_o

  IFS='.' read -ra ip_o <<<"$ip"
  IFS='.' read -ra mask_o <<<"$mask"

  printf '%d.%d.%d.%d' \
    "$((ip_o[0] & mask_o[0]))" "$((ip_o[1] & mask_o[1]))" \
    "$((ip_o[2] & mask_o[2]))" "$((ip_o[3] & mask_o[3]))"
}

#######################################
# Compute the IPv4 broadcast address for an address/mask pair: the address
# bitwise-OR'd with the inverted mask.
# Globals:
#   None
# Arguments:
#   1 - IPv4 address
#   2 - Subnet mask
# Outputs:
#   The broadcast address, in dotted-decimal form, to stdout.
# Returns:
#   The final printf status; callers must supply valid input.
#######################################
function __libsh_net_ipv4_broadcast() {
  local ip=${1} mask=${2}
  local -a ip_o mask_o

  IFS='.' read -ra ip_o <<<"$ip"
  IFS='.' read -ra mask_o <<<"$mask"

  printf '%d.%d.%d.%d' \
    "$((ip_o[0] | (~mask_o[0] & 255)))" "$((ip_o[1] | (~mask_o[1] & 255)))" \
    "$((ip_o[2] | (~mask_o[2] & 255)))" "$((ip_o[3] | (~mask_o[3] & 255)))"
}

#######################################
# Expand an IPv6 address (handling '::' compression) into a flat 32-digit
# hex string -- 8 groups of 4 hex digits, 16 bytes.
# Globals:
#   None
# Arguments:
#   1 - IPv6 address
# Outputs:
#   The expanded 32-hex-digit string to stdout.
# Returns:
#   The final printf status; callers must supply valid input.
#######################################
function __libsh_net_ipv6_expand() {
  local address=${1}
  local left right double_colon_count missing i group out=""
  local -a left_groups right_groups groups=()

  double_colon_count=$(grep -o '::' <<<"$address" | wc -l)

  if [[ $double_colon_count -eq 1 ]]; then
    left="${address%%::*}"
    right="${address#*::}"

    left_groups=()
    [[ -n $left ]] && IFS=':' read -ra left_groups <<<"$left"
    right_groups=()
    [[ -n $right ]] && IFS=':' read -ra right_groups <<<"$right"

    missing=$((8 - ${#left_groups[@]} - ${#right_groups[@]}))

    groups=("${left_groups[@]}")
    for ((i = 0; i < missing; i++)); do
      groups+=("0")
    done
    groups+=("${right_groups[@]}")
  else
    IFS=':' read -ra groups <<<"$address"
  fi

  for group in "${groups[@]}"; do
    printf -v group '%04x' "0x$group"
    out+="$group"
  done

  printf '%s' "$out"
}

#######################################
# Zero out every bit beyond a prefix length in an expanded (32-hex-digit)
# IPv6 address, byte by byte -- a direct port of PSFoundation's
# Resolve-IPv6PrefixData masking loop.
# Globals:
#   None
# Arguments:
#   1 - Expanded 32-hex-digit IPv6 address
#   2 - Prefix length, 0-128
# Outputs:
#   The masked 32-hex-digit string to stdout.
# Returns:
#   The final printf status; callers must supply valid input.
#######################################
function __libsh_net_ipv6_apply_prefix() {
  local hex=${1} remaining=${2}
  local j byte_hex byte_val mask out=""

  for ((j = 0; j < 16; j++)); do
    byte_hex=${hex:$((j * 2)):2}
    byte_val=$((16#$byte_hex))

    if ((remaining >= 8)); then
      remaining=$((remaining - 8))
    elif ((remaining > 0)); then
      mask=$(((0xFF << (8 - remaining)) & 0xFF))
      byte_val=$((byte_val & mask))
      remaining=0
    else
      byte_val=0
    fi

    printf -v byte_hex '%02x' "$byte_val"
    out+="$byte_hex"
  done

  printf '%s' "$out"
}

#######################################
# Combine the RFC 4291 solicited-node multicast prefix
# (ff02::1:ff00:0/104) with the lower 24 bits of an expanded IPv6 address.
# Globals:
#   None
# Arguments:
#   1 - Expanded 32-hex-digit IPv6 address
# Outputs:
#   The expanded 32-hex-digit multicast address to stdout.
# Returns:
#   The final printf status; callers must supply valid input.
#######################################
function __libsh_net_ipv6_multicast() {
  local hex=${1} prefix

  printf -v prefix '%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x%02x' \
    0xFF 0x02 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x00 0x01 0xFF

  printf '%s%s' "$prefix" "${hex: -6}"
}

#######################################
# Render an expanded (32-hex-digit) IPv6 address back into standard,
# RFC 5952 compressed notation: the longest run of two or more consecutive
# all-zero groups is replaced with '::'.
# Globals:
#   None
# Arguments:
#   1 - Expanded 32-hex-digit IPv6 address
# Outputs:
#   The compressed address to stdout.
# Returns:
#   The final printf status; callers must supply valid input.
#######################################
function __libsh_net_ipv6_hex_to_string() {
  local hex=${1}
  local -a groups=()
  local i group

  for ((i = 0; i < 32; i += 4)); do
    group=$(printf '%x' "0x${hex:i:4}")
    groups+=("$group")
  done

  local best_start=-1 best_len=0 cur_start=-1 cur_len=0

  for ((i = 0; i < 8; i++)); do
    if [[ ${groups[i]} == "0" ]]; then
      [[ $cur_start -eq -1 ]] && cur_start=$i
      cur_len=$((cur_len + 1))
    else
      if ((cur_len > best_len)); then
        best_len=$cur_len
        best_start=$cur_start
      fi
      cur_start=-1
      cur_len=0
    fi
  done

  if ((cur_len > best_len)); then
    best_len=$cur_len
    best_start=$cur_start
  fi

  if ((best_len >= 2)); then
    local -a left=() right=()
    for ((i = 0; i < best_start; i++)); do
      left+=("${groups[i]}")
    done
    for ((i = best_start + best_len; i < 8; i++)); do
      right+=("${groups[i]}")
    done

    local left_str="${left[*]}"
    left_str=${left_str// /:}
    local right_str="${right[*]}"
    right_str=${right_str// /:}

    printf '%s::%s' "$left_str" "$right_str"
  else
    local all_str="${groups[*]}"
    printf '%s' "${all_str// /:}"
  fi
}

#######################################
# Validate encoded URI component characters without decoding them.
# Globals:
#   None
# Arguments:
#   1 - Component text
#   2 - Additional allowed characters (trusted expression suffix)
# Outputs:
#   None
# Returns:
#   0 valid, 1 invalid characters or percent escapes.
#######################################
function __libsh_net_uri_component() {
  local LC_ALL=C text=$1 allowed="^[a-zA-Z0-9._~!\$&'()*+,;=%$2-]*$"
  [[ $text =~ $allowed ]] || return 1

  while [[ $text == *%* ]]; do
    text=${text#*%}
    [[ $text =~ ^[a-fA-F0-9]{2} ]] || return 1
    text=${text:2}
  done
}

#######################################
# Split an absolute URI and validate its generic component grammar.
# Uses RFC 3986 syntax, excluding IPvFuture and scoped IPv6 literals.
# Globals:
#   __libsh_net_uri (caller-local associative array, written)
# Arguments:
#   1 - URI value
#   2 - uri, dsn or http; the latter two require one DNS/IP service host
# Outputs:
#   None; components stay encoded in the caller-local array.
# Returns:
#   0 valid, 1 malformed or unsupported URI.
#######################################
function __libsh_net_uri_split() {
  local LC_ALL=C rest=$1 authority='' host='' port='' userinfo='' tail
  local has_authority=0 has_userinfo=0 has_port=0 has_fragment=0
  __libsh_net_uri=()

  [[ $rest =~ ^[a-zA-Z][a-zA-Z0-9+.-]*: ]] || return 1
  __libsh_net_uri[scheme]=${rest%%:*}
  rest=${rest#*:}
  __libsh_net_uri[fragment]=''
  if [[ $rest == *'#'* ]]; then
    has_fragment=1
    __libsh_net_uri[fragment]=${rest#*#}
    rest=${rest%%#*}
  fi

  __libsh_net_uri[query]=''
  if [[ $rest == *'?'* ]]; then
    __libsh_net_uri[query]=${rest#*\?}
    rest=${rest%%\?*}
  fi
  __libsh_net_uri_component "${__libsh_net_uri[fragment]}" ':@/?' || return 1
  __libsh_net_uri_component "${__libsh_net_uri[query]}" ':@/?' || return 1

  if [[ $rest == //* ]]; then
    has_authority=1
    rest=${rest#//}
    authority=${rest%%/*}
    rest=${rest#"$authority"}
    tail=$authority

    if [[ $tail == *@* ]]; then
      has_userinfo=1
      userinfo=${tail%%@*}
      tail=${tail#*@}
      __libsh_net_uri_component "$userinfo" ':' || return 1
    fi

    if [[ $tail == \[* ]]; then
      host=${tail#\[}
      host=${host%%\]*}
      [[ $tail == *\]* ]] || return 1
      lib::net::ipv6_validate "$host" || return 1
      tail=${tail#*\]}
    else
      host=${tail%%:*}
      tail=${tail#"$host"}
      __libsh_net_uri_component "$host" '' || return 1
    fi

    if [[ -n $tail ]]; then
      [[ $tail == :* ]] || return 1
      has_port=1
      port=${tail#:}
      [[ -z $port || $port =~ ^[0-9]+$ ]] || return 1
    fi
  fi

  __libsh_net_uri_component "$rest" ':@/' || return 1
  if [[ $2 != uri ]]; then
    [[ $has_authority == 1 ]] || return 1
    [[ $2 != dsn || $has_fragment == 0 ]] || return 1
    __libsh_net_endpoint_host "$host" || return 1
    if [[ $has_port == 1 ]]; then
      lib::net::port_validate "$port" || return 1
    fi
  fi

  __libsh_net_uri[authority]=$authority
  __libsh_net_uri[userinfo]=$userinfo
  __libsh_net_uri[username]=${userinfo%%:*}
  __libsh_net_uri[password]=''
  if [[ $userinfo == *:* ]]; then
    __libsh_net_uri[password]=${userinfo#*:}
  fi
  __libsh_net_uri[host]=$host
  __libsh_net_uri[port]=$port
  __libsh_net_uri[path]=$rest
  __libsh_net_uri[has_authority]=$has_authority
  __libsh_net_uri[has_userinfo]=$has_userinfo
  __libsh_net_uri[has_port]=$has_port
  __libsh_net_uri[has_fragment]=$has_fragment
}

#######################################
# Validate an absolute URI without resolving or decoding it.
# Accepts hierarchical and opaque URIs. IPvFuture/scoped IPv6 are unsupported.
# Generic URI ports may be empty or arbitrary decimal digits; use dsn_validate
# for a usable service endpoint. Relative references are not absolute URIs.
# Globals:
#   None
# Arguments:
#   1 - URI value
# Outputs:
#   None
# Returns:
#   0 valid, 1 invalid, 2 incorrect argument count.
#######################################
function lib::net::uri_validate() {
  [[ $# == 1 ]] || return 2
  local -A __libsh_net_uri=()

  __libsh_net_uri_split "$1" uri
}

#######################################
# Parse one encoded component from an absolute URI.
# No decoding or normalization is performed; bracketed IPv6 hosts lose only
# their brackets. Absent and explicitly empty components both produce empty
# output. Input never reaches external command arguments or diagnostics.
# Globals:
#   None
# Arguments:
#   1 - URI value
#   2 - scheme, authority, userinfo, username, password, host, port, path,
#       query or fragment
# Outputs:
#   Requested component without an added newline; sanitized errors to stderr.
# Returns:
#   0 success, 1 invalid URI, 2 invalid invocation/component selector.
#######################################
function lib::net::uri_parse() {
  [[ $# == 2 ]] || return 2
  __libsh_net_uri_parse "$1" "$2" uri
}

#######################################
# Validate a single-host connection URI, without scheme-specific defaults.
# Requires a DNS/IP host, optional service port 1..65535, and no fragment.
# Driver keyword strings, socket paths and multi-host authorities are rejected.
# Globals:
#   None
# Arguments:
#   1 - DSN value
# Outputs:
#   None
# Returns:
#   0 valid, 1 invalid, 2 incorrect argument count.
#######################################
function lib::net::dsn_validate() {
  [[ $# == 1 ]] || return 2
  local -A __libsh_net_uri=()

  __libsh_net_uri_split "$1" dsn
}

#######################################
# Parse an encoded component from a single-host connection URI.
# Uses the same selectors/output rules as uri_parse and grammar as dsn_validate.
# For secret-bearing endpoint extraction into variables, use endpoint_from_uri.
# Globals:
#   None
# Arguments:
#   1 - DSN value
#   2 - Component selector accepted by uri_parse
# Outputs:
#   Component without an added newline; sanitized errors to stderr.
# Returns:
#   0 success, 1 invalid DSN, 2 invalid invocation/component selector.
#######################################
function lib::net::dsn_parse() {
  [[ $# == 2 ]] || return 2
  __libsh_net_uri_parse "$1" "$2" dsn
}

#######################################
# Select a public URI component after validating the entire input.
# Globals:
#   None
# Arguments:
#   1 - URI value
#   2 - Component selector
#   3 - uri or dsn validation profile
# Outputs:
#   Component without a newline; sanitized errors to stderr.
# Returns:
#   0 success, 1 invalid URI, 2 unsupported selector.
#######################################
function __libsh_net_uri_parse() {
  local -A __libsh_net_uri=()
  case $2 in
    scheme | authority | userinfo | username | password | host | port | path | query | fragment) ;;
    *)
      lib::log::print_error 'Unsupported URI component selector.'
      return 2
      ;;
  esac

  if ! __libsh_net_uri_split "$1" "$3"; then
    lib::log::print_error 'Invalid or unsupported connection URI.'
    return 1
  fi

  printf '%s' "${__libsh_net_uri[$2]}"
}

#######################################
# Look up a hostname with getent, or nslookup when getent is unavailable.
# Pass a hostname, not a URI/DSN; parsing belongs to the caller. getent uses
# the system name-service configuration, while nslookup queries DNS directly.
# Resolver timeouts follow system/tool defaults.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Hostname
# Outputs:
#   Unique IP addresses, one per line; sanitized errors to stderr.
# Returns:
#   0 addresses found, 1 missing resolver/lookup failure, 2 invalid invocation.
# Dependencies:
#   getent or nslookup, checked only at invocation.
#######################################
function lib::net::dns_lookup() {
  if [[ $# != 1 || -z ${1:-} || $1 == -* || $1 == *[[:space:][:cntrl:]]* ]]; then
    lib::log::print_error 'dns_lookup requires one hostname.'
    return 2
  fi

  local response backend line address _ in_answer=0 output='' seen=$'\n'
  if command -v getent >/dev/null 2>&1; then
    backend=getent
    response=$(getent ahosts "$1" 2>/dev/null) || {
      lib::log::print_error 'Hostname lookup failed.'
      return 1
    }
  elif command -v nslookup >/dev/null 2>&1; then
    backend=nslookup
    response=$(nslookup "$1" 2>/dev/null) || {
      lib::log::print_error 'Hostname lookup failed.'
      return 1
    }
  else
    lib::log::print_error 'dns_lookup requires getent or nslookup.'
    return 1
  fi

  while IFS= read -r line; do
    if [[ $backend == nslookup ]]; then
      case $line in
        Name:*)
          in_answer=1
          continue
          ;;
        Address:* | Addresses:*)
          [[ $in_answer == 1 ]] || continue
          line=${line#*:}
          ;;
        *) continue ;;
      esac
    fi

    IFS=$' \t' read -r address _ <<<"$line"
    lib::net::ip_validate "$address" || continue
    if [[ $seen != *$'\n'"$address"$'\n'* ]]; then
      output+="$address"$'\n'
      seen+="$address"$'\n'
    fi
  done <<<"$response"

  if [[ -z $output ]]; then
    lib::log::print_error 'Hostname lookup returned no IP addresses.'
    return 1
  fi

  printf '%s' "$output"
}

#######################################
# Probe HTTP(S) with one GET, accepting only 2xx responses.
# TLS verification stays enabled. Redirects are opt-in, capped at five, and
# cannot downgrade HTTPS to HTTP. The total timeout includes redirects.
# The URL is supplied to curl on stdin; response bodies and curl diagnostics
# are discarded. Proxy and trust-store environment settings remain effective.
# Globals:
#   PATH and curl proxy/trust environment (read)
# Arguments:
#   1 - HTTP(S) URL
#   2+ - Optional --timeout SECONDS (positive integer, default 10),
#        -f or --follow-redirects
# Outputs:
#   Final HTTP status without a newline on HTTP completion, even if rejected;
#   sanitized errors on stderr. No status on transport failure.
# Returns:
#   0 accepted 2xx, 1 rejected HTTP status, 2 invalid invocation/URL,
#   3 missing curl or transport/TLS/timeout failure. Never exits.
# Dependencies:
#   curl, checked only at invocation.
#######################################
function lib::net::http_probe() {
  [[ $# -ge 1 ]] || return 2
  local url=$1 timeout status scheme redirects
  local -A __libsh_net_uri=()
  # Parser inputs are consumed through Bash dynamic scope.
  # shellcheck disable=SC2034
  local -a OPTS=('--timeout,:timeout:1:optional' '-f,--follow-redirects:follow:0:optional')
  # shellcheck disable=SC2034
  local -A OPTS_HELP=([timeout]='Total timeout in seconds' [follow]='Follow at most five redirects') OPTS_VALUES=()
  local -a options=()

  shift
  lib::opt::parse ${1+"$@"} || return 2
  timeout=$(__libsh_net_decimal "${OPTS_VALUES[timeout]:-10}" 86400 1) || return 2
  if ! __libsh_net_uri_split "$url" http; then
    lib::log::print_error 'http_probe requires an HTTP(S) URL with a valid host.'
    return 2
  fi

  scheme=${__libsh_net_uri[scheme],,}
  case $scheme in
    http) redirects='=http,https' ;;
    https) redirects='=https' ;;
    *)
      lib::log::print_error 'http_probe supports only HTTP and HTTPS.'
      return 2
      ;;
  esac
  if [[ ${OPTS_VALUES[follow]:-0} == 1 ]]; then
    options+=(--location)
  fi

  if ! command -v curl >/dev/null 2>&1; then
    lib::log::print_error 'http_probe requires curl.'
    return 3
  fi

  # Validated URI text cannot contain quotes, backslashes or literal newlines,
  # so it remains one quoted config value without exposing it in curl argv.
  status=$(curl --disable --silent --globoff --output /dev/null \
    --write-out '%{http_code}' --connect-timeout "$timeout" --max-time "$timeout" \
    --proto '=http,https' --proto-redir "$redirects" --max-redirs 5 \
    ${options[@]+"${options[@]}"} --config - <<<"url = \"$url\"" 2>/dev/null) || {
    lib::log::print_error 'HTTP transport failed.'
    return 3
  }

  if [[ ! $status =~ ^[1-5][0-9][0-9]$ ]]; then
    lib::log::print_error 'HTTP transport returned no valid status.'
    return 3
  fi

  printf '%s' "$status"
  [[ $status == 2* ]]
}
