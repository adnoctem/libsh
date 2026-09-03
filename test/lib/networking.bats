#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/log.sh"
	source "$REPO_ROOT/lib/networking.sh"

	TEST_TMP=$(mktemp -d)
	ORIGINAL_PATH="$PATH"
	mkdir -p "$TEST_TMP/bin"
	export PATH="$TEST_TMP/bin:$PATH"
}

teardown() {
	export PATH="$ORIGINAL_PATH"
	[[ -n ${TEST_TMP:-} ]] && rm -rf "$TEST_TMP"
}

# Install a fake 'nc' that fails 'fail_times' calls before succeeding, so
# tests exercise the retry loop without depending on real network state. Every
# invocation's arguments are appended to nc-args.log, so callers of
# lib::networking::tcp_dsn_probe can assert the host/port it actually resolved.
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
# lib::networking::tcp_dsn_probe uses, for a fixed host/port.
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

# lib::networking::tcp_probe
@test "lib::networking::tcp_probe succeeds immediately when the port is open" {
	install_fake_nc 0

	run lib::networking::tcp_probe 127.0.0.1 1234

	assert_success
	assert_output --partial "127.0.0.1:1234 connection established"
}

@test "lib::networking::tcp_probe retries until the port opens" {
	install_fake_nc 2

	run lib::networking::tcp_probe 127.0.0.1 1234 "" 5 1

	assert_success
	assert_output --partial "connection established"
}

@test "lib::networking::tcp_probe exits 1 after exhausting its retry budget" {
	install_fake_nc 999

	run lib::networking::tcp_probe 127.0.0.1 1234 "" 2 1

	assert_failure 1
	assert_output --partial "FATAL: could not reach 127.0.0.1:1234"
}

@test "lib::networking::tcp_probe uses the given label in output" {
	install_fake_nc 0

	run lib::networking::tcp_probe 127.0.0.1 1234 "database"

	assert_output --partial "Checking for an active database connection"
}

# lib::networking::tcp_dsn_probe
@test "lib::networking::tcp_dsn_probe fails cleanly without trurl on PATH" {
	PATH="$TEST_TMP/bin" run lib::networking::tcp_dsn_probe "mysql://user:pass@127.0.0.1:3306/db" 3306

	assert_failure 1
	assert_output --partial "requires 'trurl'"
}

# tcp_dsn_probe's default label is just the parsed host (see
# lib::networking::tcp_probe's own default label, which never kicks in since
# tcp_dsn_probe always passes one explicitly) -- the port isn't visible in
# that message, so these assert the port trurl resolved via the fake nc's
# argument log instead.
@test "lib::networking::tcp_dsn_probe parses host and port with trurl" {
	install_fake_trurl "127.0.0.1" "3306"
	install_fake_nc 0

	run lib::networking::tcp_dsn_probe "mysql://user:pass@127.0.0.1:3306/db" 5432

	assert_success
	assert_output --partial "127.0.0.1 connection established"
	assert_equal "$(cat "$TEST_TMP/nc-args.log")" "-z -w5 127.0.0.1 3306"
}

@test "lib::networking::tcp_dsn_probe falls back to the default port" {
	install_fake_trurl "127.0.0.1" ""
	install_fake_nc 0

	run lib::networking::tcp_dsn_probe "mysql://127.0.0.1/db" 3306

	assert_success
	assert_output --partial "127.0.0.1 connection established"
	assert_equal "$(cat "$TEST_TMP/nc-args.log")" "-z -w5 127.0.0.1 3306"
}

@test "lib::networking::tcp_dsn_probe uses the host as the default label" {
	install_fake_trurl "db.internal" "5432"
	install_fake_nc 0

	run lib::networking::tcp_dsn_probe "postgres://db.internal:5432/app" 5432

	assert_output --partial "Checking for an active db.internal connection"
}

# --- Adapter resolution / address lookup mocks ---------------------------
# Fake 'ip' (Linux) and 'route'/'ifconfig'/'ipconfig' (Darwin, paired with
# fake_uname_darwin from paths.bats's precedent) covering exactly the
# invocations lib/networking.sh's OS-resolution functions make -- confirmed
# via grep against the real implementation, not guessed.

fake_uname_darwin() {
	cat >"$TEST_TMP/bin/uname" <<-'FAKE'
		#!/usr/bin/env bash
		echo "Darwin"
	FAKE
	chmod +x "$TEST_TMP/bin/uname"
}

# iface, ipv4 CIDR, IPv4 gateway, IPv6 global CIDR (optional), IPv6
# link-local CIDR, IPv6 gateway (optional)
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

# lib::networking::default_adapter
@test "lib::networking::default_adapter resolves the interface from the default route" {
	install_fake_ip eth0 192.168.1.50/24 192.168.1.1

	run lib::networking::default_adapter

	assert_success
	assert_output "eth0"
}

