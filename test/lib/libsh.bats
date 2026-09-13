#!/usr/bin/env bats

setup() {
  REPO_ROOT=$(git rev-parse --show-toplevel)

  load "$REPO_ROOT/test/bats/plugins/bats-support/load"
  load "$REPO_ROOT/test/bats/plugins/bats-assert/load"
}

# Keep public APIs enumerable by lib:: and private implementation helpers
# under __libsh_. Both namespaces identify the containing module.
@test "library functions follow the public or private naming convention" {
  local violations=()

  for file in "$REPO_ROOT"/lib/*.sh; do
    local module
    module=$(basename "$file" .sh)

    local name public_pattern private_pattern
    public_pattern="^lib::${module}::[a-z][a-z0-9_]*$"
    [[ $module != lib ]] || public_pattern="^lib::[a-z][a-z0-9_]*$"
    private_pattern="^__libsh_${module}_[a-z][a-z0-9_]*$"
    while read -r name; do
      [[ -z $name ]] && continue
      [[ $name =~ $public_pattern || $name =~ $private_pattern ]] || violations+=("$(basename "$file"): $name")
    done < <(grep -oE '^(function )?[A-Za-z0-9_:]+\(\)' "$file" | sed 's/^function //; s/()$//')
  done

  assert_equal "${violations[*]:-}" ""
}

# The entrypoint must load both public APIs and their private dependencies.
@test "lib/lib.sh loads every public function and private helper" {
  local missing=()

  source "$REPO_ROOT/lib/lib.sh"

  local file name
  for file in "$REPO_ROOT"/lib/*.sh; do
    [[ "$(basename "$file")" == "lib.sh" ]] && continue

    while read -r name; do
      [[ -z $name ]] && continue
      declare -F "$name" >/dev/null || missing+=("$name")
    done < <(grep -oE '^(function )?[A-Za-z0-9_:]+\(\)' "$file" | sed 's/^function //; s/()$//')
  done

  assert_equal "${missing[*]:-}" ""
}

@test "lib/lib.sh reports how many modules it loaded" {
  source "$REPO_ROOT/lib/lib.sh"

  # The arithmetic context strips the leading whitespace BSD/macOS 'wc'
  # pads its count with, which a bare command substitution would not.
  local expected
  expected=$(($(find "$REPO_ROOT/lib" -maxdepth 1 -name '*.sh' ! -name 'lib.sh' | wc -l)))

  assert_equal "${LIBSH_LOADED:-0}" "$expected"
}

@test "every file in lib/ declares its shell for shellcheck" {
  local violations=()

  for file in "$REPO_ROOT"/lib/*.sh; do
    head -n 1 "$file" | grep -q 'shellcheck shell=bash' || violations+=("$(basename "$file")")
  done

  assert_equal "${violations[*]:-}" ""
}

# A module without a test file is how coverage quietly rots: this fails the
# moment lib/<module>.sh lands without test/lib/<module>.bats next to it.
# lib.sh is the exception -- the entrypoint is covered by this file.
@test "every module in lib/ has a matching .bats file" {
  local missing=()

  local file module
  for file in "$REPO_ROOT"/lib/*.sh; do
    module=$(basename "$file" .sh)

    [[ $module == "lib" ]] && continue
    [[ -f "$REPO_ROOT/test/lib/${module}.bats" ]] || missing+=("${module}.sh")
  done

  assert_equal "${missing[*]:-}" ""
}

@test "core-only loading exposes no extension functions or legacy namespaces" {
  run bash -c 'source "$1/lib/lib.sh"; declare -F | cut -d " " -f 3' _ "$REPO_ROOT"
  assert_success
  refute_output --partial 'ext::'
  refute_output --partial 'lib::lib::'
  refute_output --partial 'lib::utils::'
  assert_output --partial 'lib::load'
}

@test "extensions follow their namespaces and have matching test suites" {
  local file name module
  for file in "$REPO_ROOT"/extensions/lib*.sh; do
    module=${file##*/lib}
    module=${module%.sh}
    [[ -f $REPO_ROOT/test/extensions/$module.bats ]]
    [[ $(head -n 1 "$file") == '# shellcheck shell=bash' ]]
    while read -r name; do
      [[ $name =~ ^ext::${module}::[a-z][a-z0-9_]*$ || $name =~ ^__libsh_ext_${module}_[a-z][a-z0-9_]*$ ]]
    done < <(sed -nE 's/^(function )?([A-Za-z0-9_:]+)\(\).*/\2/p' "$file")
  done
}

