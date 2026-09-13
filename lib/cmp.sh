# shellcheck shell=bash

# Version, byte-count, filesystem attribute and content comparisons.

#######################################
# Compare normalized nonnegative decimal strings of arbitrary length.
# Globals:
#   None
# Arguments:
#   1 - Normalized nonnegative left decimal (no leading zeros except zero)
#   2 - Normalized nonnegative right decimal (no leading zeros except zero)
# Outputs:
#   -1, 0 or 1 and newline.
# Returns:
#   0 success.
#######################################
function __libsh_cmp_decimal() {
  local LC_ALL=C

  if [[ $1 == "$2" ]]; then
    printf '0\n'
  elif [[ ${#1} -lt ${#2} || (${#1} -eq ${#2} && $1 < $2) ]]; then
    printf '%s\n' -1
  else
    printf '1\n'
  fi
}

#######################################
# Compare complete SemVer 2.0.0 versions by precedence, ignoring build
# metadata.
# Specification: https://semver.org/spec/v2.0.0.html#spec-item-11
# Globals:
#   None
# Arguments:
#   1 - Left operand
#   2 - Right operand
# Outputs:
#   -1 (left older), 0 (equal precedence), 1 (left newer); errors stderr.
# Returns:
#   0 compared, 2 invalid invocation/version. No integer-size limit.
#######################################
function lib::cmp::semver_compare() {
  if [[ $# != 2 ]] || ! lib::core::semver_validate "$1" || ! lib::core::semver_validate "$2"; then
    lib::log::red 'semver_compare requires two complete valid versions.'
    return 2
  fi

  local LC_ALL=C field left right order i
  local -a left_parts right_parts

  for field in major minor patch; do
    left=$(lib::core::semver_parse "$1" "$field") || return 2
    right=$(lib::core::semver_parse "$2" "$field") || return 2

    order=$(__libsh_cmp_decimal "$left" "$right")
    if [[ $order != 0 ]]; then
      printf '%s\n' "$order"
      return 0
    fi
  done

  left=$(lib::core::semver_parse "$1" prerelease) || return 2
  right=$(lib::core::semver_parse "$2" prerelease) || return 2

  if [[ $left == "$right" ]]; then
    printf '0\n'
    return 0
  fi

  if [[ -z $left ]]; then
    printf '1\n'
    return 0
  fi

  if [[ -z $right ]]; then
    printf '%s\n' -1
    return 0
  fi

  IFS=. read -r -a left_parts <<<"$left"
  IFS=. read -r -a right_parts <<<"$right"

  for ((i = 0; i < ${#left_parts[@]} && i < ${#right_parts[@]}; i++)); do
    left=${left_parts[$i]} right=${right_parts[$i]}
    [[ $left != "$right" ]] || continue

    if [[ $left =~ ^[0-9]+$ && $right =~ ^[0-9]+$ ]]; then
      __libsh_cmp_decimal "$left" "$right"
    elif [[ $left =~ ^[0-9]+$ ]]; then
      printf '%s\n' -1
    elif [[ $right =~ ^[0-9]+$ ]]; then
      printf '1\n'
    elif [[ $left < $right ]]; then
      printf '%s\n' -1
    else
      printf '1\n'
    fi
    return 0
  done

  __libsh_cmp_decimal "${#left_parts[@]}" "${#right_parts[@]}"
}

#######################################
# Compare logical byte counts; use data helpers to convert explicit units
# first.
# Globals:
#   None
# Arguments:
#   1 - Left byte count (nonnegative signed 64-bit range)
#   2 - Right byte count (nonnegative signed 64-bit range)
# Outputs:
#   -1, 0 or 1 and newline; errors stderr.
# Returns:
#   0 compared, 2 invalid invocation/byte count.
#######################################
function lib::cmp::size_compare() {
  local left right

  if [[ $# != 2 ]] || ! left=$(__libsh_data_uint "$1") || ! right=$(__libsh_data_uint "$2"); then
    lib::log::red 'size_compare requires two nonnegative byte counts within signed 64-bit range.'
    return 2
  fi

  __libsh_cmp_decimal "$left" "$right"
}

#######################################
# Read normalized filesystem attributes, without reading file contents.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Path
#   2 - Entry type: file, directory or link
# Outputs:
#   Mode, UID, GID, mtime seconds, and (except directories) logical size.
# Returns:
#   0 success, 2 metadata failure.
#######################################
function __libsh_cmp_attributes() {
  local record mode uid gid modified size follow=follow

  [[ $2 != link ]] || follow=nofollow
  record=$(__libsh_fs_stat "$1" attributes "$follow") || return 2

  if [[ ! $record =~ ^[0-7]{1,4}\ [0-9]+\ [0-9]+\ -?[0-9]+\ [0-9]+$ ]]; then
    lib::log::red 'Invalid filesystem attribute record.'
    return 2
  fi

  IFS=' ' read -r mode uid gid modified size <<<"$record"
  size=$(__libsh_data_uint "$size") || return 2
  mode=$((8#$mode))
  printf '%s %s %s %s' "$mode" "$uid" "$gid" "$modified"
  [[ $2 == directory ]] || printf ' %s' "$size"
  printf '\n'
}

#######################################
# Test equality of regular-file attributes, following explicit symlink inputs.
# Compares size, mode (including special bits), numeric UID/GID, whole-second
# mtime. Ignores contents, inode, atime, ctime, ACLs, xattrs, and subsecond
# times.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Left operand
#   2 - Right operand
# Outputs:
#   Errors stderr; no comparison data on stdout.
# Returns:
#   0 equal, 1 different, 2 invalid input or metadata failure.
# Dependencies:
#   uname and platform stat. Use file_diff for content differences.
#######################################
function lib::cmp::file_compare() {
  if [[ $# != 2 || ! -f ${1:-} || ! -f ${2:-} ]]; then
    lib::log::red 'file_compare requires two existing regular files.'
    return 2
  fi

  local left right

  left=$(__libsh_cmp_attributes "$1" file) || return 2
  right=$(__libsh_cmp_attributes "$2" file) || return 2
  [[ $left == "$right" ]]
}

#######################################
# Print a unified content diff of two regular files, including binary
# detection.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Left operand
#   2 - Right operand
# Outputs:
#   Diff on stdout, errors stderr. A literal '-' is a filename, not stdin.
# Returns:
#   0 same contents, 1 different, 2 invalid input or diff failure.
# Dependencies:
#   diff (GNU or macOS). No ignore or whitespace normalization flags.
#######################################
function lib::cmp::file_diff() {
  if [[ $# != 2 || ! -f ${1:-} || ! -f ${2:-} || ! -r $1 || ! -r $2 ]]; then
    lib::log::red 'file_diff requires two readable regular files.'
    return 2
  fi

  local left=$1 right=$2 status

  [[ $left == /* ]] || left=./$left
  [[ $right == /* ]] || right=./$right

  if diff -u -- "$left" "$right"; then
    return 0
  else
    status=$?
  fi

  [[ $status == 1 ]] && return 1
  lib::log::red 'File diff failed.'
  return 2
}

#######################################
# Classify a tree entry without following symlinks.
# Globals:
#   None
# Arguments:
#   1 - PATH
# Outputs:
#   link, directory, file, or error on stderr.
# Returns:
#   0 classified, 2 missing/unsupported entry (FIFO/socket/device).
#######################################
function __libsh_cmp_type() {
  if [[ -L $1 ]]; then
    printf 'link\n'
  elif [[ -d $1 ]]; then
    printf 'directory\n'
  elif [[ -f $1 ]]; then
    printf 'file\n'
  else
    lib::log::red 'Tree comparison encountered a missing or unsupported entry.'
    return 2
  fi
}

#######################################
# Preflight all entries, including unmatched subtrees, before comparing trees.
# Globals:
#   None (requires dotglob/nullglob in caller's subshell)
# Arguments:
#   1 - Directory path
#   2 - Comparison mode: attributes or contents
# Outputs:
#   Errors stderr.
# Returns:
#   0 inspectable, 2 inaccessible or unsupported tree.
#######################################
function __libsh_cmp_tree_check() {
  local entry type

  if [[ ! -r $1 || ! -x $1 ]]; then
    lib::log::red 'Tree comparison requires readable/searchable directories.'
    return 2
  fi

  for entry in "$1"/*; do
    type=$(__libsh_cmp_type "$entry") || return 2
    case $type in
      directory) __libsh_cmp_tree_check "$entry" "$2" || return 2 ;;
      file)
        if [[ $2 == contents && ! -r $entry ]]; then
          lib::log::red 'Tree content comparison requires readable files.'
          return 2
        fi
        ;;
    esac
  done
}

#######################################
# Compare two symlink texts without losing trailing newlines during capture.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Left symlink path
#   2 - Right symlink path
# Outputs:
#   None; errors stderr.
# Returns:
#   0 identical link text, 1 different, 2 readlink failure.
#######################################
function __libsh_cmp_links() {
  local left right

  left=$(readlink -n "$1" && printf '.') || return 2
  right=$(readlink -n "$2" && printf '.') || return 2
  [[ $left == "$right" ]]
}

#######################################
# Compare matching tree roots recursively with deterministic glob traversal.
# Globals:
#   None (requires dotglob/nullglob and LC_ALL=C in caller's subshell)
# Arguments:
#   1 - Left directory
#   2 - Right directory
#   3 - Comparison mode: attributes or contents
# Outputs:
#   Content diffs/escaped mismatch paths in contents mode; errors stderr.
# Returns:
#   0 equal, 1 different, 2 inspection failure (takes precedence).
#######################################
function __libsh_cmp_tree() {
  local entry other left_type right_type left_attr right_attr status=0 result

  if [[ $3 == attributes ]]; then
    left_attr=$(__libsh_cmp_attributes "$1" directory) || return 2
    right_attr=$(__libsh_cmp_attributes "$2" directory) || return 2
    [[ $left_attr == "$right_attr" ]] || status=1
  fi

  for entry in "$1"/*; do
    other=$2/${entry##*/}

    if [[ ! -e $other && ! -L $other ]]; then
      [[ $3 != contents ]] || printf 'Only in %q: %q\n' "$1" "${entry##*/}"
      status=1
      continue
    fi

    left_type=$(__libsh_cmp_type "$entry") || return 2
    right_type=$(__libsh_cmp_type "$other") || return 2
    if [[ $left_type != "$right_type" ]]; then
      [[ $3 != contents ]] || printf 'Entry types differ: %q and %q\n' "$entry" "$other"
      status=1
      continue
    fi

    case $left_type in
      directory)
        if __libsh_cmp_tree "$entry" "$other" "$3"; then
          result=0
        else
          result=$?
        fi
        ;;
      link)
        if __libsh_cmp_links "$entry" "$other"; then
          result=0
        else
          result=$?
        fi
        if [[ $result == 1 && $3 == contents ]]; then
          printf 'Symbolic links differ: %q and %q\n' "$entry" "$other"
        fi
        ;;
      file)
        if [[ $3 == contents ]]; then
          if lib::cmp::file_diff "$entry" "$other"; then
            result=0
          else
            result=$?
          fi
        else
          result=0
        fi
        ;;
    esac

    [[ $result != 2 ]] || return 2
    [[ $result == 0 ]] || status=1

    if [[ $3 == attributes && $left_type != directory ]]; then
      left_attr=$(__libsh_cmp_attributes "$entry" "$left_type") || return 2
      right_attr=$(__libsh_cmp_attributes "$other" "$right_type") || return 2
      [[ $left_attr == "$right_attr" ]] || status=1
    fi
  done

  for entry in "$2"/*; do
    other=$1/${entry##*/}
    if [[ ! -e $other && ! -L $other ]]; then
      [[ $3 != contents ]] || printf 'Only in %q: %q\n' "$2" "${entry##*/}"
      status=1
    fi
  done

  return "$status"
}

#######################################
# Validate roots and isolate traversal options for directory comparisons.
# Globals:
#   None; cwd, options, locale and traps are preserved in the caller.
# Arguments:
#   1 - Comparison mode: attributes or contents
#   2 - Left directory
#   3 - Right directory
# Outputs:
#   As __libsh_cmp_tree.
# Returns:
#   0 equal, 1 different, 2 invalid or inaccessible inputs.
#######################################
function __libsh_cmp_directories() {
  if [[ $# != 3 || ! -d ${2:-} || ! -d ${3:-} ]]; then
    lib::log::red 'Directory comparison requires two existing directories.'
    return 2
  fi

  (
    local LC_ALL=C left=$2 right=$3
    [[ $left == /* ]] || left=./$left
    [[ $right == /* ]] || right=./$right
    unset GLOBIGNORE
    set +f
    shopt -u failglob
    shopt -s dotglob nullglob
    __libsh_cmp_tree_check "$left" "$1" || return 2
    __libsh_cmp_tree_check "$right" "$1" || return 2
    __libsh_cmp_tree "$left" "$right" "$1"
  )
}

#######################################
# Test recursive equality of relative paths, entry types and attributes.
# Includes root and child mode/UID/GID/whole-second mtime and file/link size.
# Ignores directory inode sizes. Compares symlink text without following
# links;
# counts hard-linked paths independently; crosses mounts; includes hidden
# files.
# Excludes file contents, ACLs, xattrs and subsecond timestamps. Not a
# snapshot.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Left operand
#   2 - Right operand
# Outputs:
#   Errors stderr; no comparison data on stdout.
# Returns:
#   0 equal, 1 different, 2 invalid/inaccessible/unsupported entries.
# Dependencies:
#   uname, platform stat and readlink.
#######################################
function lib::cmp::dir_compare() {
  __libsh_cmp_directories attributes "$@"
}

#######################################
# Compare directory contents recursively without following child symlinks.
# Includes hidden entries, empty directories and symlink text; crosses mounts;
# ignores ownership, modes, times and hardlink topology. Never opens special
# files.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Left operand
#   2 - Right operand
# Outputs:
#   Unified file diffs and escaped path/type/link mismatches on stdout;
#   errors stderr. Output may be partial on an operational failure.
# Returns:
#   0 same contents/tree, 1 different, 2 invalid/unreadable/special entry.
# Dependencies:
#   diff and readlink. No snapshot guarantee for concurrent changes.
#######################################
function lib::cmp::dir_diff() {
  __libsh_cmp_directories contents "$@"
}
