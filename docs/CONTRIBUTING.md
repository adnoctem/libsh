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

| Command       | Arguments | Purpose                                                                           |
| ------------- | --------- | --------------------------------------------------------------------------------- |
| `init`        |           | Check out the BATS submodules and verify the required tooling                     |
| `format`      |           | Format all Bash sources in place with `shfmt`                                     |
| `lint`        |           | Run every linter: `shellcheck`, `shfmt`, `markdownlint`, `actionlint`, `gitleaks` |
| `test`        | `WHAT`    | Run the BATS test suite                                                           |
| `build`       | `WHAT`    | Create distribution archives in `dist/`                                           |
| `all`         |           | Clean `dist/`, then build every archive                                           |
| `clean`       |           | Remove the `dist/` output directory                                               |
| `version`     |           | Print the current version                                                         |
| `tools-check` |           | Report which required tools are missing, and fail if any are                      |

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

### Linting

Run every linter across the repository:

```shell
make lint
```

This requires the following tools on your `PATH`. Run `make tools-check` to see which are missing; `make lint` refuses
to start until they are all present, rather than failing halfway through:

| Tool           | Scope                                                     |
| -------------- | --------------------------------------------------------- |
| `shellcheck`   | `lib/*.sh`, `scripts/*.sh`, and the executables in `bin/` |
| `shfmt`        | Formatting drift across the repository                    |
| `markdownlint` | All Markdown outside `test/` and `secrets/`               |
| `actionlint`   | GitHub Actions workflows                                  |
| `gitleaks`     | Secret scanning                                           |

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

- every function in `lib/` is namespaced `lib::<filename>::<function>`
- every file in `lib/` declares `# shellcheck shell=bash` on its first line
- every module in `lib/` has a matching `.bats` file
- [`lib/lib.sh`](../lib/lib.sh), the single-entrypoint loader, exposes every function the modules define

A new library module without a test file fails the suite, so coverage cannot quietly rot.

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
- Functions carry a [Google Shell Style](https://google.github.io/styleguide/shellguide.html) header comment
  documenting `Globals:`, `Arguments:`, `Outputs:`, and `Returns:`

**Scripts under `scripts/`**

- Start with `#!/usr/bin/env bash` followed by `set -euo pipefail`
- Named `<domain>-<verb>[-<object>].sh`, where the domain is the resource being acted on and never the binary that
  implements it
- Parse arguments through `lib::opts::parse` rather than positionally, and expose `--help` and `--check-prerequisites`
- Anything that changes state also offers `--dry-run`
- Anything destructive is gated behind `lib::ui::confirm`, with `-y`/`--yes` to bypass it for unattended runs
- Secrets are read from a file or an environment variable, never accepted as a plain command-line argument alone

**Tooling under `tools/`**

- Repository-maintenance-only: scripts here only make sense run against a full `libsh` checkout (this repo's own
  release process), unlike `scripts/`'s user-facing operational scripts. They are never installed onto a target
  machine by [`bin/install`](../bin/install) unless explicitly requested with `INCLUDE_TOOLS=1`
- Follow the same conventions as `scripts/` above (shebang, `set -euo pipefail`, `lib::opts::parse`, `--help`,
  `--check-prerequisites`, `--dry-run` for anything that changes state)

**Library modules under `lib/`**

- Begin with `# shellcheck shell=bash` on the first line
- Define functions as `lib::<filename>::<function>` — no exceptions, so the full set of provided functions stays
  enumerable
- Ship a matching `test/lib/<module>.bats`
- Write errors with `lib::log::red`, which goes to stderr; progress output goes to stdout

### Versioning

The project follows [SemVer](https://semver.org/) and versions are cut automatically by
[semantic-release](https://semantic-release.gitbook.io/) from [Conventional Commits](https://www.conventionalcommits.org/)
on `main` — there is no manual version bump to make. `fix:` commits bump PATCH, `feat:` commits bump MINOR, and a
`BREAKING CHANGE:` footer (or a `!` after the type/scope) bumps MAJOR. Describe breaking changes and migration
instructions in that footer; semantic-release surfaces it in the generated release notes.

The `VERSION` variable in the [`Makefile`](../Makefile) (read by [`make version`](../Makefile)) reflects the most
recently released version between releases. It is written back automatically as part of the release commit — do not
edit it by hand.

A green [`testing.yaml`](../.github/workflows/testing.yaml) run on `main` dispatches
[`release.yaml`](../.github/workflows/release.yaml), which runs semantic-release. Its `prepareCmd`
([`tools/release-prepare.sh`](../tools/release-prepare.sh)) syncs the `Makefile`'s `VERSION` to the resolved next
version, rebuilds `dist/` via `make build`, and writes `dist/CHECKSUMS_SHA256.txt`, before semantic-release tags the
release, publishes those archives as GitHub release assets, and commits the updated `Makefile` and `CHANGELOG.md`
back to `main`.
