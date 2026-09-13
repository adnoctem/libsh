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
# Returns:
#   The final output command status.
#######################################
function lib::log::print() {
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
# Returns:
#   The final output command status.
#######################################
function lib::log::plain() {
  printf '%s\n' "${1:-}"
}

#######################################
# Write red output to stderr
# Globals:
#   None
# Arguments:
#   1 - Message to log
# Outputs:
#   Colored message to stderr.
# Returns:
#   The final output command status.
#######################################
function lib::log::red() {
  lib::log::print "31m" "${1}" >&2
}

#######################################
# Write yellow output to stdout
# Globals:
#   None
# Arguments:
#   1 - Message to log
# Outputs:
#   Colored message to stdout.
# Returns:
#   The final output command status.
#######################################
function lib::log::yellow() {
  lib::log::print "33m" "${1}"
}

#######################################
# Write green output to stdout
# Globals:
#   None
# Arguments:
#   1 - Message to log
# Outputs:
#   Colored message to stdout.
# Returns:
#   The final output command status.
#######################################
function lib::log::green() {
  lib::log::print "32m" "${1}"
}

#######################################
# Write cyan output to stdout
# Globals:
#   None
# Arguments:
#   1 - Message to log
# Outputs:
#   Colored message to stdout.
# Returns:
#   The final output command status.
#######################################
function lib::log::cyan() {
  lib::log::print "36m" "${1}"
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
# Returns:
#   The final output command status.
#######################################
function lib::log::timed() {
  local color=${1} message=${2:-} time

  # '--rfc-3339' is GNU-only; '%z' (a bare offset with no colon, e.g.
  # '-0500') is the portable part shared by GNU and BSD/macOS date, so the
  # colon RFC 3339 requires is inserted afterward instead.
  time=$(date '+%Y-%m-%d %H:%M:%S%z' | sed -E 's/([0-9]{2})([0-9]{2})$/\1:\2/')

  lib::log::print "$color" "[$time]: $message"
}

#######################################
# Write timestamped red output to stderr
# Globals:
#   None
# Arguments:
#   1 - Message to log
# Outputs:
#   Timestamped colored message to stderr.
# Returns:
#   The final output command status.
#######################################
function lib::log::timed_red() {
  lib::log::timed "31m" "${1}" >&2
}

#######################################
# Write timestamped yellow output to stdout
# Globals:
#   None
# Arguments:
#   1 - Message to log
# Outputs:
#   Timestamped colored message to stdout.
# Returns:
#   The final output command status.
#######################################
function lib::log::timed_yellow() {
  lib::log::timed "33m" "${1}"
}

#######################################
# Write timestamped green output to stdout
# Globals:
#   None
# Arguments:
#   1 - Message to log
# Outputs:
#   Timestamped colored message to stdout.
# Returns:
#   The final output command status.
#######################################
function lib::log::timed_green() {
  lib::log::timed "32m" "${1}"
}

#######################################
# Write timestamped cyan output to stdout
# Globals:
#   None
# Arguments:
#   1 - Message to log
# Outputs:
#   Timestamped colored message to stdout.
# Returns:
#   The final output command status.
#######################################
function lib::log::timed_cyan() {
  lib::log::timed "36m" "${1}"
}

#######################################
# Append one plain-text log entry to a file, creating it when absent.
# Message bytes are preserved and followed by one newline. Existing symlinks
# to regular files are followed; missing parents are not created. This does
# not lock concurrent writers or roll back a partially failed append.
# Globals:
#   PATH (read when timestamping); the caller's umask governs new files.
# Arguments:
#   1 - Log file path
#   2 - Message (may be empty or contain embedded newlines)
#   3 - Optional --timestamp, prefixing UTC time as [YYYY-MM-DDTHH:MM:SSZ]
# Outputs:
#   Entry to the file; errors to stderr. No stdout.
# Returns:
#   0 on success, 1 on timestamp/open/write failure, 2 on invalid arguments.
# Dependencies:
#   date, only with --timestamp.
#######################################
function lib::log::write() {
  if [[ $# -lt 2 || $# -gt 3 || -z ${1:-} || ($# == 3 && $3 != --timestamp) ]]; then
    lib::log::red 'write requires FILE MESSAGE and optional --timestamp.'
    return 2
  fi

  local file=$1 message=$2 timestamp

  if [[ (-e $file || -L $file) && ! -f $file ]]; then
    lib::log::red 'Log destination must be a regular file or an absent path.'
    return 1
  fi

  if [[ $# == 3 ]]; then
    if ! timestamp=$(date -u '+%Y-%m-%dT%H:%M:%SZ'); then
      lib::log::red 'Could not obtain the log timestamp.'
      return 1
    fi

    message="[$timestamp] $message"
  fi

  if ! printf '%s\n' "$message" >>"$file"; then
    lib::log::red 'Could not append the log entry.'
    return 1
  fi
}
