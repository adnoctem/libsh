# AGENTS.md

Agent guidance for `libsh`. This file lives in `docs/` and is symlinked as
`AGENTS.md` at the repository root so it is loaded automatically. Human-facing
sources of truth: [`CONTRIBUTING.md`](CONTRIBUTING.md) (workflow, commit
format), [`NOMENCLATURE.md`](NOMENCLATURE.md) (naming rules),
[`API.md`](API.md) (documented public APIs), [`TODO.md`](TODO.md) (known gaps).

## Repository shape

A Bash 4.0+ (MIT) library with core, optional extensions, and executable bundles:

- `lib/` — sourced modules; `lib/lib.sh` is the single entrypoint and
  auto-discovers modules, so adding `lib/<module>.sh` needs no edit there
- `extensions/` — optional `lib<name>.sh` addons, loaded with `lib::load_extensions <name>`
- `scripts/` — user-facing operational scripts
- `bin/` — standalone `install`, `libman`, `libtree`; never source `lib/` from these
- `tools/` — repo-maintenance scripts, installed only with `INCLUDE_TOOLS=1`

`dist/` (build output) and `secrets/` (local planning notes) are gitignored;
`test/bats/` is vendored submodules. Do not lint or format `test/bats` or `secrets`.

## Commands

Run `make init` first (checks out BATS submodules).

- `make lint` — shellcheck, shfmt `--diff`, markdownlint, actionlint, gitleaks (authoritative)
- `make format` — rewrite Bash sources in place with shfmt (2-space indent; settings in `.editorconfig`)
- `make test` — all BATS tests; `make test WHAT=lib`, `WHAT=extensions`, or `WHAT=bin` for one directory
- Single test file: `test/bats/core/bin/bats test/lib/opt.bats` (a `bats` on `PATH` is preferred; `make test` falls back to the submodule)
- `make build [WHAT=lib]` — write archives to `dist/`; `make all` cleans and rebuilds
- `make test-container` — Docker: installed bundle on bookworm Bash and Bash 4.0, UID 10001, read-only root; separate disposable root containers test account/ownership changes. `make build-test-image` builds only

`PRINT_HELP=y make <target>` describes a target instead of running it.

## Conventions enforced by tests/lint

- `lib/` modules: first line `# shellcheck shell=bash`; public API
  `lib::<module>::<function>`, private helpers `__libsh_<module>_<function>`
  (`<module>` = filename without `.sh`). Every core module needs `test/lib/<module>.bats`. Only `lib/lib.sh` uses the global `lib::<function>` scope (`lib::load`, `lib::load_extensions`), without `lib::lib` repetition.
  Extensions use `ext::<name>::<function>` and `__libsh_ext_<name>_<function>`, with
  `test/extensions/<name>.bats`. Sourcing the loader exposes core only; addons are explicit.
- Every public or private function in `lib/` and `extensions/` must use `function name() { ... }`.
  Executable scripts in `scripts/`, `tools/`, and `bin/`, and test helpers, may omit `function`.
- No `local -n` namerefs (must run on Bash 4.0–4.2); associative arrays are fine.
- `scripts/` names: `<domain>-<verb>[-<object>].sh` with an approved verb from
  NOMENCLATURE.md. Function namespace derives from the filename
  (`archive-create.sh` → `archive_create::`, entry point `main`).
- Scripts parse args via `lib::opt::parse`: define `OPTS`, `declare -A OPTS_HELP`,
  `declare -A OPTS_VALUES` first; spec format is
  `"<short>,<long>:<key>:<0|1>:<required|optional>"`. Provide `--help`,
  `--check-prerequisites`, `--dry-run` for state changes, and gate destructive
  actions with `ext::ui::confirm`. After parsing, return from `main` if `${OPTS_VALUES[help]:-}` is `1`;
  help returns to the caller. Library functions declare all three parser arrays locally.
- Scripts resolve `LIBSH_DIR` (nonempty wins) with a checkout `../lib` fallback,
  fail if the library is missing, and `cd -P` once before sourcing. Never invoke
  `libman` at runtime.
- Errors via `lib::log::red` (stderr); progress output to stdout.
- Group related steps into logical paragraphs separated by one blank line; do not add spacing
  between every statement. Short `case` arms are welcome for simple mappings; expand complex arms.
  Follow [the readability and header standard](CONTRIBUTING.md#shell-readability-and-function-comments),
  using `lib::net::ip_address` for comment layout. Labels stand alone; section contents are indented.
  `shfmt` handles mechanical formatting only; preserve fixture contents and Bash 4.0 idioms.
- `bin/` executables stay standalone; their tests use fake `curl` release fixtures
  under `test/bin`.

## Commits and releases

- Conventional Commits are required: `type(scope): summary` with scopes
  `lib|scripts|bin|test|config|docs`. A body is mandatory except for `docs:` and
  must be at least 20 characters.
- Never edit the `Makefile` `VERSION` by hand. semantic-release on `main`/`next`
  rewrites it through `tools/release-prepare.sh`, rebuilds `dist/`, and publishes
  the archives. `fix:` bumps PATCH, `feat:` MINOR, `BREAKING CHANGE:` MINOR. Releases outside 0.x are blocked until the policy is explicitly changed.
- CI: `testing.yaml` lints and tests on Linux/macOS plus the container, then
  dispatches `release.yaml`. `superlint.yaml` is a second, less authoritative linter.

## Known state

- Generated `CHANGELOG.md` is excluded from lint/format checks; do not hand-edit it.
- `API.md` covers every public core/extension function; `test/lib/libsh.bats` checks
  that each public function has exactly one reference entry. Keep behavior and docs aligned.
- `mysql-backup.sh` / `mysql-restore.sh` function prefixes do not match their
  filenames yet (tracked in TODO.md); new scripts must not copy that pattern.
