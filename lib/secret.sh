# shellcheck shell=bash

# Read secrets from disk, so they never have to appear in argv where
# 'ps' and the shell history can see them.

#######################################
# Read a secret from the first line of a file.
#
# Only the first line is used: a trailing newline is an editor artifact,
# not part of the secret.
# Globals:
#   None
# Arguments:
#   1 - Path to the file holding the secret
# Outputs:
#   The secret to stdout. Warnings and errors go to stderr, so callers can
#   capture the value with a command substitution without catching them.
# Returns:
#   0 on success, 1 if the file is missing, unreadable or empty.
#######################################
function lib::secret::from_file() {
  local path=${1} mode secret

  if [[ ! -f $path ]]; then
    lib::log::red "Secret file '$path' does not exist."
    return 1
  fi

  if [[ ! -r $path ]]; then
    lib::log::red "Secret file '$path' is not readable."
    return 1
  fi

  # A secret every account on the box can read defeats the point of
  # keeping it off the command line in the first place.
  mode=$(stat -c '%a' "$path" 2>/dev/null || true)
  if [[ -n $mode && ! $mode =~ ^[0-7]?[0-7]00$ ]]; then
    lib::log::yellow "Secret file '$path' is mode $mode; 600 is recommended." >&2
  fi

  IFS= read -r secret <"$path" || true

  if [[ -z $secret ]]; then
    lib::log::red "Secret file '$path' is empty."
    return 1
  fi

  printf '%s' "$secret"
}
