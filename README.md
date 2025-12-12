<p align="center">
    <!-- PowerShell -->
    <picture>
      <source media="(prefers-color-scheme: dark)" srcset="https://github.com/adnoctem/artwork/blob/425046029eaed451f5ced22ddc650059dff11878/projects/libsh/icon/color/bash-icon-color.png?raw=true">
      <img src="https://github.com/adnoctem/artwork/blob/425046029eaed451f5ced22ddc650059dff11878/projects/libsh/icon/color/bash-icon-color.png?raw=true" alt="BASH Logo" width="225">
    </picture>
    <h1 align="center">libsh</h1>
</p>

[![GitHub top language](https://img.shields.io/github/languages/top/adnoctem/libsh)](https://www.gnu.org/software/bash/)
[![GitHub License](https://img.shields.io/github/license/adnoctem/libsh?label=License)](https://opensource.org/license/mit)
[![GitHub Tag](https://img.shields.io/github/v/tag/adnoctem/libsh?label=Version)](https://github.com/adnoctem/libsh/releases)
[![Continuous Integration](https://github.com/adnoctem/libsh/actions/workflows/ci.yaml/badge.svg)](https://github.com/adnoctem/libsh/actions/workflows/ci.yaml)
[![GitHub last commit](https://img.shields.io/github/last-commit/adnoctem/libsh?label=Activity)](https://github.com/adnoctem/libsh/commits/main/)

A library of open-source [MIT][license]-licensed [Bash][bash] scripts written and maintained by `Ad Noctem Collective` for use
with [Bash][bash] version 5 and above. Refer to the GNU Projects's in-depth [Bash Documentation][bash_docs] for more
information on how these scripts work. Scripts meant for direct execution by the user, an init system or other means of
automation are located in the [`scripts`](scripts) directory. The [`lib`](lib) directory contains library scripts meant
to be re-used across files or even different repositories with things like [Git Submodules][git_submodules] or _contrib_
scripts like [git_subtree]. You may of course take a look at other repositories of ours for tips on how to achieve
re-use.

## ✨ TL;DR

```shell
# refer to the script 'help' command output for more information
./scripts/tar-archive.sh /var/www/html /opt/backup/destination
```

### 🔃 Contributing

Contributions are welcome via GitHub's Pull Requests. Fork the repository and implement your changes within the forked
repository, after that you may submit a [Pull Request][gh_pr_fork_docs].

### 📥 Maintainers

This project is owned and maintained by [Ad Noctem Collective](https://github.com/adnoctem) refer to
the [`AUTHORS`](.github/AUTHORS) or [`CODEOWNERS`](.github/CODEOWNERS) for more information. You may also use the linked
contact details to reach out directly.

### ©️ Copyright

_Assets provided by:_ **[Icons8 LLC][icons8]**

<!-- File references -->

[license]: LICENSE

<!-- General links -->

[icons8]: https://icons8.com/
[bash]: https://www.gnu.org/software/bash/
[bash_docs]: https://www.gnu.org/software/bash/manual/
[git_submodules]: https://git-scm.com/book/en/v2/Git-Tools-Submodules
[git_subtree]: https://www.atlassian.com/git/tutorials/git-subtree
[gh_pr_fork_docs]: https://docs.github.com/en/pull-requests/collaborating-with-pull-requests/proposing-changes-to-your-work-with-pull-requests/creating-a-pull-request-from-a-fork
