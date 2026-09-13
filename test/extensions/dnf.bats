#!/usr/bin/env bats

setup() {
  REPO_ROOT=${REPO_ROOT:-$(cd "$BATS_TEST_DIRNAME/../.." && pwd)}
  load "$REPO_ROOT/test/bats/plugins/bats-support/load"
  load "$REPO_ROOT/test/bats/plugins/bats-assert/load"
  source "$REPO_ROOT/lib/lib.sh"
  lib::load_extensions dnf
}

@test "DNF installed query uses RPM without interpreting package patterns" {
  # shellcheck disable=SC2329 # backend fixture
  rpm() { [[ $* == '--query -- bash.x86_64' ]]; }
  run ext::dnf::is_installed bash.x86_64
  assert_success
  run ext::dnf::is_installed absent
  assert_failure 1
  run ext::dnf::is_installed --help
  assert_failure 2
}

@test "DNF pending packages use cache-only formatted repoquery and deduplicate" {
  # shellcheck disable=SC2329 # backend fixture
  dnf() {
    [[ $* == '--cacheonly --quiet repoquery --upgrades --queryformat %{name}.%{arch}' ]] || return 1
    printf 'bash.x86_64\nlibstdc++.x86_64\nbash.x86_64\n'
  }
  run ext::dnf::pending_packages
  assert_success
  assert_output $'bash.x86_64\nlibstdc++.x86_64'
}

@test "DNF pending queries distinguish empty results and backend failures" {
  # shellcheck disable=SC2329
  dnf() { :; }
  run ext::dnf::pending_packages
  assert_success
  assert_output ''
  # shellcheck disable=SC2329
  dnf() {
    printf 'partial.x86_64\n'
    return 1
  }
  run ext::dnf::pending_packages
  assert_failure 1
  assert_output ''
  # shellcheck disable=SC2329
  dnf() { printf 'unexpected diagnostic\n'; }
  run ext::dnf::pending_packages
  assert_failure 1
  assert_output ''
}
