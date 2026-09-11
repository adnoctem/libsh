# Bash Library - Executables

These executables are standalone: none requires an installed copy of `libsh`.

- **`install`** bootstraps `libman` and installs the library from a verified release.
- **`libman`** manages a machine's library installation, updates, and removal.
- **`libtree`** vendors the library into another repository through `git subtree`.

## Install and Configure Your Shell

```shell
# Install without modifying shell configuration
curl -fsSL https://raw.githubusercontent.com/adnoctem/libsh/main/bin/install | bash

# Also add the LIBSH_DIR export to ~/.bashrc (use zsh for ~/.zshrc)
curl -fsSL https://raw.githubusercontent.com/adnoctem/libsh/main/bin/install | bash -s -- --init-shell bash

# Pin a release; environment variables and flags both work
curl -fsSL https://raw.githubusercontent.com/adnoctem/libsh/main/bin/install | LIBSH_VERSION=1.2.0 bash
```

The piped bootstrap requires a release whose `bin` bundle includes `libman`. From a checkout, `bash bin/install`
uses the adjacent manager and can also install older library releases. Check `bash bin/install --help` for options.

Root installations default to `/usr/local/lib/libsh`, with the `libman` command in `/usr/local/bin`.
Other users default to `$HOME/.local/lib/libsh` and `$HOME/.local/bin`. Override both paths when needed.

`--init-shell bash|zsh|auto` opts into a marked `export LIBSH_DIR='…'` block in the selected rc file.
`auto` uses the basename of `$SHELL`. Repeating the command replaces that block; unrelated contents and existing rc
symlinks are preserved. The block exports a path only: it does not source Bash library functions into Zsh.
Without this flag (or its environment equivalent), no shell configuration is changed.

The installer prints the export to run in your current shell. Alternatively, open a new interactive shell after setup.
Add the printed `PATH` line to the same rc file **yourself**, if the command directory is not already on your path:

```shell
# Example for a user installation; append manually to ~/.bashrc or ~/.zshrc
export PATH="$HOME/.local/bin:$PATH"
```

The installer and manager never change `PATH`, `BASH_ENV`, `/etc/environment`, or the parent shell.
`--no-modify-profile` explicitly forbids rc changes and conflicts with `--init-shell`.
The former `--profile-targets` / `LIBSH_PROFILE_TARGETS` settings are rejected with migration instructions.
When migrating an older installation, manually remove any old libsh auto-sourcing blocks, profile.d file, or
`BASH_ENV` setting you no longer want; the manager does not edit those locations.

## Manage an Installation

```shell
libman status             # Installed versions, paths and release repository; offline
libman path               # Only the directory containing lib.sh; offline
libman update             # Latest library release from the saved repository
libman install 1.2.0      # Select an exact library release, including a downgrade
libman self-update       # Update the standalone manager independently
libman uninstall         # Confirm removal interactively; --yes for automation
```

Until you add its directory to `PATH`, invoke the printed absolute command path instead.
The installed manager remembers its installation paths, repository, and tools selection. Re-running the installer
against the same installation is also supported; it is no longer necessary for routine updates.
Changing command or tools directories requires uninstalling and reinstalling.
`update` and `self-update` use `latest` unless a version override is supplied.

Downloads have connection and total timeouts and are verified against the release's SHA-256 manifest.
The manager stages complete releases beside the stable library path, under `<install-dir>.libman/releases/`, then
atomically switches its `current` symlink. Updates do not leave removed modules behind. Old releases remain on disk
so already-loaded shells can keep using their resolved release directory; uninstall removes that managed state.
A recognized legacy library/tools directory is moved to `<directory>.libman-backup` and retained even after uninstall.
Unrelated files, commands, and symlinks are refused rather than overwritten.

Operations on one installation use a directory lock. If a process is killed without cleanup, verify that no manager
is running before manually removing `<install-dir>.libman-lock`. Uninstall leaves shell configuration in place and
prints a reminder to remove the export block and any manually added `PATH` line.

### Configuration

Flags override environment values, which override saved settings where applicable.
`LIBSH_DIR` is for **consuming** an installation; `LIBSH_INSTALL_DIR` chooses which installation to **manage**.

| Environment variable      | Flag                           | Purpose                                                    |
| ------------------------- | ------------------------------ | ---------------------------------------------------------- |
| `LIBSH_VERSION`           | `--version TAG`                | Release, default `latest`; optional leading `v`            |
| `LIBSH_REPO`              | `--repo OWNER/REPO`            | GitHub release repository, default `adnoctem/libsh`        |
| `LIBSH_INSTALL_DIR`       | `--install-dir PATH`           | Absolute stable library path                               |
| `LIBMAN_BIN_DIR`          | `--bin-dir PATH`               | Absolute manager command directory                         |
| `LIBSH_INIT_SHELL`        | `--init-shell bash\|zsh\|auto` | Opt-in rc export; unset by default                         |
| `LIBSH_NO_MODIFY_PROFILE` | `--no-modify-profile`          | Nonempty value forbids rc changes                          |
| `INCLUDE_TOOLS`           | `--include-tools`              | `1` also installs maintenance tools; saved for updates     |
| `LIBSH_TOOLS_DIR`         | `--tools-dir PATH`             | Tools path, default alongside the library as `libsh-tools` |

Installation and updates require Linux or macOS, Bash 4.0+, curl, tar/gzip, standard file utilities, and either
`sha256sum` or `shasum`. The library has no runtime dependency on the manager and never downloads itself.
For container images, install during the build and declare `ENV LIBSH_DIR=/usr/local/lib/libsh` explicitly.
When copying between stages, preserve both the library symlink and its sibling `.libman` state, or copy the resolved
library directory's contents to a real destination. Shell rc files are not a discovery mechanism for CI or containers.

## Consume the Library in Scripts

```bash
#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
LIB_DIR=${LIBSH_DIR:-"$(dirname "$SCRIPT_DIR")/lib"}
[[ -r $LIB_DIR/lib.sh ]] || { printf 'Missing libsh: %s\n' "$LIB_DIR" >&2; exit 1; }
LIB_DIR=$(cd -P -- "$LIB_DIR" && pwd)
# shellcheck source=lib/lib.sh
source "$LIB_DIR/lib.sh"
```

A nonempty `LIBSH_DIR` takes precedence. An unset or empty value falls back to the checkout's `lib` directory;
an invalid explicit value fails with an actionable error. Resolve the directory once before sourcing multiple modules.
Repository tests and release tooling deliberately use checkout-local sources, and bootstrap executables remain standalone.
Document the required libsh release/APIs in the consuming repository's `CONTRIBUTING.md`; pin CI installations explicitly.
After sourcing `lib.sh`, `LIBSH_LOADED_VERSION` identifies the loaded release (`development` for an unstamped checkout).
`libman status` describes the current installation, which may have changed since that shell loaded its functions.

## Vendor Sources with `libtree`

```shell
curl -LJO https://raw.githubusercontent.com/adnoctem/libsh/main/bin/libtree
chmod +x libtree
./libtree --help
```

Use `libtree` when the library source should be committed in the consuming repository, with an upstream-tracking
branch for later subtree updates. It does not manage machine installations or shell configuration.
