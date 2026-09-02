# shellcheck shell=bash

# Remove credentials from the shell history file.
#
# What this can and cannot do
# ---------------------------
# A script runs in its own process. Its history list is not the terminal's,
# so calling `history -c` here would clear an empty list and leave the
# command you actually typed sitting in your shell untouched. There is no
# way for a child process to edit its parent shell's in-memory history.
#
# What is reachable is the history *file* on disk, which is what
# lib::history::scrub rewrites. Two limits follow from that:
#
#   - Lines the interactive shell has not flushed yet are not in the file
#     when this runs, and get written afterwards anyway. bash and zsh both
#     flush at exit by default; setups using zsh's INC_APPEND_HISTORY or
#     SHARE_HISTORY (and bash's `history -a` in PROMPT_COMMAND) write
#     immediately and are scrubbed reliably.
#   - The entry stays in the current session's in-memory list until that
#     session ends.
#
# The dependable fix is to never put the secret in argv: use
# --password-file or the MYSQL_PWD environment variable.

#######################################
# Resolve the path of the shell history file.
#
# HISTFILE is a shell variable, not an exported one, so it is almost never
# visible from here -- fall back to the login shell's default.
# Globals:
#   HISTFILE, SHELL (read)
# Arguments:
#   None
# Outputs:
#   The history file path to stdout.
#######################################
function lib::history::file() {
  local file=${HISTFILE:-}

  if [[ -z $file ]]; then
    case "$(basename "${SHELL:-bash}")" in
    zsh) file="${HOME}/.zsh_history" ;;
    *) file="${HOME}/.bash_history" ;;
    esac
  fi

  printf '%s' "$file"
}

#######################################
# Remove every line of the shell history file that contains the given
# secret.
#
# Matching is a plain substring match, so a short or dictionary-word
# secret can take unrelated commands with it -- the length warning below
# exists for exactly that case.
# Globals:
#   HISTFILE, SHELL (read, via lib::history::file)
# Arguments:
#   1 - The secret to scrub. An empty value is a no-op.
# Outputs:
#   A summary and the in-memory caveat to stdout.
#   The rewritten history file is left mode 600.
# Returns:
#   0 on success or when there is nothing to do, 1 if the file exists but
#   could not be rewritten.
#######################################
function lib::history::scrub() {
  local secret=${1:-} file tmp rc=0 before after

  if [[ -z $secret ]]; then
    return 0
  fi

  if [[ ${#secret} -lt 8 ]]; then
    lib::log::yellow "Secret is short (${#secret} chars); history lines that merely contain it will be removed too."
  fi

  file=$(lib::history::file)

  if [[ ! -f $file ]]; then
    lib::log::yellow "No shell history file at '$file'; nothing to scrub."
    return 0
  fi

  if [[ ! -w $file ]]; then
    lib::log::red "Shell history file '$file' is not writable; left it untouched."
    return 1
  fi

  # Same directory, so the replacement is an atomic rename rather than a
  # copy across filesystems.
  tmp=$(mktemp "${file}.libsh.XXXXXX")
  chmod 600 "$tmp"

  # 'grep -v' exits 1 when it selects nothing, which here only means every
  # line held the secret. Anything above 1 is a real failure.
  grep -vF -- "$secret" "$file" >"$tmp" || rc=$?
  if ((rc > 1)); then
    rm -f "$tmp"
    lib::log::red "Could not filter '$file'; left it untouched."
    return 1
  fi

  before=$(wc -l <"$file")
  after=$(wc -l <"$tmp")
  mv "$tmp" "$file"

  lib::log::green "Removed $((before - after)) line(s) containing the secret from '$file'."
  lib::log::yellow "This shell's own history list is out of reach: run 'history -c' (bash) or 'fc -p' (zsh), or start a new session."
  return 0
}
