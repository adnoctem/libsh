#!/usr/bin/env bats

setup() {
	REPO_ROOT=${REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"
	source "$REPO_ROOT/lib/lib.sh"
}

@test "hashes match known empty and abc vectors for MD5 and every SHA-2 algorithm" {
	run lib::hash::string_md5 ''
	assert_success
	assert_output d41d8cd98f00b204e9800998ecf8427e
	run lib::hash::string_md5 abc
	assert_output 900150983cd24fb0d6963f7d28e17f72
	run lib::hash::string_sha abc
	assert_success
	assert_output ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad
	run lib::hash::string_sha abc 224
	assert_output 23097d223405d8228642a477bda255b32aadbce4bda0b3f7e36c9da7
	run lib::hash::string_sha abc 384
	assert_output cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7
	run lib::hash::string_sha abc 512
	assert_output ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f
}

@test "hashing preserves literal whitespace backslashes and trailing newlines" {
	local value=$' a\\b\t\n\n' digest
	digest=$(lib::hash::string_sha "$value")
	# Fixed vector for these exact bytes, independently generated.
	assert_equal "$digest" 978c7b7157291655f3cf79720430c5309b98fa6698c116914ce45b28c370b310
	[[ $digest != "$(lib::hash::string_sha "${value%$'\n'}")" ]]
	run lib::hash::string_md5 --help
	assert_success
	[[ ${#output} == 32 ]]
}

@test "hash APIs reject missing arguments unsupported algorithms and explicit empty algorithms" {
	run lib::hash::string_md5
	assert_failure 2
	run lib::hash::string_md5 a b
	assert_failure 2
	run lib::hash::string_sha
	assert_failure 2
	local algorithm
	for algorithm in '' 1 128 0256 '256;false'; do
		run lib::hash::string_sha abc "$algorithm"
		assert_failure 2
	done
}

@test "hash backends fail cleanly without returning partial digests" {
	# shellcheck disable=SC2329 # resolved dynamically by the hashing helper
	sha256sum() {
		printf partial
		return 7
	}
	local result
	if result=$(lib::hash::string_sha abc 2>/dev/null); then return 1; fi
	assert_equal "$result" ''
	run lib::hash::string_sha abc
	assert_failure 1
	# shellcheck disable=SC2329
	sha256sum() { printf 'unexpected output\n'; }
	run lib::hash::string_sha abc
	assert_failure 1
	assert_output --partial 'invalid digest'
}

@test "macOS hash fallbacks receive exact stdin and explicit algorithm selection" {
	local original_path=$PATH
	mkdir "$BATS_TEST_TMPDIR/bin"
	cat >"$BATS_TEST_TMPDIR/bin/md5" <<'SH'
#!/bin/bash
[[ $* == -q ]] || exit 9
input=$(cat; printf .)
[[ $input == $'abc\n.' ]] || exit 8
printf '0bee89b07a248e27c83fc3d5951213c1\n'
SH
	cat >"$BATS_TEST_TMPDIR/bin/shasum" <<'SH'
#!/bin/bash
[[ $* == '-a 384' ]] || exit 9
input=$(cat; printf .)
[[ $input == abc. ]] || exit 8
printf 'cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7  -\n'
SH
	ln -s "$(command -v cat)" "$BATS_TEST_TMPDIR/bin/cat"
	chmod +x "$BATS_TEST_TMPDIR/bin/md5" "$BATS_TEST_TMPDIR/bin/shasum"
	PATH="$BATS_TEST_TMPDIR/bin" run lib::hash::string_md5 $'abc\n'
	assert_success
	assert_output 0bee89b07a248e27c83fc3d5951213c1
	PATH="$BATS_TEST_TMPDIR/bin" run lib::hash::string_sha abc 384
	assert_success
	assert_output cb00753f45a35e8bb5a03d699ac65007272c32ab0eded1631a8b605a43ff5bed8086072ba1e7cc2358baeca134c825a7
	PATH="$original_path"
}

@test "missing hash dependencies are operational errors and sourcing remains safe" {
	mkdir "$BATS_TEST_TMPDIR/empty-bin"
	PATH="$BATS_TEST_TMPDIR/empty-bin" run lib::hash::string_sha abc
	assert_failure 1
	PATH="$BATS_TEST_TMPDIR/empty-bin" run lib::hash::string_md5 abc
	assert_failure 1
}
