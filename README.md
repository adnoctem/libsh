<p align="center">
    <!-- libsh -->
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://github.com/adnoctem/artwork/blob/425046029eaed451f5ced22ddc650059dff11878/projects/libsh/icon/color/bash-icon-color.png?raw=true">
      <img src="https://github.com/adnoctem/artwork/blob/425046029eaed451f5ced22ddc650059dff11878/projects/libsh/icon/color/bash-icon-color.png?raw=true" alt="Bash Logo" width="225">
    </picture>
    <h1 align="center">libsh</h1>
</p>

[![GitHub top language][badge_language]][bash]
[![GitHub License][badge_license]][mit_license]
[![GitHub Tag][badge_version]][gh_repo_releases]
[![Testing][badge_testing]][gh_repo_workflow_testing]
[![GitHub last commit][badge_activity]][gh_repo_commits]

> [!WARNING]
>
> During pre-1.0 development (`0.x`), this project will regularly introduce breaking changes without a major version bump.
> Public APIs, file layouts, and command-line interfaces may change between releases. Pin a release for reproducible builds
> and review its release notes before updating. Stable compatibility guarantees will begin with version `1.0.0`.

An open-source [MIT][license]-licensed [Bash][bash] library maintained by [Ad Noctem Collective][gh_org] for
Bash 4.0 and above. It provides reusable functions for filesystem operations, data conversion, networking, logging,
argument parsing and system administration, with optional extensions for domain-specific tasks.

The [`lib`][dir_lib] directory contains core modules, loaded through a single entrypoint. A default installation includes
core only; [`extensions`][dir_extensions] are installed and loaded explicitly. The [`scripts`][dir_scripts] directory holds
operational scripts for direct execution by users, init systems and automation.

Standalone executables in [`bin`][dir_bin] handle distribution: [`install`][bin_install] bootstraps [`libman`][bin_libman]
to manage a shared installation, while [`libtree`][bin_libtree] vendors core and selected addons through [Git subtree][git_subtree].
You can also reuse the repository through [Git submodules][git_submodules]. See the [installation guide][doc_installation]
for installation paths, selective bundles, updates and container usage.

## ✨ TL;DR

Install core and configure your shell. The installer can add a `LIBSH_DIR` export to your Bash or Zsh rc file;
it does not load library functions or change `PATH`. Use the paths printed by the installer if you choose a custom
or system-wide installation.

```shell
# Install core and opt in to a LIBSH_DIR export in ~/.bashrc (or use --init-shell zsh).
curl -fsSL https://raw.githubusercontent.com/adnoctem/libsh/main/bin/install | bash -s -- --init-shell bash

# For the default user installation, make libman available in this shell.
# Add this PATH line to your shell configuration yourself if needed.
export PATH="$HOME/.local/bin:$PATH"
export LIBSH_DIR="$(libman path)"

# Inspect the installation and update core and the standalone manager.
libman status
libman update
libman self-update

# Install optional addons matching the installed core release.
libman extension-add git secret
libman extensions
```

Run the following library examples in **Bash 4.0+**, including on macOS; its bundled Bash 3.2 is insufficient.
The [Bash manual][bash_docs] explains the language and shell features used throughout the project.
Start a fresh consuming shell after updating: already-sourced functions remain in existing shells.

```bash
# Load core; LIBSH_DIR points to the directory containing lib.sh.
source "$LIBSH_DIR/lib.sh"

# Log readable, timestamped messages. Debug is silent unless enabled.
lib::log::print_info 'Starting configuration'
LIBSH_DEBUG=true lib::log::print_debug 'Debug enabled for this call'
lib::log::print_success 'Core is ready'

# Keep calculations in bytes and format only for display.
bytes=$(lib::data::bytes_from 2 MiB)
lib::data::bytes_to "$bytes" KB 3   # 2097.152
lib::data::bytes_format "$bytes"    # 2.00 MiB

# Installing an addon does not load it; request it explicitly when needed.
lib::load_extensions git secret
```

Try an edit against a disposable configuration file. Editing uses POSIX extended regular expressions with sed-style
replacement text. No match is an error. Default edits replace the file; `--in-place` retains the existing file object
and can work in a nonwritable parent directory, but an interrupted write can leave partial contents.

```bash
source "$LIBSH_DIR/lib.sh"

config=$(mktemp /tmp/libsh-example.XXXXXXXX)
printf 'workers=2\n' >"$config"
lib::fs::file_replace_content "$config" '^workers=[0-9]+$' 'workers=4'
cat "$config" # workers=4

lib::fs::file_replace_content "$config" '^workers=[0-9]+$' 'workers=8' --in-place
cat "$config" # workers=8
rm -- "$config"
```

Operational scripts run from a checkout and have their own command dependencies. Inspect help and check prerequisites
before invoking them; use `--dry-run` to preview supported state-changing operations.

