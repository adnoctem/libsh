# shellcheck shell=bash

# BASH functions to obtain correct paths.

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
git::toplevel() {
  path=$(git rev-parse --show-toplevel)

  echo "${path%/}"
}
