#!/usr/bin/env bats

setup() {
	REPO_ROOT=${REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"
	source "$REPO_ROOT/lib/lib.sh"
	LEFT=$BATS_TEST_TMPDIR/left
	RIGHT=$BATS_TEST_TMPDIR/right
	mkdir "$LEFT" "$RIGHT"
}

@test "SemVer precedence matches the specification chain in both directions" {
	local -a versions=(1.0.0-alpha 1.0.0-alpha.1 1.0.0-alpha.beta 1.0.0-beta 1.0.0-beta.2 1.0.0-beta.11 1.0.0-rc.1 1.0.0 1.0.1 1.1.0 2.0.0)
	local i
	for ((i = 0; i < ${#versions[@]} - 1; i++)); do
		run lib::cmp::semver_compare "${versions[$i]}" "${versions[$((i + 1))]}"
		assert_success
		assert_output -1
		run lib::cmp::semver_compare "${versions[$((i + 1))]}" "${versions[$i]}"
		assert_success
		assert_output 1
	done
}

@test "SemVer comparison ignores builds handles huge numbers and uses ASCII identifiers" {
	run lib::cmp::semver_compare 1.2.3+one 1.2.3+two
	assert_success
	assert_output 0
	run lib::cmp::semver_compare 999999999999999999999999.0.0 1000000000000000000000000.0.0
	assert_output -1
	run lib::cmp::semver_compare 1.0.0-999999999999999999999999 1.0.0-1000000000000000000000000
	assert_output -1
	run lib::cmp::semver_compare 1.0.0-12 1.0.0-12a
	assert_output -1
	run lib::cmp::semver_compare 1.0.0-Z 1.0.0-a
	assert_output -1
	run lib::cmp::semver_compare 1.0.0-a.0 1.0.0-a
	assert_output 1
	run lib::cmp::semver_compare 01.0.0 1.0.0
	assert_failure 2
	run lib::cmp::semver_compare 1.0.0
	assert_failure 2
}

@test "size comparisons use exact byte values at signed-64 boundaries" {
	run lib::cmp::size_compare 00042 42
	assert_success
	assert_output 0
	run lib::cmp::size_compare 9223372036854775807 9223372036854775806
	assert_output 1
	run lib::cmp::size_compare 0 1
	assert_output -1
	local value
	for value in '' -1 1KiB 1.2 9223372036854775808; do
		run lib::cmp::size_compare "$value" 0
		assert_failure 2
	done
}

@test "file attributes ignore contents but detect size mode and modification-time changes" {
	printf aaa >"$LEFT/file"
	printf bbb >"$RIGHT/file"
	chmod 640 "$LEFT/file" "$RIGHT/file"
	touch -t 202001020304.05 "$LEFT/file" "$RIGHT/file"
	run lib::cmp::file_compare "$LEFT/file" "$RIGHT/file"
	assert_success
	assert_output ''
	chmod 600 "$RIGHT/file"
	run lib::cmp::file_compare "$LEFT/file" "$RIGHT/file"
	assert_failure 1
	chmod 640 "$RIGHT/file"
	touch -t 202101020304.05 "$RIGHT/file"
	run lib::cmp::file_compare "$LEFT/file" "$RIGHT/file"
	assert_failure 1
	printf bbbb >"$RIGHT/file"
	touch -r "$LEFT/file" "$RIGHT/file"
	run lib::cmp::file_compare "$LEFT/file" "$RIGHT/file"
	assert_failure 1
}

@test "file attributes follow explicit symlinks and distinguish invocation failures" {
	printf data >"$LEFT/file"
	ln -s "$LEFT/file" "$RIGHT/link"
	run lib::cmp::file_compare "$LEFT/file" "$RIGHT/link"
	assert_success
	run lib::cmp::file_compare "$LEFT" "$RIGHT"
	assert_failure 2
	run lib::cmp::file_compare "$LEFT/file" "$RIGHT/missing"
	assert_failure 2
	# shellcheck disable=SC2329 # metadata backend failure fixture
	stat() { return 7; }
	run lib::cmp::file_compare "$LEFT/file" "$LEFT/file"
	assert_failure 2
}

@test "file attributes compare numeric UID GID and BSD octal modes" {
	: >"$LEFT/file"
	: >"$RIGHT/file"
	local fixture_uid=12 fixture_gid=34
	# shellcheck disable=SC2329 # platform/backend fixtures
	uname() { printf 'Darwin\n'; }
	# shellcheck disable=SC2329
	stat() {
		[[ $1 == -L && $2 == -f && $3 == '%Mp%03Lp %u %g %m %z' ]] || return 9
		if [[ $4 == "$LEFT/file" ]]; then
			printf '0640 12 34 100 0\n'
		else printf '640 %s %s 100 0\n' "$fixture_uid" "$fixture_gid"; fi
	}
	run lib::cmp::file_compare "$LEFT/file" "$RIGHT/file"
	assert_success
	fixture_uid=13
	run lib::cmp::file_compare "$LEFT/file" "$RIGHT/file"
	assert_failure 1
	fixture_uid=12 fixture_gid=35
	run lib::cmp::file_compare "$LEFT/file" "$RIGHT/file"
	assert_failure 1
}

@test "file diffs report content differences and treat a literal dash as a filename" {
	printf 'a\n' >"$LEFT/file"
	cp "$LEFT/file" "$RIGHT/file"
	run lib::cmp::file_diff "$LEFT/file" "$RIGHT/file"
	assert_success
	assert_output ''
	printf 'b\n' >"$RIGHT/file"
	run lib::cmp::file_diff "$LEFT/file" "$RIGHT/file"
	assert_failure 1
	assert_output --partial '-a'
	assert_output --partial '+b'
	cd "$LEFT" || return 1
	printf 'a\n' >./-
	run lib::cmp::file_diff - file
	assert_success
	mkfifo fifo
	run lib::cmp::file_diff fifo file
	assert_failure 2
}

@test "diff errors are distinguished from content differences" {
	: >"$LEFT/file"
	# shellcheck disable=SC2329 # external diff failure fixture
	diff() { return 7; }
	run lib::cmp::file_diff "$LEFT/file" "$LEFT/file"
	assert_failure 2
	run lib::cmp::dir_diff "$LEFT" "$LEFT"
	assert_failure 2
}

@test "recursive attribute comparison detects names hidden entries types and nested attributes" {
	mkdir "$LEFT/sub" "$RIGHT/sub"
	printf abc >"$LEFT/sub/.hidden"
	cp -p "$LEFT/sub/.hidden" "$RIGHT/sub/.hidden"
	touch -t 202001020304.05 "$LEFT" "$RIGHT" "$LEFT/sub" "$RIGHT/sub"
	run lib::cmp::dir_compare "$LEFT" "$RIGHT"
	assert_success
	chmod 700 "$RIGHT/sub"
	run lib::cmp::dir_compare "$LEFT" "$RIGHT"
	assert_failure 1
	chmod 755 "$LEFT/sub" "$RIGHT/sub"
	mv "$RIGHT/sub/.hidden" "$RIGHT/sub/renamed"
	run lib::cmp::dir_compare "$LEFT" "$RIGHT"
	assert_failure 1
	run lib::cmp::dir_compare "$LEFT/missing" "$RIGHT"
	assert_failure 2
}

@test "directory attributes ignore directory inode size but compare root metadata" {
	local fixture_mode=755
	# shellcheck disable=SC2329 # metadata fixture
	__libsh_fs_stat() {
		[[ $2 == attributes ]] || return 9
		if [[ $1 == "$LEFT" ]]; then
			printf '755 12 34 100 32\n'
		else printf '%s 12 34 100 4096\n' "$fixture_mode"; fi
	}
	run lib::cmp::dir_compare "$LEFT" "$RIGHT"
	assert_success
	fixture_mode=700
	run lib::cmp::dir_compare "$LEFT" "$RIGHT"
	assert_failure 1
}

@test "directory diffs include hidden files empty directories and escaped unmatched names" {
	mkdir "$LEFT/empty" "$RIGHT/empty"
	printf left >"$LEFT/.hidden"
	printf right >"$RIGHT/.hidden"
	run lib::cmp::dir_diff "$LEFT" "$RIGHT"
	assert_failure 1
	assert_output --partial '.hidden'
	cp "$LEFT/.hidden" "$RIGHT/.hidden"
	mkdir "$RIGHT/extra"
	run lib::cmp::dir_diff "$LEFT" "$RIGHT"
	assert_failure 1
	assert_output --partial 'extra'
	: >"$LEFT/empty/file"
	mkdir "$RIGHT/empty/file"
	run lib::cmp::dir_diff "$LEFT" "$RIGHT"
	assert_failure 1
	assert_output --partial 'Entry types differ'
	: >"$LEFT/line"$'\n'
	run lib::cmp::dir_diff "$LEFT" "$RIGHT"
	assert_output --partial "line\\n"
}

@test "tree comparisons preserve newline filenames and do not follow child symlinks" {
	local name=$'[*]\tline\n\n'
	printf content >"$LEFT/$name"
	cp -p "$LEFT/$name" "$RIGHT/$name"
	ln -s .. "$LEFT/loop"
	ln -s .. "$RIGHT/loop"
	ln -s missing "$LEFT/broken"
	ln -s missing "$RIGHT/broken"
	touch -t 202001020304.05 "$LEFT" "$RIGHT"
	run lib::cmp::dir_diff "$LEFT" "$RIGHT"
	assert_success
	# Make link mtimes deterministic using a metadata fixture for link records.
	# shellcheck disable=SC2329
	__libsh_cmp_attributes() { printf 'stable\n'; }
	run lib::cmp::dir_compare "$LEFT" "$RIGHT"
	assert_success
	ln -s $'missing\n' "$RIGHT/different"
	ln -s missing "$LEFT/different"
	run lib::cmp::dir_diff "$LEFT" "$RIGHT"
	assert_failure 1
	assert_output --partial 'Symbolic links differ'
	run lib::cmp::dir_compare "$LEFT" "$RIGHT"
	assert_failure 1
}

@test "tree comparisons reject special files even inside an unmatched subtree" {
	mkdir "$LEFT/unmatched"
	mkfifo "$LEFT/unmatched/fifo"
	run lib::cmp::dir_compare "$LEFT" "$RIGHT"
	assert_failure 2
	run lib::cmp::dir_diff "$LEFT" "$RIGHT"
	assert_failure 2
}

@test "tree comparisons fail on unreadable directories even when other entries differ" {
	if [[ $EUID == 0 ]]; then skip 'effective root access bypasses ordinary permissions'; fi
	mkdir "$LEFT/denied"
	chmod 000 "$LEFT/denied"
	local attr_status content_status
	if lib::cmp::dir_compare "$LEFT" "$RIGHT"; then attr_status=0; else attr_status=$?; fi
	if lib::cmp::dir_diff "$LEFT" "$RIGHT"; then content_status=0; else content_status=$?; fi
	chmod 700 "$LEFT/denied"
	assert_equal "$attr_status" 2
	assert_equal "$content_status" 2
}

@test "batch-two primitives preserve strict options traps cwd and caller glob state" {
	mkdir "$LEFT/empty"
	run bash -c '
    set -euo pipefail
    source "$1/lib/lib.sh"
    cd "$2"
    set -f
    shopt -s failglob
    GLOBIGNORE="*"
    trap ":" USR1
    opts=$(set +o); traps=$(trap -p); cwd=$PWD
    lib::cmp::semver_compare 1.2.3 1.2.4 >/dev/null
    lib::cmp::size_compare 0 1 >/dev/null
    lib::hash::string_sha abc >/dev/null
    lib::fs::relativize ../foo . >/dev/null
    lib::fs::dir_empty empty
    lib::fs::dir_size empty >/dev/null
    lib::cmp::dir_compare empty empty
    lib::cmp::dir_diff empty empty
    [[ $(set +o) == "$opts" && $(trap -p) == "$traps" && $PWD == "$cwd" && $GLOBIGNORE == "*" ]]
    shopt -q failglob
  ' _ "$REPO_ROOT" "$LEFT"
	assert_success
}

@test "file attributes include special permission bits" {
	: >"$LEFT/file"
	cp -p "$LEFT/file" "$RIGHT/file"
	chmod 1640 "$LEFT/file"
	chmod 0640 "$RIGHT/file"
	run lib::cmp::file_compare "$LEFT/file" "$RIGHT/file"
	assert_failure 1
}