@test "loader exposes all requested addon functions and helpers" {
  source "$REPO_ROOT/lib/lib.sh"
  local file name module
  for file in "$REPO_ROOT"/extensions/lib*.sh; do
    module=${file##*/lib}
    module=${module%.sh}
    lib::load_extensions "$module"
    while read -r name; do
      declare -F "$name" >/dev/null
    done < <(sed -nE 's/^(function )?([A-Za-z0-9_:]+)\(\).*/\2/p' "$file")
  done
}

@test "loader rejects invalid and unavailable names before sourcing addons" {
  source "$REPO_ROOT/lib/lib.sh"
  run lib::load_extensions secret ../git
  assert_failure 2
  run lib::load_extensions secret nonexistent
  assert_failure 1
  if lib::load_extensions secret nonexistent; then return 1; fi
  run declare -F ext::secret::resolve
  assert_failure
}

@test "repeated addon requests preserve already loaded functions" {
  source "$REPO_ROOT/lib/lib.sh"
  lib::load_extensions git
  ext::git::toplevel() { printf 'preserved'; }
  lib::load_extensions git git
  source "$REPO_ROOT/lib/lib.sh"
  lib::load_extensions git
  run ext::git::toplevel
  assert_output preserved
}

@test "failed addon sources can be retried and run after core" {
  local fixture="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$fixture/lib" "$fixture/extensions"
  cp "$REPO_ROOT/lib/"*.sh "$fixture/lib/"
  printf 'declare -F lib::os::root_check >/dev/null || return 9\nreturn 1\n' >"$fixture/extensions/libexample.sh"
  source "$fixture/lib/lib.sh"
  run lib::load_extensions example
  assert_failure 1
  printf 'ext::example::ready() { :; }\n' >"$fixture/extensions/libexample.sh"
  lib::load_extensions example
  declare -F ext::example::ready
}

@test "core loader rejects addon arguments and extensions remain explicit" {
  source "$REPO_ROOT/lib/lib.sh"
  run lib::load secret
  assert_failure 2
  run declare -F ext::secret::resolve
  assert_failure
  lib::load_extensions secret
  declare -F ext::secret::resolve
}

@test "extension loader ensures core before executing addon source" {
  local fixture="$BATS_TEST_TMPDIR/fixture"
  mkdir -p "$fixture/lib" "$fixture/extensions"
  cp "$REPO_ROOT/lib/"*.sh "$fixture/lib/"
  printf 'declare -F lib::os::root_check >/dev/null || return 9\n' >"$fixture/extensions/libexample.sh"
  source "$fixture/lib/lib.sh"
  unset -f lib::os::root_check
  unset __libsh_lib_core_dir
  lib::load_extensions example
  declare -F lib::os::root_check
}

@test "all sourced library functions use the function keyword" {
  local file declaration
  local violations=()

  for file in "$REPO_ROOT"/lib/*.sh "$REPO_ROOT"/extensions/*.sh; do
    while IFS= read -r declaration; do
      violations+=("${file##*/}: $declaration")
    done < <(grep -nE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_:]*[[:space:]]*\([[:space:]]*\)' "$file" || true)
  done

  assert_equal "${violations[*]:-}" ""
}

#######################################
# Check a function header at a definition line reported by Bash's parser.
# Globals:
#   None
# Arguments:
#   1 - Source file
#   2 - Function definition line number
# Outputs:
#   Header violations to stdout for BATS diagnostics.
# Returns:
#   0 for the standard layout, 1 for a malformed or missing header.
#######################################
assert_function_header() {
  awk -v definition="$2" '
    { lines[NR] = $0 }
    END {
      border = "#######################################"
      end = definition - 1
      while (end > 0 && (lines[end] ~ /^# shellcheck / || lines[end] == "")) end--
      if (lines[end] != border) {
        print FILENAME ":" definition ": missing closing header border"
        exit 1
      }
      start = end - 1
      while (start > 0 && lines[start] != border) start--
      if (!start) {
        print FILENAME ":" definition ": missing opening header border"
        exit 1
      }
      expected[1] = "Globals"
      expected[2] = "Arguments"
      expected[3] = "Outputs"
      expected[4] = "Returns"
      section = 0
      count = 0
      description = 0
      failed = 0
      for (i = start + 1; i < end; i++) {
        line = lines[i]
        if (line ~ /^# (Globals|Arguments|Outputs|Returns|Inputs|Dependencies):$/) {
          if (section && !count) failed = 1
          label = substr(line, 3, length(line) - 3)
          if (label == "Inputs") {
            if (section != 2 || inputs++) failed = 1
          } else if (label == "Dependencies") {
            if (section != 4 || dependencies++) failed = 1
          } else {
            section++
            if (label != expected[section]) failed = 1
          }
          count = 0
        } else if (section) {
          if (line !~ /^#   [^ ]|^#    +[^ ]/) failed = 1
          if (line ~ /^#   +[^ ]/) count++
        } else {
          if (line !~ /^#( |$)/) failed = 1
          if (line ~ /^# [^ ]/) description++
        }
      }
      if (section != 4 || !count || !description || failed) {
        print FILENAME ":" definition ": invalid function-header sections"
        exit 1
      }
    }
  ' "$1"
}

@test "sourced functions use the standard multiline function header" {
  # Bash supplies real definition locations, so heredoc text and comments cannot
  # accidentally count as functions. No additional shell parser is needed in CI.
  run bash -O extdebug -c '
    source "$1/lib/lib.sh"
    for file in "$1"/extensions/lib*.sh; do
      source "$file"
    done
    while IFS= read -r name; do
      declare -F "$name"
    done < <(compgen -A function)
  ' _ "$REPO_ROOT"
  assert_success

  local name definition file
  while read -r name definition file; do
    case $file in
      "$REPO_ROOT"/lib/* | "$REPO_ROOT"/extensions/*)
        assert_function_header "$file" "$definition"
        ;;
    esac
  done <<<"$output"
}

@test "function-header check rejects compact labels and accepts ShellCheck annotations" {
  local fixture="$BATS_TEST_TMPDIR/header.sh" definition
  cat >"$fixture" <<'HEADER'
#######################################
# A sample function.
# Globals:
#   None
# Arguments:
#   None
# Outputs:
#   None
# Returns:
#   0 on success.
#######################################
# shellcheck disable=SC2120
function example() { :; }
HEADER
  definition=13
  assert_function_header "$fixture" "$definition"

  sed 's/# Globals:/# Globals: None/' "$fixture" >"$fixture.bad"
  run assert_function_header "$fixture.bad" "$definition"
  assert_failure 1

  sed 's/# Arguments:/# Returns:/' "$fixture" >"$fixture.bad"
  run assert_function_header "$fixture.bad" "$definition"
  assert_failure 1
}
