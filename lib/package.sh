# shellcheck shell=bash

# Work with packages and executables.

package::is_executable() {
  local package=${1}

  if [[ -z "$package" ]]; then
    return 1
  fi

  command_package=$(command -v "$package")
  if [[ -z "$command_package" ]]; then
    return 1
  fi

  return 0
}
