# shellcheck shell=bash

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
function ext::py::venv() {
  local venv activate python

  venv="$(pwd)/.venv"
  activate="$venv/bin/activate"

  if [[ ! -e $activate ]]; then
    # Ubuntu and Debian ship 'python3' with no unversioned 'python'.
    python=python3
    command -v python3 >/dev/null 2>&1 || python=python

    "$python" -m venv "$venv" || return $?
  fi

  # shellcheck disable=SC1090 # activation path determined at runtime
  source "$activate"
}
