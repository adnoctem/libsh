# shellcheck shell=bash

#######################################
# Validate one nonempty path argument without accessing the filesystem.
# Globals: None
# Arguments: PATH
# Outputs: Invocation errors on stderr.
# Returns: 0 valid, 2 invalid invocation.
#######################################
function __libsh_fs_path() {
  if [[ $# != 1 || -z ${1:-} ]]; then
    lib::log::red 'Expected one nonempty path.'
    return 2
  fi
}

#######################################
# Normalize an absolute path lexically, preserving arbitrary filename bytes.
# Globals: None
# Arguments: Absolute path
# Outputs: Normalized absolute path followed by / (a capture sentinel).
# Returns: 0 success. Repeated slashes collapse; .. cannot ascend above root.
#######################################
function __libsh_fs_normalize() {
  local remaining=$1 part result='' count=0 i
  local -a parts=()
  while [[ -n $remaining ]]; do
    part=${remaining%%/*}
    if [[ $remaining == */* ]]; then remaining=${remaining#*/}; else remaining=''; fi
    case $part in
    '' | .) ;;
    ..)
      if ((count > 0)); then
        count=$((count - 1))
        unset 'parts[count]'
      fi
      ;;
    *)
      parts[count]=$part
      count=$((count + 1))
      ;;
    esac
  done
  for ((i = 0; i < count; i++)); do result+="/${parts[$i]}"; done
  printf '%s/' "$result"
}

