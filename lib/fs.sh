# shellcheck shell=bash

# Filesystem inspection, lexical paths, directory creation and staged text edits.

#######################################
# Validate one nonempty path argument without accessing the filesystem.
# Globals:
#   None
# Arguments:
#   1 - PATH
# Outputs:
#   Invocation errors on stderr.
# Returns:
#   0 valid, 2 invalid invocation.
#######################################
function __libsh_fs_path() {
  if [[ $# != 1 || -z ${1:-} ]]; then
    lib::log::red 'Expected one nonempty path.'
    return 2
  fi
}

#######################################
# Normalize an absolute path lexically, preserving arbitrary filename bytes.
# Globals:
#   None
# Arguments:
#   1 - Absolute path
# Outputs:
#   Normalized absolute path followed by / (a capture sentinel).
# Returns:
#   0 success. Repeated slashes collapse; .. cannot ascend above root.
#######################################
function __libsh_fs_normalize() {
  local remaining=$1 part result='' count=0 i
  local -a parts=()

  while [[ -n $remaining ]]; do
    part=${remaining%%/*}
    if [[ $remaining == */* ]]; then
      remaining=${remaining#*/}
    else
      remaining=''
    fi

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

  for ((i = 0; i < count; i++)); do
    result+="/${parts[$i]}"
  done

  printf '%s/' "$result"
}

#######################################
# Compute a lexical relative path; neither operand needs to exist.
# Collapses repeated / and dot components. Symlinks are never resolved.
# Globals:
#   PWD (read as the logical base for relative operands)
# Arguments:
#   1 - Nonempty path to express relatively
#   2 - Nonempty base directory path
# Outputs:
#   Relative path and newline; identical paths produce '.'; errors stderr.
# Returns:
#   0 success, 2 invalid invocation or unavailable absolute PWD.
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
# Mode is octal; timestamps use whole seconds for portable comparisons.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Path
#   2 - Field: size, uid, gid, user, group or attributes
#   3 - Link handling: follow or nofollow (optional, default follow)
# Outputs:
#   Field plus newline; attributes are mode UID GID mtime-seconds size.
# Returns:
#   0 success, 1 stat/platform failure, 2 invalid field.
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
        size) format=%s ;;
        uid) format=%u ;;
        gid) format=%g ;;
        user) format=%U ;;
        group) format=%G ;;
        attributes) format='%a %u %g %Y %s' ;;
        *) return 2 ;;
      esac

      stat ${options[@]+"${options[@]}"} -c "$format" -- "$path" || return 1
      ;;
    Darwin)
      case $field in
        size) format=%z ;;
        uid) format=%u ;;
        gid) format=%g ;;
        user) format=%Su ;;
        group) format=%Sg ;;
        attributes) format='%Mp%03Lp %u %g %m %z' ;;
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
# Globals:
#   PATH (read)
# Arguments:
#   1 - Path
#   2 - Field: uid, gid, user or group (optional, default uid)
# Outputs:
#   Numeric UID/GID or resolved user/group name and newline; errors stderr.
# Returns:
#   0 success, 1 lookup failure, 2 invalid invocation.
# Dependencies:
#   uname and platform stat. Name lookup follows the host stat policy.
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
# Globals:
#   None
# Arguments:
#   1 - PATH
# Outputs:
#   Invocation errors on stderr; otherwise none.
# Returns:
#   0 directory, 1 absent/not a directory, 2 invalid invocation.
#######################################
function lib::fs::dir_exists() {
  __libsh_fs_path "$@" || return 2
  [[ -d $1 ]]
}

#######################################
# Test for a regular file, following symlinks as Bash file tests do.
# Globals:
#   None
# Arguments:
#   1 - PATH
# Outputs:
#   Invocation errors on stderr; otherwise none.
# Returns:
#   0 regular file, 1 absent/not regular, 2 invalid invocation.
#######################################
function lib::fs::file_exists() {
  __libsh_fs_path "$@" || return 2
  [[ -f $1 ]]
}

