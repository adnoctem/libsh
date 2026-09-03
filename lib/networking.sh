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
function lib::networking::tcp_probe() {
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
# Convenience wrapper around lib::networking::tcp_probe: parse host/port out
# of a DSN with 'trurl' first. Kept separate from lib::networking::tcp_probe
# itself so this module carries no hard dependency on trurl being installed
# -- only callers of THIS function need it on PATH.
# Globals:
#   None
# Arguments:
#   1 - DSN/URL to parse (e.g. "mysql://user:pass@host:3306/db")
#   2 - Default port to use if the DSN doesn't specify one
#   3 - Label to use in log output (optional, defaults to the DSN's host)
#   4 - Number of retries before giving up (optional, default 60)
#   5 - Per-attempt connect timeout in seconds (optional, default 5)
# Outputs:
#   Same as lib::networking::tcp_probe.
# Returns:
#   Same as lib::networking::tcp_probe.
#######################################
function lib::networking::tcp_dsn_probe() {
  local dsn=${1} default_port=${2} label=${3:-} tries=${4:-60} timeout=${5:-5}
  local host port

  if ! command -v trurl &>/dev/null; then
    lib::log::red "lib::networking::tcp_dsn_probe requires 'trurl' on PATH to parse DSNs."
    exit 1
  fi

  host=$(trurl "${dsn}" --get '{host}')
  port=$(trurl "${dsn}" --get '{port}')
  port=${port:-${default_port}}

  lib::networking::tcp_probe "${host}" "${port}" "${label:-${host}}" "${tries}" "${timeout}"
}

# Default-adapter discovery and IP/gateway/DNS/MAC/prefix/broadcast/multicast
# address resolution -- a port of PSFoundation's networking.ps1, redesigned
# around Linux's 'ip' (iproute2, not the often-absent-on-containers net-tools
# 'ifconfig'/'route') and macOS's BSD-native 'ifconfig'/'route'/'ipconfig'
# instead of Windows' CIM/Get-NetAdapter/[System.Net.IPAddress]. PSFoundation
# threads a resolved adapter object through every function to avoid
# re-resolving it; here that's just an optional interface-name string, since
# re-running 'ip'/'ifconfig' is cheap and bash has no structured objects.
# Every function logs a red error and returns 1 on failure, matching the
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
lib::networking::default_adapter() {
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
    lib::log::red "No default network adapter found."
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
lib::networking::ip_address() {
  local family=${1:-ipv4} iface=${2:-} ip

  if [[ -z $iface ]]; then
    iface=$(lib::networking::default_adapter) || return 1
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
    lib::log::red "No $family address found on adapter '$iface'."
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
lib::networking::subnet_mask() {
  local iface=${1:-} cidr hex

  if [[ -z $iface ]]; then
    iface=$(lib::networking::default_adapter) || return 1
  fi

  if [[ $(uname) == "Darwin" ]]; then
    hex=$(ifconfig "$iface" 2>/dev/null | awk '/inet /{print $4; exit}')
    if [[ -z $hex ]]; then
      lib::log::red "No IPv4 subnet mask found on adapter '$iface'."
      return 1
    fi
    lib::networking::__hex_mask_to_dotted "$hex"
    return 0
  fi

  cidr=$(ip -4 -o addr show dev "$iface" 2>/dev/null | awk '{print $4}' | cut -d/ -f2 | head -1)

  if [[ -z $cidr ]]; then
    lib::log::red "No IPv4 subnet mask found on adapter '$iface'."
    return 1
  fi

  lib::networking::__cidr_to_dotted_mask "$cidr"
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
lib::networking::default_gateway() {
  local family=${1:-ipv4} iface=${2:-} flag=-4 gateway

  if [[ -z $iface ]]; then
    iface=$(lib::networking::default_adapter) || return 1
  fi
  [[ $family == "ipv6" ]] && flag=-6

  if [[ $(uname) == "Darwin" ]]; then
    if [[ $family == "ipv6" ]]; then
      gateway=$(route -n get -inet6 default 2>/dev/null | awk '/gateway:/{print $2}')
    else
      gateway=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
    fi
  else
    gateway=$(ip $flag route show default dev "$iface" 2>/dev/null |
      awk '{for (i = 1; i <= NF; i++) if ($i == "via") print $(i + 1)}' | head -1)
  fi

  if [[ -z $gateway ]]; then
    lib::log::red "No $family default gateway found on adapter '$iface'."
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
lib::networking::dns_servers() {
  local family=${1:-} servers

  case "$family" in
  ipv4) servers=$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | grep -v ':') ;;
  ipv6) servers=$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null | grep ':') ;;
  *) servers=$(awk '/^nameserver/{print $2}' /etc/resolv.conf 2>/dev/null) ;;
  esac

  if [[ -z $servers ]]; then
    lib::log::red "No ${family:-} DNS servers found in /etc/resolv.conf."
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
lib::networking::mac_address() {
  local iface=${1:-} mac

  if [[ -z $iface ]]; then
    iface=$(lib::networking::default_adapter) || return 1
  fi

  if [[ $(uname) == "Darwin" ]]; then
    mac=$(ifconfig "$iface" 2>/dev/null | awk '/ether /{print $2; exit}')
  else
    mac=$(cat "/sys/class/net/$iface/address" 2>/dev/null)
  fi

  if [[ -z $mac ]]; then
    lib::log::red "No MAC address found on adapter '$iface'."
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
lib::networking::network_prefix() {
  local family=${1:-ipv4} iface=${2:-} ip mask data address prefix_length expanded masked

  if [[ -z $iface ]]; then
    iface=$(lib::networking::default_adapter) || return 1
  fi

  if [[ $family == "ipv4" ]]; then
    ip=$(lib::networking::ip_address ipv4 "$iface") || return 1
    mask=$(lib::networking::subnet_mask "$iface") || return 1
    lib::networking::__ipv4_and "$ip" "$mask"
    return 0
  fi

  data=$(lib::networking::__ipv6_prefix_data "$iface") || return 1
  address="${data%/*}"
  prefix_length="${data#*/}"
  expanded=$(lib::networking::__ipv6_expand "$address")
  masked=$(lib::networking::__ipv6_apply_prefix "$expanded" "$prefix_length")
  lib::networking::__ipv6_hex_to_string "$masked"
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
lib::networking::network_prefix_cidr() {
  local family=${1:-ipv4} iface=${2:-} prefix mask cidr data prefix_length

  if [[ -z $iface ]]; then
    iface=$(lib::networking::default_adapter) || return 1
  fi

  if [[ $family == "ipv4" ]]; then
    prefix=$(lib::networking::network_prefix ipv4 "$iface") || return 1
    mask=$(lib::networking::subnet_mask "$iface") || return 1
    cidr=$(lib::networking::__dotted_mask_to_cidr "$mask")
    printf '%s/%s' "$prefix" "$cidr"
    return 0
  fi

  data=$(lib::networking::__ipv6_prefix_data "$iface") || return 1
  prefix_length="${data#*/}"
  prefix=$(lib::networking::network_prefix ipv6 "$iface") || return 1
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
lib::networking::broadcast_address() {
  local iface=${1:-} ip mask

  if [[ -z $iface ]]; then
    iface=$(lib::networking::default_adapter) || return 1
  fi

  ip=$(lib::networking::ip_address ipv4 "$iface") || return 1
  mask=$(lib::networking::subnet_mask "$iface") || return 1
  lib::networking::__ipv4_broadcast "$ip" "$mask"
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
lib::networking::multicast_address() {
  local iface=${1:-} ip expanded multicast

  if [[ -z $iface ]]; then
    iface=$(lib::networking::default_adapter) || return 1
  fi

  ip=$(lib::networking::ip_address ipv6 "$iface") || return 1
  expanded=$(lib::networking::__ipv6_expand "$ip")
  multicast=$(lib::networking::__ipv6_multicast "$expanded")
  lib::networking::__ipv6_hex_to_string "$multicast"
}

#######################################
# Check whether a string is a valid IPv4 address per RFC 791: four
# dot-separated decimal octets, each 0-255, no leading zeros. Arithmetic
# decomposition, no regex.
# Globals:
#   None
# Arguments:
#   1 - The string to validate
# Returns:
#   0 if valid, 1 otherwise.
#######################################
lib::networking::is_ipv4() {
  local address=${1:-}
  local -a octets
  local octet

  [[ -z $address ]] && return 1
  [[ $address == .* || $address == *. ]] && return 1

  IFS='.' read -ra octets <<<"$address"
  [[ ${#octets[@]} -eq 4 ]] || return 1

  for octet in "${octets[@]}"; do
    [[ -n $octet ]] || return 1
    [[ $octet =~ ^[0-9]+$ ]] || return 1
    if [[ ${#octet} -gt 1 && ${octet:0:1} == "0" ]]; then
      return 1
    fi
    ((octet >= 0 && octet <= 255)) || return 1
  done

  return 0
}

#######################################
# Check whether a string is a valid IPv6 address per RFC 4291: full form,
# '::' compression (at most once), and IPv4-mapped addresses
# (::ffff:x.x.x.x, whose embedded IPv4 portion is delegated to is_ipv4).
# Structural decomposition, no regex for the address as a whole.
# Globals:
#   None
# Arguments:
#   1 - The string to validate
# Returns:
#   0 if valid, 1 otherwise.
#######################################
lib::networking::is_ipv6() {
  local address=${1:-}
  local last_segment left right double_colon_count group
  local -a explicit left_groups right_groups

  [[ -z $address ]] && return 1

  # Delegate the embedded IPv4 portion of a mapped address, e.g.
  # ::ffff:192.168.1.1, to is_ipv4, then treat it as a placeholder hex
  # group for the rest of this validation.
  if [[ $address == *:* ]]; then
    last_segment=${address##*:}
    if [[ $last_segment == *.* ]]; then
      lib::networking::is_ipv4 "$last_segment" || return 1
      address="${address%:*}:0"
    fi
  fi

  # '::' must appear at most once. Non-overlapping match count, matching
  # how .NET's IndexOf-based scan in the PSFoundation original treats a
  # run of 3+ colons.
  double_colon_count=$(grep -o '::' <<<"$address" | wc -l)
  [[ $double_colon_count -gt 1 ]] && return 1

  if [[ $double_colon_count -eq 1 ]]; then
    left="${address%%::*}"
    right="${address#*::}"

    left_groups=()
    [[ -n $left ]] && IFS=':' read -ra left_groups <<<"$left"
    right_groups=()
    [[ -n $right ]] && IFS=':' read -ra right_groups <<<"$right"

    explicit=("${left_groups[@]}" "${right_groups[@]}")
    [[ ${#explicit[@]} -gt 7 ]] && return 1
  else
    IFS=':' read -ra explicit <<<"$address"
    [[ ${#explicit[@]} -eq 8 ]] || return 1
  fi

  for group in "${explicit[@]}"; do
    [[ ${#group} -ge 1 && ${#group} -le 4 ]] || return 1
    [[ $group =~ ^[0-9a-fA-F]+$ ]] || return 1
    ((16#$group <= 0xFFFF)) || return 1
  done

  return 0
}

# --- Internal helpers ---------------------------------------------------
# Not part of the module's public surface (still lib::networking::-
# namespaced, same as every function here -- this repo has no true-private
# convention), but meant to be called by the functions above, not directly.

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
lib::networking::__ipv6_prefix_data() {
  local iface=${1:-} line address prefix_length

  if [[ -z $iface ]]; then
    iface=$(lib::networking::default_adapter) || return 1
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
    lib::log::red "No IPv6 address with a valid prefix length found on adapter '$iface'."
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
#######################################
lib::networking::__cidr_to_dotted_mask() {
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
#######################################
lib::networking::__dotted_mask_to_cidr() {
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
#######################################
lib::networking::__hex_mask_to_dotted() {
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
#######################################
lib::networking::__ipv4_and() {
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
#######################################
lib::networking::__ipv4_broadcast() {
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
#######################################
lib::networking::__ipv6_expand() {
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
#######################################
lib::networking::__ipv6_apply_prefix() {
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
#######################################
lib::networking::__ipv6_multicast() {
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
#######################################
lib::networking::__ipv6_hex_to_string() {
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
    for ((i = 0; i < best_start; i++)); do left+=("${groups[i]}"); done
    for ((i = best_start + best_len; i < 8; i++)); do right+=("${groups[i]}"); done

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
