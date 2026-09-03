# Bash Library - Executables

The files contained in this `bin` directory are self-contained Bash executables which you may download and use at will.
You can use any familiar tool like `curl` or `wget` to download these executables and make them executable on your
system. Afterward the respective tool will be fully usable to you or tell you otherwise since it includes the required
functions from `lib` within.

There are two, solving different problems:

- **`install`** deploys `lib` onto _this machine_ (e.g. a container image) and wires it up to be sourced by
  interactive and non-interactive shells. Use this when you want `lib::*` functions available at runtime, e.g. inside
  a Dockerfile.
- **`libtree`** vendors `lib`'s sources _into another repository_ via `git subtree`, with an upstream-tracking branch
  so you can pull in later changes with `libtree update`. Use this when you want the source itself checked into your
  own project.

## ✨ TL;DR

```shell
# install 'lib' onto this machine and wire it up for sourcing
curl -fsSL https://raw.githubusercontent.com/adnoctem/libsh/main/bin/install | bash

# pin a specific release instead of the latest one
curl -fsSL https://raw.githubusercontent.com/adnoctem/libsh/main/bin/install | LIBSH_VERSION=1.2.0 bash
```

```shell
# with curl
curl -LJO https://raw.githubusercontent.com/adnoctem/libsh/main/bin/libtree && chmod +x libtree
```

```shell
# with wget
wget --no-check-certificate --content-disposition https://raw.githubusercontent.com/adnoctem/libsh/main/bin/libtree && \
chmod +x libtree
```

### `install` configuration

`install` is configured entirely through environment variables, since piping into `bash` leaves no room for flags
(direct, non-piped invocation also accepts the equivalent CLI flags — see `./install --help`):

| Variable                  | Default                                                   | Purpose                                                        |
| ------------------------- | --------------------------------------------------------- | -------------------------------------------------------------- |
| `LIBSH_VERSION`           | `latest`                                                  | Release to install                                             |
| `LIBSH_REPO`              | `adnoctem/libsh`                                          | GitHub repository to install from                              |
| `LIBSH_INSTALL_DIR`       | `/usr/local/lib/libsh` (root) or `$HOME/.local/lib/libsh` | Where `lib` is deployed                                        |
| `LIBSH_PROFILE_TARGETS`   | `profile.d,bash_env`                                      | Comma-separated subset of `profile.d,bash_env,bashrc,zshrc`    |
| `LIBSH_NO_MODIFY_PROFILE` | unset                                                     | Set to deploy files only, without touching any profile         |
| `INCLUDE_TOOLS`           | unset                                                     | Set to `1` to also install the maintenance-only `tools` bundle |
| `LIBSH_TOOLS_DIR`         | alongside `LIBSH_INSTALL_DIR`, named `libsh-tools`        | Where `tools` is deployed when `INCLUDE_TOOLS=1`               |

`/etc/environment` itself is a flat `KEY=value` file parsed by PAM, not a shell script — it can't `source` anything.
That's why the `bash_env` target instead points the `BASH_ENV` variable (which bash _does_ auto-source for
non-interactive shells) at a real script, `/etc/profile.d/libsh.sh`.