#######################################
# Test whether an existing regular file has zero logical bytes.
# Globals:
#   None
# Arguments:
#   1 - PATH (symlinks followed)
# Outputs:
#   Invocation errors on stderr; otherwise none.
# Returns:
#   0 empty file, 1 absent/wrong type/nonempty, 2 invalid invocation.
#######################################
function lib::fs::file_empty() {
  __libsh_fs_path "$@" || return 2
  [[ -f $1 && ! -s $1 ]]
}

#######################################
# Test whether a directory contains no entries, including hidden entries.
# Globals:
#   None; glob options are changed only inside a subshell.
# Arguments:
#   1 - PATH (explicit root symlink followed)
# Outputs:
#   Errors on stderr; otherwise none.
# Returns:
#   0 empty directory, 1 absent/wrong type/nonempty, 2 invalid/unreadable.
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
# Uses effective access tests; does not probe read-only mounts by writing.
# Globals:
#   None
# Arguments:
#   1 - PATH (symlinks followed)
# Outputs:
#   Invocation errors on stderr; otherwise none.
# Returns:
#   0 writable/searchable directory, 1 false, 2 invalid invocation.
#######################################
function lib::fs::dir_writable() {
  __libsh_fs_path "$@" || return 2
  [[ -d $1 && -w $1 && -x $1 ]]
}

#######################################
# Test whether the current user can write an existing regular file.
# This is an access test, not a guarantee that a future write succeeds.
# Globals:
#   None
# Arguments:
#   1 - PATH (symlinks followed)
# Outputs:
#   Invocation errors on stderr; otherwise none.
# Returns:
#   0 writable regular file, 1 false, 2 invalid invocation.
#######################################
function lib::fs::file_writable() {
  __libsh_fs_path "$@" || return 2
  [[ -f $1 && -w $1 ]]
}

#######################################
# Test execute access to an existing regular file, without running it.
# Globals:
#   None
# Arguments:
#   1 - PATH (symlinks followed)
# Outputs:
#   Invocation errors on stderr; otherwise none.
# Returns:
#   0 executable regular file, 1 false, 2 invalid invocation.
#######################################
function lib::fs::file_executable() {
  __libsh_fs_path "$@" || return 2
  [[ -f $1 && -x $1 ]]
}

#######################################
# Read logical file length in bytes, including sparse holes.
# Globals:
#   PATH (read)
# Arguments:
#   1 - PATH (must resolve to a regular file; symlinks followed)
# Outputs:
#   Nonnegative decimal bytes and newline; errors stderr.
# Returns:
#   0 success, 1 missing/wrong type/stat failure/overflow, 2 invalid args.
# Dependencies:
#   uname and platform stat. Maximum is signed 64-bit bytes.
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
# Globals:
#   None
# Arguments:
#   1 - Directory path
# Outputs:
#   Decimal logical bytes and newline; errors stderr.
# Returns:
#   0 success, 1 inaccessible tree, stat failure, or overflow.
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
# Counts each hard-linked path; skips symlinks and special files below the
# root;
# crosses mount boundaries. Unreadable directories fail. File data is not
# read.
# This is not allocated disk usage or an atomic snapshot of a changing tree.
# Globals:
#   PATH (read); glob options change only in a subshell.
# Arguments:
#   1 - PATH (explicit root symlink followed)
# Outputs:
#   Nonnegative decimal bytes and newline, only after full success.
# Returns:
#   0 success, 1 missing/unreadable tree/stat failure/overflow, 2 bad args.
# Dependencies:
#   uname and platform stat.
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
  ); then
    return 1
  fi

  printf '%s\n' "$total"
}

