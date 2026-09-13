#!/usr/bin/env bats

setup() {
  REPO_ROOT=${REPO_ROOT:-$(git rev-parse --show-toplevel)}

  load "$REPO_ROOT/test/bats/plugins/bats-support/load"
  load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

  source "$REPO_ROOT/lib/lib.sh"

  TEST_TMP=$(mktemp -d)
  ORIGINAL_PATH="$PATH"
  mkdir -p "$TEST_TMP/bin"
  export PATH="$TEST_TMP/bin:$PATH"

  # Default every test to a faked non-Darwin 'uname', so the Linux-mocked
  # tests (fake 'ip', etc.) are deterministic regardless of which CI
  # platform actually runs them -- without this, they only pass by
  # accident on Linux runners and fail for real on macOS ones, since the
  # function would then correctly take the real Darwin branch and talk
  # to the real 'route'/'ifconfig' instead of the installed fakes.
  # Darwin-specific tests override this via fake_uname_darwin below.
  cat >"$TEST_TMP/bin/uname" <<-'FAKE'
		#!/usr/bin/env bash
		echo "Linux"
	FAKE
  chmod +x "$TEST_TMP/bin/uname"
}

teardown() {
  export PATH="$ORIGINAL_PATH"
  [[ -n ${TEST_TMP:-} ]] && rm -rf "$TEST_TMP"
}

# Install a fake 'nc' that fails 'fail_times' calls before succeeding, so
# tests exercise the retry loop without depending on real network state. Every
# invocation's arguments are appended to nc-args.log, so callers of
# lib::net::tcp_dsn_probe can assert the host/port it actually resolved.
#######################################
# Install a netcat fixture that fails a configured number of attempts.
# Globals:
#   TEST_TMP (read)
# Arguments:
#   1 - Failed attempts before success (optional, default 0)
# Outputs:
#   Executable fixture on disk; command errors to stderr.
# Returns:
#   The chmod status.
#######################################
install_fake_nc() {
  local fail_times=${1:-0}

  cat >"$TEST_TMP/bin/nc" <<-FAKE
		#!/usr/bin/env bash
		echo "\$*" >>"$TEST_TMP/nc-args.log"
		count_file="$TEST_TMP/nc-calls"
		count=\$(cat "\$count_file" 2>/dev/null || echo 0)
		count=\$((count + 1))
		echo "\$count" >"\$count_file"
		[[ \$count -gt $fail_times ]]
	FAKE
  chmod +x "$TEST_TMP/bin/nc"
}

# Install a fake 'trurl' that answers the two '--get' formats
# lib::net::tcp_dsn_probe uses, for a fixed host/port.
#######################################
# Install a URL-tool fixture with a fixed host and port.
# Globals:
#   TEST_TMP (read)
# Arguments:
#   1 - Host to return
#   2 - Port to return
# Outputs:
#   Executable fixture on disk; command errors to stderr.
# Returns:
#   The chmod status.
#######################################
install_fake_trurl() {
  local host=${1} port=${2}

  cat >"$TEST_TMP/bin/trurl" <<-FAKE
		#!/usr/bin/env bash
		case "\$3" in
		'{host}') echo "$host" ;;
		'{port}') echo "$port" ;;
		esac
	FAKE
  chmod +x "$TEST_TMP/bin/trurl"
}

@test "endpoint parser handles encoded userinfo, paths, queries, IPv4 and IPv6" {
  local uri host='' port='' expected
  while IFS='|' read -r uri expected; do
    lib::net::endpoint_from_uri uri host port --default-port 5432
    [[ "$host:$port" == "$expected" ]]
  done <<-'CASES'
		postgres://user:p%40ss%3A%2F%3F%23@db.example:05432/app?host=evil:9#fragment|db.example:5432
		mysql://127.0.0.1/db|127.0.0.1:5432
		postgresql://[::1]:65535/db|::1:65535
		postgres://[2001:db8::1]/db|2001:db8::1:5432
		postgres://[::ffff:192.0.2.1]:1|::ffff:192.0.2.1:1
		postgres://[1:2:3:4:5:6:192.0.2.1]:1|1:2:3:4:5:6:192.0.2.1:1
		custom+db://a!$&'()*+,;=:p%25@db.internal./name%20here|db.internal.:5432
		postgres://localhost?port=1#host=other|localhost:5432
	CASES
}

@test "endpoint parser rejects unsupported authorities and leaves both outputs unchanged" {
  local uri host=oldhost port=oldport
  while IFS= read -r uri; do
    if lib::net::endpoint_from_uri uri host port --default-port 5432; then
      printf 'Unexpected acceptance: %s\n' "$uri"
      return 1
    fi
    [[ $host == oldhost && $port == oldport ]]
  done <<-'CASES'
		db:5432
		1postgres://db
		postgres:///db
		postgres://user@@db:5432
		postgres://user:%GG@db:5432
		postgres://db/path%
		postgres://db:0
		postgres://db:65536
		postgres://db:9999999999999999999999
		postgres://db:
		postgres://db:-1
		postgres://db:1+2
		postgres://db:5432,other:5432
		postgres://db,other
		postgres://::1
		postgres://[::1
		postgres://[::1]extra
		postgres://[::1]:
		postgres://[::1]]:5432
		postgres://[fe80::1%25eth0]
		postgres://[1:2:3:4:5:6:7:8::]
		postgres://[1:2:3:4:5:6:7]
		postgres://[:::1]
		postgres://[1::2::3]
		postgres://[::1:]
		postgres://[1::2:]
		postgres://[1:2:3:4:5:192.0.2.1]
		postgres://[::ffff:999.0.0.1]
		postgres://[127.0.0.1]
		postgres://999.1.1.1
		postgres://-option
		postgres://db..
		postgres://db name
		postgres://%2Fsocket
	CASES
}

