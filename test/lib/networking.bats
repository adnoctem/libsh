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
# lib::networking::tcp_dsn can assert the host/port it actually resolved.
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
# lib::networking::tcp_dsn uses, for a fixed host/port.
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

# lib::networking::tcp
@test "lib::networking::tcp succeeds immediately when the port is open" {
	install_fake_nc 0

	run lib::networking::tcp 127.0.0.1 1234

	assert_success
	assert_output --partial "127.0.0.1:1234 connection established"
}

@test "lib::networking::tcp retries until the port opens" {
	install_fake_nc 2

	run lib::networking::tcp 127.0.0.1 1234 "" 5 1

	assert_success
	assert_output --partial "connection established"
}

@test "lib::networking::tcp exits 1 after exhausting its retry budget" {
	install_fake_nc 999

	run lib::networking::tcp 127.0.0.1 1234 "" 2 1

	assert_failure 1
	assert_output --partial "FATAL: could not reach 127.0.0.1:1234"
}

@test "lib::networking::tcp uses the given label in output" {
	install_fake_nc 0

	run lib::networking::tcp 127.0.0.1 1234 "database"

	assert_output --partial "Checking for an active database connection"
}

# lib::networking::tcp_dsn
@test "lib::networking::tcp_dsn fails cleanly without trurl on PATH" {
	PATH="$TEST_TMP/bin" run lib::networking::tcp_dsn "mysql://user:pass@127.0.0.1:3306/db" 3306

	assert_failure 1
	assert_output --partial "requires 'trurl'"
}

# tcp_dsn's default label is just the parsed host (see lib::networking::tcp's
# own default label, which never kicks in since tcp_dsn always passes one
# explicitly) -- the port isn't visible in that message, so these assert the
# port trurl resolved via the fake nc's argument log instead.
@test "lib::networking::tcp_dsn parses host and port with trurl" {
	install_fake_trurl "127.0.0.1" "3306"
	install_fake_nc 0

	run lib::networking::tcp_dsn "mysql://user:pass@127.0.0.1:3306/db" 5432

	assert_success
	assert_output --partial "127.0.0.1 connection established"
	assert_equal "$(cat "$TEST_TMP/nc-args.log")" "-z -w5 127.0.0.1 3306"
}

@test "lib::networking::tcp_dsn falls back to the default port" {
	install_fake_trurl "127.0.0.1" ""
	install_fake_nc 0

	run lib::networking::tcp_dsn "mysql://127.0.0.1/db" 3306

	assert_success
	assert_output --partial "127.0.0.1 connection established"
	assert_equal "$(cat "$TEST_TMP/nc-args.log")" "-z -w5 127.0.0.1 3306"
}

@test "lib::networking::tcp_dsn uses the host as the default label" {
	install_fake_trurl "db.internal" "5432"
	install_fake_nc 0

	run lib::networking::tcp_dsn "postgres://db.internal:5432/app" 5432

	assert_output --partial "Checking for an active db.internal connection"
}