```shell
./scripts/archive-create.sh --help
./scripts/archive-create.sh --check-prerequisites
./scripts/archive-create.sh --sources ./docs --output-dir /tmp/libsh-archives --dry-run
```

## 📚 Documentation

| Document                                        | What you will find                                                                                                         |
| ----------------------------------------------- | -------------------------------------------------------------------------------------------------------------------------- |
| [Architecture][doc_architecture]                | Repository layout, core and extension boundaries, loading, runtime contracts and release flow.                             |
| [API reference][doc_api]                        | Every public core and extension function, with arguments, return statuses, output behavior, dependencies and examples.     |
| [Installation and management][doc_installation] | Bootstrap options, libman commands, addon selection, shell setup, container images and vendoring with libtree.             |
| [Contributing guidelines][doc_contributing]     | Development setup, build and test commands, source formatting, function comments, conventional commits and release policy. |
| [Nomenclature][doc_nomenclature]                | File naming, approved script verbs, public namespaces and private helper conventions.                                      |
| [Agent guidance][doc_agents]                    | Repository-specific instructions for coding agents, including supported Bash versions and required checks.                 |
| [Code of Conduct][doc_conduct]                  | Participation expectations, private conduct reporting and maintainer enforcement.                                          |
| [Security policy][doc_security]                 | Private vulnerability reporting, version support, installation trust, privilege boundaries and handling secrets.           |
| [Source acknowledgements][doc_acknowledgements] | Upstream tools, design references, installer examples and documentation inspiration.                                       |
| [TODO][doc_todo]                                | Remaining work and ideas under consideration; completed work is recorded in Git history and release notes.                 |

### 🔃 Contributing

Contributions are welcome via GitHub's Pull Requests. Fork the repository and implement your changes within the forked
repository, after that you may submit a [Pull Request][gh_pr_fork_docs].

Refer to the [Contributing Guidelines][doc_contributing] for the build targets, coding conventions, and commit
message format, and to [`NOMENCLATURE.md`][doc_nomenclature] for how scripts and library functions are named.
Participation follows the [Code of Conduct][doc_conduct]. Report suspected vulnerabilities privately
using the [Security Policy][doc_security].

### 📥 Maintainers

This project is owned and maintained by [Ad Noctem Collective][gh_org]. Refer to
the [`AUTHORS`][authors] or [`CODEOWNERS`][codeowners] for more information. You may also use the linked
contact details to reach out directly.

### ©️ Copyright

_Assets provided by:_ **[Icons8 LLC][icons8]**

Project references and upstream tools are listed in [Source Acknowledgements][doc_acknowledgements].

<!-- File references -->

[license]: LICENSE
[authors]: .github/AUTHORS
[codeowners]: .github/CODEOWNERS
[dir_lib]: lib
[dir_extensions]: extensions
[dir_scripts]: scripts
[dir_bin]: bin
[bin_install]: bin/install
[bin_libman]: bin/libman
[bin_libtree]: bin/libtree
[doc_architecture]: docs/ARCHITECTURE.md
[doc_api]: docs/API.md
[doc_installation]: bin/README.md
[doc_contributing]: docs/CONTRIBUTING.md
[doc_nomenclature]: docs/NOMENCLATURE.md
[doc_agents]: docs/AGENTS.md
[doc_conduct]: docs/CODE_OF_CONDUCT.md
[doc_security]: docs/SECURITY.md
[doc_acknowledgements]: docs/ACKNOWLEDGEMENTS.md
[doc_todo]: docs/TODO.md

<!-- General links -->

[icons8]: https://icons8.com/
[mit_license]: https://opensource.org/license/mit
[bash]: https://www.gnu.org/software/bash/
[bash_docs]: https://www.gnu.org/software/bash/manual/
[git_submodules]: https://git-scm.com/book/en/v2/Git-Tools-Submodules
[git_subtree]: https://www.atlassian.com/git/tutorials/git-subtree

<!-- GitHub links -->

[gh_org]: https://github.com/adnoctem
[gh_repo_releases]: https://github.com/adnoctem/libsh/releases
[gh_repo_workflow_testing]: https://github.com/adnoctem/libsh/actions/workflows/testing.yaml
[gh_repo_commits]: https://github.com/adnoctem/libsh/commits/main/
[gh_pr_fork_docs]: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request-from-a-fork

<!-- Badge images -->

[badge_language]: https://img.shields.io/github/languages/top/adnoctem/libsh
[badge_license]: https://img.shields.io/github/license/adnoctem/libsh?label=License
[badge_version]: https://img.shields.io/github/v/tag/adnoctem/libsh?label=Version
[badge_testing]: https://github.com/adnoctem/libsh/actions/workflows/testing.yaml/badge.svg
[badge_activity]: https://img.shields.io/github/last-commit/adnoctem/libsh?label=Activity