@test "endpoint parser validates references, defaults and unset input under strict mode" {
  local uri='postgres://db:5432' host=old port=old
  run lib::net::endpoint_from_uri uri host host
  assert_failure 2
  run lib::net::endpoint_from_uri uri uri port
  assert_failure 2
  run lib::net::endpoint_from_uri uri host port --default-port 0
  assert_failure 2
  uri='postgres://db'
  run lib::net::endpoint_from_uri uri host port
  assert_failure 2
  run bash -uc 'source "$1/lib/lib.sh"; if lib::net::endpoint_from_uri missing host port; then exit 1; fi; echo survived' bash "$REPO_ROOT"
  assert_success
  assert_output --partial survived
}

#######################################
# Install a sleep fixture that records calls and returns a chosen status.
# Globals:
#   TEST_TMP (read)
# Arguments:
#   1 - Exit status (optional, default 0)
# Outputs:
#   Executable fixture on disk; command errors to stderr.
# Returns:
#   The chmod status.
#######################################
install_fake_sleep() {
  cat >"$TEST_TMP/bin/sleep" <<-FAKE
		#!/usr/bin/env bash
		printf '%s\n' "\$*" >>"$TEST_TMP/sleep-calls"
		exit ${1:-0}
	FAKE
  chmod +x "$TEST_TMP/bin/sleep"
}

@test "tcp_wait counts attempts and sleeps exactly, returning on exhaustion" {
  install_fake_nc 999
  install_fake_sleep
  if lib::net::tcp_wait db 5432 --attempts 3 --timeout 2 --interval 4; then return 1; fi
  [[ $(cat "$TEST_TMP/nc-calls") == 3 ]]
  [[ $(wc -l <"$TEST_TMP/sleep-calls") -eq 2 ]]
  [[ $(head -1 "$TEST_TMP/sleep-calls") == 4 ]]
  [[ $(head -1 "$TEST_TMP/nc-args.log") == '-z -w2 db 5432' ]]
}

@test "tcp_wait stops at delayed success and skips sleep for zero interval" {
  install_fake_nc 2
  install_fake_sleep
  lib::net::tcp_wait ::1 05432 --attempts 5 --interval 0
  [[ $(cat "$TEST_TMP/nc-calls") == 3 && ! -e $TEST_TMP/sleep-calls ]]
}

@test "tcp_wait uses the macOS TCP connection timeout" {
  install_fake_nc 0
  install_fake_sleep
  uname() { printf 'Darwin\n'; }
  lib::net::tcp_wait db 5432 --timeout 3
  [[ $(cat "$TEST_TMP/nc-args.log") == '-z -w3 -G 3 db 5432' ]]
}

@test "tcp_wait immediate success and single failure never sleep" {
  install_fake_nc 0
  install_fake_sleep
  lib::net::tcp_wait db 5432 --attempts 1
  [[ ! -e $TEST_TMP/sleep-calls ]]
  install_fake_nc 999
  if lib::net::tcp_wait db 5432 --attempts 1; then return 1; fi
  [[ ! -e $TEST_TMP/sleep-calls ]]
}

@test "tcp_wait validates inputs and dependencies before connecting" {
  install_fake_nc 0
  install_fake_sleep
  local flag value
  for flag in --attempts --timeout --interval; do
    for value in -1 '1+1' 99999999999999999999 ''; do
      run lib::net::tcp_wait db 5432 "$flag" "$value"
      assert_failure 2
    done
  done
  run lib::net::tcp_wait -bad 5432
  assert_failure 2
  run lib::net::tcp_wait db 65536
  assert_failure 2
  run lib::net::tcp_wait db 5432 --attempts 0
  assert_failure 2
  run lib::net::tcp_wait db 5432 --timeout 0
  assert_failure 2
  run lib::net::tcp_wait db 5432 --interval 1 --interval 1
  assert_failure 2
  [[ ! -e $TEST_TMP/nc-calls ]]
  mkdir "$TEST_TMP/empty-path"
  PATH="$TEST_TMP/empty-path" run lib::net::tcp_wait db 5432
  assert_failure 1
}

@test "tcp_wait stops on sleep failure and allows strict-mode cleanup" {
  install_fake_nc 999
  install_fake_sleep 1
  run bash -c '
		set -euo pipefail
		source "$1/lib/lib.sh"
		before=$(set +o)
		if lib::net::tcp_wait db 5432 --attempts 4; then exit 1; fi
		[[ $(set +o) == "$before" ]]
		echo cleanup
	' bash "$REPO_ROOT"
  assert_success
  assert_output --partial cleanup
  [[ $(cat "$TEST_TMP/nc-calls") == 1 ]]
}

