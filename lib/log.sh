# shellcheck shell=bash

# Intent logs use UTC timestamps and readable labels. Info, success and notice
# go to stdout; debug, warnings and errors go to stderr. Files are always plain
# text. Raw print/plain/write remain available for unstructured output.

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
# Check whether debug logging is enabled at call time without external commands.
# Globals:
#   LIBSH_DEBUG (read): 1 or case-insensitive true enables debug.
# Arguments:
#   None
# Outputs:
#   Nothing.
# Returns:
#   0 enabled, 1 disabled, 2 unexpected arguments.
#######################################
# shellcheck disable=SC2120 # public predicate rejects unexpected arguments
function lib::log::debug_enabled() {
  [[ $# == 0 ]] || return 2

  case ${LIBSH_DEBUG:-} in
    1 | [tT][rR][uU][eE]) return 0 ;;
    *) return 1 ;;
  esac
}

#######################################
# Emit one timestamped intent record to the selected terminal stream.
# Prefix once, preserve literal message bytes, and color only the intent label.
# Globals:
#   TERM, NO_COLOR (read); PATH through lib::os::date.
# Arguments:
#   1 - Intent label
#   2 - ANSI foreground color number
#   3 - Destination descriptor (1 or 2)
#   4 - Message (exactly one string)
# Outputs:
#   Record and newline to the destination; backend errors to stderr.
# Returns:
#   0 success, 1 timestamp/output failure, 2 invalid arguments.
#######################################
function __libsh_log_print() {
  [[ $# == 4 ]] || return 2
  local intent=$1 color=$2 destination=$3 message=$4 timestamp

  timestamp=$(lib::os::date) || return 1

  if [[ -t $destination && ${TERM:-} != dumb && -z ${NO_COLOR:-} ]]; then
    printf '[%s] \033[1;%sm%s\033[0m: %s\n' "$timestamp" "$color" "$intent" "$message" >&"$destination" || return 1
  else
    printf '[%s] %s: %s\n' "$timestamp" "$intent" "$message" >&"$destination" || return 1
  fi
}

#######################################
# Append one timestamped intent record using the raw file writer.
# Globals:
#   PATH through lib::os::date; caller umask governs new files.
# Arguments:
#   1 - Intent label
#   2 - File path (nonempty)
#   3 - Message (exactly one string)
# Outputs:
#   Plain-text record and newline to the file; backend errors to stderr.
# Returns:
#   0 success, 1 timestamp/open/write failure, 2 invalid arguments.
#######################################
function __libsh_log_write() {
  [[ $# == 3 && -n $2 ]] || return 2
  local intent=$1 file=$2 message=$3 timestamp

  timestamp=$(lib::os::date) || return 1
  lib::log::write "$file" "[$timestamp] $intent: $message"
}

#######################################
# Print a timestamped INFO record.
# Globals:
#   TERM, NO_COLOR, PATH (read).
# Arguments:
#   1 - Message (may be empty or contain embedded newlines)
# Outputs:
#   Record and newline to stdout; backend errors to stderr.
# Returns:
#   0 success, 1 timestamp/output failure, 2 invalid arguments.
# Dependencies:
#   date, through lib::os::date.
#######################################
function lib::log::print_info() {
  __libsh_log_print INFO 37 1 ${1+"$@"}
}

#######################################
# Print a timestamped SUCCESS record.
# Globals:
#   TERM, NO_COLOR, PATH (read).
# Arguments:
#   1 - Message (may be empty or contain embedded newlines)
# Outputs:
#   Record and newline to stdout; backend errors to stderr.
# Returns:
#   0 success, 1 timestamp/output failure, 2 invalid arguments.
# Dependencies:
#   date, through lib::os::date.
#######################################
function lib::log::print_success() {
  __libsh_log_print SUCCESS 32 1 ${1+"$@"}
}

#######################################
# Print a timestamped NOTICE record.
# Globals:
#   TERM, NO_COLOR, PATH (read).
# Arguments:
#   1 - Message (may be empty or contain embedded newlines)
# Outputs:
#   Record and newline to stdout; backend errors to stderr.
# Returns:
#   0 success, 1 timestamp/output failure, 2 invalid arguments.
# Dependencies:
#   date, through lib::os::date.
#######################################
function lib::log::print_notice() {
  __libsh_log_print NOTICE 33 1 ${1+"$@"}
}

#######################################
# Print a timestamped DEBUG record only when debug is enabled.
# Disabled calls return before argument validation, timestamps or file access.
# Globals:
#   LIBSH_DEBUG, TERM, NO_COLOR, PATH (read).
# Arguments:
#   1 - Message (may be empty or contain embedded newlines)
# Outputs:
#   Record and newline to stderr; backend errors to stderr.
# Returns:
#   0 success or disabled, 1 timestamp/output failure, 2 invalid arguments when enabled.
# Dependencies:
#   date only when enabled, through lib::os::date.
#######################################
function lib::log::print_debug() {
  # shellcheck disable=SC2119 # predicate intentionally receives no arguments
  lib::log::debug_enabled || return 0

  __libsh_log_print DEBUG 36 2 ${1+"$@"}
}

#######################################
# Print a timestamped WARN record.
# Globals:
#   TERM, NO_COLOR, PATH (read).
# Arguments:
#   1 - Message (may be empty or contain embedded newlines)
# Outputs:
#   Record and newline to stderr; backend errors to stderr.
# Returns:
#   0 success, 1 timestamp/output failure, 2 invalid arguments.
# Dependencies:
#   date, through lib::os::date.
#######################################
function lib::log::print_warn() {
  __libsh_log_print WARN 33 2 ${1+"$@"}
}

#######################################
# Print a timestamped ERROR record.
# Globals:
#   TERM, NO_COLOR, PATH (read).
# Arguments:
#   1 - Message (may be empty or contain embedded newlines)
# Outputs:
#   Record and newline to stderr; backend errors to stderr.
# Returns:
#   0 success, 1 timestamp/output failure, 2 invalid arguments.
# Dependencies:
#   date, through lib::os::date.
#######################################
function lib::log::print_error() {
  __libsh_log_print ERROR 31 2 ${1+"$@"}
}

#######################################
# Append a timestamped INFO record.
# Globals:
#   PATH (read); caller umask governs new files.
# Arguments:
#   1 - File path (nonempty)
#   2 - Message (may be empty or contain embedded newlines)
# Outputs:
#   Record and newline to the named file (append only, no ANSI); backend errors to stderr.
# Returns:
#   0 success, 1 timestamp/output failure, 2 invalid arguments.
# Dependencies:
#   date, through lib::os::date.
#######################################
function lib::log::write_info() {
  __libsh_log_write INFO ${1+"$@"}
}

#######################################
# Append a timestamped SUCCESS record.
# Globals:
#   PATH (read); caller umask governs new files.
# Arguments:
#   1 - File path (nonempty)
#   2 - Message (may be empty or contain embedded newlines)
# Outputs:
#   Record and newline to the named file (append only, no ANSI); backend errors to stderr.
# Returns:
#   0 success, 1 timestamp/output failure, 2 invalid arguments.
# Dependencies:
#   date, through lib::os::date.
#######################################
function lib::log::write_success() {
  __libsh_log_write SUCCESS ${1+"$@"}
}

#######################################
# Append a timestamped NOTICE record.
# Globals:
#   PATH (read); caller umask governs new files.
# Arguments:
#   1 - File path (nonempty)
#   2 - Message (may be empty or contain embedded newlines)
# Outputs:
#   Record and newline to the named file (append only, no ANSI); backend errors to stderr.
# Returns:
#   0 success, 1 timestamp/output failure, 2 invalid arguments.
# Dependencies:
#   date, through lib::os::date.
#######################################
function lib::log::write_notice() {
  __libsh_log_write NOTICE ${1+"$@"}
}

#######################################
# Append a timestamped DEBUG record only when debug is enabled.
# Disabled calls return before argument validation, timestamps or file access.
# Globals:
#   LIBSH_DEBUG, PATH (read); caller umask governs new files.
# Arguments:
#   1 - File path (nonempty)
#   2 - Message (may be empty or contain embedded newlines)
# Outputs:
#   Record and newline to the named file (append only, no ANSI); backend errors to stderr.
# Returns:
#   0 success or disabled, 1 timestamp/output failure, 2 invalid arguments when enabled.
# Dependencies:
#   date only when enabled, through lib::os::date.
#######################################
function lib::log::write_debug() {
  # shellcheck disable=SC2119 # predicate intentionally receives no arguments
  lib::log::debug_enabled || return 0

  __libsh_log_write DEBUG ${1+"$@"}
}

#######################################
# Append a timestamped WARN record.
# Globals:
#   PATH (read); caller umask governs new files.
# Arguments:
#   1 - File path (nonempty)
#   2 - Message (may be empty or contain embedded newlines)
# Outputs:
#   Record and newline to the named file (append only, no ANSI); backend errors to stderr.
# Returns:
#   0 success, 1 timestamp/output failure, 2 invalid arguments.
# Dependencies:
#   date, through lib::os::date.
#######################################
function lib::log::write_warn() {
  __libsh_log_write WARN ${1+"$@"}
}

#######################################
# Append a timestamped ERROR record.
# Globals:
#   PATH (read); caller umask governs new files.
# Arguments:
#   1 - File path (nonempty)
#   2 - Message (may be empty or contain embedded newlines)
# Outputs:
#   Record and newline to the named file (append only, no ANSI); backend errors to stderr.
# Returns:
#   0 success, 1 timestamp/output failure, 2 invalid arguments.
# Dependencies:
#   date, through lib::os::date.
#######################################
function lib::log::write_error() {
  __libsh_log_write ERROR ${1+"$@"}
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
    printf '%s\n' 'libsh: write requires FILE MESSAGE and optional --timestamp.' >&2
    return 2
  fi

  local file=$1 message=$2 timestamp

  if [[ (-e $file || -L $file) && ! -f $file ]]; then
    printf '%s\n' 'libsh: Log destination must be a regular file or an absent path.' >&2
    return 1
  fi

  if [[ $# == 3 ]]; then
    if ! timestamp=$(lib::os::date); then
      printf '%s\n' 'libsh: Could not obtain the log timestamp.' >&2
      return 1
    fi

    message="[$timestamp] $message"
  fi

  if ! printf '%s\n' "$message" >>"$file"; then
    printf '%s\n' 'libsh: Could not append the log entry.' >&2
    return 1
  fi
}