#######################################
# Compute a lexical relative path; neither operand needs to exist.
# Globals: PWD (read as the logical base for relative operands)
# Arguments: PATH BASE (both nonempty; BASE denotes a directory)
# Outputs: Relative path and newline; identical paths produce '.'; errors stderr.
# Returns: 0 success, 2 invalid invocation or unavailable absolute PWD.
# Collapses repeated / and dot components. Symlinks are never resolved.
#######################################
function lib::fs::relativize() {
  if [[ $# != 2 || -z ${1:-} || -z ${2:-} ]]; then
    lib::log::red 'relativize requires PATH and BASE.'
    return 2
  fi
  local path=$1 base=$2 result='' part
  if [[ $path != /* || $base != /* ]]; then
    if [[ ${PWD:-} != /* ]]; then
      lib::log::red 'An absolute PWD is required for relative paths.'
      return 2
    fi
    [[ $path == /* ]] || path=$PWD/$path
    [[ $base == /* ]] || base=$PWD/$base
  fi
  path=$(__libsh_fs_normalize "$path")
  base=$(__libsh_fs_normalize "$base")
  # The final slash protects pathnames ending in newline during capture.
  path=${path#/} base=${base#/}
  while [[ -n $path && -n $base && ${path%%/*} == "${base%%/*}" ]]; do
    path=${path#*/} base=${base#*/}
  done
  while [[ -n $base ]]; do
    part=${base%%/*}
    base=${base#*/}
    [[ -z $part ]] || result+='../'
  done
  result+=${path%/}
  result=${result%/}
  printf '%s\n' "${result:-.}"
}

#######################################
# Read a supported stat field using the Linux or macOS command syntax.
# Globals: PATH (read)
# Arguments: PATH FIELD (size|uid|gid|user|group|attributes) [follow|nofollow]
# Outputs: Field plus newline; attributes are mode UID GID mtime-seconds size.
# Returns: 0 success, 1 stat/platform failure, 2 invalid field.
# Mode is octal; timestamps use whole seconds for portable comparisons.
#######################################
function __libsh_fs_stat() {
  local path=$1 field=$2 platform format
  local -a options=()
  [[ $path == /* ]] || path=./$path
  [[ ${3-follow} == nofollow ]] || options=(-L)
  platform=$(uname -s) || return 1
  case $platform in
  Linux)
    case $field in
    size) format=%s ;; uid) format=%u ;; gid) format=%g ;;
    user) format=%U ;; group) format=%G ;; attributes) format='%a %u %g %Y %s' ;;
    *) return 2 ;;
    esac
    stat ${options[@]+"${options[@]}"} -c "$format" -- "$path" || return 1
    ;;
  Darwin)
    case $field in
    size) format=%z ;; uid) format=%u ;; gid) format=%g ;;
    user) format=%Su ;; group) format=%Sg ;; attributes) format='%Mp%03Lp %u %g %m %z' ;;
    *) return 2 ;;
    esac
    stat ${options[@]+"${options[@]}"} -f "$format" "$path" || return 1
    ;;
  *)
    lib::log::red 'Filesystem metadata requires Linux or macOS.'
    return 1
    ;;
  esac
}

#######################################
# Read ownership, following a symlink supplied as PATH.
# Globals: PATH (read)
# Arguments: PATH [FIELD=uid (uid|gid|user|group)]
# Outputs: Numeric UID/GID or resolved user/group name and newline; errors stderr.
# Returns: 0 success, 1 lookup failure, 2 invalid invocation.
# Dependencies: uname and platform stat. Name lookup follows the host stat policy.
#######################################
function lib::fs::owner_get() {
  if [[ $# -lt 1 || $# -gt 2 || -z ${1:-} || ! ${2-uid} =~ ^(uid|gid|user|group)$ ]]; then
    lib::log::red 'owner_get requires PATH and an optional uid, gid, user, or group field.'
    return 2
  fi
  if [[ ! -e $1 ]]; then
    lib::log::red 'Ownership lookup requires an existing target.'
    return 1
  fi
  local value
  value=$(__libsh_fs_stat "$1" "${2-uid}") || return 1
  printf '%s\n' "$value"
}

#######################################
# Test for a directory, following symlinks as Bash file tests do.
# Globals: None
# Arguments: PATH
# Outputs: Invocation errors on stderr; otherwise none.
# Returns: 0 directory, 1 absent/not a directory, 2 invalid invocation.
#######################################
function lib::fs::dir_exists() {
  __libsh_fs_path "$@" || return 2
  [[ -d $1 ]]
}

#######################################
# Test for a regular file, following symlinks as Bash file tests do.
# Globals: None
# Arguments: PATH
# Outputs: Invocation errors on stderr; otherwise none.
# Returns: 0 regular file, 1 absent/not regular, 2 invalid invocation.
#######################################
function lib::fs::file_exists() {
  __libsh_fs_path "$@" || return 2
  [[ -f $1 ]]
}

#######################################
# Test whether an existing regular file has zero logical bytes.
# Globals: None
# Arguments: PATH (symlinks followed)
# Outputs: Invocation errors on stderr; otherwise none.
# Returns: 0 empty file, 1 absent/wrong type/nonempty, 2 invalid invocation.
#######################################
function lib::fs::file_empty() {
  __libsh_fs_path "$@" || return 2
  [[ -f $1 && ! -s $1 ]]
}

#######################################
# Test whether a directory contains no entries, including hidden entries.
# Globals: None; glob options are changed only inside a subshell.
# Arguments: PATH (explicit root symlink followed)
# Outputs: Errors on stderr; otherwise none.
# Returns: 0 empty directory, 1 absent/wrong type/nonempty, 2 invalid/unreadable.
#######################################
function lib::fs::dir_empty() {
  __libsh_fs_path "$@" || return 2
  [[ -d $1 ]] || return 1
  if [[ ! -r $1 || ! -x $1 ]]; then
    lib::log::red 'Directory is not readable/searchable.'
    return 2
  fi
  (
    unset GLOBIGNORE
    set +f
    shopt -u failglob
    shopt -s dotglob nullglob
    local -a entries=("$1"/*)
    [[ ${#entries[@]} == 0 ]]
  )
}

#######################################
# Test whether the current user can write/search an existing directory.
# Globals: None
# Arguments: PATH (symlinks followed)
# Outputs: Invocation errors on stderr; otherwise none.
# Returns: 0 writable/searchable directory, 1 false, 2 invalid invocation.
# Uses effective access tests; does not probe read-only mounts by writing.
#######################################
function lib::fs::dir_writable() {
  __libsh_fs_path "$@" || return 2
  [[ -d $1 && -w $1 && -x $1 ]]
}

#######################################
# Test whether the current user can write an existing regular file.
# Globals: None
# Arguments: PATH (symlinks followed)
# Outputs: Invocation errors on stderr; otherwise none.
# Returns: 0 writable regular file, 1 false, 2 invalid invocation.
# This is an access test, not a guarantee that a future write succeeds.
#######################################
function lib::fs::file_writable() {
  __libsh_fs_path "$@" || return 2
  [[ -f $1 && -w $1 ]]
}

#######################################
# Test execute access to an existing regular file, without running it.
# Globals: None
# Arguments: PATH (symlinks followed)
# Outputs: Invocation errors on stderr; otherwise none.
# Returns: 0 executable regular file, 1 false, 2 invalid invocation.
#######################################
function lib::fs::file_executable() {
  __libsh_fs_path "$@" || return 2
  [[ -f $1 && -x $1 ]]
}

#######################################
# Read logical file length in bytes, including sparse holes.
# Globals: PATH (read)
# Arguments: PATH (must resolve to a regular file; symlinks followed)
# Outputs: Nonnegative decimal bytes and newline; errors stderr.
# Returns: 0 success, 1 missing/wrong type/stat failure/overflow, 2 invalid args.
# Dependencies: uname and platform stat. Maximum is signed 64-bit bytes.
#######################################
function lib::fs::file_size() {
  __libsh_fs_path "$@" || return 2
  if [[ ! -f $1 ]]; then
    lib::log::red 'file_size requires an existing regular file.'
    return 1
  fi
  local size
  size=$(__libsh_fs_stat "$1" size) || return 1
  if ! size=$(__libsh_data_uint "$size"); then
    lib::log::red 'File size is outside the signed 64-bit byte range.'
    return 1
  fi
  printf '%s\n' "$size"
}

#######################################
# Sum a directory tree while the caller has enabled dotglob/nullglob.
# Globals: None
# Arguments: Directory path
# Outputs: Decimal logical bytes and newline; errors stderr.
# Returns: 0 success, 1 inaccessible tree, stat failure, or overflow.
#######################################
function __libsh_fs_dir_bytes() {
  local entry size total=0
  if [[ ! -d $1 || ! -r $1 || ! -x $1 ]]; then
    lib::log::red 'Directory is not readable/searchable.'
    return 1
  fi
  for entry in "$1"/*; do
    [[ ! -L $entry ]] || continue
    if [[ -d $entry ]]; then
      size=$(__libsh_fs_dir_bytes "$entry") || return 1
    elif [[ -f $entry ]]; then
      size=$(lib::fs::file_size "$entry") || return 1
    elif [[ -e $entry ]]; then
      continue
    else
      lib::log::red 'An entry disappeared during directory size inspection.'
      return 1
    fi
    if ((size > 9223372036854775807 - total)); then
      lib::log::red 'Directory size exceeds the signed 64-bit byte range.'
      return 1
    fi
    total=$((total + size))
  done
  printf '%s\n' "$total"
}

#######################################
# Sum logical regular-file bytes recursively, including hidden entries.
# Globals: PATH (read); glob options change only in a subshell.
# Arguments: PATH (explicit root symlink followed)
# Outputs: Nonnegative decimal bytes and newline, only after full success.
# Returns: 0 success, 1 missing/unreadable tree/stat failure/overflow, 2 bad args.
# Counts each hard-linked path; skips symlinks and special files below the root;
# crosses mount boundaries. Unreadable directories fail. File data is not read.
# This is not allocated disk usage or an atomic snapshot of a changing tree.
# Dependencies: uname and platform stat.
#######################################
function lib::fs::dir_size() {
  __libsh_fs_path "$@" || return 2
  local total
  if ! total=$(
    unset GLOBIGNORE
    set +f
    shopt -u failglob
    shopt -s dotglob nullglob
    __libsh_fs_dir_bytes "$1"
  ); then return 1; fi
  printf '%s\n' "$total"
}

#######################################
# Ensure the parent directory of a file path exists, without creating the file.
# Globals: PATH (read)
# Arguments: PATH
# Outputs: Errors stderr; otherwise none.
# Returns: 0 success, 1 mkdir failure, 2 invalid invocation.
# Dependencies: mkdir. Symlinks in the parent path are followed.
#######################################
function lib::fs::ensure_existence() {
  __libsh_fs_path "$@" || return 2
  local path=$1 parent
  # Preserve the former no-op for an existing path.
  [[ ! -e $path ]] || return 0
  while [[ $path == */ && $path != / ]]; do path=${path%/}; done
  case $path in
  /* | */*)
    parent=${path%/*}
    parent=${parent:-/}
    ;;
  *) parent=. ;;
  esac
  lib::fs::ensure_directory "$parent"
}

#######################################
# Ensure a directory itself exists.
# Globals: PATH (read)
# Arguments: PATH
# Outputs: Errors stderr; otherwise none.
# Returns: 0 success, 1 mkdir failure, 2 invalid invocation.
# Dependencies: mkdir. Existing directory symlinks are accepted.
#######################################
function lib::fs::ensure_directory() {
  __libsh_fs_path "$@" || return 2
  [[ ! -d $1 ]] || return 0
  mkdir -p -- "$1" || return 1
}