@test "tcp_wait returns before connecting if platform discovery fails" {
  install_fake_nc 0
  install_fake_sleep
  uname() { return 1; }
  if lib::net::tcp_wait db 5432; then return 1; fi
  [[ ! -e $TEST_TMP/nc-calls && ! -e $TEST_TMP/sleep-calls ]]
}

@test "new parser and wait keep URI credentials out of diagnostics and helper argv" {
  install_fake_nc 0
  install_fake_sleep
  local uri='postgres://syntheticUser:syntheticPassword@db:5432/app' host='' port=''
  lib::net::endpoint_from_uri uri host port >"$TEST_TMP/out" 2>"$TEST_TMP/err"
  lib::net::tcp_wait "$host" "$port" >>"$TEST_TMP/out" 2>>"$TEST_TMP/err"
  uri='postgres://syntheticUser:syntheticPassword@db:bad/app'
  if lib::net::endpoint_from_uri uri host port >>"$TEST_TMP/out" 2>>"$TEST_TMP/err"; then return 1; fi
  run grep -E 'syntheticUser|syntheticPassword|postgres://' "$TEST_TMP/out" "$TEST_TMP/err" "$TEST_TMP/nc-args.log"
  assert_failure 1
}

# lib::net::tcp_probe
@test "lib::net::tcp_probe succeeds immediately when the port is open" {
  install_fake_nc 0

  run lib::net::tcp_probe 127.0.0.1 1234

  assert_success
  assert_output --partial "127.0.0.1:1234 connection established"
}

@test "lib::net::tcp_probe retries until the port opens" {
  install_fake_nc 2

  run lib::net::tcp_probe 127.0.0.1 1234 "" 5 1

  assert_success
  assert_output --partial "connection established"
}

@test "lib::net::tcp_probe exits 1 after exhausting its retry budget" {
  install_fake_nc 999

  run lib::net::tcp_probe 127.0.0.1 1234 "" 2 1

  assert_failure 1
  assert_output --partial "FATAL: could not reach 127.0.0.1:1234"
}

@test "lib::net::tcp_probe uses the given label in output" {
  install_fake_nc 0

  run lib::net::tcp_probe 127.0.0.1 1234 "database"

  assert_output --partial "Checking for an active database connection"
}

# lib::net::tcp_dsn_probe
@test "lib::net::tcp_dsn_probe fails cleanly without trurl on PATH" {
  ln -s "$(command -v date)" "$TEST_TMP/bin/date"
  PATH="$TEST_TMP/bin" run lib::net::tcp_dsn_probe "mysql://user:pass@127.0.0.1:3306/db" 3306

  assert_failure 1
  assert_output --partial "requires 'trurl'"
}

# tcp_dsn_probe's default label is just the parsed host (see
# lib::net::tcp_probe's own default label, which never kicks in since
# tcp_dsn_probe always passes one explicitly) -- the port isn't visible in
# that message, so these assert the port trurl resolved via the fake nc's
# argument log instead.
@test "lib::net::tcp_dsn_probe parses host and port with trurl" {
  install_fake_trurl "127.0.0.1" "3306"
  install_fake_nc 0

  run lib::net::tcp_dsn_probe "mysql://user:pass@127.0.0.1:3306/db" 5432

  assert_success
  assert_output --partial "127.0.0.1 connection established"
  assert_equal "$(cat "$TEST_TMP/nc-args.log")" "-z -w5 127.0.0.1 3306"
}

@test "lib::net::tcp_dsn_probe falls back to the default port" {
  install_fake_trurl "127.0.0.1" ""
  install_fake_nc 0

  run lib::net::tcp_dsn_probe "mysql://127.0.0.1/db" 3306

  assert_success
  assert_output --partial "127.0.0.1 connection established"
  assert_equal "$(cat "$TEST_TMP/nc-args.log")" "-z -w5 127.0.0.1 3306"
}

@test "lib::net::tcp_dsn_probe uses the host as the default label" {
  install_fake_trurl "db.internal" "5432"
  install_fake_nc 0

  run lib::net::tcp_dsn_probe "postgres://db.internal:5432/app" 5432

  assert_output --partial "Checking for an active db.internal connection"
}

# --- Adapter resolution / address lookup mocks ---------------------------
# Fake 'ip' (Linux) and 'route'/'ifconfig'/'ipconfig' (Darwin, paired with
# fake_uname_darwin from paths.bats's precedent) covering exactly the
# invocations lib/net.sh's OS-resolution functions make -- confirmed
# via grep against the real implementation, not guessed.

#######################################
# Install a uname fixture reporting Darwin on any host platform.
# Globals:
#   TEST_TMP (read)
# Arguments:
#   None
# Outputs:
#   Executable fixture on disk; command errors to stderr.
# Returns:
#   The chmod status.
#######################################
fake_uname_darwin() {
  cat >"$TEST_TMP/bin/uname" <<-'FAKE'
		#!/usr/bin/env bash
		echo "Darwin"
	FAKE
  chmod +x "$TEST_TMP/bin/uname"
}

