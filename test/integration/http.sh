#!/usr/bin/env bash
# Exercise real curl against local netcat listeners without a server runtime.
set -euo pipefail

# shellcheck disable=SC1090 # exercise the checkout or an installed bundle
source "${1:?Pass the installed lib.sh path}"
test_http_dir=$(mktemp -d)
test_http_pids=()
test_http_port=''
export NO_PROXY=127.0.0.1 no_proxy=127.0.0.1

#######################################
# Stop fixture listeners and remove their files.
# Globals:
#   test_http_pids, test_http_dir (read)
# Arguments:
#   None
# Outputs:
#   Cleanup errors to stderr.
# Returns:
#   Final cleanup status.
#######################################
cleanup() {
  local pid
  for pid in ${test_http_pids[@]+"${test_http_pids[@]}"}; do
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
  done
  rm -rf "$test_http_dir"
}
trap cleanup EXIT
trap 'exit 1' INT TERM

#######################################
# Start a local listener serving one fixed HTTP response.
# Globals:
#   test_http_dir (read), test_http_port and test_http_pids (written)
# Arguments:
#   1 - Response bytes; empty for a listener that never responds
# Outputs:
#   Listener logs in the fixture directory.
# Returns:
#   0 ready, 1 unable to bind after ten attempts.
#######################################
start_server() {
  local attempt pid
  for ((attempt = 0; attempt < 10; attempt++)); do
    test_http_port=$((20000 + RANDOM))
    printf '%s' "$1" >"$test_http_dir/response.$test_http_port"
    nc -l 127.0.0.1 "$test_http_port" <"$test_http_dir/response.$test_http_port" \
      >"$test_http_dir/request.$test_http_port" 2>"$test_http_dir/error.$test_http_port" &
    pid=$!
    sleep 0.1
    if kill -0 "$pid" 2>/dev/null; then
      test_http_pids+=("$pid")
      return 0
    fi
    wait "$pid" 2>/dev/null || true
  done
  cat "$test_http_dir/error.$test_http_port" >&2
  return 1
}

start_server $'HTTP/1.1 200 OK\r\nContent-Length: 2\r\nConnection: close\r\n\r\nok'
[[ $(lib::net::http_probe "http://127.0.0.1:$test_http_port/" --timeout 2) == 200 ]]

start_server $'HTTP/1.1 503 Unavailable\r\nContent-Length: 0\r\nConnection: close\r\n\r\n'
test_http_status=0
test_http_output=$(lib::net::http_probe "http://127.0.0.1:$test_http_port/" --timeout 2) || test_http_status=$?
[[ $test_http_status == 1 && $test_http_output == 503 ]]

# Keep a destination listener ready while two separate redirect responses test
# default rejection and explicit following.
start_server $'HTTP/1.1 204 No Content\r\nConnection: close\r\n\r\n'
test_http_destination=$test_http_port
test_http_redirect=$'HTTP/1.1 302 Found\r\nContent-Length: 0\r\nLocation: http://127.0.0.1:'"$test_http_destination"$'/\r\nConnection: close\r\n\r\n'
start_server "$test_http_redirect"
test_http_status=0
test_http_output=$(lib::net::http_probe "http://127.0.0.1:$test_http_port/" --timeout 2) || test_http_status=$?
[[ $test_http_status == 1 && $test_http_output == 302 ]]

start_server "$test_http_redirect"
[[ $(lib::net::http_probe "http://127.0.0.1:$test_http_port/" -f --timeout 2) == 204 ]]

start_server ''
test_http_status=0
test_http_output=$(lib::net::http_probe "http://127.0.0.1:$test_http_port/" --timeout 1) || test_http_status=$?
[[ $test_http_status == 3 && -z $test_http_output ]]
printf 'Real HTTP integration passed.\n'
