# shellcheck shell=bash

# Log to stdout, optionally with colored text.
#
# Red is the exception: it goes to stderr, because an error that only
# reaches stdout is invisible to cron and CI alerting that watches the
# error stream. Everything else is progress reporting and stays on stdout.

#######################################
# Write a message to stdout in the given color.
# Globals:
#   None
# Arguments:
#   1 - The Bash color code, including its trailing 'm' (e.g. '31m')
#   2 - The string to log
# Outputs:
#   The given string, in the given color.
#######################################
function lib::log::write() {
  local color=${1} message=${2:-}

  # printf, not 'echo -e': the message is data. A backslash in a path, a
  # pattern or a password must not be read as an escape sequence.
  printf '\033[1;%s%s\033[0m\n' "$color" "$message"
}

#######################################
# Write a message to stdout without any color.
# Globals:
#   None
# Arguments:
#   1 - The string to log
# Outputs:
#   The given string, verbatim.
#######################################
function lib::log::plain() {
  printf '%s\n' "${1:-}"
}

# Write red output to stderr
function lib::log::red() {
  lib::log::write "31m" "${1}" >&2
}

# Write yellow output to stdout
function lib::log::yellow() {
  lib::log::write "33m" "${1}"
}

# Write green output to stdout
function lib::log::green() {
  lib::log::write "32m" "${1}"
}

# Write cyan output to stdout
function lib::log::cyan() {
  lib::log::write "36m" "${1}"
}

#######################################
# Write a message to stdout in the given color, prefixed with an
# RFC-3339 timestamp.
# Globals:
#   None
# Arguments:
#   1 - The Bash color code, including its trailing 'm' (e.g. '31m')
#   2 - The string to log
# Outputs:
#   The given string, timestamped and colored.
#######################################
function lib::log::timed() {
  local color=${1} message=${2:-} time

  # '--rfc-3339' is GNU-only; '%z' (a bare offset with no colon, e.g.
  # '-0500') is the portable part shared by GNU and BSD/macOS date, so the
  # colon RFC 3339 requires is inserted afterward instead.
  time=$(date '+%Y-%m-%d %H:%M:%S%z' | sed -E 's/([0-9]{2})([0-9]{2})$/\1:\2/')

  lib::log::write "$color" "[$time]: $message"
}

# Write timestamped red output to stderr
function lib::log::timed_red() {
  lib::log::timed "31m" "${1}" >&2
}

# Write timestamped yellow output to stdout
function lib::log::timed_yellow() {
  lib::log::timed "33m" "${1}"
}

# Write timestamped green output to stdout
function lib::log::timed_green() {
  lib::log::timed "32m" "${1}"
}

# Write timestamped cyan output to stdout
function lib::log::timed_cyan() {
  lib::log::timed "36m" "${1}"
}
