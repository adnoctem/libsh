# shellcheck shell=bash

#######################################
# Hash exact string bytes using an available GNU or macOS command.
# Globals: PATH (read)
# Arguments: md5|224|256|384|512 STRING
# Outputs: Lowercase hexadecimal digest and newline; errors on stderr.
# Returns: 0 success, 1 missing/failed backend or malformed output.
# Bash strings cannot contain NUL bytes. No newline is added to the input.
#######################################
function __libsh_hash_digest() {
  local LC_ALL=C algorithm=$1 value=$2 output digest length
  local -a backend
  if [[ $algorithm == md5 ]]; then
    length=32
    if command -v md5sum >/dev/null 2>&1; then
      backend=(md5sum)
    elif command -v md5 >/dev/null 2>&1; then
      backend=(md5 -q)
    else
      lib::log::red 'MD5 hashing requires md5sum or md5.'
      return 1
    fi
  else
    length=$((algorithm / 4))
    if command -v "sha${algorithm}sum" >/dev/null 2>&1; then
      backend=("sha${algorithm}sum")
    elif command -v shasum >/dev/null 2>&1; then
      backend=(shasum -a "$algorithm")
    else
      lib::log::red 'SHA hashing requires the corresponding sha*sum command or shasum.'
      return 1
    fi
  fi
  if ! output=$(
    set -o pipefail
    printf '%s' "$value" | "${backend[@]}"
  ); then
    lib::log::red 'Hash command failed.'
    return 1
  fi
  digest=${output%%[[:space:]]*}
  if [[ ${#digest} != "$length" || ! $digest =~ ^[0-9a-f]+$ ]]; then
    lib::log::red 'Hash command returned an invalid digest.'
    return 1
  fi
  printf '%s\n' "$digest"
}

#######################################
# Compute an MD5 checksum of a string (not a password/security primitive).
# Globals: PATH (read)
# Arguments: STRING
# Outputs: Lowercase hexadecimal digest and newline; errors on stderr.
# Returns: 0 success, 1 backend failure, 2 incorrect argument count.
# Dependencies: md5sum (GNU) or md5 (macOS), checked at invocation.
#######################################
function lib::hash::string_md5() {
  if [[ $# != 1 ]]; then
    lib::log::red 'string_md5 requires one string.'
    return 2
  fi
  __libsh_hash_digest md5 "$1"
}

#######################################
# Compute a SHA-2 digest of a string, without an implicit newline.
# Globals: PATH (read)
# Arguments: STRING [ALGORITHM=256 (224|256|384|512)]
# Outputs: Lowercase hexadecimal digest and newline; errors on stderr.
# Returns: 0 success, 1 backend failure, 2 invalid invocation.
# Dependencies: sha*sum (GNU) or shasum (macOS), checked at invocation.
#######################################
function lib::hash::string_sha() {
  if [[ $# -lt 1 || $# -gt 2 || ! ${2-256} =~ ^(224|256|384|512)$ ]]; then
    lib::log::red 'string_sha requires STRING and an optional SHA-2 algorithm (224, 256, 384, 512).'
    return 2
  fi
  __libsh_hash_digest "${2-256}" "$1"
}
