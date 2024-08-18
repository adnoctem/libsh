# shellcheck shell=bash

# Bash functions for working with paths.

# Ensure a base-directory for a given path exists
paths::ensure_existence() {
  local path=${1}

  if [[ ! -e "${path}" ]]; then
    mkdir -p "$(dirname "${path}")"
  fi
}
