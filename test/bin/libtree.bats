#!/usr/bin/env bats

setup() {
  REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
  load "$REPO_ROOT/test/bats/plugins/bats-support/load"
  load "$REPO_ROOT/test/bats/plugins/bats-assert/load"
  upstream="$BATS_TEST_TMPDIR/upstream"
  consumer="$BATS_TEST_TMPDIR/consumer"
  export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
  export GIT_AUTHOR_NAME=Test GIT_AUTHOR_EMAIL=test@example.invalid
  export GIT_COMMITTER_NAME=Test GIT_COMMITTER_EMAIL=test@example.invalid
  git init -q -b main "$upstream"
  cp -R "$REPO_ROOT/lib" "$REPO_ROOT/extensions" "$upstream/"
  git -C "$upstream" add .
  git -C "$upstream" commit -qm initial
  git init -q -b main "$consumer"
  git -C "$consumer" commit --allow-empty -qm initial
  cd "$consumer" || return 1
}

@test "libtree defaults to core-only vendoring without switching branches" {
  run bash "$REPO_ROOT/bin/libtree" pull --repo "$upstream"
  assert_success
  [[ -f scripts/libsh/lib/lib.sh && ! -e scripts/libsh/extensions ]]
  [[ $(git branch --show-current) == main ]]
  [[ -z $(git status --porcelain) ]]
}

@test "libtree remembers addons and can remove them on update" {
  run bash "$REPO_ROOT/bin/libtree" pull vendor/libsh --repo "$upstream" --extensions secret,git
  assert_success
  [[ -f vendor/libsh/extensions/libsecret.sh && ! -f vendor/libsh/extensions/libapt.sh ]]
  run bash -c 'source vendor/libsh/lib/lib.sh; lib::load_extensions secret git'
  assert_success
  printf '\n# updated fixture\n' >>"$upstream/extensions/libsecret.sh"
  git -C "$upstream" commit -qam update
  run bash "$REPO_ROOT/bin/libtree" update vendor/libsh
  assert_success
  run tail -1 vendor/libsh/extensions/libsecret.sh
  assert_output '# updated fixture'
  run bash "$REPO_ROOT/bin/libtree" update vendor/libsh --extensions none
  assert_success
  [[ ! -e vendor/libsh/extensions/libsecret.sh ]]
  [[ -z $(git status --porcelain) ]]
}

@test "libtree refuses missing addons without changing the consumer" {
  local before
  before=$(git rev-parse HEAD)
  run bash "$REPO_ROOT/bin/libtree" pull --repo "$upstream" --extensions absent
  assert_failure
  [[ $(git rev-parse HEAD) == "$before" && ! -e scripts/libsh ]]
}
