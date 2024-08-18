# shellcheck shell=bash
#
# Bash general utility functions

# shellcheck disable=SC1091

# Reload the rc files for Bash (and/or Zsh)
utils::rc() {
  if [ -e "${HOME}/.bashrc" ]; then source "${HOME}/.bashrc"; fi
  if [ -e "${HOME}/.zshrc" ]; then source "${HOME}/.zshrc"; fi
}

# Active an existing Python Venv or create one if it doesn't exist
utils::venv() {
  if [ -e "$(pwd)/.venv/bin/activate" ]; then
    source "$(pwd)/.venv/bin/activate"
    exit 0
  else
    python -m venv "(pwd)/.venv"
    exit 0
  fi
}
