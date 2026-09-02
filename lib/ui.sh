# shellcheck shell=bash

# lib::ui -- interactive helpers for steps that don't have a byte count
# to drive `pv`. Use `pv` for anything streaming bytes (dumps, transfers,
# copies) -- it already gives accurate progress/ETA and shouldn't be
# reimplemented here. Use lib::ui:: for steps that are either indeterminate
# (waiting on a remote call) or need a yes/no gate before something
# destructive.

#######################################
# Run a spinner while a background PID is alive. No-ops to a plain
# `wait` when stdout isn't a terminal, so cron/CI logs stay clean.
# Arguments:
#   $1 - PID to watch
#   $2 - Message to display (optional)
# Returns:
#   The watched process's exit code.
#######################################
function lib::ui::spinner() {
  local pid=$1
  local message=${2:-"Working..."}
  local -a frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
  local i=0

  if [[ ! -t 1 ]]; then
    wait "$pid"
    return $?
  fi

  tput civis 2>/dev/null
  while kill -0 "$pid" 2>/dev/null; do
    printf "\r%s %s" "${frames[i]}" "$message"
    i=$(((i + 1) % ${#frames[@]}))
    sleep 0.1
  done
  wait "$pid"
  local rc=$?
  tput cnorm 2>/dev/null
  printf "\r\033[K"
  return $rc
}

#######################################
# Ask a yes/no question. Refuses to silently proceed when not attached
# to a terminal (cron/CI) unless a default is explicitly given, so an
# unattended run never sails past a destructive confirmation by accident.
# Arguments:
#   $1 - Prompt text
#   $2 - Default: "y" or "n" (optional, no default = require a TTY)
# Returns:
#   0 for yes, 1 for no.
#######################################
function lib::ui::confirm() {
  local prompt=$1
  local default=${2:-}

  if [[ ! -t 0 ]]; then
    if [[ $default == "y" ]]; then return 0; fi
    if [[ $default == "n" ]]; then return 1; fi
    lib::log::red "'$prompt' needs a TTY to confirm and no default was given; refusing to proceed unattended."
    return 1
  fi

  local suffix="y/N"
  [[ $default == "y" ]] && suffix="Y/n"
  local reply
  read -r -p "$prompt [$suffix] " reply
  reply=${reply:-$default}
  [[ $reply =~ ^[Yy]$ ]]
}