# iface, ipv4 CIDR, IPv4 gateway, IPv6 global CIDR (optional), IPv6
# link-local CIDR, IPv6 gateway (optional)
#######################################
# Install a Linux network-tool fixture with configured addresses and routes.
# Globals:
#   TEST_TMP (read)
# Arguments:
#   1 - Interface name
#   2 - IPv4 CIDR
#   3 - IPv4 gateway
#   4 - Global IPv6 CIDR (optional)
#   5 - Link-local IPv6 CIDR (optional, default fe80::50/64)
#   6 - IPv6 gateway (optional)
# Outputs:
#   Executable fixture on disk; command errors to stderr.
# Returns:
#   The chmod status.
#######################################
install_fake_ip() {
  local iface=$1 ipv4_cidr=$2 gw4=$3 ipv6_global_cidr=${4:-} \
    ipv6_ll_cidr=${5:-fe80::50/64} gw6=${6:-}

  cat >"$TEST_TMP/bin/ip" <<-FAKE
		#!/usr/bin/env bash
		case "\$*" in
		"-4 route show default")
			echo "default via $gw4 dev $iface proto dhcp metric 100"
			;;
		"-4 route show default dev $iface")
			echo "default via $gw4 dev $iface proto dhcp metric 100"
			;;
		"-6 route show default dev $iface")
			[[ -n "$gw6" ]] && echo "default via $gw6 dev $iface proto ra metric 100"
			;;
		"-4 -o addr show dev $iface")
			echo "2: $iface    inet $ipv4_cidr brd 255.255.255.255 scope global $iface"
			;;
		"-6 -o addr show dev $iface scope global")
			[[ -n "$ipv6_global_cidr" ]] && echo "3: $iface    inet6 $ipv6_global_cidr scope global"
			;;
		"-6 -o addr show dev $iface")
			echo "4: $iface    inet6 $ipv6_ll_cidr scope link"
			;;
		esac
	FAKE
  chmod +x "$TEST_TMP/bin/ip"
}

# Two default routes at different metrics, to exercise the lowest-metric
# selection default_adapter is documented to do.
#######################################
# Install a route fixture with two default routes and different metrics.
# Globals:
#   TEST_TMP (read)
# Arguments:
#   None
# Outputs:
#   Executable fixture on disk; command errors to stderr.
# Returns:
#   The chmod status.
#######################################
install_fake_ip_multi_route() {
  cat >"$TEST_TMP/bin/ip" <<-'FAKE'
		#!/usr/bin/env bash
		if [[ "$*" == "-4 route show default" ]]; then
			echo "default via 10.0.0.1 dev eth1 proto dhcp metric 200"
			echo "default via 192.168.1.1 dev eth0 proto dhcp metric 100"
		fi
	FAKE
  chmod +x "$TEST_TMP/bin/ip"
}

# iface, IPv4 CIDR, IPv4 gateway, hex netmask, MAC, IPv6 CIDR (optional,
# non-link-local), IPv6 link-local CIDR
#######################################
# Install macOS route and interface fixtures on any host platform.
# Globals:
#   TEST_TMP (read)
# Arguments:
#   1 - Interface name
#   2 - IPv4 CIDR
#   3 - IPv4 gateway
#   4 - Hex subnet mask
#   5 - MAC address
#   6 - IPv6 CIDR (optional)
#   7 - Link-local IPv6 CIDR (optional, default fe80::50)
# Outputs:
#   Executable fixtures on disk; command errors to stderr.
# Returns:
#   The final chmod status.
#######################################
install_fake_darwin_tools() {
  local iface=$1 ipv4_cidr=$2 gw4=$3 hex_mask=$4 mac=$5 \
    ipv6_cidr=${6:-} ipv6_ll_cidr=${7:-fe80::50}

  cat >"$TEST_TMP/bin/route" <<-FAKE
		#!/usr/bin/env bash
		if [[ "\$*" == "-n get default" ]]; then
			echo "   route to: default"
			echo "destination: default"
			echo "    gateway: $gw4"
			echo "  interface: $iface"
		fi
	FAKE
  chmod +x "$TEST_TMP/bin/route"

  cat >"$TEST_TMP/bin/ipconfig" <<-FAKE
		#!/usr/bin/env bash
		[[ "\$1" == "getifaddr" && "\$2" == "$iface" ]] && echo "${ipv4_cidr%%/*}"
	FAKE
  chmod +x "$TEST_TMP/bin/ipconfig"

  cat >"$TEST_TMP/bin/ifconfig" <<-FAKE
		#!/usr/bin/env bash
		[[ "\$1" != "$iface" ]] && exit 1
		echo "$iface: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500"
		echo "ether $mac"
		echo "inet ${ipv4_cidr%%/*} netmask $hex_mask broadcast 255.255.255.255"
		[[ -n "$ipv6_cidr" ]] && echo "inet6 ${ipv6_cidr%%/*} prefixlen ${ipv6_cidr##*/} scopeid 0x0"
		echo "inet6 $ipv6_ll_cidr%$iface prefixlen 64 scopeid 0x4"
	FAKE
  chmod +x "$TEST_TMP/bin/ifconfig"
}

# lib::net::default_adapter
@test "lib::net::default_adapter resolves the interface from the default route" {
  install_fake_ip eth0 192.168.1.50/24 192.168.1.1

  run lib::net::default_adapter

  assert_success
  assert_output "eth0"
}

