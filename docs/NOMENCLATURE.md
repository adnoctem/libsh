# `libsh` Nomenclature

Use these conventions when adding or renaming files and functions. This document
covers `lib/` and `scripts/`; executable entry points in `bin/` are outside its scope.
See [CONTRIBUTING.md](CONTRIBUTING.md) for implementation and testing requirements.

## [lib](../lib)

> File Nomenclature: `<module>.sh`
>
> Public Function Nomenclature: `lib::<module>::<function>`
>
> Private Function Nomenclature: `__libsh_<module>_<function>`

TODO: Complete the module and function naming specification after the separate
`lib/` naming review. The public/private distinction already applies; see the
[library conventions](CONTRIBUTING.md#technical-requirements).

## [scripts](../scripts)

> File Nomenclature: `<domain>-<verb>[-<object>].sh`
>
> Function Nomenclature: `<domain>_<verb>[_<object>]::<function>`

### File names

Use lowercase words separated by hyphens and the `.sh` extension. Names identify
one operation on a system or resource:

- **Domain:** the system or resource being acted on, such as `mysql`, `dns`,
  `archive`, or `ubuntu`. Use the resource name rather than the implementing
  binary: `archive`, not `tar`; `dns`, not `dig`.
- **Verb:** one operation from the approved table below. Give independent
  operations separate scripts, such as `arch-update-packages.sh` and
  `arch-update-mirrors.sh`.
- **Object:** include it when the domain and verb alone leave the operation
  ambiguous. For example, `mysql-migrate-charset.sh` identifies what is being
  migrated, while `mysql-backup.sh` needs no additional object.

Use a singular domain and a plural object when it naturally denotes a collection,
for example `dns-compare-zones.sh`. Keeping the domain first groups related
operations in directory listings and shell completion.

### Approved verbs

Use an existing verb when it fits. Propose additions to this table in the same
change as the script that needs them.

| Verb      | Use for                                                          |
| --------- | ---------------------------------------------------------------- |
| `backup`  | Create a point-in-time copy of a resource                        |
| `restore` | Load a backup into a live system                                 |
| `sync`    | Reconcile two locations or systems                               |
| `deploy`  | Ship a build or artifact to a target                             |
| `install` | Set up a dependency or tool on this machine                      |
| `update`  | Change an existing resource in place                             |
| `remove`  | Delete or decommission a resource                                |
| `test`    | Validate without changing the resource                           |
| `new`     | Create a new instance from scratch                               |
| `convert` | Produce data in another format while retaining the original      |
| `invoke`  | Run an arbitrary named task or pipeline                          |
| `migrate` | Change an existing system's structure or representation in place |
| `compare` | Report differences without changing either input                 |
| `list`    | Enumerate existing resources without changing them               |
| `create`  | Produce an artifact from existing inputs                         |
| `extract` | Unpack an archive into files or directories                      |

Use `new` for a new instance, such as `mysql-new-database.sh`, and `create` for
an artifact built from existing inputs, such as `archive-create.sh`. Use
`convert` when retaining the original and `migrate` when changing it in place.
Destructive behavior follows the confirmation requirements in
[CONTRIBUTING.md](CONTRIBUTING.md), regardless of the chosen verb.

### Function names

Derive the function namespace from the complete filename: remove `.sh`, replace
every hyphen with an underscore, and append `::`. Function names following the
prefix use lowercase words separated by underscores.

| File                       | Function namespace        |
| -------------------------- | ------------------------- |
| `mysql-backup.sh`          | `mysql_backup::`          |
| `mysql-migrate-charset.sh` | `mysql_migrate_charset::` |
| `dns-compare-zones.sh`     | `dns_compare_zones::`     |
| `archive-extract.sh`       | `archive_extract::`       |

Use `main` as the script's unprefixed entry point. Name dependency checks
`<prefix>::prerequisites` and the operation implementation `<prefix>::exec`
where those functions are needed. Additional helpers such as `::plan` or
`::from_manifest` use the same namespace; there is no fixed function count.

When renaming a script, update its function namespace, call sites, and related
documentation or automation in the same change. Known legacy prefix mismatches
are tracked in [TODO.md](TODO.md); they do not define exceptions for new scripts.
