#!/usr/bin/env bash
# Real OpenBSD/macOS nc integration; no Python/Node test server required.
set -euo pipefail

# shellcheck disable=SC1090 # test either the checkout or an installed bundle
source "${1:?Pass the installed lib.sh path}"
test_tcp_dir=$(mktemp -d)
test_tcp_pid=''
cleanup() {
  if [[ -n $test_tcp_pid ]]; then
    kill "$test_tcp_pid" 2>/dev/null || true
    wait "$test_tcp_pid" 2>/dev/null || true
  fi
  rm -rf "$test_tcp_dir"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

# Retry a randomly chosen local port if another process already owns it.
for ((test_tcp_bind = 0; test_tcp_bind < 10; test_tcp_bind++)); do
  test_tcp_port=$((20000 + RANDOM))
  nc -l 127.0.0.1 "$test_tcp_port" </dev/null >"$test_tcp_dir/out" 2>"$test_tcp_dir/err" &
  test_tcp_pid=$!
  sleep 0.1
  if kill -0 "$test_tcp_pid" 2>/dev/null; then break; fi
  wait "$test_tcp_pid" 2>/dev/null || true
  test_tcp_pid=''
done
[[ -n $test_tcp_pid ]] || {
  cat "$test_tcp_dir/err" >&2
  exit 1
}
lib::net::tcp_wait 127.0.0.1 "$test_tcp_port" --attempts 3 --timeout 1 --interval 1
# Kill/wait is bounded even if a platform keeps its listener open after -z.
kill "$test_tcp_pid" 2>/dev/null || true
wait "$test_tcp_pid" 2>/dev/null || true
test_tcp_pid=''
if lib::net::tcp_wait 127.0.0.1 "$test_tcp_port" --attempts 2 --timeout 1 --interval 0; then
  printf 'Closed local endpoint unexpectedly accepted a connection.\n' >&2
  exit 1
fi
printf 'Real TCP integration passed.\n'
