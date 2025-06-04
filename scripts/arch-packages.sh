#!/usr/bin/env bash
#
# Manage the packages of your Arch Linux installation.

# Mitigate potential path issues depending on where you're running the script from
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# shellcheck source=lib/log.sh
. "$LIB_DIR"/log.sh

# shellcheck source=lib/perm.sh
. "$LIB_DIR"/perm.sh

# -------------------------
#   GLOBAL defaults
# -------------------------

MIRROR_COUNTRIES="Germany,Netherlands,Sweden,Belgium,France,Austria"

#######################################
# Print the usage output for the script.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Writes usage to stdout
#######################################
function arch_packages::usage() {
  local script_name

  script_name=$(basename "${0}")

  echo "$script_name"
  echo
  echo "Manage the packages of your Arch Linux installation."
  echo
  echo "Usage: ./scripts/$script_name <COMMAND>"
  echo
  echo "help    - Print this usage information"
  echo "deps    - Show the required dependencies to run this script"
  echo
  echo "Examples:"
  echo "  ./scripts/$script_name (with configured Globals)"
  echo "  ./scripts/$script_name mysql://db_user:db_password@127.0.0.1:3306/db_name"
  echo "  ./scripts/$script_name mysql://db_user:db_password@127.0.0.1:3306/db_name ./Backups"
}

#######################################
# Check if the required dependencies for
# the scripts are installed.
# Arguments:
#   None
# Returns:
#   0 if all dependencies were found, 1 otherwise.
#######################################
function arch_packages::deps() {
  local deps=('pacman' 'yay')

  for dep in "${deps[@]}"; do
    package::is_executable "${dep}"
    rc=$?

    if [ $rc -ne 0 ]; then
      log::red "Could not find package '${dep}' in system PATH. Please install '${dep}' to proceed!"
      return 1
    fi

    log::green "Found package '${dep}' in system PATH."
  done

  log::green "Found all dependant packages: '${deps[*]}' in system PATH. Ready to proceed!"
  return 0
}

#######################################
# Update the system using the 'yay' and
# 'pacman' package managers.
# Arguments:
#   None
# Returns:
#   The parent exist code of the tool.
#######################################
arch_packages::update() {
  local tools=("pacman" "yay")
  log::green "Updating system packages with ${tools[0]}"
  perm::run_as_root "${tools[0]}" -Su

  log::green "Updating system packages with ${tools[1]}"
  "${tools[1]}" -Su
}

#######################################
# Update the system mirrors using the
# 'reflector' tool.
# Globals:
#   MIRROR_COUNTRIES
# Arguments:
#   None
# Returns:
#   The parent exist code of the tool.
#######################################
arch_packages::mirrors() {
  sudo reflector \
    --save /etc/pacman.d/mirrorlist \
    --country "$MIRROR_COUNTRIES" \
    --protocol https \
    --latest 10
}

# --------------------------------
#   MAIN
# --------------------------------
function main() {
  local cmd=${1}

  case "${cmd}" in
  help)
    arch_packages::usage
    ;;
  deps)
    arch_packages::deps
    return $?
    ;;
  update)
    arch_packages::update
    return $?
    ;;
  mirrors)
    arch_packages::mirrors
    return $?
    ;;
  *)
    log::yellow "Unknown command: ${cmd}. See 'help' command for usage information:"
    arch_packages::usage
    return $?
    ;;
  esac
}

# ------------
# 'main' call
# ------------
main "$@"
