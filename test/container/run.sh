#!/usr/bin/env bash
set -euo pipefail

[[ $EUID == 10001 && $(id -g) == 10001 ]]
for test_container_tool in node python python3 trurl; do
  if command -v "$test_container_tool" >/dev/null 2>&1; then
    printf 'Unexpected runtime tool: %s\n' "$test_container_tool" >&2
    exit 1
  fi
done
# shellcheck source=lib/lib.sh
source /usr/local/lib/libsh/lib.sh
lib::load_extensions secret
mounted=''
ext::secret::read_file mounted /run/secrets/certificate
[[ $mounted == $'-----BEGIN CERTIFICATE-----\nsynthetic\n-----END CERTIFICATE-----\n\n' ]]
if { printf 'write' >/run/secrets/certificate; } 2>/dev/null; then
  printf 'Secret mount unexpectedly writable.\n' >&2
  exit 1
fi
if { printf 'write' >/root-filesystem-write-test; } 2>/dev/null; then exit 1; fi
if ext::secret::read_file denied /run/secrets/denied; then exit 1; fi

export REPO_ROOT=/opt/libsh-test
bash "$REPO_ROOT/test/bats/core/bin/bats" "$REPO_ROOT/test/extensions/secret.bats" "$REPO_ROOT/test/lib" "$REPO_ROOT/test/bin/libman.bats"
bash "$REPO_ROOT/test/integration/tcp.sh" /usr/local/lib/libsh/lib.sh
printf 'Container verification passed with Bash %s.\n' "$BASH_VERSION"
