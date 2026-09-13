#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

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