@test "lib::net::default_adapter picks the lowest-metric route" {
  install_fake_ip_multi_route

  run lib::net::default_adapter

  assert_success
  assert_output "eth0"
}

@test "lib::net::default_adapter fails cleanly with no default route" {
  cat >"$TEST_TMP/bin/ip" <<-'FAKE'
		#!/usr/bin/env bash
		exit 1
	FAKE
  chmod +x "$TEST_TMP/bin/ip"

  run lib::net::default_adapter

  assert_failure 1
  assert_output --partial "No default network adapter found"
}

@test "lib::net::default_adapter resolves via 'route' on Darwin" {
  fake_uname_darwin
  install_fake_darwin_tools en0 10.0.1.50/24 10.0.1.1 0xffffff00 aa:bb:cc:dd:ee:ff

  run lib::net::default_adapter

  assert_success
  assert_output "en0"
}

# lib::net::ip_address
@test "lib::net::ip_address resolves the IPv4 address" {
  install_fake_ip eth0 192.168.1.50/24 192.168.1.1

  run lib::net::ip_address ipv4 eth0

  assert_success
  assert_output "192.168.1.50"
}

@test "lib::net::ip_address prefers a global IPv6 address over link-local" {
  install_fake_ip eth0 192.168.1.50/24 192.168.1.1 2001:db8::50/64

  run lib::net::ip_address ipv6 eth0

  assert_success
  assert_output "2001:db8::50"
}

@test "lib::net::ip_address falls back to link-local when no global IPv6 address exists" {
  install_fake_ip eth0 192.168.1.50/24 192.168.1.1

  run lib::net::ip_address ipv6 eth0

  assert_success
  assert_output "fe80::50"
}

@test "lib::net::ip_address auto-resolves the adapter when none is given" {
  install_fake_ip eth0 192.168.1.50/24 192.168.1.1

  run lib::net::ip_address ipv4

  assert_success
  assert_output "192.168.1.50"
}

@test "lib::net::ip_address resolves via 'ipconfig'/'ifconfig' on Darwin" {
  fake_uname_darwin
  install_fake_darwin_tools en0 10.0.1.50/24 10.0.1.1 0xffffff00 aa:bb:cc:dd:ee:ff 2001:db8::50/64

  run lib::net::ip_address ipv4 en0

  assert_success
  assert_output "10.0.1.50"
}

@test "lib::net::ip_address strips the zone-id suffix from a Darwin link-local address" {
  fake_uname_darwin
  install_fake_darwin_tools en0 10.0.1.50/24 10.0.1.1 0xffffff00 aa:bb:cc:dd:ee:ff

  run lib::net::ip_address ipv6 en0

  assert_success
  refute_output --partial "%"
}

# lib::net::subnet_mask
@test "lib::net::subnet_mask converts the adapter's CIDR to dotted-decimal" {
  install_fake_ip eth0 192.168.1.50/24 192.168.1.1

  run lib::net::subnet_mask eth0

  assert_success
  assert_output "255.255.255.0"
}

@test "lib::net::subnet_mask converts a Darwin hex netmask to dotted-decimal" {
  fake_uname_darwin
  install_fake_darwin_tools en0 10.0.1.50/20 10.0.1.1 0xfffff000 aa:bb:cc:dd:ee:ff

  run lib::net::subnet_mask en0

  assert_success
  assert_output "255.255.240.0"
}

# lib::net::default_gateway
@test "lib::net::default_gateway resolves the IPv4 gateway" {
  install_fake_ip eth0 192.168.1.50/24 192.168.1.1

  run lib::net::default_gateway ipv4 eth0

  assert_success
  assert_output "192.168.1.1"
}

@test "lib::net::default_gateway resolves the IPv6 gateway" {
  install_fake_ip eth0 192.168.1.50/24 192.168.1.1 "" fe80::50/64 fe80::1

  run lib::net::default_gateway ipv6 eth0

  assert_success
  assert_output "fe80::1"
}

@test "lib::net::default_gateway resolves via 'route' on Darwin" {
  fake_uname_darwin
  install_fake_darwin_tools en0 10.0.1.50/24 10.0.1.1 0xffffff00 aa:bb:cc:dd:ee:ff

  run lib::net::default_gateway ipv4 en0

  assert_success
  assert_output "10.0.1.1"
}

# lib::net::mac_address
@test "lib::net::mac_address resolves via /sys/class/net on Linux" {
  # Genuine ambient-state check, same precedent as test/lib/git.bats
  # testing against the real repo rather than mocking git -- /sys is a
  # kernel-virtual filesystem this test can't redirect, and every Linux
  # CI runner has at least a loopback interface to read. Guarded on the
  # real filesystem, not the faked 'uname' from setup(): /sys genuinely
  # doesn't exist on macOS, no matter what 'uname' claims.
  if [[ ! -d /sys/class/net ]]; then
    skip "/sys/class/net does not exist on this platform"
  fi

  run lib::net::mac_address lo

  assert_success
  assert_output "00:00:00:00:00:00"
}

