#!/usr/bin/env bash
#
# Compare DNS zones across two different nameservers.

# Mitigate potential path issues depending on where you're running the script from
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)

LIB_DIR="$(dirname "$SCRIPT_DIR")/lib"

# shellcheck source=lib/log.sh
. "${LIB_DIR}"/log.sh

# shellcheck source=lib/package.sh
. "${LIB_DIR}"/package.sh

# -------------------------
#   GLOBAL defaults
# -------------------------

ZONE=${1}
NS1=${2:-"8.8.8.8"}
NS2=${3:-"1.1.1.1"}

#######################################
# Print the usage output for the script.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   Writes usage to stdout
#######################################
function dig_compare_zones::usage() {
  local script_name

  script_name=$(basename "${0}")

  echo "$script_name"
  echo
  echo "Compare DNS zones across nameservers."
  echo
  echo "Usage: ./scripts/$script_name <ZONE> [NS1] [NS2]"
  echo
  echo "help    - Print this usage information"
  echo "deps    - Show the required dependencies to run this script"
  echo
  echo "Examples:"
  echo "  ./scripts/$script_name adnoctem.co 8.8.8.8 1.1.1.1"
  echo "  ./scripts/$script_name adnoctem.co dns.google one.one.one.one"
  echo "  ./scripts/$script_name deps"
}

#######################################
# Check if the required dependencies for
# the script are installed.
# Arguments:
#   None
# Returns:
#   0 if all dependencies were found, 1 otherwise.
#######################################
function dig_compare_zones::deps() {
  local deps=('dig')

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
# Run the DNS zone comparison.
# Globals:
#   ZONE
#   NS1
#   NS2
# Arguments:
#   The DNS zone to compare.
#   The IP or hostname of nameserver 1.
#   The IP or hostname of nameserver 2.
# Returns:
#   0 if the source path does not exist.
#   Otherwise the parent return value of 'tar'.
#######################################
function dig_compare_zones::run() {
  local errors warnings record_types

  declare -i errors=0
  declare -i warnings=0
  declare -a record_types=('A' 'AAAA' 'CNAME' 'MX' 'TXT' 'NS' 'SOA' 'ANY')

  for type in "${record_types[@]}"; do
    result_ns1=$(dig "${type}" "@${NS1}" "${ZONE}" +short | sort)
    result_ns2=$(dig "${type}" "@${NS2}" "${ZONE}" +short | sort)
    result="\e[34mNameserver ${NS1}:\e[0m\n${result_ns1}\n\n\e[34mNameserver ${NS2}:\e[0m\n${result_ns2}\n"

    if [[ ${result_ns1} != "${result_ns2}" ]]; then
      case "${type}" in
      A | a)
        errors+=1
        log::yellow "${type} record differs across nameservers, please examine values:"
        echo -e "${result}"
        ;;
      AAAA | aaaa)
        errors+=1
        log::yellow "${type} record differs across nameservers, please examine values:"
        echo -e "${result}"
        ;;
      CNAME | cname)
        errors+=1
        log::yellow "${type} record differs across nameservers, please examine values:"
        echo -e "${result}"
        ;;
      MX | mx)
        errors+=1
        log::yellow "${type} record differs across nameservers, please examine values:"
        echo -e "${result}"
        ;;
      TXT | txt)
        errors+=1
        log::yellow "${type} record differs across nameservers, please examine values:"
        echo -e "${result}"
        ;;
      NS | ns)
        warnings+=1
        log::yellow "${type} record differs across nameservers, please examine values:"
        echo -e "${result}"
        ;;
      SOA | soa)
        warnings+=1
        log::yellow "${type} record differs across nameservers, please examine values:"
        echo -e "${result}"
        ;;
      ANY | any)
        warnings+=1
        log::yellow "${type} record differs across nameservers, please examine values:"
        echo -e "${result}"
        ;;
      esac
    else
      log::green "${type} record matches across nameservers '${NS1}' and '${NS2}'!"
    fi
  done

  log::cyan "Comparison of DNS zone ${ZONE} across nameservers: '${NS1}' and '${NS2}' returned ${errors} errors and ${warnings} warnings."
}

# --------------------------------
#   MAIN
# --------------------------------
function main() {
  local cmd=${1}

  case "${cmd}" in
  help)
    dig_compare_zones::usage
    ;;
  deps)
    dig_compare_zones::deps
    return $?
    ;;
  *)
    dig_compare_zones::run "$@"
    return $?
    ;;
  esac
}

# ------------
# 'main' call
# ------------
main "$@"
