# shellcheck shell=bash

# Git repository paths and reference queries.

#######################################
# Obtain the toplevel directory of a Git
# repository.
#
# Return the repository's root path
# Globals:
#   path (written)
# Arguments:
#   None
# Outputs:
#   The absolute directory path.
# Returns:
#   The final echo status; Git failure is not explicitly propagated.
#######################################
function ext::git::toplevel() {
  path=$(git rev-parse --show-toplevel)

  echo "${path%/}"
}

#######################################
# Check if a remote exists
# Globals:
#   remote, rc (written)
# Arguments:
#   1 - Extended regular expression to match remote names
# Outputs:
#   Matching remote names to stdout; command errors to stderr.
# Returns:
#   The grep status: 0 match, 1 no match, 2 error (subject to pipefail).
#######################################
function ext::git::remote_exists() {
  remote=${1}

  git remote show | grep -E "$remote"
  rc=$?

  return $rc
}

#######################################
# Check if a branch exists
# Globals:
#   branch, rc (written)
# Arguments:
#   1 - Extended regular expression to match local branch names
# Outputs:
#   Matching branch lines to stdout; command errors to stderr.
# Returns:
#   The grep status: 0 match, 1 no match, 2 error (subject to pipefail).
#######################################
function ext::git::branch_exists() {
  branch=${1}

  git branch -l | grep -E "$branch"
  rc=$?

  return $rc
}