@test "lib::net::mac_address resolves via 'ifconfig' on Darwin" {
  fake_uname_darwin
  install_fake_darwin_tools en0 10.0.1.50/24 10.0.1.1 0xffffff00 aa:bb:cc:dd:ee:ff

  run lib::net::mac_address en0

  assert_success
  assert_output "aa:bb:cc:dd:ee:ff"
}

# lib::net::dns_servers
@test "lib::net::dns_servers reads /etc/resolv.conf" {
  # Genuine ambient-state check -- /etc/resolv.conf isn't adapter-scoped
  # or parameterized by this function, so there's nothing to mock; every
  # CI runner has at least one nameserver configured.
  run lib::net::dns_servers

  assert_success
  [[ -n $output ]]
}

# --- Prefix / broadcast / multicast (pure arithmetic, mocked adapter) ----

@test "lib::net::network_prefix computes the IPv4 network address" {
  install_fake_ip eth0 192.168.1.50/24 192.168.1.1

  run lib::net::network_prefix ipv4 eth0

  assert_success
  assert_output "192.168.1.0"
}

@test "lib::net::network_prefix computes the IPv4 network address for a non-octet-aligned mask" {
  install_fake_ip eth0 172.26.175.147/20 172.26.160.1

  run lib::net::network_prefix ipv4 eth0

  assert_success
  assert_output "172.26.160.0"
}

@test "lib::net::network_prefix computes the IPv6 network prefix" {
  install_fake_ip eth0 192.168.1.50/24 192.168.1.1 2001:db8:abcd:1234::1/64

  run lib::net::network_prefix ipv6 eth0

  assert_success
  assert_output "2001:db8:abcd:1234::"
}

@test "lib::net::network_prefix_cidr appends the CIDR suffix" {
  install_fake_ip eth0 192.168.1.50/24 192.168.1.1

  run lib::net::network_prefix_cidr ipv4 eth0

  assert_success
  assert_output "192.168.1.0/24"
}

@test "lib::net::network_prefix_cidr works for IPv6" {
  install_fake_ip eth0 192.168.1.50/24 192.168.1.1 2001:db8:abcd:1234::1/64

  run lib::net::network_prefix_cidr ipv6 eth0

  assert_success
  assert_output "2001:db8:abcd:1234::/64"
}

@test "lib::net::broadcast_address computes the IPv4 broadcast address" {
  install_fake_ip eth0 192.168.1.50/24 192.168.1.1

  run lib::net::broadcast_address eth0

  assert_success
  assert_output "192.168.1.255"
}

@test "lib::net::broadcast_address computes the broadcast address for a non-octet-aligned mask" {
  install_fake_ip eth0 172.26.175.147/20 172.26.160.1

  run lib::net::broadcast_address eth0

  assert_success
  assert_output "172.26.175.255"
}

@test "lib::net::multicast_address computes the RFC 4291 solicited-node address" {
  install_fake_ip eth0 192.168.1.50/24 192.168.1.1 "" fe80::215:5dff:fea7:c0f1/64

  run lib::net::multicast_address eth0

  assert_success
  assert_output "ff02::1:ffa7:c0f1"
}

# --- ipv4_validate / ipv6_validate (pure validation, table-driven) --------------------

@test "lib::net::ipv4_validate accepts valid addresses" {
  for addr in "192.168.1.1" "0.0.0.0" "255.255.255.255" "1.2.3.4" "10.0.0.1"; do
    run lib::net::ipv4_validate "$addr"
    assert_success
  done
}

@test "lib::net::ipv4_validate rejects invalid addresses" {
  for addr in "256.1.1.1" "1.1.1" "1.1.1.1.1" "01.1.1.1" "1.2.3.4." ".1.2.3.4" \
    "1.2.3.abc" "" "1..2.3" "-1.2.3.4" "1.2.3.4 "; do
    run lib::net::ipv4_validate "$addr"
    assert_failure
  done
}

@test "lib::net::ipv6_validate accepts valid addresses" {
  for addr in "2001:db8::1" "::1" "::" "fe80::1234:5678:9abc:def0" \
    "1:2:3:4:5:6:7:8" "::ffff:192.168.1.1" "2001:db8:0:0:0:0:0:1"; do
    run lib::net::ipv6_validate "$addr"
    assert_success
  done
}

@test "lib::net::ipv6_validate rejects invalid addresses" {
  for addr in "1:2:3:4:5:6:7:8:9" "2001:db8:::1" "2001:db8::1::2" "gggg::1" \
    "12345::1" "::ffff:999.168.1.1" "" "1:2:3:4:5:6:7" "fe80::1%eth0"; do
    run lib::net::ipv6_validate "$addr"
    assert_failure
  done
}

@test "IP validators reject overflow trailing lines and malformed IPv4 tails" {
  local address
  for address in '18446744073709551617.2.3.4' $'1.2.3.4\nextra' $'1.2.3.4\n' \
    '1:2:3:4:5:6:7:192.0.2.1' '1:2:3:4:5:6::192.0.2.1' $'::1\nextra' ':::'; do
    run lib::net::ip_validate "$address"
    assert_failure 1
    assert_output ''
  done

  for address in '1:2:3:4:5:6:192.0.2.1' '::192.0.2.1' '::' '192.0.2.1'; do
    run lib::net::ip_validate "$address"
    assert_success
    assert_output ''
  done
}

