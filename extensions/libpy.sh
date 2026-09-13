# shellcheck shell=bash

# Create and activate Python virtual environments.

#######################################
# Activate a Python venv in this shell, creating an absent path first.
# Existing incomplete paths are refused rather than overwritten. --python
# selects the creation interpreter only; existing environments are activated
# as-is. Failed creation can leave a partial directory for caller inspection.
# Globals:
#   Activation may modify PATH, VIRTUAL_ENV, the prompt and shell functions.
# Arguments:
#   1 - Optional venv path (default .venv in the current directory)
#   2+ - Optional --python COMMAND_OR_PATH (default python3, then python)
# Outputs:
#   Python/activation output; errors to stderr.
# Returns:
#   Creation/activation status; 1 incomplete path/missing interpreter,
#   2 invalid invocation. Activation failures may partially change the shell.
#######################################
function ext::py::venv() {
  local venv=$PWD/.venv activate python
  # shellcheck disable=SC2034 # consumed through parser dynamic scope
  local -a OPTS=('--python,:python:1:optional')
  # shellcheck disable=SC2034
  local -A OPTS_HELP=([python]='Creation interpreter') OPTS_VALUES=()

  if [[ $# -gt 0 && $1 != --* ]]; then
    [[ -n $1 ]] || return 2
    venv=$1
    shift
  fi
  lib::opt::parse ${1+"$@"} || return 2
  [[ ! ${OPTS_VALUES[python]+set} || -n ${OPTS_VALUES[python]} ]] || return 2
  [[ $venv == /* ]] || venv=$PWD/$venv
  activate=$venv/bin/activate

  if [[ ! -e $venv && ! -L $venv ]]; then
    python=${OPTS_VALUES[python]:-python3}
    if [[ ! ${OPTS_VALUES[python]+set} ]] && ! command -v "$python" >/dev/null 2>&1; then
      python=python
    fi
    command -v "$python" >/dev/null 2>&1 || return 1
    "$python" -m venv "$venv" || return $?
  fi

  if [[ ! -f $activate || ! -r $activate ]]; then
    lib::log::print_error 'The venv path has no readable activation script.'
    return 1
  fi

  # shellcheck disable=SC1090 # caller-selected activation script
  source "$activate"
}
