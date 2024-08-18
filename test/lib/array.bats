#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(git rev-parse --show-toplevel)

	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"

	source "$REPO_ROOT/lib/array.sh"
}

# array::is_empty
@test 'array::is_empty succeeds with an empty array' {
	test_array=()

	run array::is_empty "${test_array[@]}"
	assert_success
}

@test "array::is_empty fails with a full array" {
	test_array=('black' 'red' 'gold')

	run array::is_empty "${test_array[@]}"
	assert_failure
}

# array::contains
@test "array::contains succeeds with a valid element" {
	test_array=('black' 'red' 'gold')
	test_element=black

	run array::contains "${test_element}" "${test_array[@]}"
	assert_success
}

@test "array::contains fails with an invalid element" {
	test_array=('black' 'red' 'gold')
	test_element=blue

	run array::contains "${test_element}" "${test_array[@]}"
	assert_failure
}
