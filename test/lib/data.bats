#!/usr/bin/env bats

setup() {
	REPO_ROOT=${REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/lib.sh"
}

# lib::data::array_is_empty
@test 'lib::data::array_is_empty succeeds with an empty array' {
	test_array=()

	run lib::data::array_is_empty "${test_array[@]}"
	assert_success
}

@test "lib::data::array_is_empty fails with a full array" {
	test_array=('black' 'red' 'gold')

	run lib::data::array_is_empty "${test_array[@]}"
	assert_failure
}

# lib::data::array_contains
@test "lib::data::array_contains succeeds with a valid element" {
	test_array=('black' 'red' 'gold')
	test_element=black

	run lib::data::array_contains "${test_element}" "${test_array[@]}"
	assert_success
}

@test "lib::data::array_contains fails with an invalid element" {
	test_array=('black' 'red' 'gold')
	test_element=blue

	run lib::data::array_contains "${test_element}" "${test_array[@]}"
	assert_failure
}

@test "array membership compares individual literal elements including empties" {
	lib::data::array_contains '' '' alpha
	lib::data::array_contains 'a b' 'a b' c
	lib::data::array_contains 'a.*' 'a.*' c
	run lib::data::array_contains 'a b' a b
	assert_failure 1
	run lib::data::array_contains 'a.*' abc
	assert_failure 1
	run lib::data::array_contains ''
	assert_failure 1
	run lib::data::array_contains
	assert_failure 2
}

@test "byte conversion distinguishes SI and IEC and normalizes decimal input" {
	run lib::data::bytes_from 0008 KB
	assert_success
	assert_output 8000
	run lib::data::bytes_from 8 KiB
	assert_output 8192
	run lib::data::bytes_from 1 EiB
	assert_output 1152921504606846976
}

@test "byte conversion accepts signed-64 maximum and rejects overflow or expressions" {
	run lib::data::bytes_from 9223372036854775807 B
	assert_success
	assert_output 9223372036854775807
	local value
	for value in 9223372036854775808 -1 1.5 '1+2' '1;false'; do
		run lib::data::bytes_from "$value" B
		assert_failure 2
	done
	run lib::data::bytes_from 8 EiB
	assert_failure 2
	run lib::data::bytes_from 1 kb
	assert_failure 2
}

@test "byte display truncates fractions exactly even at large magnitudes" {
	run lib::data::bytes_to 1023 KiB 3
	assert_success
	assert_output 0.999
	run lib::data::bytes_to 9223372036854775807 EiB 6
	assert_output 7.999999
	run lib::data::bytes_to 9223372036854775807 EB 6
	assert_output 9.223372
	run lib::data::bytes_to 15 B 0
	assert_output 15
}

@test "automatic byte formatting chooses units without rounding upward" {
	run lib::data::bytes_format 1024
	assert_output '1.00 KiB'
	run lib::data::bytes_format 1000 si 0
	assert_output '1 KB'
	run lib::data::bytes_format 0
	assert_output '0.00 B'
	run lib::data::bytes_format 1023 iec 0
	assert_output '1023 B'
	run lib::data::bytes_format 1024 wrong
	assert_failure 2
	run lib::data::bytes_to 1 B ''
	assert_failure 2
}
