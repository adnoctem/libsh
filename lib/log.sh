# shellcheck shell=bash

# Log to stdout or stderr, optionally with colored text.

#######################################
# Log to stdout, either colorized or not.
#
# Globals:
#   None
# Arguments:
#   1 - The BASH color code with suffix -m
#   2 - The string to log to stdout
# Outputs:
#   The given string in the given color.
#######################################

# Write un-colored output to stdout
log() {
  if [[ $# -eq 1 ]]; then
    echo -e "$1" &>/dev/null
  else
    echo -e "\033[1;${1}${2}\033[0m"
  fi
}

# Write red output to stdout
log::red() {
  log "31m" "${1}"
}

# Write yellow output to stdout
log::yellow() {
  log "33m" "${1}"
}

# Write green output to stdout
log::green() {
  log "32m" "${1}"
}

# Write cyan output to stdout
log::cyan() {
  log "36m" "${1}"
}

# Write un-colored output to stdout, including a time prefix
log_time() {
  local time
  time=$(date --rfc-3339=seconds)

  if [[ $# -eq 1 ]]; then
    echo -e "[$time]: $1" &>/dev/null
  else
    echo -e "\033[1;[$time]: ${1}${2}\033[0m"
  fi
}

# Write red output to stdout
log_time::red() {
  local time
  time=$(date --rfc-3339=seconds)

  log "31m" "[$time]: ${1}"
}

# Write yellow output to stdout
log_time::yellow() {
  local time
  time=$(date --rfc-3339=seconds)

  log "33m" "[$time]: ${1}"
}

# Write green output to stdout
log_time::green() {
  local time
  time=$(date --rfc-3339=seconds)

  log "32m" "[$time]: ${1}"
}

# Write cyan output to stdout
log_time::cyan() {
  local time
  time=$(date --rfc-3339=seconds)

  log "36m" "[$time]: ${1}"
}
