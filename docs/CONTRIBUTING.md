# Ad Noctem Collective - `libsh` Repository Contributing Guidelines

Contributions are welcome via GitHub's Pull Requests. This document outlines the process to help get your contribution accepted.

## ⚒️ Building

The project uses [`make`](https://www.gnu.org/software/make/) to drive all development workflows. Every target is defined
in the [`Makefile`](../Makefile) at the repository root, and the external tools it calls are listed under
[Linting](#linting).

Before running anything else, initialize the project. This checks out the BATS submodules under
[`test/bats`](../test/bats) and verifies that the required tools are installed:

```shell
make init
```

The available targets:

| Command            | Arguments    | Purpose                                                                              |
| ------------------ | ------------ | ------------------------------------------------------------------------------------ |
| `init`             |              | Check out the BATS submodules and verify the required tooling                        |
| `format`           |              | Format all Bash sources in place with `shfmt`                                        |
| `lint`             |              | Run every linter: `shellcheck`, `shfmt`, `markdownlint`, `actionlint`, `gitleaks`    |
| `test`             | `WHAT`       | Run the BATS test suite                                                              |
| `build`            | `WHAT`       | Create distribution archives in `dist/`                                              |
| `build-test-image` | `TEST_IMAGE` | Build the installed-library Docker test image, initializing BATS submodules          |
| `test-container`   | `TEST_IMAGE` | Run non-root library and disposable root account tests on bookworm Bash and Bash 4.0 |
| `all`              |              | Clean `dist/`, then build every archive                                              |
| `clean`            |              | Remove the `dist/` output directory                                                  |
| `version`          |              | Print the current version                                                            |
| `tools-check`      |              | Report which required tools are missing, and fail if any are                         |

Every target also accepts `PRINT_HELP=y` to describe itself instead of running:

```shell
PRINT_HELP=y make build
```

### Source Formatting

Format all Bash sources in the repository in place:

```shell
make format
```

To check formatting without modifying files, suitable for CI jobs and pre-commit hooks:

```shell
make shfmt
```

The formatter delegates indentation, spacing, and line-continuation rules entirely to `shfmt`, which reads its settings
from [`.editorconfig`](../.editorconfig). There is no repository-specific post-processing.

Settings default to:

- **Indentation**: 2 spaces
- **Line endings**: LF
- **Excluded directories**: `test/bats` (vendored submodules) and `secrets` (local planning notes and retired scripts),
  both marked `ignore = true` in `.editorconfig` and honoured through `shfmt --apply-ignore`

### Logical Paragraphs

Group shell code into logical paragraphs, separated by one blank line. Keep related declarations together, then
separate them from the work that follows. Within a function, add a paragraph boundary when the purpose changes:
resolving configuration, validating inputs, downloading, verifying, installing, or reporting the result.

Keep an operation and its immediate status check together, including assignments such as `rc=$?`. Keep a value's
assignment, validation, and immediate use together when they form one step. Avoid blank lines after every statement
or around every `if`; short helpers may need none. Keep comments attached to the block they describe.
Expand control flow onto multiple lines so branches are easy to scan; short, single-action `case` alternatives can
remain compact.

Use the [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) as the baseline for new shell
code, with this repository's documented API naming, Bash 4.0 compatibility, and executable shebang conventions taking
precedence. Existing code is not yet fully aligned; repository-wide conformance belongs in a separate change.
`shfmt` handles mechanical formatting, including two-space indentation for `.sh` files and the standalone entry
points in `bin/`. Logical paragraph boundaries remain an author's decision and should survive formatting.

### Linting

Run every linter across the repository:

```shell
make lint
```

This requires the following tools on your `PATH`. Run `make tools-check` to see which are missing; `make lint` refuses
to start until they are all present, rather than failing halfway through:

| Tool           | Scope                                                                                      |
| -------------- | ------------------------------------------------------------------------------------------ |
| `shellcheck`   | Library, scripts, tools, `bin/` executables, BATS tests, and container/integration helpers |
| `shfmt`        | Formatting drift across the repository                                                     |
| `markdownlint` | All Markdown outside `test/` and `secrets/`                                                |
| `actionlint`   | GitHub Actions workflows                                                                   |
| `gitleaks`     | Secret scanning                                                                            |

Individual linters can be run on their own, which is useful while iterating:

```shell
make shellcheck
make markdownlint
```

The `shellcheck` target derives its file list from `lib/`, `scripts/`, and `bin/`, so a new script is covered the moment
it lands — nothing has to be added to the `Makefile`.

### Building Distribution Archives

Create the release archives, written to `dist/` with their directory layout preserved:

```shell
make build
```

This produces the complete bundle (`libsh-<version>.tar.gz`) plus one archive per directory: `scripts`, `lib`, and
`bin`. Build a single bundle instead:

```shell
make build WHAT=lib
```

To clear `dist/` first and rebuild everything:

```shell
make all
```

### Pre-Commit Hooks

The repository ships a pre-configured [`.pre-commit-config.yaml`](../.pre-commit-config.yaml). After installing
[pre-commit](https://pre-commit.com/), activate the hooks from the repository root:

```shell
pre-commit install
```

The hooks vendor their own tool binaries, so they work without a local `make init`. They are deliberately a **fast
subset** of `make lint` — treat `make lint` as authoritative before opening a pull request.

### Running Tests

Run the whole BATS suite:

```shell
make test
```

Run a single directory of tests:

```shell
make test WHAT=lib
```

`make test` prefers a `bats` on your `PATH` and falls back to the vendored submodule, so it behaves identically locally
and in CI.

Tests live in [`test/lib`](../test/lib) and mirror the library: `lib/<module>.sh` is covered by
`test/lib/<module>.bats`. Repository-wide rules live in [`test/lib/libsh.bats`](../test/lib/libsh.bats), which enforces
that:

- public functions in `lib/` use `lib::<module>::<function>` and private helpers use `__libsh_<module>_<function>`,
  where `<module>` is the containing filename without `.sh`
- every file in `lib/` declares `# shellcheck shell=bash` on its first line
- every module in `lib/` has a matching `.bats` file
- [`lib/lib.sh`](../lib/lib.sh), the single-entrypoint loader, exposes every function the modules define

A new library module without a test file fails the suite, so coverage cannot quietly rot.

Standalone installer and manager tests live in [`test/bin`](../test/bin), using local checksummed release fixtures.
`make test` includes both directories; `make test WHAT=bin` runs only these installation tests.

To test the installed library in a container, install Docker and start its daemon, then run:

```shell
make test-container
```

This initializes the BATS submodules, builds the test image, and runs both bookworm Bash and Bash 4.0 as UID/GID 10001
with a read-only root filesystem and writable `/tmp`. Each run includes the secret/networking tests and real local TCP
checks, plus the standalone manager lifecycle and bootstrap tests. Building may download the base image, system packages, and Bash source.

Use `make build-test-image` to build without running tests. Both targets accept `TEST_IMAGE=<tag>` to override the
default `libsh-container-test` tag and `PRINT_HELP=y` to print help without initializing submodules or invoking Docker.
CI uses `make build-test-image test-container`; Make shares the build prerequisite so the image is built once.

## ℹ️ Commit Message Format

This specification is inspired by and supersedes the **AngularJS commit message format**.

We have very precise rules over how our Git commit messages must be formatted.
This format leads to **easier to read commit history**.

Each commit message consists of a **header**, a **body**, and a **footer**.

```text
<header>
<BLANK LINE>
<body>
<BLANK LINE>
<footer>
```

The `header` is mandatory and must conform to the [Commit Message Header](#commit-header) format.

The `body` is mandatory for all commits except for those of type "docs".
When the body is present it must be at least 20 characters long and must conform to
the [Commit Message Body](#commit-body) format.

The `footer` is optional. The [Commit Message Footer](#commit-footer) format describes what the footer is used for and
the structure it must have.

### <a name="commit-header"></a>Commit Message Header

```text
<type>(<scope>): <short summary>
  │       │             │
  │       │             └─⫸ Summary in present tense. Not capitalized. No period at the end.
  │       │
  │       └─⫸ Commit Scope: lib|scripts|bin|test|config|docs
  │
  └─⫸ Commit Type: build|ci|docs|feat|fix|perf|refactor|test|chore
```

The `<type>` and `<summary>` fields are mandatory, the `(<scope>)` field is optional.

#### Type

Must be one of the following:

- **feat**: New features
- **fix**: Bugfixes
- **docs**: Documentation changes
- **refactor**: Code changes which neither add features nor fix bugs
- **test**: Adding tests or improving upon existing tests
- **chore**: Miscellaneous maintenance tasks which can generally be ignored
- **build**: Changes or improvements to the build tool or to the project's dependencies (_supported Scopes_: `config`)
- **ci**: Changes to CI configuration files and scripts (_supported Scopes_: `actions`)

#### Scopes

The following is the list of supported scopes:

- `lib` — Changes affecting the Bash library (`lib/`)
- `scripts` — Changes to executable scripts (`scripts/`)
- `bin` — Changes to the standalone entry points (`bin/`)
- `test` — Changes to the BATS test suite (`test/`)
- `config` — Changes to configuration files (`Makefile`, `.editorconfig`, `.pre-commit-config.yaml`, etc.)
- `docs` — Documentation changes (`README.md`, `docs/`)

#### Summary

Use the summary field to provide a succinct description of the change:

- use the imperative, present tense: "change" not "changed" nor "changes"
- don't capitalize the first letter
- no dot (.) at the end

#### <a name="commit-body"></a>Commit Message Body

Just as in the summary, use the imperative, present tense: "fix" not "fixed" nor "fixes".

Explain the motivation for the change in the commit message body. This commit message should explain _why_ you are
making the change.
You can include a comparison of the previous behavior with the new behavior in order to illustrate the impact of the
change.

#### <a name="commit-footer"></a>Commit Message Footer

The footer can contain information about breaking changes and deprecations and is also the place to reference GitHub
issues, Jira tickets, and other PRs that this commit closes or is related to.
For example:

```text
BREAKING CHANGE: <breaking change summary>
<BLANK LINE>
<breaking change description + migration instructions>
<BLANK LINE>
<BLANK LINE>
Fixes #<issue number>
```

or

```text
DEPRECATED: <what is deprecated>
<BLANK LINE>
<deprecation description + recommended update path>
<BLANK LINE>
<BLANK LINE>
Closes #<pr number>
```

Breaking Change section should start with the phrase "BREAKING CHANGE: " followed by a summary of the breaking change, a
blank line, and a detailed description of the breaking change that also includes migration instructions.

Similarly, a Deprecation section should start with "DEPRECATED: " followed by a short description of what is deprecated,
a blank line, and a detailed description of the deprecation that also mentions the recommended update path.

#### Revert commits

If the commit reverts a previous commit, it should begin with `revert:`, followed by the header of the reverted commit.

The content of the commit message body should contain:

- information about the SHA of the commit being reverted in the following format: `This reverts commit <SHA>`,
- a clear description of the reason for reverting the commit message.

## ✅ How to Contribute

1. Fork this repository, develop, and test your changes
2. Run `make format`, `make lint`, and `make test` to ensure your changes pass all checks
3. Add your GitHub username to the [`AUTHORS`](../.github/AUTHORS) and [`CODEOWNERS`](../.github/CODEOWNERS) files
4. Submit a pull request

_**NOTE**_: In order to make testing and merging of PRs easier, please submit changes to unrelated areas of the
repository in separate PRs.

### Technical Requirements

Naming follows [`NOMENCLATURE.md`](NOMENCLATURE.md); most of the rules below are enforced by `make test` rather than by
review.

**Everywhere:**

- Must target Bash 4.0 or higher (associative arrays are used; `local -n` namerefs are deliberately avoided so the
  library also runs on 4.0–4.2)
- Must pass `make lint` with zero findings and `make test` with zero failures
- Follow the [shell readability standard](#shell-readability-and-function-comments) below.

**Scripts under `scripts/`**

- Start with `#!/usr/bin/env bash` followed by `set -euo pipefail`
- Named `<domain>-<verb>[-<object>].sh`, where the domain is the resource being acted on and never the binary that
  implements it
- Resolve a nonempty `LIBSH_DIR` before falling back to checkout-local `../lib`; fail if the selected library is missing.
  Resolve that directory physically once before sourcing modules, so updates cannot mix releases.
  See [the consumer example](../bin/README.md#consume-the-library-in-scripts). Do not invoke `libman` at runtime.
- Parse arguments through `lib::opt::parse` rather than positionally, and expose `--help` and `--check-prerequisites`
- The parser returns on help: after parsing, return from `main` when `${OPTS_VALUES[help]:-}` is `1`.
  Library functions declare all three parser arrays locally to preserve the enclosing caller's state.
- Anything that changes state also offers `--dry-run`
- Anything destructive is gated behind `ext::ui::confirm`, with `-y`/`--yes` to bypass it for unattended runs
- Secrets are read from a file or an environment variable, never accepted as a plain command-line argument alone

**Tooling under `tools/`**

- Repository-maintenance-only: scripts here only make sense run against a full `libsh` checkout (this repo's own
  release process), unlike `scripts/`'s user-facing operational scripts. They are never installed onto a target
  machine by [`bin/install`](../bin/install) unless explicitly requested with `INCLUDE_TOOLS=1`
- Follow the same conventions as `scripts/` above (shebang, `set -euo pipefail`, `lib::opt::parse`, `--help`,
  `--check-prerequisites`, `--dry-run` for anything that changes state)

**Library modules under `lib/` and `extensions/`**

- Begin with `# shellcheck shell=bash` on the first line
- Define every public and private function with the `function` keyword: `function name() { ... }`.
  Executable scripts under `scripts/`, `tools/`, and `bin/`, and test helpers, may omit the keyword.
- Reserve `lib::<module>::<function>` for the public API, where `<module>` is the containing filename without `.sh`.
  Public functions can call as many private helpers as needed.
  Only `lib/lib.sh` uses the global `lib::<function>` scope: `lib::load` and `lib::load_extensions`.
  This loader exception avoids `lib::lib` repetition; it does not exempt functions from the keyword requirement.
  Extensions in `extensions/lib<name>.sh` use `ext::<name>::<function>` for their public APIs.
- Name private helpers `__libsh_<module>_<function>`, for example `__libsh_net_endpoint_host`.
  Do not put private helpers in the public namespace as `lib::<module>::__<function>`.
  Function names after either prefix use lowercase letters, digits, and underscores, starting with a letter.
- Private helpers are implementation details, not supported consumer APIs. Bash still loads them into the caller's
  shell; the naming convention distinguishes their role and keeps the public API enumerable by its `lib::` prefix.
  Reserve `__libsh_` for library internals, including private helper names and internal variables.
- Extension private helpers use `__libsh_ext_<name>_<function>`.
- Ship a matching `test/lib/<module>.bats` for core or `test/extensions/<name>.bats` for an extension
- Write errors with `lib::log::red`, which goes to stderr; progress output goes to stdout

### Shell readability and function comments

Use logical paragraphs: keep adjacent steps that serve one purpose together, and separate different
steps with one blank line. Validation, preparation, processing, and output often form useful groups;
they are not mandatory sections for every function. Small helpers may need no internal blank lines.
Use `lib::load`, `lib::opt::parse`, and `lib::net::ip_address` as reference examples.

- Keep short, readable `case` arms for simple mappings. Use one arm per line; expand long or multi-step
  arms, especially option parsing. Separate related groups where it helps scanning.
- Expand inline `if`/`else` and loop bodies. Keep `then`/`do` on the opening line and closing keywords
  on their own lines. A short guard such as `command || return 1` is fine.
- Keep closely related declarations and assignments together. Split them when they become hard to
  scan; do not enforce one variable per line or add spacing merely to increase line counts.
- Use two spaces for owned shell sources and BATS tests. Preserve literal fixture contents and tabs
  required by `<<-` heredocs. `.editorconfig` controls indentation, indented case arms and leading
  continuation operators for both `make format` and pre-commit.
- Target 80 columns. Wrap long pipelines at their stages. Keep reviewed exceptions for literal
  output, fixture data, URLs, digests, regexes and Bash compatibility expressions.
- Preserve the established variable-expansion style. Quote arguments; use braces for boundaries,
  defaults, arrays and other required expansions. Preserve intentionally unquoted matching operands.
- Declare function-specific variables locally. Separate declarations from fallible command
  substitutions so their status can be checked. Preserve intentional output-variable writes.
- Keep pipeline/subshell boundaries and arithmetic safe under the caller's shell options. A formatting
  pass must not alter return values, output bytes, evaluation order, traps, or shell state.

Each public or private function in `lib/` and `extensions/`, and each production executable function,
uses this header layout, modeled on `lib::net::ip_address`:

```bash
#######################################
# Describe the operation and its important behavioral limits.
# Globals:
#   None
# Arguments:
#   1 - Input description
#   2 - Optional input (default: value)
# Outputs:
#   Result to stdout. Errors to stderr.
# Returns:
#   Describe this function's actual return statuses.
#######################################
function lib::module::example() {
  ...
}
```

Keep the four required sections in that order, with labels on separate lines, three spaces after `#`
for section contents, and `None` for an empty section. Number arguments individually (`1+` for variadic
arguments); explain defaults, accepted values and caller-owned output references. An optional `Inputs:`
section after `Arguments:` describes stdin; optional `Dependencies:` after `Returns:` lists commands
or platform requirements. Put behavioral notes and specification references in the description.

Add a brief file overview after the shellcheck directive or shebang. Explain non-obvious implementation
choices without narrating every statement. Reusable test helpers use the same header layout; BATS
lifecycle hooks, test cases and small local test doubles may use concise descriptive comments.
Fixtures and vendored sources are not subject to the production function-header rule.

The [Google Shell Style Guide](https://google.github.io/styleguide/shellguide.html) remains the baseline.
Repository choices take precedence: Bash 4.0 support, executable `env bash` shebangs, existing filenames
and namespaces, and mandatory `function` declarations in sourced libraries. Correctness issues found
while applying style rules should be reviewed separately from formatting changes.

### Versioning

The project follows [SemVer](https://semver.org/) and versions are cut automatically by
[semantic-release](https://semantic-release.gitbook.io/) from [Conventional Commits](https://www.conventionalcommits.org/)
on `main` — there is no manual version bump to make. `fix:` commits bump PATCH, `feat:` commits bump MINOR, and a
`BREAKING CHANGE:` footer (or a `!` after the type/scope) bumps MINOR under the current pre-1.0 policy. A version check blocks releases outside `0.x`; enabling `1.0.0` requires an explicit policy change. Describe breaking changes and migration
instructions in that footer; semantic-release surfaces it in the generated release notes.

Release configuration stays in JSON `.releaserc`. Its breaking-change rule selects a minor release.
`verifyReleaseCmd` checks the proposed version before preparation; `release-prepare.sh` also rejects non-`0.x`
versions before changing files. Run `make test-release` (BATS and Node.js) to check this policy.
Graduating to `1.0.0` requires reviewing both the JSON rule and the version restriction explicitly.

The `VERSION` variable in the [`Makefile`](../Makefile) (read by [`make version`](../Makefile)) reflects the most
recently released version between releases. It is written back automatically as part of the release commit — do not
edit it by hand.

A green [`testing.yaml`](../.github/workflows/testing.yaml) run on `main` dispatches
[`release.yaml`](../.github/workflows/release.yaml), which runs semantic-release. Its `prepareCmd`
([`tools/release-prepare.sh`](../tools/release-prepare.sh)) syncs the `Makefile`'s `VERSION` to the resolved next
version, rebuilds `dist/` via `make build`, and writes `dist/CHECKSUMS_SHA256.txt`, before semantic-release tags the
release, publishes those archives as GitHub release assets, and commits the updated `Makefile` and `CHANGELOG.md`
back to `main`.