@test "validators have consistent argument and service port rules under strict mode" {
  local fn port
  for fn in ipv4_validate ipv6_validate ip_validate port_validate uri_validate dsn_validate; do
    run "lib::net::$fn"
    assert_failure 2
    run "lib::net::$fn" one two
    assert_failure 2
  done
  for port in 1 65535 00080; do
    run lib::net::port_validate "$port"
    assert_success
  done
  for port in 0 0000 65536 -1 +80 1.0 '' '1+2' 18446744073709551617; do
    run lib::net::port_validate "$port"
    assert_failure 1
    assert_output ''
  done

  run bash -c '
    source "$1/lib/lib.sh"
    set -euo pipefail
    lib::net::ipv6_validate ::
    lib::net::ipv6_validate ::ffff:192.0.2.1
    lib::net::ip_validate 192.0.2.1
    lib::net::port_validate 00080
  ' _ "$REPO_ROOT"
  assert_success
}

@test "URI parsing preserves encoded components and IPv6 host text" {
  local uri='Postgres://user%40name:p%3Ass@[2001:db8::1]:005432/db%2Fname?k=a%26b#part%20one'
  local component
  local -A expected=(
    [scheme]=Postgres [authority]='user%40name:p%3Ass@[2001:db8::1]:005432'
    [userinfo]='user%40name:p%3Ass' [username]='user%40name' [password]='p%3Ass'
    [host]='2001:db8::1' [port]=005432 [path]='/db%2Fname' [query]='k=a%26b' [fragment]='part%20one'
  )
  for component in scheme authority userinfo username password host port path query fragment; do
    run lib::net::uri_parse "$uri" "$component"
    assert_success
    assert_output "${expected[$component]}"
  done
}

@test "URI validation supports opaque and empty components without imposing service grammar" {
  local uri
  for uri in 'urn:example:animal:ferret:nose' 'mailto:user@example.com' 'file:///tmp/a' \
    'scheme:' 'https://host:/' 'https://host:999999/' 'custom://encoded%2Ehost/a?x=?/#'; do
    run lib::net::uri_validate "$uri"
    assert_success
    assert_output ''
  done
  run lib::net::uri_parse 'file:///tmp/a' host
  assert_success
  assert_output ''
  run lib::net::uri_parse 'urn:example:animal' path
  assert_output 'example:animal'
  run lib::net::uri_parse 'https://host' missing
  assert_failure 2
}

@test "URI validation rejects illegal bytes malformed authorities and escapes" {
  local uri
  for uri in '/relative' '//host/path' '1scheme:foo' 'https://a b/' 'https://host/%2' \
    'https://host/%xz' 'https://host/a#b#c' 'https://host/"' "https://host/\\" \
    'https://user@other@host/' 'https://[::1]extra/' 'https://::1/' \
    'https://[v1.test]/' 'https://[fe80::1%25eth0]/' $'https://host/\n' 'https://host/é'; do
    run lib::net::uri_validate "$uri"
    assert_failure 1
    assert_output ''
  done
}

@test "DSN parser requires a single service host and preserves absent defaults" {
  local dsn
  for dsn in 'mysql://user:p%40ss@db.example:3306/db' 'redis://[::1]/0' 'amqp://host' \
    'postgresql://host:0005432/database?sslmode=require'; do
    run lib::net::dsn_validate "$dsn"
    assert_success
  done
  run lib::net::dsn_parse 'redis://host/0' port
  assert_success
  assert_output ''
  run lib::net::dsn_parse 'mysql://user:p%40ss@host/db' password
  assert_output 'p%40ss'

  for dsn in 'host=localhost dbname=test' 'mysql:host=localhost' 'postgres://one,two/db' \
    'redis:///socket' 'redis://host:0' 'redis://host:' 'redis://host:65536' \
    'redis://host/db#fragment' 'redis://256.1.1.1' 'redis://host%2Eexample'; do
    run lib::net::dsn_validate "$dsn"
    assert_failure 1
  done
}

@test "URI parsing preserves caller state and keeps secrets out of diagnostics" {
  run bash -c '
    source "$1/lib/lib.sh"
    set -euo pipefail
    uri="mysql://user:private-value@host:3306/db"
    before=$(set +o; declare -p uri; pwd; umask)
    [[ $(lib::net::dsn_parse "$uri" host) == host ]]
    lib::net::uri_validate "$uri"
    after=$(set +o; declare -p uri; pwd; umask)
    [[ $before == "$after" ]]
  ' _ "$REPO_ROOT"
  assert_success
  run lib::net::uri_parse 'mysql://user:private-value@host/%bad%' host
  assert_failure 1
  [[ $output != *private-value* ]]
}

@test "DNS lookup prefers getent and deduplicates address records" {
  # shellcheck disable=SC2329 # called by dns_lookup
  getent() {
    [[ $1 == ahosts && $2 == db.example ]] || return 9
    printf '%s\n' '192.0.2.1 STREAM db.example' '192.0.2.1 DGRAM' '192.0.2.1 RAW' '2001:db8::1 STREAM'
  }
  run lib::net::dns_lookup db.example
  assert_success
  assert_output $'192.0.2.1\n2001:db8::1'
}

