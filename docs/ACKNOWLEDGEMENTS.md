# Ad Noctem Collective `libsh` - Repository Source Acknowledgements

References, tools and projects that informed `libsh`. Installer links record design references;
Bitnami inspired the core/extension approach without code copying. Upstream code and dependencies
retain their own licenses; a reference here does not imply that its code is bundled with `libsh`.

## 🌐 Sites

- [GNU Bash - language and built-in reference][bash_docs]
- [Google's Shell Style Guide - source readability and function comments][shell_style]
- [XDG Base Directory Specification - user directory conventions][xdg_spec]
- [Semantic Versioning - version parsing and comparison][semver_spec]
- [BATS Docs - shell testing and suite setup][bats_docs]

## 📦 Repositories

- [`bitnami/containers` - container library and initialization design inspiration][bitnami_repo]
- [`adnoctem/PSFoundation` - networking and operation-tracking API inspiration][psfoundation_repo]
- [`bats-core/bats-core` - vendored Bash test framework][bats_repo]
- [`bats-core/bats-support` - vendored test helpers][bats_support_repo]
- [`bats-core/bats-assert` - vendored assertion helpers][bats_assert_repo]
- [`jkroepke/helm-secrets` - BATS suite setup reference][helm_secrets_setup]
- [`koalaman/shellcheck` - shell static analysis][shellcheck_repo]
- [`mvdan/sh` - shell formatting with shfmt][shfmt_repo]
- [`outline/outline` - architecture and community-policy documentation style][outline_docs]

## 🛠️ Installers

- [`docker/docker-install` - Docker's install script][docker_install_repo]
- [`starship/starship` - Starship's install script][starship_install]
- [`pnpm/get.pnpm.io` - pnpm's install script][pnpm_install]
- [`nvm-sh/nvm` - nvm's install script][nvm_install]

## 🧩 Snippets

- [Convert a MySQL database character set and collation - Stack Overflow][so_mysql_charset]

## 💡 Under Review

- [`krebs/array` - POSIX array implementation and API ideas; not integrated][krebs_array_repo]

<!-- INTERNAL REFERENCES -->

<!-- File references -->

<!-- General links -->

[bash_docs]: https://www.gnu.org/software/bash/manual/
[shell_style]: https://google.github.io/styleguide/shellguide.html
[xdg_spec]: https://specifications.freedesktop.org/basedir-spec/latest/
[semver_spec]: https://semver.org/spec/v2.0.0.html
[bats_docs]: https://bats-core.readthedocs.io/en/stable/tutorial.html
[so_mysql_charset]: https://stackoverflow.com/questions/6115612/how-to-convert-an-entire-mysql-database-characterset-and-collation-to-utf-8

<!-- Application links -->

[bitnami_repo]: https://github.com/bitnami/containers
[psfoundation_repo]: https://github.com/adnoctem/PSFoundation
[bats_repo]: https://github.com/bats-core/bats-core
[bats_support_repo]: https://github.com/bats-core/bats-support
[bats_assert_repo]: https://github.com/bats-core/bats-assert
[helm_secrets_setup]: https://github.com/jkroepke/helm-secrets/blob/main/tests/lib/setup_suite.bash
[shellcheck_repo]: https://github.com/koalaman/shellcheck
[shfmt_repo]: https://github.com/mvdan/sh
[docker_install_repo]: https://github.com/docker/docker-install
[starship_install]: https://github.com/starship/starship/blob/master/install/install.sh
[pnpm_install]: https://github.com/pnpm/get.pnpm.io/blob/main/install.sh
[nvm_install]: https://github.com/nvm-sh/nvm/blob/master/install.sh
[krebs_array_repo]: https://github.com/krebs/array
[outline_docs]: https://github.com/outline/outline/tree/main/docs