@test "lib::networking::default_adapter picks the lowest-metric route" {
	install_fake_ip_multi_route

	run lib::networking::default_adapter

	assert_success
	assert_output "eth0"
}

@test "lib::networking::default_adapter fails cleanly with no default route" {
	cat >"$TEST_TMP/bin/ip" <<-'FAKE'
		#!/usr/bin/env bash
		exit 1
	FAKE
	chmod +x "$TEST_TMP/bin/ip"

	run lib::networking::default_adapter

	assert_failure 1
	assert_output --partial "No default network adapter found"
}

@test "lib::networking::default_adapter resolves via 'route' on Darwin" {
	fake_uname_darwin
	install_fake_darwin_tools en0 10.0.1.50/24 10.0.1.1 0xffffff00 aa:bb:cc:dd:ee:ff

	run lib::networking::default_adapter

	assert_success
	assert_output "en0"
}

# lib::networking::ip_address
@test "lib::networking::ip_address resolves the IPv4 address" {
	install_fake_ip eth0 192.168.1.50/24 192.168.1.1

	run lib::networking::ip_address ipv4 eth0

	assert_success
	assert_output "192.168.1.50"
}

@test "lib::networking::ip_address prefers a global IPv6 address over link-local" {
	install_fake_ip eth0 192.168.1.50/24 192.168.1.1 2001:db8::50/64

	run lib::networking::ip_address ipv6 eth0

	assert_success
	assert_output "2001:db8::50"
}

@test "lib::networking::ip_address falls back to link-local when no global IPv6 address exists" {
	install_fake_ip eth0 192.168.1.50/24 192.168.1.1

	run lib::networking::ip_address ipv6 eth0

	assert_success
	assert_output "fe80::50"
}

@test "lib::networking::ip_address auto-resolves the adapter when none is given" {
	install_fake_ip eth0 192.168.1.50/24 192.168.1.1

	run lib::networking::ip_address ipv4

	assert_success
	assert_output "192.168.1.50"
}

@test "lib::networking::ip_address resolves via 'ipconfig'/'ifconfig' on Darwin" {
	fake_uname_darwin
	install_fake_darwin_tools en0 10.0.1.50/24 10.0.1.1 0xffffff00 aa:bb:cc:dd:ee:ff 2001:db8::50/64

	run lib::networking::ip_address ipv4 en0

	assert_success
	assert_output "10.0.1.50"
}

@test "lib::networking::ip_address strips the zone-id suffix from a Darwin link-local address" {
	fake_uname_darwin
	install_fake_darwin_tools en0 10.0.1.50/24 10.0.1.1 0xffffff00 aa:bb:cc:dd:ee:ff

	run lib::networking::ip_address ipv6 en0

	assert_success
	refute_output --partial "%"
}

# lib::networking::subnet_mask
@test "lib::networking::subnet_mask converts the adapter's CIDR to dotted-decimal" {
	install_fake_ip eth0 192.168.1.50/24 192.168.1.1

	run lib::networking::subnet_mask eth0

	assert_success
	assert_output "255.255.255.0"
}

@test "lib::networking::subnet_mask converts a Darwin hex netmask to dotted-decimal" {
	fake_uname_darwin
	install_fake_darwin_tools en0 10.0.1.50/20 10.0.1.1 0xfffff000 aa:bb:cc:dd:ee:ff

	run lib::networking::subnet_mask en0

	assert_success
	assert_output "255.255.240.0"
}

# lib::networking::default_gateway
@test "lib::networking::default_gateway resolves the IPv4 gateway" {
	install_fake_ip eth0 192.168.1.50/24 192.168.1.1

	run lib::networking::default_gateway ipv4 eth0

	assert_success
	assert_output "192.168.1.1"
}

@test "lib::networking::default_gateway resolves the IPv6 gateway" {
	install_fake_ip eth0 192.168.1.50/24 192.168.1.1 "" fe80::50/64 fe80::1

	run lib::networking::default_gateway ipv6 eth0

	assert_success
	assert_output "fe80::1"
}

@test "lib::networking::default_gateway resolves via 'route' on Darwin" {
	fake_uname_darwin
	install_fake_darwin_tools en0 10.0.1.50/24 10.0.1.1 0xffffff00 aa:bb:cc:dd:ee:ff

	run lib::networking::default_gateway ipv4 en0

	assert_success
	assert_output "10.0.1.1"
}

# lib::networking::mac_address
@test "lib::networking::mac_address resolves via /sys/class/net on Linux" {
	# Genuine ambient-state check, same precedent as test/lib/git.bats
	# testing against the real repo rather than mocking git -- /sys is a
	# kernel-virtual filesystem this test can't redirect, and every Linux
	# CI runner has at least a loopback interface to read.
	run lib::networking::mac_address lo

	assert_success
	assert_output "00:00:00:00:00:00"
}

