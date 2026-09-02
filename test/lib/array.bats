#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/array.sh"
}

# lib::array::is_empty
@test 'lib::array::is_empty succeeds with an empty array' {
	test_array=()

	run lib::array::is_empty "${test_array[@]}"
	assert_success
}

@test "lib::array::is_empty fails with a full array" {
	test_array=('black' 'red' 'gold')

	run lib::array::is_empty "${test_array[@]}"
	assert_failure
}

# lib::array::contains
@test "lib::array::contains succeeds with a valid element" {
	test_array=('black' 'red' 'gold')
	test_element=black

	run lib::array::contains "${test_element}" "${test_array[@]}"
	assert_success
}

@test "lib::array::contains fails with an invalid element" {
	test_array=('black' 'red' 'gold')
	test_element=blue

	run lib::array::contains "${test_element}" "${test_array[@]}"
	assert_failure
}