@test "DNS fallback excludes the resolver server address from nslookup output" {
  # shellcheck disable=SC2329 # availability fixture
  command() {
    [[ $1 != -v || $2 != getent ]] || return 1
    builtin command "$@"
  }
  # shellcheck disable=SC2329 # called by dns_lookup
  nslookup() {
    printf '%s\n' 'Server: 192.0.2.53' 'Address: 192.0.2.53#53' '' \
      'Non-authoritative answer:' 'Name: db.example' 'Address: 192.0.2.1' \
      'Name: db.example' 'Address: 2001:db8::1'
  }
  run lib::net::dns_lookup db.example
  assert_success
  assert_output $'192.0.2.1\n2001:db8::1'
}

@test "DNS lookup reports missing tools failed resolution and empty results" {
  # shellcheck disable=SC2329 # called by dns_lookup
  getent() {
    printf 'partial output\n'
    return 2
  }
  run lib::net::dns_lookup missing.example
  assert_failure 1
  [[ $output != *partial* ]]

  # shellcheck disable=SC2329
  getent() { printf 'not-an-address STREAM\n'; }
  run lib::net::dns_lookup missing.example
  assert_failure 1
  run lib::net::dns_lookup --help
  assert_failure 2
  run lib::net::dns_lookup
  assert_failure 2

  # shellcheck disable=SC2329 # availability fixture
  command() {
    [[ $1 != -v || ($2 != getent && $2 != nslookup) ]] || return 1
    builtin command "$@"
  }
  run lib::net::dns_lookup db.example
  assert_failure 1
}

@test "HTTP probe uses bounded verified GET defaults and hides URL from curl arguments" {
  # shellcheck disable=SC2329 # called by http_probe
  curl() {
    [[ $1 == --disable ]] || return 9
    [[ " $* " == *' --max-time 10 '* && " $* " == *' --connect-timeout 10 '* ]] || return 9
    [[ " $* " != *' --location '* && " $* " != *' --insecure '* && " $* " != *' --head '* ]] || return 9
    [[ " $* " != *private-value* && " $* " == *' --config - '* ]] || return 9
    local config
    IFS= read -r config
    [[ $config == 'url = "https://user:private-value@host/path"' ]] || return 9
    printf 204
  }
  run lib::net::http_probe 'https://user:private-value@host/path'
  assert_success
  assert_output 204
}

@test "HTTP probe supports redirect flags and a total timeout without HTTPS downgrade" {
  # shellcheck disable=SC2329 # called by http_probe
  curl() {
    [[ " $* " == *' --location '* && " $* " == *' --max-redirs 5 '* ]] || return 9
    [[ " $* " == *' --max-time 7 '* && " $* " == *' --proto-redir =https '* ]] || return 9
    printf 200
  }
  local flag
  for flag in -f --follow-redirects; do
    run lib::net::http_probe https://host --timeout 7 "$flag"
    assert_success
    assert_output 200
  done
}

@test "HTTP rejection transport errors and invalid invocations are distinguishable" {
  # shellcheck disable=SC2329 # called by http_probe
  curl() { printf 404; }
  run lib::net::http_probe https://host
  assert_failure 1
  assert_output 404

  # shellcheck disable=SC2329
  curl() { printf 302; }
  run lib::net::http_probe https://host
  assert_failure 1
  assert_output 302

  # shellcheck disable=SC2329
  curl() {
    printf 200
    printf 'private-value' >&2
    return 28
  }
  run lib::net::http_probe https://host
  assert_failure 3
  [[ $output != *200* && $output != *private-value* ]]

  run lib::net::http_probe https://host --timeout 0
  assert_failure 2
  run lib::net::http_probe ftp://host
  assert_failure 2
  run lib::net::http_probe $'https://host/\nurl = "file:///etc/passwd"'
  assert_failure 2
  run lib::net::http_probe https://host --unknown
  assert_failure 2
}

@test "HTTP probe preserves caller parser arrays and strict shell settings" {
  run bash -c '
    source "$1/lib/lib.sh"
    set -euo pipefail
    curl() { printf 200; }
    declare -a OPTS=(caller)
    declare -A OPTS_HELP=([caller]=help) OPTS_VALUES=([caller]=value)
    before=$(set +o; declare -p OPTS OPTS_HELP OPTS_VALUES; pwd; umask)
    lib::net::http_probe https://host
    after=$(set +o; declare -p OPTS OPTS_HELP OPTS_VALUES; pwd; umask)
    [[ $before == "$after" ]]
  ' _ "$REPO_ROOT"
  assert_success
  assert_output 200
}

@test "HTTP probe allows URL fragments and distinguishes missing tools or malformed responses" {
  # shellcheck disable=SC2329 # called by http_probe
  curl() { printf 200; }
  run lib::net::http_probe 'http://host/path#fragment'
  assert_success
  assert_output 200

  # shellcheck disable=SC2329
  curl() { printf 000; }
  run lib::net::http_probe http://host
  assert_failure 3
  [[ $output != *000* ]]

  # shellcheck disable=SC2329 # availability fixture
  command() {
    [[ $1 != -v || $2 != curl ]] || return 1
    builtin command "$@"
  }
  run lib::net::http_probe http://host
  assert_failure 3
}
