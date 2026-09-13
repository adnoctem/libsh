#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/lib.sh"
	lib::load_extensions apt

	# A representative 'apt-get -s upgrade' run: one security-only package,
	# one updates-only package, and one listing both origins.
	SIMULATION='Reading package lists...
Building dependency tree...
Inst libssl3 [3.0.13-0ubuntu3.4] (3.0.14-0ubuntu3.5 Ubuntu:24.04/noble-security [amd64])
Inst vim [9.1.0-1] (9.1.1-1 Ubuntu:24.04/noble-updates [amd64])
Inst libc6 [2.39-0ubuntu8.3] (2.39-0ubuntu8.4 Ubuntu:24.04/noble-updates, Ubuntu:24.04/noble-security [amd64])
Conf libssl3 (3.0.14-0ubuntu3.5 Ubuntu:24.04/noble-security [amd64])
3 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.'
}

# ext::apt::pending_packages
@test "ext::apt::pending_packages lists every Inst line, and only those" {
	result=$(printf '%s\n' "$SIMULATION" | ext::apt::pending_packages)

	assert_equal "$result" "libssl3
vim
libc6"
}

@test "ext::apt::pending_packages is empty when nothing is pending" {
	result=$(printf '0 upgraded, 0 newly installed, 0 to remove and 0 not upgraded.\n' | ext::apt::pending_packages)

	assert_equal "$result" ""
}

# ext::apt::security_packages
@test "ext::apt::security_packages picks the security-pocket packages" {
	result=$(printf '%s\n' "$SIMULATION" | ext::apt::security_packages)

	assert_equal "$result" "libssl3
libc6"
}

# A package upgraded from -updates is not a security fix; counting it as one
# would make the security-only upgrade path do more than it claims.
@test "ext::apt::security_packages excludes updates-only packages" {
	result=$(printf '%s\n' "$SIMULATION" | ext::apt::security_packages)

	refute [ "$(printf '%s\n' "$result" | grep -c '^vim$')" -gt 0 ]
}

# 'Conf' lines repeat the origin, so matching on the pocket alone rather
# than on 'Inst' would double-count every security package.
@test "ext::apt::security_packages ignores Conf lines" {
	result=$(printf '%s\n' "$SIMULATION" | ext::apt::security_packages | grep -c '^libssl3$')

	assert_equal "$result" "1"
}

# ext::apt::summary_line
@test "ext::apt::summary_line returns apt's own count line" {
	result=$(printf '%s\n' "$SIMULATION" | ext::apt::summary_line)

	assert_equal "$result" "3 upgraded, 0 newly installed, 0 to remove and 0 not upgraded."
}

# ext::apt::is_installed
@test "ext::apt::is_installed succeeds for an installed package" {
	if ! command -v dpkg-query >/dev/null; then
		skip "dpkg-query is needed; this module is Debian/APT-specific"
	fi

	run ext::apt::is_installed bash

	assert_success
}

@test "ext::apt::is_installed fails for a package that is not installed" {
	run ext::apt::is_installed definitely-not-a-real-package

	assert_failure
}
