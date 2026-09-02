#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/log.sh"
	source "$REPO_ROOT/lib/history.sh"

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

# lib::history::file
@test "lib::history::file honours HISTFILE when it is set" {
	run lib::history::file

	assert_output "$HISTFILE"
}

@test "lib::history::file falls back to the zsh history file" {
	HISTFILE="" SHELL=/usr/bin/zsh HOME=/home/example run lib::history::file

	assert_output "/home/example/.zsh_history"
}

@test "lib::history::file falls back to the bash history file" {
	HISTFILE="" SHELL=/bin/bash HOME=/home/example run lib::history::file

	assert_output "/home/example/.bash_history"
}

# lib::history::scrub
@test "lib::history::scrub removes the lines holding the secret" {
	lib::history::scrub "sup3rs3cr3tvalue" >/dev/null

	refute grep -q "sup3rs3cr3tvalue" "$HISTFILE"
	assert_equal "$(grep -c . "$HISTFILE")" "3"
}

@test "lib::history::scrub leaves unrelated lines untouched" {
	lib::history::scrub "sup3rs3cr3tvalue" >/dev/null

	assert_equal "$(cat "$HISTFILE")" 'ls -la
git status
echo unrelated'
}

@test "lib::history::scrub reports how many lines it removed" {
	run lib::history::scrub "sup3rs3cr3tvalue"

	assert_output --partial "Removed 1 line(s)"
}

@test "lib::history::scrub warns that the in-memory history is out of reach" {
	run lib::history::scrub "sup3rs3cr3tvalue"

	assert_output --partial "out of reach"
}

# An empty secret must not rewrite the file: a caller whose password came
# from MYSQL_PWD has nothing in argv to scrub.
@test "lib::history::scrub is a no-op for an empty secret" {
	local before
	before=$(cat "$HISTFILE")

	run lib::history::scrub ""

	assert_success
	assert_equal "$(cat "$HISTFILE")" "$before"
}

@test "lib::history::scrub warns when the secret is short enough to over-match" {
	run lib::history::scrub "abc"

	assert_output --partial "Secret is short"
}

@test "lib::history::scrub succeeds when there is no history file" {
	rm -f "$HISTFILE"

	run lib::history::scrub "sup3rs3cr3tvalue"

	assert_success
	assert_output --partial "nothing to scrub"
}

@test "lib::history::scrub leaves the rewritten file mode 600" {
	chmod 644 "$HISTFILE"

	lib::history::scrub "sup3rs3cr3tvalue" >/dev/null

	assert_equal "$(stat -c '%a' "$HISTFILE")" "600"
}

@test "lib::history::scrub leaves no temporary files behind" {
	lib::history::scrub "sup3rs3cr3tvalue" >/dev/null

	assert_equal "$(find "$TEST_TMP" -name 'history.libsh.*' | wc -l)" "0"
}
