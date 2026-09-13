#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/lib.sh"
	lib::load_extensions shell

	TEST_TMP=$(mktemp -d)

	# Every test points HISTFILE at a scratch file: none of this may ever
	# touch the real shell history.
	export HISTFILE="$TEST_TMP/history"
	printf '%s\n' \
		'ls -la' \
		'./scripts/mysql-backup.sh -u root --password sup3rs3cr3tvalue -H db' \
		'git status' \
		'echo unrelated' >"$HISTFILE"
}

teardown() {
	[[ -n ${TEST_TMP:-} ]] && rm -rf "$TEST_TMP"
}

# ext::shell::history_file
@test "ext::shell::history_file honours HISTFILE when it is set" {
	run ext::shell::history_file

	assert_output "$HISTFILE"
}

@test "ext::shell::history_file falls back to the zsh history file" {
	HISTFILE="" SHELL=/usr/bin/zsh HOME=/home/example run ext::shell::history_file

	assert_output "/home/example/.zsh_history"
}

@test "ext::shell::history_file falls back to the bash history file" {
	HISTFILE="" SHELL=/bin/bash HOME=/home/example run ext::shell::history_file

	assert_output "/home/example/.bash_history"
}

# ext::shell::history_scrub
@test "ext::shell::history_scrub removes the lines holding the secret" {
	ext::shell::history_scrub "sup3rs3cr3tvalue" >/dev/null

	refute grep -q "sup3rs3cr3tvalue" "$HISTFILE"
	assert_equal "$(grep -c . "$HISTFILE")" "3"
}

@test "ext::shell::history_scrub leaves unrelated lines untouched" {
	ext::shell::history_scrub "sup3rs3cr3tvalue" >/dev/null

	assert_equal "$(cat "$HISTFILE")" 'ls -la
git status
echo unrelated'
}

@test "ext::shell::history_scrub reports how many lines it removed" {
	run ext::shell::history_scrub "sup3rs3cr3tvalue"

	assert_output --partial "Removed 1 line(s)"
}

@test "ext::shell::history_scrub warns that the in-memory history is out of reach" {
	run ext::shell::history_scrub "sup3rs3cr3tvalue"

	assert_output --partial "out of reach"
}

# An empty secret must not rewrite the file: a caller whose password came
# from MYSQL_PWD has nothing in argv to scrub.
@test "ext::shell::history_scrub is a no-op for an empty secret" {
	local before
	before=$(cat "$HISTFILE")

	run ext::shell::history_scrub ""

	assert_success
	assert_equal "$(cat "$HISTFILE")" "$before"
}

@test "ext::shell::history_scrub warns when the secret is short enough to over-match" {
	run ext::shell::history_scrub "abc"

	assert_output --partial "Secret is short"
}

@test "ext::shell::history_scrub succeeds when there is no history file" {
	rm -f "$HISTFILE"

	run ext::shell::history_scrub "sup3rs3cr3tvalue"

	assert_success
	assert_output --partial "nothing to scrub"
}

@test "ext::shell::history_scrub leaves the rewritten file mode 600" {
	chmod 644 "$HISTFILE"

	ext::shell::history_scrub "sup3rs3cr3tvalue" >/dev/null

	# '-c' is GNU-only; '-f' with a BSD-style format is the macOS/BSD stat
	# equivalent.
	mode=$(stat -c '%a' "$HISTFILE" 2>/dev/null || stat -f '%Lp' "$HISTFILE" 2>/dev/null)
	assert_equal "$mode" "600"
}

@test "ext::shell::history_scrub leaves no temporary files behind" {
	ext::shell::history_scrub "sup3rs3cr3tvalue" >/dev/null

	# The arithmetic context strips the leading whitespace BSD/macOS 'wc'
	# pads its count with, which a bare command substitution would not.
	local count=$(($(find "$TEST_TMP" -name 'history.libsh.*' | wc -l)))
	assert_equal "$count" "0"
}
