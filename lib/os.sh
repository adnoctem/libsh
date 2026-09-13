# shellcheck shell=bash

# Bash functions for working with paths, including resolving the XDG Base
# Directory Specification's user directories.
#
# ref: https://specifications.freedesktop.org/basedir-spec/latest/

# Ensure a base-directory for a given path exists
function lib::os::ensure_existence() {
  local path=${1}

  if [[ ! -e ${path} ]]; then
    mkdir -p "$(dirname "${path}")"
  fi
}

# Ensure a directory itself exists, rather than its parent
function lib::os::ensure_directory() {
  local path=${1}

  if [[ ! -d ${path} ]]; then
    mkdir -p "${path}"
  fi
}

#######################################
# Resolve the user's XDG config directory. XDG_CONFIG_HOME always wins when
# set; otherwise falls back to the platform-native default -- macOS doesn't
# follow the XDG spec, so Darwin gets ~/Library/Application Support instead
# of ~/.config, matching Go's os.UserConfigDir() (and gopskit's own Config
# field, which wraps it).
# Globals:
#   HOME, XDG_CONFIG_HOME
# Arguments:
#   1 - App name to nest under the base directory (optional)
# Outputs:
#   The resolved path to stdout.
#######################################
function lib::os::config_home() {
  local app=${1:-} base

  if [[ -n ${XDG_CONFIG_HOME:-} ]]; then
    base="$XDG_CONFIG_HOME"
  elif [[ $(uname) == "Darwin" ]]; then
    base="$HOME/Library/Application Support"
  else
    base="$HOME/.config"
  fi

  [[ -n $app ]] && base="$base/$app"
  printf '%s' "$base"
}

#######################################
# Resolve the user's XDG data directory. XDG_DATA_HOME always wins when
# set; otherwise falls back to the platform-native default. On Darwin,
# gopskit's own Data path (~/Library/<app>/Data) nests the app name before
# a fixed 'Data' leaf, the reverse of config/cache's app-last shape -- kept
# as-is here for parity rather than smoothed over.
# Globals:
#   HOME, XDG_DATA_HOME
# Arguments:
#   1 - App name to nest under the base directory (optional)
# Outputs:
#   The resolved path to stdout.
#######################################
function lib::os::data_home() {
  local app=${1:-} base

  if [[ -n ${XDG_DATA_HOME:-} ]]; then
    base="$XDG_DATA_HOME"
    [[ -n $app ]] && base="$base/$app"
  elif [[ $(uname) == "Darwin" ]]; then
    base="$HOME/Library"
    [[ -n $app ]] && base="$base/$app/Data"
  else
    base="$HOME/.local/share"
    [[ -n $app ]] && base="$base/$app"
  fi

  printf '%s' "$base"
}

#######################################
# Resolve the user's XDG cache directory. XDG_CACHE_HOME always wins when
# set; otherwise falls back to the platform-native default -- Darwin gets
# ~/Library/Caches, matching Go's os.UserCacheDir() (and gopskit's own
# Cache field, which wraps it).
# Globals:
#   HOME, XDG_CACHE_HOME
# Arguments:
#   1 - App name to nest under the base directory (optional)
# Outputs:
#   The resolved path to stdout.
#######################################
function lib::os::cache_home() {
  local app=${1:-} base

  if [[ -n ${XDG_CACHE_HOME:-} ]]; then
    base="$XDG_CACHE_HOME"
  elif [[ $(uname) == "Darwin" ]]; then
    base="$HOME/Library/Caches"
  else
    base="$HOME/.cache"
  fi

  [[ -n $app ]] && base="$base/$app"
  printf '%s' "$base"
}

#######################################
# Resolve the user's XDG state directory. XDG_STATE_HOME always wins when
# set; otherwise falls back to the platform-native default. gopskit has no
# equivalent of its own (no State field anywhere in its PlatformPaths) --
# ~/Library/<app>/State on Darwin is this module's own extrapolation from
# data_home's shape, not sourced from gopskit.
# Globals:
#   HOME, XDG_STATE_HOME
# Arguments:
#   1 - App name to nest under the base directory (optional)
# Outputs:
#   The resolved path to stdout.
#######################################
function lib::os::state_home() {
  local app=${1:-} base

  if [[ -n ${XDG_STATE_HOME:-} ]]; then
    base="$XDG_STATE_HOME"
    [[ -n $app ]] && base="$base/$app"
  elif [[ $(uname) == "Darwin" ]]; then
    base="$HOME/Library"
    [[ -n $app ]] && base="$base/$app/State"
  else
    base="$HOME/.local/state"
    [[ -n $app ]] && base="$base/$app"
  fi

  printf '%s' "$base"
}

# Work with packages and executables.

function lib::os::is_executable() {
  local package=${1}

  if [[ -z $package ]]; then
    return 1
  fi

  command_package=$(command -v "$package")
  if [[ -z $command_package ]]; then
    return 1
  fi

  return 0
}

# Run commands with elevated privileges.

# Check if the current user is root
function lib::os::root_check() {
  if [[ $EUID -ne 0 ]]; then
    return 1
  else
    return 0
  fi
}

# Prefix commands with sudo or not
function lib::os::root_exec() {
  if [[ $EUID -ne 0 ]]; then
    sudo "$@"
  else
    "$@"
  fi
}

#######################################
# Reload the rc files for Bash (and/or Zsh).
# Globals:
#   HOME (read)
# Arguments:
#   None
# Returns:
#   0, whether or not either file exists.
#######################################
function lib::os::rc() {
  # shellcheck disable=SC1090,SC1091 # caller-owned rc file
  if [ -e "${HOME}/.bashrc" ]; then source "${HOME}/.bashrc"; fi
  # shellcheck disable=SC1090,SC1091 # caller-owned rc file
  if [ -e "${HOME}/.zshrc" ]; then source "${HOME}/.zshrc"; fi

  return 0
}