#######################################
# Ensure the parent directory of a file path exists, without creating the
# file.
# Globals:
#   PATH (read)
# Arguments:
#   1 - PATH
# Outputs:
#   Errors stderr; otherwise none.
# Returns:
#   0 success, 1 mkdir failure, 2 invalid invocation.
# Dependencies:
#   mkdir. Symlinks in the parent path are followed.
#######################################
function lib::fs::ensure_existence() {
  __libsh_fs_path "$@" || return 2
  local path=$1 parent

  # Preserve the former no-op for an existing path.
  [[ ! -e $path ]] || return 0

  while [[ $path == */ && $path != / ]]; do
    path=${path%/}
  done

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
# Globals:
#   PATH (read)
# Arguments:
#   1 - PATH
# Outputs:
#   Errors stderr; otherwise none.
# Returns:
#   0 success, 1 mkdir failure, 2 invalid invocation.
# Dependencies:
#   mkdir. Existing directory symlinks are accepted.
#######################################
function lib::fs::ensure_directory() {
  __libsh_fs_path "$@" || return 2
  [[ ! -d $1 ]] || return 0
  mkdir -p -- "$1" || return 1
}

#######################################
# Resolve an editing target through its physical parent and optional links.
# Globals:
#   None; directory changes stay in the subshell.
# Arguments:
#   1 - Nonempty path
#   2 - 1 to reject a final symlink, 0 to follow it
# Outputs:
#   Absolute target followed by a dot sentinel; errors to stderr.
# Returns:
#   0 on success, 1 on missing parents, refused links or a link loop.
# Dependencies:
#   readlink, only when following a symlink.
#######################################
function __libsh_fs_edit_target() (
  local path=$1 parent name target count=0

  while :; do
    [[ $path == /* ]] || path=./$path
    parent=${path%/*}
    name=${path##*/}
    parent=${parent:-/}

    cd -P -- "$parent" || return 1
    path=$PWD/$name
    [[ -L $path ]] || break

    if [[ $2 == 1 || $count == 40 ]]; then
      lib::log::red 'Editing refused a symlink or an excessive link chain.'
      return 1
    fi

    target=$(readlink -n "$path" && printf '.') || return 1
    path=${target%.}
    count=$((count + 1))
  done

  printf '%s.' "$path"
)

#######################################
# Encode a pattern or replacement for a generated sed script.
# User text remains data: real newlines are escaped and trailing backslashes
# are rejected. Replacement escapes are limited to portable sed syntax.
# Globals:
#   None
# Arguments:
#   1 - pattern or replacement
#   2 - Text to encode
# Outputs:
#   Encoded text followed by a dot sentinel; errors to stderr.
# Returns:
#   0 on success, 2 for a trailing or unsupported replacement escape.
#######################################
function __libsh_fs_edit_escape() {
  local kind=$1 value=$2 encoded='' character next i

  for ((i = 0; i < ${#value}; i++)); do
    character=${value:i:1}

    if [[ $character == $'\n' ]]; then
      if [[ $kind == pattern ]]; then
        encoded+='\n'
      else
        encoded+=$'\\\n'
      fi
    elif [[ $character == "\\" ]]; then
      i=$((i + 1))
      if ((i == ${#value})); then
        lib::log::red 'A sed expression cannot end with an unpaired backslash.'
        return 2
      fi

      next=${value:i:1}
      if [[ $next == $'\n' ]]; then
        if [[ $kind == pattern ]]; then
          encoded+='\n'
        else
          encoded+=$'\\\n'
        fi
      elif [[ $kind == pattern || $next == "\\" || $next == '&' || $next == [1-9] ]]; then
        encoded+="\\$next"
      else
        lib::log::red 'Replacement escapes must be \\, \&, or \1 through \9; use literal tabs/newlines.'
        return 2
      fi
    else
      encoded+=$character
    fi
  done

  printf '%s.' "$encoded"
}

#######################################
# Read identity and permission fields for an editing target without following it.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Target path
# Outputs:
#   Device, inode, link count, octal mode, UID and GID; errors to stderr.
# Returns:
#   0 on success, 1 on stat/platform failure.
# Dependencies:
#   uname and platform stat.
#######################################
function __libsh_fs_edit_identity() {
  local platform
  platform=$(uname -s) || return 1

  case $platform in
    Linux) stat -c '%d %i %h %a %u %g' -- "$1" || return 1 ;;
    Darwin) stat -f '%d %i %l %Mp%03Lp %u %g' "$1" || return 1 ;;
    *)
      lib::log::red 'File editing requires Linux or macOS.'
      return 1
      ;;
  esac
}

#######################################
# Transform a staged text file using portable sed -E operations.
# Globals:
#   None
# Arguments:
#   1 - Operation: replace, multiline, remove or append
#   2 - Nonempty ERE pattern
#   3 - Replacement or insertion text
#   4 - Private work directory containing original and result files
# Outputs:
#   Transformed bytes in result; errors to stderr. No stdout.
# Returns:
#   0 on success, 1 on no match/I/O failure, 2 on invalid sed expressions.
# Dependencies:
#   sed, cp, cat, head, tail and the filesystem size helper.
#######################################
function __libsh_fs_edit_transform() {
  local operation=$1 pattern=$2 content=$3 work=$4 delimiter=''
  local candidate encoded last original_size missing_newline=0 trim=0 size lines

  # Pick a delimiter absent from both values, avoiding delimiter-escape ambiguity.
  for candidate in '|' / : @ % '~' ',' ';' '^' '#' '!' '=' '+' '_' $'\037'; do
    if [[ $pattern != *"$candidate"* && $content != *"$candidate"* ]]; then
      delimiter=$candidate
      break
    fi
  done

  if [[ -z $delimiter ]]; then
    lib::log::red 'No available sed delimiter for the supplied expressions.'
    return 2
  fi

  encoded=$(__libsh_fs_edit_escape pattern "$pattern") || return 2
  pattern=${encoded%.}
  if [[ $operation == replace || $operation == multiline ]]; then
    encoded=$(__libsh_fs_edit_escape replacement "$content") || return 2
    content=${encoded%.}
  fi

  original_size=$(lib::fs::file_size "$work/original") || return 1
  last=$(tail -c 1 "$work/original" && printf '.') || return 1
  if [[ $original_size != 0 && $last != $'\n.' ]]; then
    missing_newline=1
  fi

  cat "$work/original" >"$work/input" || return 1
  if [[ $operation == multiline || $missing_newline == 1 ]]; then
    printf '\n' >>"$work/input" || return 1
  fi

  # Joining the file after appending one newline preserves its exact original
  # terminal newline in pattern space. sed p adds one extra newline we trim later.
  : >"$work/prefix" || return 1
  if [[ $operation == multiline ]]; then
    printf ':libsh_join\n$! {\nN\nb libsh_join\n}\n' >"$work/prefix" || return 1
  fi

  cp -- "$work/prefix" "$work/match.sed" || return 1
  printf '\\%s%s%s=\n' "$delimiter" "$pattern" "$delimiter" >>"$work/match.sed" || return 1
  if ! sed -E -n -f "$work/match.sed" "$work/input" >"$work/matches"; then
    lib::log::red 'Could not evaluate the sed pattern.'
    return 2
  fi

  if [[ ! -s $work/matches ]]; then
    lib::log::red 'The pattern did not match; the file was left unchanged.'
    return 1
  fi

  last=$(tail -n 1 "$work/matches") || return 1
  if [[ $operation == append ]]; then
    head -n "$last" "$work/original" >"$work/result" || return 1
    tail -n "+$((last + 1))" "$work/original" >"$work/suffix" || return 1

    if [[ -n $content ]]; then
      encoded=$(tail -c 1 "$work/result" && printf '.') || return 1
      if [[ $encoded != $'\n.' ]]; then
        printf '\n' >>"$work/result" || return 1
      fi

      printf '%s' "$content" >>"$work/result" || return 1
      if [[ -s $work/suffix && $content != *$'\n' ]]; then
        printf '\n' >>"$work/result" || return 1
      fi
    fi

    cat "$work/suffix" >>"$work/result" || return 1
    return 0
  fi

  cp -- "$work/prefix" "$work/edit.sed" || return 1
  if [[ $operation == remove ]]; then
    printf '\\%s%s%sd\n' "$delimiter" "$pattern" "$delimiter" >>"$work/edit.sed" || return 1
    lines=$(sed -n '$=' "$work/input") || return 1
    [[ $missing_newline == 0 || $last == "$lines" ]] || trim=1
  else
    printf 's%s%s%s%s%sg\n' "$delimiter" "$pattern" "$delimiter" "$content" "$delimiter" >>"$work/edit.sed" || return 1
    [[ $operation != multiline && $missing_newline == 0 ]] || trim=1
  fi

  if ! sed -E -f "$work/edit.sed" "$work/input" >"$work/edited"; then
    lib::log::red 'Could not apply the sed replacement.'
    return 2
  fi

  size=$(lib::fs::file_size "$work/edited") || return 1
  if [[ $trim == 1 && $size != 0 ]]; then
    size=$((size - 1))
  fi

  if [[ $size == 0 ]]; then
    : >"$work/result" || return 1
  else
    head -c "$size" "$work/edited" >"$work/result" || return 1
  fi
}

#######################################
# Stage and commit a text edit while preserving mode, UID and GID.
# The work directory is private and on the target filesystem. Hard-linked
# targets are refused. ACLs/xattrs and concurrent hostile path changes are
# outside this contract; ordinary concurrent content changes are checked.
# Globals:
#   PATH (read); parser arrays, locale, umask and traps stay in this subshell.
# Arguments:
#   1 - Operation: replace, multiline, remove or append
#   2 - File path
#   3 - Nonempty ERE pattern
#   4 - Replacement/insertion text (empty for remove)
#   5+ - Optional -n or --no-dereference
# Outputs:
#   Updated file on success; errors to stderr. No stdout.
# Returns:
#   0 on success, 1 on no match/operational failure, 2 on invalid arguments.
# Dependencies:
#   sed, stat, uname, mktemp, cp, chmod, cmp, tr, mv, rm, head, tail, cat;
#   readlink when following a symlink.
#######################################
function __libsh_fs_edit() (
  local operation=$1 requested=$2 pattern=$3 content=$4
  local target current identity device inode links mode uid gid stage_identity
  local __libsh_fs_work=''
  local LC_ALL=C
  # Parser inputs are read by lib::opt::parse through Bash dynamic scope.
  # shellcheck disable=SC2034
  local -a OPTS=('-n,--no-dereference:no_dereference:0:optional')
  # shellcheck disable=SC2034
  local -A OPTS_HELP=([no_dereference]='Refuse symlink targets') OPTS_VALUES=()

  shift 4
  lib::opt::parse ${1+"$@"} || return 2
  export LC_ALL

  if [[ -z $requested || -z $pattern ]]; then
    lib::log::red 'File editing requires a nonempty path and pattern.'
    return 2
  fi

  target=$(__libsh_fs_edit_target "$requested" "${OPTS_VALUES[no_dereference]:-0}") || return 1
  target=${target%.}
  if [[ ! -f $target || ! -r $target ]]; then
    lib::log::red 'Editing requires a readable regular file.'
    return 1
  fi

  identity=$(__libsh_fs_edit_identity "$target") || return 1
  IFS=' ' read -r device inode links mode uid gid <<<"$identity"
  if [[ ! $device =~ ^[0-9]+$ || ! $inode =~ ^[0-9]+$ || ! $links =~ ^[0-9]+$ ||
    ! $mode =~ ^[0-7]+$ || ! $uid =~ ^[0-9]+$ || ! $gid =~ ^[0-9]+$ ]]; then
    lib::log::red 'Could not read file identity and ownership.'
    return 1
  fi

  if [[ $links != 1 ]]; then
    lib::log::red 'Editing refuses hard-linked files.'
    return 1
  fi

  umask 077
  __libsh_fs_work=$(mktemp -d "${target%/*}/.libsh-edit.XXXXXXXX") || return 1
  trap 'rm -rf -- "$__libsh_fs_work"' EXIT
  trap 'exit 1' HUP INT TERM

  cp -- "$target" "$__libsh_fs_work/original" || return 1
  tr -d '\000' <"$__libsh_fs_work/original" >"$__libsh_fs_work/text" || return 1
  if ! cmp -s "$__libsh_fs_work/original" "$__libsh_fs_work/text"; then
    lib::log::red 'File editing requires text without NUL bytes.'
    return 2
  fi

  cp -p -- "$target" "$__libsh_fs_work/result" || return 1
  chmod u+w "$__libsh_fs_work/result" || return 1
  __libsh_fs_edit_transform "$operation" "$pattern" "$content" "$__libsh_fs_work" || return $?

  chmod "$mode" "$__libsh_fs_work/result" || return 1
  stage_identity=$(__libsh_fs_edit_identity "$__libsh_fs_work/result") || return 1
  if [[ ${stage_identity#* * * } != "$mode $uid $gid" ]]; then
    lib::log::red 'Could not preserve file mode and ownership.'
    return 1
  fi

  current=$(__libsh_fs_edit_target "$requested" "${OPTS_VALUES[no_dereference]:-0}") || return 1
  if [[ ${current%.} != "$target" || -L $target ]] \
    || [[ $(__libsh_fs_edit_identity "$target") != "$identity" ]] \
    || ! cmp -s "$target" "$__libsh_fs_work/original"; then
    lib::log::red 'The editing target changed; the edit was not committed.'
    return 1
  fi

  if cmp -s "$target" "$__libsh_fs_work/result"; then
    return 0
  fi

  mv -f -- "$__libsh_fs_work/result" "$target" || return 1
)

#######################################
# Replace all ERE matches within each line using sed -E replacement syntax.
# Use & for the match, \1..\9 for captures, \\ for a backslash and \& for &.
# Supply actual tabs/newlines rather than nonportable replacement escapes.
# Unmodified bytes and the original terminal newline are preserved. Symlinks
# are followed by default; hard-linked and NUL-containing files are refused.
# Globals:
#   None
# Arguments:
#   1 - File path
#   2 - Nonempty POSIX extended regular expression
#   3 - sed replacement text
#   4+ - Optional -n or --no-dereference to refuse a final symlink
# Outputs:
#   Edited file; errors to stderr. No stdout.
# Returns:
#   0 on success, 1 on no match/operational failure, 2 on invalid invocation.
# Dependencies:
#   Standard Linux/macOS tools listed in __libsh_fs_edit.
#######################################
function lib::fs::file_replace_content() {
  if [[ $# -lt 3 ]]; then
    lib::log::red 'file_replace_content requires FILE PATTERN REPLACEMENT.'
    return 2
  fi

  __libsh_fs_edit replace "$@"
}

#######################################
# Replace all ERE matches across the complete file using sed -E.
# The whole file is held in sed pattern space; dot matches embedded newlines,
# ^/$ address file boundaries, and \n matches newline. Replacement syntax
# and metadata/link handling are the same as file_replace_content.
# Globals:
#   None
# Arguments:
#   1 - File path
#   2 - Nonempty POSIX extended regular expression
#   3 - sed replacement text
#   4+ - Optional -n or --no-dereference to refuse a final symlink
# Outputs:
#   Edited file; errors to stderr. No stdout.
# Returns:
#   0 on success, 1 on no match/operational failure, 2 on invalid invocation.
# Dependencies:
#   Standard Linux/macOS tools listed in __libsh_fs_edit.
#######################################
function lib::fs::file_replace_content_multiline() {
  if [[ $# -lt 3 ]]; then
    lib::log::red 'file_replace_content_multiline requires FILE PATTERN REPLACEMENT.'
    return 2
  fi

  __libsh_fs_edit multiline "$@"
}

#######################################
# Remove every complete line matching an ERE, including its terminator.
# Unmatched bytes keep their original line endings. Metadata and link handling
# are the same as file_replace_content.
# Globals:
#   None
# Arguments:
#   1 - File path
#   2 - Nonempty POSIX extended regular expression
#   3+ - Optional -n or --no-dereference to refuse a final symlink
# Outputs:
#   Edited file; errors to stderr. No stdout.
# Returns:
#   0 on success, 1 on no match/operational failure, 2 on invalid invocation.
# Dependencies:
#   Standard Linux/macOS tools listed in __libsh_fs_edit.
#######################################
function lib::fs::file_remove_content() {
  if [[ $# -lt 2 ]]; then
    lib::log::red 'file_remove_content requires FILE PATTERN.'
    return 2
  fi

  local file=$1 pattern=$2
  shift 2

  __libsh_fs_edit remove "$file" "$pattern" '' ${1+"$@"}
}

#######################################
# Insert literal text after the last line matching an ERE.
# Add a separator newline after an unterminated matching line and, when needed,
# before remaining original lines. At EOF the inserted text determines the
# final newline. Empty insertion text is a no-op only if the pattern matches.
# Metadata and link handling are the same as file_replace_content.
# Globals:
#   None
# Arguments:
#   1 - File path
#   2 - Nonempty POSIX extended regular expression
#   3 - Literal text to insert (not sed replacement syntax)
#   4+ - Optional -n or --no-dereference to refuse a final symlink
# Outputs:
#   Edited file; errors to stderr. No stdout.
# Returns:
#   0 on success, 1 on no match/operational failure, 2 on invalid invocation.
# Dependencies:
#   Standard Linux/macOS tools listed in __libsh_fs_edit.
#######################################
function lib::fs::file_append_content_after_last_match() {
  if [[ $# -lt 3 ]]; then
    lib::log::red 'file_append_content_after_last_match requires FILE PATTERN CONTENT.'
    return 2
  fi

  __libsh_fs_edit append "$@"
}

#######################################
# Validate an owner expression accepted by the filesystem wrappers.
# Globals:
#   None
# Arguments:
#   1 - USER, USER:GROUP or :GROUP; names or decimal IDs
# Outputs:
#   None
# Returns:
#   0 valid, 2 invalid/empty expression.
#######################################
function __libsh_fs_owner() {
  local LC_ALL=C owner=$1 part
  local -a parts=()
  [[ -n $owner && $owner != : && $owner != *:*:* && $owner != *: ]] || return 2
  IFS=: read -r -a parts <<<"$owner"
  for part in "${parts[@]}"; do
    [[ -z $part ]] && continue
    [[ $part =~ ^[a-zA-Z0-9_][a-zA-Z0-9_.-]*\$?$ ]] || return 2
  done
}

#######################################
# Set ownership of one path, following a final symlink by default.
# No recursion or automatic privilege elevation is performed.
# Globals:
#   PATH (read)
# Arguments:
#   1 - Path
#   2 - USER, USER:GROUP or :GROUP; names or numeric IDs
#   3 - Optional -n or --no-dereference to change the link itself
# Outputs:
#   Errors to stderr; no stdout.
# Returns:
#   0 success, 1 chown/path failure, 2 invalid invocation.
# Dependencies:
#   chown; caller must have the required ownership-changing privileges.
#######################################
function lib::fs::owner_set() {
  [[ $# == 2 || ($# == 3 && ($3 == -n || $3 == --no-dereference)) ]] || return 2
  [[ -n $1 ]] || return 2
  __libsh_fs_owner "$2" || return 2
  local path=$1
  local -a options=()
  while [[ $path != / && $path == */ ]]; do
    path=${path%/}
  done
  [[ $path == /* ]] || path=./$path
  [[ $# != 3 ]] || options=(-h)

  chown ${options[@]+"${options[@]}"} -- "$2" "$path" || return 1
}
