# ✅ `TODO`s - FMJ Studios Bash Library

## ➕ Additions

- Add sources of archived (private) project `vpsman`

## ✏️ Planned Changes

- Finish BATS testing for all of `lib`
- Add BATS testing for all `scripts`
- Transition to a BATS `setup_suite` to use more demanding tools like Container runtimes to `scripts` unit testing
- Add implementation for the `install` executable

## 💡 Ideas

- Potentially introduce a new top-level `lib` "namespace" to functions from library scripts
- Add public URL to use the `install` executable like `get.bashlib.fmj.studio` using GitHub Pages
- Add POSIX utilities for working with arrays like [`krebs/array`](https://github.com/krebs/array/blob/master/array)

## 🔗 Links

- [BATS Docs - Tutorial](https://bats-core.readthedocs.io/en/stable/tutorial.html)
- [Google's Shell Style Guide](https://google.github.io/styleguide/shellguide.html)
- [jkroepke's Helm Secrets Plugin](https://github.com/jkroepke/helm-secrets/blob/main/tests/lib/setup_suite.bash) for BATS reference

### Installer

- [Docker's Install script](https://github.com/docker/docker-install)
- [Starship's Install script](https://github.com/starship/starship/blob/master/install/install.sh)
- [PNPM's Install script](https://github.com/pnpm/get.pnpm.io/blob/main/install.sh)
- [nvm's Install script](https://github.com/nvm-sh/nvm/blob/master/install.sh)
