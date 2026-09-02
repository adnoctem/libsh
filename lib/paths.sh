# shellcheck shell=bash

# Bash functions for working with paths.

# Ensure a base-directory for a given path exists
lib::paths::ensure_existence() {
  local path=${1}

  if [[ ! -e ${path} ]]; then
    mkdir -p "$(dirname "${path}")"
  fi
}

# Ensure a directory itself exists, rather than its parent
lib::paths::ensure_directory() {
  local path=${1}

  if [[ ! -d ${path} ]]; then
    mkdir -p "${path}"
  fi
}
