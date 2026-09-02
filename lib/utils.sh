# shellcheck shell=bash
#
# Bash general utility functions.

# shellcheck disable=SC1090,SC1091 # the sourced paths only exist at runtime

#######################################
# Reload the rc files for Bash (and/or Zsh).
# Globals:
#   HOME (read)
# Arguments:
#   None
# Returns:
#   0, whether or not either file exists.
#######################################
function lib::utils::rc() {
  if [ -e "${HOME}/.bashrc" ]; then source "${HOME}/.bashrc"; fi
  if [ -e "${HOME}/.zshrc" ]; then source "${HOME}/.zshrc"; fi

  return 0
}

#######################################
# Activate the Python venv in the current directory, creating it first if
# it does not exist yet.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Whatever 'python -m venv' writes, when it has to create the venv.
# Returns:
#   0 on success, otherwise the return value of 'python -m venv'.
#######################################
function lib::utils::venv() {
  local venv activate python

  venv="$(pwd)/.venv"
  activate="$venv/bin/activate"

  if [[ ! -e $activate ]]; then
    # Ubuntu and Debian ship 'python3' with no unversioned 'python'.
    python=python3
    command -v python3 >/dev/null 2>&1 || python=python

    "$python" -m venv "$venv" || return $?
  fi

  source "$activate"
}