@test "lib::networking::mac_address resolves via 'ifconfig' on Darwin" {
	fake_uname_darwin
	install_fake_darwin_tools en0 10.0.1.50/24 10.0.1.1 0xffffff00 aa:bb:cc:dd:ee:ff

	run lib::networking::mac_address en0

	assert_success
	assert_output "aa:bb:cc:dd:ee:ff"
}

# lib::networking::dns_servers
@test "lib::networking::dns_servers reads /etc/resolv.conf" {
	# Genuine ambient-state check -- /etc/resolv.conf isn't adapter-scoped
	# or parameterized by this function, so there's nothing to mock; every
	# CI runner has at least one nameserver configured.
	run lib::networking::dns_servers

	assert_success
	[[ -n $output ]]
}

# --- Prefix / broadcast / multicast (pure arithmetic, mocked adapter) ----

@test "lib::networking::network_prefix computes the IPv4 network address" {
	install_fake_ip eth0 192.168.1.50/24 192.168.1.1

	run lib::networking::network_prefix ipv4 eth0

	assert_success
	assert_output "192.168.1.0"
}

@test "lib::networking::network_prefix computes the IPv4 network address for a non-octet-aligned mask" {
	install_fake_ip eth0 172.26.175.147/20 172.26.160.1

	run lib::networking::network_prefix ipv4 eth0

	assert_success
	assert_output "172.26.160.0"
}

@test "lib::networking::network_prefix computes the IPv6 network prefix" {
	install_fake_ip eth0 192.168.1.50/24 192.168.1.1 2001:db8:abcd:1234::1/64

	run lib::networking::network_prefix ipv6 eth0

	assert_success
	assert_output "2001:db8:abcd:1234::"
}

@test "lib::networking::network_prefix_cidr appends the CIDR suffix" {
	install_fake_ip eth0 192.168.1.50/24 192.168.1.1

	run lib::networking::network_prefix_cidr ipv4 eth0

	assert_success
	assert_output "192.168.1.0/24"
}

@test "lib::networking::network_prefix_cidr works for IPv6" {
	install_fake_ip eth0 192.168.1.50/24 192.168.1.1 2001:db8:abcd:1234::1/64

	run lib::networking::network_prefix_cidr ipv6 eth0

	assert_success
	assert_output "2001:db8:abcd:1234::/64"
}

@test "lib::networking::broadcast_address computes the IPv4 broadcast address" {
	install_fake_ip eth0 192.168.1.50/24 192.168.1.1

	run lib::networking::broadcast_address eth0

	assert_success
	assert_output "192.168.1.255"
}

@test "lib::networking::broadcast_address computes the broadcast address for a non-octet-aligned mask" {
	install_fake_ip eth0 172.26.175.147/20 172.26.160.1

	run lib::networking::broadcast_address eth0

	assert_success
	assert_output "172.26.175.255"
}

@test "lib::networking::multicast_address computes the RFC 4291 solicited-node address" {
	install_fake_ip eth0 192.168.1.50/24 192.168.1.1 "" fe80::215:5dff:fea7:c0f1/64

	run lib::networking::multicast_address eth0

	assert_success
	assert_output "ff02::1:ffa7:c0f1"
}

# --- is_ipv4 / is_ipv6 (pure validation, table-driven) --------------------

@test "lib::networking::is_ipv4 accepts valid addresses" {
	for addr in "192.168.1.1" "0.0.0.0" "255.255.255.255" "1.2.3.4" "10.0.0.1"; do
		run lib::networking::is_ipv4 "$addr"
		assert_success
	done
}

@test "lib::networking::is_ipv4 rejects invalid addresses" {
	for addr in "256.1.1.1" "1.1.1" "1.1.1.1.1" "01.1.1.1" "1.2.3.4." ".1.2.3.4" \
		"1.2.3.abc" "" "1..2.3" "-1.2.3.4" "1.2.3.4 "; do
		run lib::networking::is_ipv4 "$addr"
		assert_failure
	done
}

@test "lib::networking::is_ipv6 accepts valid addresses" {
	for addr in "2001:db8::1" "::1" "::" "fe80::1234:5678:9abc:def0" \
		"1:2:3:4:5:6:7:8" "::ffff:192.168.1.1" "2001:db8:0:0:0:0:0:1"; do
		run lib::networking::is_ipv6 "$addr"
		assert_success
	done
}

@test "lib::networking::is_ipv6 rejects invalid addresses" {
	for addr in "1:2:3:4:5:6:7:8:9" "2001:db8:::1" "2001:db8::1::2" "gggg::1" \
		"12345::1" "::ffff:999.168.1.1" "" "1:2:3:4:5:6:7" "fe80::1%eth0"; do
		run lib::networking::is_ipv6 "$addr"
		assert_failure
	done
}
