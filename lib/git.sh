# shellcheck shell=bash

# Bash functions to obtain correct paths.

#######################################
# Obtain the toplevel directory of a Git
# repository.
#
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   The absolute directory path.
#######################################

# Return the repository's root path
lib::git::toplevel() {
  path=$(git rev-parse --show-toplevel)

  echo "${path%/}"
}

# Check if a remote exists
lib::git::remote_exists() {
  remote=${1}

  git remote show | grep -E "$remote"
  rc=$?

  return $rc
}

# Check if a branch exists
lib::git::branch_exists() {
  branch=${1}

  git branch -l | grep -E "$branch"
  rc=$?

  return $rc
}
