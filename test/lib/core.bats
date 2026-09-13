#!/usr/bin/env bats

setup() {
  REPO_ROOT=${REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
  load "$REPO_ROOT/test/bats/plugins/bats-support/load"
  load "$REPO_ROOT/test/bats/plugins/bats-assert/load"
  source "$REPO_ROOT/lib/lib.sh"
}

@test "SemVer accepts complete versions without a numeric size limit" {
  local version
  for version in 0.0.0 1.2.3 1.2.3-alpha.1+001 1.2.3-- 1.2.3-0A 99999999999999999999999999.2.3; do
    lib::core::semver_validate "$version"
  done
}

@test "SemVer rejects malformed identifiers and leading numeric zeros" {
  local version
  for version in '' v1.2.3 01.2.3 1.02.3 1.2.03 1.2 1.2.3.4 1.2.3-01 1.2.3-a..b 1.2.3- 1.2.3+ 1.2.3+a+b ' 1.2.3' 1.2.3_a $'1.2.3\n'; do
    run lib::core::semver_validate "$version"
    assert_failure 1
    assert_output ''
  done
  run lib::core::semver_validate
  assert_failure 2
}

@test "SemVer parsing preserves prerelease and metadata and exposes all fields" {
  local field expected
  for field in major minor patch prerelease build; do
    case $field in major) expected=1 ;; minor) expected=2 ;; patch) expected=3 ;; prerelease) expected=alpha.1 ;; build) expected=001 ;; esac
    run lib::core::semver_parse 1.2.3-alpha.1+001 "$field"
    assert_success
    assert_output "$expected"
  done
  run lib::core::semver_parse 1.2.3 build
  assert_success
  assert_output ''
  run lib::core::semver_parse 1.2 major
  assert_failure 2
  run lib::core::semver_parse 1.2.3 unknown
  assert_failure 2
}

@test "retry preserves argv and stops immediately after success" {
  local count="$BATS_TEST_TMPDIR/count" sleeps="$BATS_TEST_TMPDIR/sleeps"
  printf 0 >"$count"
  try_command() {
    # shellcheck disable=SC2016 # literal command-substitution text must stay data
    [[ $# == 2 && $1 == 'two words' && $2 == '$(false)' ]] || return 9
    local n
    n=$(cat "$count")
    printf '%s' "$((n + 1))" >"$count"
    ((n >= 2))
  }
  # shellcheck disable=SC2329 # invoked by the dynamically loaded retry helper
  sleep() { printf '%s\n' "$1" >>"$sleeps"; }
  # shellcheck disable=SC2016 # regression input, never evaluated
  lib::core::retry 2 5 -- try_command 'two words' '$(false)'
  assert_equal "$(cat "$count")" 3
  assert_equal "$(cat "$sleeps")" $'2\n2'
}

@test "retry does not sleep after its final failure or mutate the caller shell" {
  local sentinel=original
  fail_command() {
    sentinel=changed
    return 8
  }
  # shellcheck disable=SC2329 # invoked by the dynamically loaded retry helper
  sleep() { return 99; }
  run lib::core::retry 0 3 -- fail_command
  assert_failure 1
  if lib::core::retry 2 1 -- fail_command; then return 1; fi
  assert_equal "$sentinel" original
  run lib::core::retry 1 0 -- true
  assert_failure 2
  run lib::core::retry 1 2 true
  assert_failure 2
}

@test "retry stops when the interval sleep fails" {
  # shellcheck disable=SC2329 # invoked by the dynamically loaded retry helper
  sleep() { return 7; }
  run lib::core::retry 1 3 -- false
  assert_failure 1
  assert_output --partial 'sleep failed'
}

@test "result stores support update removal sorted listing and status filtering" {
  local results=''
  lib::core::results_add results zeta pending
  lib::core::results_add results alpha success
  lib::core::results_add results zeta failure
  run lib::core::results_list results
  assert_success
  assert_output $'alpha\tsuccess\nzeta\tfailure'
  run lib::core::results_list results failure
  assert_output $'zeta\tfailure'
  lib::core::results_remove results alpha
  lib::core::results_remove results missing
  run lib::core::results_list results
  assert_output $'zeta\tfailure'
  lib::core::results_remove results zeta
  run lib::core::results_list results
  assert_output ''
}

@test "result stores remain local and invalid updates preserve existing data" {
  local results='' before
  lib::core::results_add results one pending
  before=$results
  # shellcheck disable=SC2016 # reject expressions as operation IDs
  if lib::core::results_add results '$(touch bad)' success; then return 1; fi
  assert_equal "$results" "$before"
  if lib::core::results_add results one invalid; then return 1; fi
  assert_equal "$results" "$before"
  # shellcheck disable=SC2034 # accessed by validated variable reference
  local -r readonly_results=$results
  run lib::core::results_add readonly_results two success
  assert_failure 2
  # shellcheck disable=SC2034 # accessed by validated variable reference
  local -a array_results=()
  run lib::core::results_add array_results two success
  assert_failure 2
  run lib::core::results_add PATH two success
  assert_failure 2
}

@test "result stores reject malformed serialized state without modifying it" {
  local results=$'one\tpending\none\tsuccess' before
  before=$results
  if lib::core::results_remove results one; then return 1; fi
  assert_equal "$results" "$before"
  results=$'bad\tstatus'
  run lib::core::results_list results
  assert_failure 2
}

@test "batch-one primitives preserve strict shell options traps and scoped values" {
  run bash -c '
		set -euo pipefail
		source "$1/lib/lib.sh"
		trap ":" USR1
		before=$(set +o); traps=$(trap -p)
		work() {
			local results
			lib::core::results_add results setup pending
			lib::core::results_add results setup success
			lib::core::results_list results >/dev/null
			lib::core::results_remove results setup
			lib::core::retry 0 1 -- true
			lib::core::semver_validate 1.2.3+001
			lib::data::bytes_format 9223372036854775807 >/dev/null
			if lib::data::array_contains needle; then return 1; fi
		}
		work
		[[ ! ${results+x} && $(set +o) == "$before" && $(trap -p) == "$traps" ]]
	' _ "$REPO_ROOT"
  assert_success
}

@test "retry does not shadow command variables with its internal counters" {
  local interval=outer_interval attempts=outer_attempts attempt=outer_attempt
  inspect_variables() {
    [[ $interval == outer_interval && $attempts == outer_attempts && $attempt == outer_attempt ]]
  }
  lib::core::retry 0 1 -- inspect_variables
}

@test "result readers accept readonly stores but never invoke sort for empty output" {
  local results=''
  lib::core::results_add results task success
  # shellcheck disable=SC2034 # read by variable name through results_list
  local -r snapshot=$results
  run lib::core::results_list snapshot
  assert_success
  assert_output $'task\tsuccess'
  # shellcheck disable=SC2329 # invoked through results_list
  sort() { return 7; }
  run lib::core::results_list results pending
  assert_success
  assert_output ''
  run lib::core::results_list results
  assert_failure 1
  assert_output --partial 'Could not sort'
}
