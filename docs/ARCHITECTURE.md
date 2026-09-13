# `libsh` Architecture

`libsh` is a Bash 4.0+ library with a core, explicitly loaded extensions, operational scripts and standalone
installation tools. Consumers install the pieces they need, then source core from a known directory. Loading the
library never installs packages, downloads modules or starts services.

This document describes how those pieces fit together. The [API reference][api] owns function contracts;
[Contributing][contributing] owns development practices, and [Nomenclature][nomenclature] owns naming rules.

## Layout

```text
├── bin/                  # Standalone install, libman and libtree executables
├── dist/                 # Generated release archives and checksums; gitignored
├── docs/                 # Architecture, API, policies and contribution guidance
├── extensions/           # Optional lib<name>.sh addons
├── lib/                  # Core modules, including the lib.sh entrypoint
├── scripts/              # User-facing operational scripts
├── test/
│   ├── bats/             # Vendored BATS framework and assertion submodules
│   ├── bin/              # Offline installer/manager fixtures
│   ├── container/        # Installed-library and account integration fixtures
│   ├── extensions/       # Extension behavior tests
│   ├── integration/      # Local TCP and HTTP integration tests
│   ├── lib/              # Core behavior and API coverage tests
│   └── release/          # Release configuration and version-policy tests
└── tools/                # Repository maintenance and release preparation
```

`secrets/` contains gitignored local planning notes and migration candidates, not installed library code or a
required runtime secrets directory. Root `AGENTS.md` links to `docs/AGENTS.md` for agent-facing guidance.

## Core and Loading

Consumers source `lib/lib.sh`, the single entrypoint. It resolves its physical directory and discovers adjacent
core modules automatically; adding a core module does not require maintaining an import list. Core covers data,
filesystem, comparison, hashing, logging, networking, options and operating-system helpers.

```bash
source "$LIBSH_DIR/lib.sh"
lib::log::print_info 'Core loaded'
```

`LIBSH_DIR` is the caller's discovery path to the directory containing `lib.sh`. It does not load functions by
itself. The loader records the resolved release directory in `LIBSH_LIB_DIR`, the core module count in
`LIBSH_LOADED`, and the release identity in `LIBSH_LOADED_VERSION`. A checkout reports `development`.
Repeated loading of the same physical directory reuses existing functions.

Only the loader uses the global `lib::<function>` namespace, with `lib::load` and `lib::load_extensions`.
Other public functions use `lib::<module>::<function>`; private helpers use `__libsh_<module>_<function>`.
Core modules may call each other after loading. Individual module files are not independent entrypoints.

## Extensions and Consumers

A default installation contains core only. Extensions add optional domain functionality, such as package-manager,
Git, Python, secrets, shell-history or interactive-UI helpers. Each addon is installed separately and loaded explicitly:

```bash
source "$LIBSH_DIR/lib.sh"
lib::load_extensions secret git
```

Installed addons live beside core in the release's `extensions/` directory. The loader uses the physical core
location to find matching addons and preflights requested names and files before sourcing them. It never calls
`libman` or downloads a missing addon. Extensions expose `ext::<name>::<function>` and keep private helpers under
`__libsh_ext_<name>_<function>`.

Operational scripts resolve a nonempty `LIBSH_DIR` first, with a checkout-relative `../lib` fallback. They resolve
that location physically before sourcing and load any required addons explicitly. Application-specific behavior,
confirmation and exit policy belong in the consumer. The [installer guide][installation] documents this pattern.

For containers, install core and selected addons during the image build and set `LIBSH_DIR` explicitly. Both build
steps and entrypoint scripts can use that installation. Shell rc files are not a runtime discovery mechanism.

## Installation and Release Boundaries

The executables in `bin/` are standalone and never source core:

- `install` bootstraps `libman`, using an adjacent manager in a checkout or a release bundle when downloaded alone.
- `libman` downloads selected release assets, verifies their SHA-256 checksums, stages a complete release and switches
  the managed `current` symlink. Core and selected addons are activated at one version. Old releases remain available
  for shells already using their physical paths.
- `libtree` vendors core and selected addons into another repository through `git subtree`.

The stable library path and its sibling `<install-dir>.libman` state belong together. Multi-stage images must
preserve that layout or copy the resolved release contents into a real directory. `INCLUDE_TOOLS=1` opts into
maintenance tools; they are not required for library use.

A process retains functions it has already sourced. Updating an installation or removing an addon does not rewrite
those functions in a running shell. Start a new shell or process to consume the new installation consistently.
See [Security][security] for download trust and privilege boundaries.

## Runtime Contracts

Bash 4.0 is the compatibility baseline, including on macOS; the bundled macOS Bash 3.2 is insufficient. Linux and
macOS are both tested, but Linux-specific account, memory and disk helpers remain explicitly platform-dependent.
External commands are required by the operations that use them, rather than installed automatically.

Functions declare their own return statuses and output behavior. Value-producing functions generally use stdout;
diagnostics use intent logging. INFO, SUCCESS and NOTICE use stdout; WARN, ERROR and enabled DEBUG use stderr.
All intent records use UTC timestamps from `lib::os::date`. `LIBSH_DEBUG=1` or case-insensitive `true` enables debug
at call time; disabled debug calls return before validation, formatting or file access.

Caller-owned output variables preserve bytes where command substitution would strip trailing newlines. Bash
strings cannot contain NUL. Bash options, traps and application failure policy remain the caller's responsibility
unless a function documents otherwise. In particular, legacy TCP probes may exit the shell; returning waits are
available for callers that need to recover.

Privilege escalation is explicit through `lib::os::root_exec`. Its environment-preservation option forwards to
sudo policy; it does not transfer sourced functions into a child shell. Filesystem edits prepare changes in `/tmp`; default replacement uses one final sibling staging file. Explicit
`--in-place` writes retain the existing file object and need only file-write permission, but can leave partial
contents on failure. The library does not provide transactions across files or rollback after partial failure.

## Verification and Publishing

Core and addon tests run under BATS, with API coverage checking that every public function has exactly one reference
entry. Installer tests use offline release fixtures. Integration tests exercise local TCP/HTTP behavior and installed
bundles under Bash 5.2 and 4.0, including nonroot read-only containers and disposable root account tests.
Comprehensive operational-script end-to-end coverage is still tracked in [TODO][todo].

`make lint` is the local lint entrypoint. CI runs tests on Linux and macOS, container tests and pre-commit checks;
Super-Linter runs as an additional workflow. Source and tests settle before API documentation is finalized.

Release configuration remains in JSON `.releaserc`. Semantic-release analyzes conventional commits; preparation
checks the version, updates the Makefile version, builds archives and writes the checksum manifest. During `0.x`,
breaking changes request minor releases. Both verification and preparation reject releases outside `0.x` until
that policy is explicitly changed. The [contribution guide][contributing] describes the workflow in detail.

<!-- File references -->

[api]: API.md
[contributing]: CONTRIBUTING.md
[nomenclature]: NOMENCLATURE.md
[installation]: ../bin/README.md
[security]: SECURITY.md
[todo]: TODO.md
