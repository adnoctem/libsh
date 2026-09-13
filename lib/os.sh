# shellcheck shell=bash

# Bash functions for working with paths, including resolving the XDG Base
# Directory Specification's user directories.
#
# ref: https://specifications.freedesktop.org/basedir-spec/latest/

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
# Returns:
#   The final output command status.
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
# Returns:
#   The final output command status.
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
# Returns:
#   The final output command status.
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
# Returns:
#   The final output command status.
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

#######################################
# Check whether the shell can resolve a command without changing caller state.
# Globals:
#   PATH (read)
# Arguments:
#   1 - One command name (including builtins/functions).
# Outputs:
#   Errors on stderr for incorrect argument count; otherwise none.
# Returns:
#   0 available, 1 unavailable/empty, 2 incorrect argument count.
#######################################
function lib::os::is_executable() {
  if [[ $# != 1 ]]; then
    lib::log::red 'is_executable requires one command name.'
    return 2
  fi

  [[ -n $1 ]] || return 1
  command -v -- "$1" >/dev/null 2>&1
}

# Run commands with elevated privileges.

#######################################
# Check if the current user is root
# Globals:
#   EUID (read)
# Arguments:
#   None
# Outputs:
#   None
# Returns:
#   0 for root, 1 otherwise.
#######################################
function lib::os::root_check() {
  if [[ $EUID -ne 0 ]]; then
    return 1
  else
    return 0
  fi
}

#######################################
# Run a command directly as root, otherwise through sudo.
# Environment preservation is opt-in and remains subject to sudo policy.
# It applies to exported variables, not the caller's sourced shell functions.
# Globals:
#   EUID, PATH and the exported environment (read)
# Arguments:
#   1+ - Optional -e/--preserve-environment, optional --, then COMMAND and argv
# Outputs:
#   Command stdout and stderr, unchanged; invocation errors on stderr.
# Returns:
#   The command or sudo exit status; 2 for invalid options or a missing command.
#######################################
function lib::os::root_exec() {
  local preserve_environment=0

  # Parse only wrapper options; everything after COMMAND belongs to the command.
  while [[ $# -gt 0 ]]; do
    case $1 in
      -e | --preserve-environment)
        preserve_environment=1
        shift
        ;;
      --)
        shift
        break
        ;;
      -*)
        lib::log::red "Unknown root_exec option: $1"
        return 2
        ;;
      *) break ;;
    esac
  done

  if [[ $# == 0 || -z $1 ]]; then
    lib::log::red 'root_exec requires a command.'
    return 2
  fi

  if [[ $EUID -ne 0 ]]; then
    if [[ $preserve_environment == 1 ]]; then
      sudo -E -- "$@"
    else
      sudo -- "$@"
    fi
  else
    "$@"
  fi
}

#######################################
# Reload Bash configuration in the current shell. Zsh configuration is not
# read.
# Globals:
#   HOME (read); the sourced Bash configuration may change caller state.
# Arguments:
#   None
# Outputs:
#   Whatever the Bash configuration prints; invocation errors on stderr.
# Returns:
#   0 when absent, otherwise the source status; 2 for unexpected arguments.
#######################################
function lib::os::rc() {
  if [[ $# != 0 ]]; then
    lib::log::red 'rc takes no arguments.'
    return 2
  fi

  if [[ -e ${HOME}/.bashrc ]]; then
    # shellcheck disable=SC1090,SC1091 # caller-owned Bash configuration
    source "${HOME}/.bashrc"
    return $?
  fi

  return 0
}

#######################################
# Require Linux for platform-specific inspection and account backends.
# Globals:
#   PATH (read)
# Arguments:
#   None
# Outputs:
#   Errors to stderr.
# Returns:
#   0 on Linux, 1 otherwise or on platform lookup failure.
#######################################
function __libsh_os_linux() {
  local platform
  platform=$(uname -s) || return 1
  if [[ $platform != Linux ]]; then
    lib::log::red 'This operation requires Linux.'
    return 1
  fi
}

#######################################
# Read the kernel boot timestamp from /proc/stat, not /proc inode times.
# In a container this describes the exposed kernel, not container startup.
# Globals:
#   PATH (read)
# Arguments:
#   None
# Outputs:
#   Unix epoch seconds without a newline; errors to stderr.
# Returns:
#   0 success, 1 unavailable/malformed data, 2 invalid invocation.
#######################################
function lib::os::boot_time() {
  [[ $# == 0 ]] || return 2
  __libsh_os_linux || return 1
  local data key value extra result=''
  data=$(cat /proc/stat) || return 1

  while read -r key value extra; do
    [[ $key == btime ]] || continue
    [[ -z $result && -z $extra ]] || return 1
    result=$(__libsh_data_uint "$value") || return 1
  done <<<"$data"

  [[ -n $result ]] || return 1
  printf '%s' "$result"
}

#######################################
# Read the Linux machine ID, falling back to the D-Bus path if unreadable.
# Does not create an ID. Container images may expose a shared or unset ID.
# Globals:
#   PATH (read)
# Arguments:
#   None
# Outputs:
#   32 lowercase hexadecimal digits without a newline; errors to stderr.
# Returns:
#   0 success, 1 missing/invalid ID, 2 invalid invocation.
#######################################
function lib::os::machine_id() {
  [[ $# == 0 ]] || return 2
  __libsh_os_linux || return 1
  local LC_ALL=C value
  value=$(cat /etc/machine-id 2>/dev/null) || value=$(cat /var/lib/dbus/machine-id 2>/dev/null) || return 1

  [[ $value =~ ^[0-9a-f]{32}$ && $value != 00000000000000000000000000000000 ]] || return 1
  printf '%s' "$value"
}

#######################################
# Read a Linux memory counter in bytes from /proc/meminfo.
# These are the exposed kernel counters, not cgroup memory limits. Available
# memory requires MemAvailable; no estimate is substituted on older kernels.
# Globals:
#   PATH (read)
# Arguments:
#   1 - total (default), available, free, buffers, cached, swap-total, swap-free
# Outputs:
#   Integer bytes without a newline; errors to stderr.
# Returns:
#   0 success, 1 missing/malformed/overflowing counter, 2 invalid invocation.
#######################################
function lib::os::memory() {
  [[ $# -le 1 ]] || return 2
  local field=${1:-total} key data name value unit extra result=''
  case $field in
    total) key=MemTotal: ;;
    available) key=MemAvailable: ;;
    free) key=MemFree: ;;
    buffers) key=Buffers: ;;
    cached) key=Cached: ;;
    swap-total) key=SwapTotal: ;;
    swap-free) key=SwapFree: ;;
    *) return 2 ;;
  esac
  __libsh_os_linux || return 1
  data=$(cat /proc/meminfo) || return 1

  while read -r name value unit extra; do
    [[ $name == "$key" ]] || continue
    [[ -z $result && $unit == kB && -z $extra ]] || return 1
    result=$(lib::data::bytes_from "$value" KiB) || return 1
  done <<<"$data"

  [[ -n $result ]] || return 1
  printf '%s' "$result"
}

#######################################
# Identify the block-device source mounted at / on Linux.
# Returns the mounted partition/logical device, not an inferred physical parent.
# Overlay, network and other non-device roots fail. The device node need not
# be visible inside the caller's mount namespace.
# Globals:
#   PATH (read)
# Arguments:
#   None
# Outputs:
#   /dev path without a newline; errors to stderr.
# Returns:
#   0 success, 1 unavailable/non-device root, 2 invalid invocation.
# Dependencies:
#   findmnt from util-linux.
#######################################
function lib::os::disk_device_id() {
  [[ $# == 0 ]] || return 2
  __libsh_os_linux || return 1
  local LC_ALL=C device
  device=$(findmnt -n -r -o SOURCE --target /) || return 1
  [[ $device != *$'\n'* ]] || return 1
  device=${device%%\[*}

  [[ $device == /dev/?* && $device != *[[:space:][:cntrl:]\\]* ]] || return 1
  printf '%s' "$device"
}

#######################################
# Read a device's byte capacity from its fdisk -l Disk header.
# No partition changes are made. Access privileges belong to the caller;
# no sudo is invoked. Human-readable fdisk output is parsed under locale C.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Device path, typically returned by disk_device_id
# Outputs:
#   Integer bytes without a newline; errors to stderr.
# Returns:
#   0 success, 1 fdisk/unrecognized output failure, 2 invalid invocation.
# Dependencies:
#   fdisk from util-linux.
#######################################
function lib::os::disk_capacity() {
  [[ $# == 1 && -n $1 && $1 != -* && $1 != *[[:cntrl:]]* ]] || return 2
  __libsh_os_linux || return 1
  local data line result='' value
  local expression='^Disk .+: .*, ([0-9]+) bytes(,|$)'
  data=$(LC_ALL=C fdisk -l -- "$1") || return 1

  while IFS= read -r line; do
    [[ $line =~ $expression ]] || continue
    [[ -z $result ]] || return 1
    value=${BASH_REMATCH[1]}
    result=$(__libsh_data_uint "$value") || return 1
  done <<<"$data"

  [[ -n $result ]] || return 1
  printf '%s' "$result"
}

#######################################
# Decode quoting and backslash escapes in one os-release value as data.
# Shell expansions and commands are never evaluated.
# Globals:
#   None
# Arguments:
#   1 - Value following KEY=
# Outputs:
#   Decoded value followed by a dot sentinel.
# Returns:
#   0 decoded, 1 unmatched quote/escape or unquoted whitespace.
#######################################
function __libsh_os_release_value() {
  local value=$1 quote='' result='' char next i
  for ((i = 0; i < ${#value}; i++)); do
    char=${value:i:1}
    if [[ $quote == "'" ]]; then
      if [[ $char == "'" ]]; then
        quote=''
      else
        result+=$char
      fi
    elif [[ $char == "\\" ]]; then
      i=$((i + 1))
      [[ $i -lt ${#value} ]] || return 1
      next=${value:i:1}
      if [[ $quote == '"' && $next != [\$\`\"\\] ]]; then
        result+="\\"
      fi
      result+=$next
    elif [[ $char == '"' || ($char == "'" && -z $quote) ]]; then
      if [[ -z $quote ]]; then
        quote=$char
      else
        quote=''
      fi
    elif [[ -z $quote && $char == *[[:space:]]* ]]; then
      return 1
    else
      result+=$char
    fi
  done

  [[ -z $quote ]] || return 1
  printf '%s.' "$result"
}

#######################################
# Read one allowlisted Linux os-release field without sourcing shell code.
# Prefer /etc/os-release, with /usr/lib/os-release as the fallback. Later
# duplicate keys win. Branch uses BRANCH, falling back to VERSION_ID before
# its first dot. Other missing/empty fields fail.
# Globals:
#   PATH (read)
# Arguments:
#   1 - --id, --version, --branch, --codename, --name or --pretty-name
# Outputs:
#   Decoded field without a newline; errors to stderr.
# Returns:
#   0 success, 1 missing/malformed data, 2 invalid invocation/selector.
#######################################
function lib::os::metadata() {
  [[ $# == 1 ]] || return 2
  local key data line result='' found=0 fallback=''
  case $1 in
    --id) key=ID ;;
    --version) key=VERSION_ID ;;
    --branch) key=BRANCH ;;
    --codename) key=VERSION_CODENAME ;;
    --name) key=NAME ;;
    --pretty-name) key=PRETTY_NAME ;;
    *) return 2 ;;
  esac
  __libsh_os_linux || return 1
  data=$(cat /etc/os-release 2>/dev/null) || data=$(cat /usr/lib/os-release 2>/dev/null) || return 1

  while IFS= read -r line; do
    if [[ $key == BRANCH && $line == VERSION_ID=* ]]; then
      fallback=${line#*=}
    fi
    [[ $line == "$key="* ]] || continue
    result=$(__libsh_os_release_value "${line#*=}") || return 1
    result=${result%.}
    found=1
  done <<<"$data"

  if [[ $key == BRANCH && -z $result && -n $fallback ]]; then
    result=$(__libsh_os_release_value "$fallback") || return 1
    result=${result%.}
    result=${result%%.*}
    found=1
  fi

  [[ $found == 1 && -n $result ]] || return 1
  printf '%s' "$result"
}

#######################################
# Validate a portable Linux account name, excluding numeric lookup keys.
# Globals:
#   None
# Arguments:
#   1 - Name
# Outputs:
#   None
# Returns:
#   0 valid, 1 invalid.
#######################################
function __libsh_os_account_name() {
  local LC_ALL=C
  [[ ${#1} -le 32 && $1 =~ ^[a-zA-Z_][a-zA-Z0-9_-]*\$?$ ]]
}

#######################################
# Look up one validated NSS account record, distinguishing getent failures.
# Globals:
#   PATH (read)
# Arguments:
#   1 - passwd or group
#   2 - Name or numeric ID
# Outputs:
#   Record without a newline; errors to stderr.
# Returns:
#   0 found, 1 absent (getent status 2), 3 backend/malformed-record failure.
#######################################
function __libsh_os_account_record() {
  local record status colons name _ identifier rest
  __libsh_os_linux || return 3
  if record=$(getent "$1" "$2"); then
    [[ -n $record && $record != *$'\n'* ]] || return 3
  else
    status=$?
    [[ $status != 2 ]] || return 1
    return 3
  fi

  colons=${record//[^:]/}
  case $1 in
    passwd) [[ ${#colons} == 6 ]] || return 3 ;;
    group) [[ ${#colons} == 3 ]] || return 3 ;;
    *) return 3 ;;
  esac
  IFS=: read -r name _ identifier rest <<<"$record"
  [[ $identifier =~ ^[0-9]+$ ]] || return 3
  if [[ $2 =~ ^[0-9]+$ ]]; then
    [[ $identifier == "$2" ]] || return 3
  else
    [[ $name == "$2" ]] || return 3
  fi

  printf '%s' "$record"
}

#######################################
# Check whether a named Linux group exists through NSS.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Group name
# Outputs:
#   Backend errors to stderr; no stdout.
# Returns:
#   0 exists, 1 absent, 2 invalid invocation/name, 3 lookup failure.
#######################################
function lib::os::group_exists() {
  [[ $# == 1 ]] || return 2
  __libsh_os_account_name "$1" || return 2
  __libsh_os_account_record group "$1" >/dev/null
}

#######################################
# Check whether a named Linux user exists through NSS.
# Globals:
#   PATH (read)
# Arguments:
#   1 - User name
# Outputs:
#   Backend errors to stderr; no stdout.
# Returns:
#   0 exists, 1 absent, 2 invalid invocation/name, 3 lookup failure.
#######################################
function lib::os::user_exists() {
  [[ $# == 1 ]] || return 2
  __libsh_os_account_name "$1" || return 2
  __libsh_os_account_record passwd "$1" >/dev/null
}

#######################################
# Normalize a Linux UID/GID, excluding the reserved all-ones ID.
# Globals:
#   None
# Arguments:
#   1 - Decimal ID
# Outputs:
#   Normalized ID without a newline.
# Returns:
#   0 valid, 2 invalid.
#######################################
function __libsh_os_account_id() {
  local value
  value=$(__libsh_data_uint "$1") || return 2
  [[ $value -le 4294967294 ]] || return 2
  printf '%s' "$value"
}

#######################################
# Create a Linux group only when it does not already exist.
# Existing groups are reported and left unchanged, regardless of requested ID.
# --system forwards groupadd's configured system-account allocation policy.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Group name
#   2+ - Optional -i/--id GID, -s/--system
# Outputs:
#   Already-exists message on stdout; tool diagnostics to stderr.
# Returns:
#   0 created/already exists, 1 backend failure, 2 invalid invocation.
#######################################
function lib::os::group_ensure() {
  [[ $# -ge 1 ]] || return 2
  __libsh_os_account_command create group "$@"
}

#######################################
# Create a Linux user only when it does not already exist.
# Existing users are reported and left unchanged. Allocation and home creation
# follow useradd policy; --home supplies its home-directory argument only.
# Globals:
#   PATH (read)
# Arguments:
#   1 - User name
#   2+ - Optional -i/--id UID, -g/--group NAME_OR_GID,
#        -a/--append-groups COMMA_LIST, -h/--home ABSOLUTE_PATH, -s/--system
# Outputs:
#   Already-exists message on stdout; tool diagnostics to stderr.
# Returns:
#   0 created/already exists, 1 backend failure, 2 invalid invocation.
#######################################
function lib::os::user_ensure() {
  [[ $# -ge 1 ]] || return 2
  __libsh_os_account_command create user "$@"
}

#######################################
# Update the GID of an existing Linux group through groupmod.
# File ownership migration and other groupmod side effects follow the backend;
# this function does not recursively change files owned by the previous GID.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Group name
#   2+ - Required -i/--id GID
# Outputs:
#   Diagnostics to stderr; no stdout.
# Returns:
#   0 updated, 1 absent group/backend failure, 2 invalid invocation.
#######################################
function lib::os::group_update() {
  [[ $# -ge 1 ]] || return 2
  __libsh_os_account_command update group "$@"
}

#######################################
# Update explicit attributes of an existing Linux user through usermod.
# Supplementary groups are appended, never replaced. --home changes the account
# path without requesting a move. --system is a creation-only option.
# Globals:
#   PATH (read)
# Arguments:
#   1 - User name
#   2+ - At least one of -i/--id UID, -g/--group NAME_OR_GID,
#        -a/--append-groups COMMA_LIST, -h/--home ABSOLUTE_PATH
# Outputs:
#   Diagnostics to stderr; no stdout.
# Returns:
#   0 updated, 1 absent user/backend failure, 2 invalid invocation.
#######################################
function lib::os::user_update() {
  [[ $# -ge 1 ]] || return 2
  __libsh_os_account_command update user "$@"
}

#######################################
# Check existence and forward explicit account options to Linux frontends.
# Backend changes are not transactional and caller privileges are required.
# No sudo, automatic attribute reconciliation or rollback is performed.
# Globals:
#   PATH (read); parser arrays stay local.
# Arguments:
#   1 - create or update
#   2 - group or user
#   3 - Account name
#   4+ - Public ensure/update options
# Outputs:
#   Already-exists message on stdout; diagnostics to stderr.
# Returns:
#   0 success, 1 lookup/backend failure, 2 invalid options.
#######################################
function __libsh_os_account_command() {
  local operation=$1 kind=$2 account=$3 status value item tool
  local -a items=() arguments=()
  # shellcheck disable=SC2034 # consumed through parser dynamic scope
  local -a OPTS=('-i,--id:id:1:optional')
  # shellcheck disable=SC2034
  local -A OPTS_HELP=([id]='Numeric ID') OPTS_VALUES=()

  __libsh_os_account_name "$account" || return 2
  [[ $operation != create ]] || OPTS+=('-s,--system:system:0:optional')
  if [[ $kind == user ]]; then
    OPTS+=('-g,--group:group:1:optional' '-a,--append-groups:groups:1:optional' '-h,--home:home:1:optional')
  fi
  shift 3
  lib::opt::parse ${1+"$@"} || return 2

  if "lib::os::${kind}_exists" "$account"; then
    if [[ $operation == create ]]; then
      lib::log::plain "$kind '$account' already exists."
      return 0
    fi
  else
    status=$?
    [[ $status == 1 ]] || return 1
    if [[ $operation == update ]]; then
      lib::log::red "$kind '$account' does not exist."
      return 1
    fi
  fi

  if [[ ${OPTS_VALUES[id]+set} ]]; then
    value=$(__libsh_os_account_id "${OPTS_VALUES[id]}") || return 2
    if [[ $kind == group ]]; then
      arguments+=(--gid "$value")
    else
      arguments+=(--uid "$value")
    fi
  fi
  [[ ${OPTS_VALUES[system]:-0} != 1 ]] || arguments+=(--system)
  if [[ ${OPTS_VALUES[group]+set} ]]; then
    value=${OPTS_VALUES[group]}
    if [[ $value =~ ^[0-9]+$ ]]; then
      value=$(__libsh_os_account_id "$value") || return 2
    else
      __libsh_os_account_name "$value" || return 2
    fi
    arguments+=(--gid "$value")
  fi
  if [[ ${OPTS_VALUES[home]+set} ]]; then
    value=${OPTS_VALUES[home]}
    [[ $value == /* && $value != *[:$'\n\r']* ]] || return 2
    if [[ $operation == create ]]; then
      arguments+=(--home-dir "$value")
    else
      arguments+=(--home "$value")
    fi
  fi
  if [[ ${OPTS_VALUES[groups]+set} ]]; then
    value=${OPTS_VALUES[groups]}
    [[ -n $value && $value != ,* && $value != *, && $value != *,,* ]] || return 2
    IFS=, read -r -a items <<<"$value"
    value=''
    for item in "${items[@]}"; do
      if [[ $item =~ ^[0-9]+$ ]]; then
        item=$(__libsh_os_account_id "$item") || return 2
      else
        __libsh_os_account_name "$item" || return 2
      fi
      value+=${value:+,}$item
    done
    [[ $operation != update ]] || arguments+=(--append)
    arguments+=(--groups "$value")
  fi

  if [[ $operation == update ]]; then
    [[ ${arguments[0]+set} ]] || return 2
    tool=${kind}mod
  else
    tool=${kind}add
  fi
  "$tool" ${arguments[@]+"${arguments[@]}"} -- "$account" >&2 || return 1
}

#######################################
# Configure ownership and octal modes for a root path and its descendants.
# Follows links by default, including targets outside the root. With -n, links
# receive ownership changes only and their targets are never visited. Parent
# path components are resolved normally. Special files receive ownership only.
# Traversal is staged with NUL delimiters before mutation; directories are
# changed after their contents. Failed mutations are not rolled back, and
# concurrent path replacement is outside the contract.
# Globals:
#   PATH, TMPDIR (read); traps and parser arrays remain in this subshell.
# Arguments:
#   1 - One path (not a newline-separated list)
#   2+ - -f/--file-mode OCTAL, -d/--dir-mode OCTAL, -u/--user USER,
#        -g/--group GROUP, -n/--no-dereference; at least one change required
# Outputs:
#   Errors to stderr; no stdout.
# Returns:
#   0 success, 1 traversal/mutation failure, 2 invalid options/modes.
# Dependencies:
#   find, mktemp, rm, chmod, chown. Required privileges belong to the caller.
#######################################
function lib::os::recursive_configure() (
  [[ $# -ge 1 && -n $1 ]] || return 2
  local path=$1 entry owner='' file_mode='' dir_mode='' mode flag=-L
  local __libsh_os_paths=''
  # shellcheck disable=SC2034 # consumed through parser dynamic scope
  local -a OPTS=(
    '-f,--file-mode:file_mode:1:optional' '-d,--dir-mode:dir_mode:1:optional'
    '-u,--user:user:1:optional' '-g,--group:group:1:optional'
    '-n,--no-dereference:no_dereference:0:optional'
  )
  # shellcheck disable=SC2034
  local -A OPTS_HELP=() OPTS_VALUES=()
  local -a owner_options=()

  shift
  lib::opt::parse ${1+"$@"} || return 2
  if [[ ${OPTS_VALUES[file_mode]+set} ]]; then
    mode=${OPTS_VALUES[file_mode]}
    [[ $mode =~ ^[0-7]{1,4}$ ]] || return 2
    printf -v file_mode '0%04o' "$((8#$mode))"
  fi
  if [[ ${OPTS_VALUES[dir_mode]+set} ]]; then
    mode=${OPTS_VALUES[dir_mode]}
    [[ $mode =~ ^[0-7]{1,4}$ ]] || return 2
    # The extra zero explicitly clears directory set-ID bits with GNU chmod.
    printf -v dir_mode '0%04o' "$((8#$mode))"
  fi
  if [[ ${OPTS_VALUES[user]+set} ]]; then
    owner=${OPTS_VALUES[user]}
    [[ -n $owner && $owner != *:* ]] || return 2
  fi
  if [[ ${OPTS_VALUES[group]+set} ]]; then
    [[ -n ${OPTS_VALUES[group]} && ${OPTS_VALUES[group]} != *:* ]] || return 2
    owner+=:${OPTS_VALUES[group]}
  fi
  [[ -z $owner ]] || __libsh_fs_owner "$owner" || return 2
  [[ -n $owner || -n $file_mode || -n $dir_mode ]] || return 2

  if [[ ${OPTS_VALUES[no_dereference]:-0} == 1 ]]; then
    flag=-P
    owner_options=(-n)
  fi
  while [[ $path != / && $path == */ ]]; do
    path=${path%/}
  done
  [[ $path == /* ]] || path=./$path

  __libsh_os_paths=$(mktemp "${TMPDIR:-/tmp}/libsh-configure.XXXXXXXX") || return 1
  trap 'rm -f -- "$__libsh_os_paths"' EXIT
  trap 'exit 1' HUP INT TERM
  find "$flag" "$path" -depth -print0 >"$__libsh_os_paths" || return 1

  while IFS= read -r -d '' entry; do
    if [[ -n $owner ]]; then
      lib::fs::owner_set "$entry" "$owner" ${owner_options[@]+"${owner_options[@]}"} || return 1
    fi
    if [[ $flag == -P && -L $entry ]]; then
      continue
    fi

    if [[ -d $entry && -n $dir_mode ]]; then
      chmod "$dir_mode" "$entry" || return 1
    elif [[ -f $entry && -n $file_mode ]]; then
      chmod "$file_mode" "$entry" || return 1
    fi
  done <"$__libsh_os_paths"
)
