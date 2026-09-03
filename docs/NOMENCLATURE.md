# Nomenclature: `<domain>-<verb>[-<object>].sh`

Status: adopted. Supersedes the earlier `<verb>-<noun>.sh` scheme.

## Verdict

Switch to noun-first. It is the better fit for this library, for one
reason that outweighs everything else: **these are files in a directory,
not commands in a shell.** `ls scripts/` sorts alphabetically, so the
leading token decides what clusters together. Verb-first scatters every
MySQL script across the listing; noun-first puts them in one block:

```text
verb-first                     noun-first
-----------------------------  -----------------------------
backup-mysql.sh                arch-update-mirrors.sh
compare-zones-dns.sh           arch-update-packages.sh
migrate-mysql-charset.sh       archive-create.sh
new-archive.sh                 dns-compare-zones.sh
restore-mysql.sh               mysql-backup.sh
update-arch-mirrors.sh         mysql-migrate-charset.sh
update-arch-packages.sh        mysql-restore.sh
```

The right-hand column answers "what can I do to MySQL?" by reading four
adjacent lines. The left-hand column requires reading all of them. Tab
completion follows the same logic: `mysql-<TAB>` is the question people
actually ask; `backup-<TAB>` is not.

This is also where the CLIs that grew large ended up -- `aws s3 cp`,
`az group create`, `docker container run`, `gh pr merge` are all
noun-first. PowerShell's `Verb-Noun` went the other way because it
optimizes for `Get-Command -Verb Get` discovery across thousands of
cmdlets from unrelated modules; a repo with a `scripts/` directory has
no such problem, and pays the grouping cost for nothing.

**The one real cost:** verb discoverability. "Which scripts back things
up?" is no longer a prefix match. The approved-verb table below is what
keeps that from turning into a free-for-all, and `ls scripts/ | grep
-- -backup` still answers it.

## Grammar

```text
<domain>-<verb>[-<object>].sh
```

- **`<domain>`** -- the system or resource being acted on, **never the
  binary that implements it**. This is the same rule that renamed
  `mysqldump` -> `mysql`, applied to the leading token:
  `dig` is a binary, DNS is the domain; `tar` is a binary, an archive is
  the domain. The binary can be swapped out next year; the domain cannot.
- **`<verb>`** -- exactly one, from the table below. Two verbs means two
  scripts. `arch-packages.sh`'s `update`/`mirrors` subcommands become
  `arch-update-packages.sh` and `arch-update-mirrors.sh`, which is the
  same move that turned `deps` into `--check-prerequisites`.
- **`<object>`** -- optional, and only when the verb alone is ambiguous
  within the domain. `mysql-backup.sh` needs no object because backing up
  a MySQL server means one thing. `mysql-migrate-charset.sh` does, because
  migrating a schema and migrating a charset are different operations.

Singular domain, plural object where the object is naturally plural:
`arch-update-packages.sh`, `dns-compare-zones.sh`.

## Approved verbs

Extend this table in a PR; do not invent verbs per script.

| Verb      | Use for                                              |
| --------- | ---------------------------------------------------- |
| `backup`  | Create a point-in-time copy of something             |
| `restore` | Load a backup back into a live system                |
| `sync`    | Reconcile two locations/systems                      |
| `deploy`  | Ship a build/artifact to a target                    |
| `install` | Set up a dependency or tool on this machine          |
| `update`  | Change an existing thing in place                    |
| `remove`  | Delete/decommission something                        |
| `test`    | Validate/check without changing anything             |
| `new`     | Create a new instance of something from scratch      |
| `convert` | Transform data from one format to another            |
| `invoke`  | Run an arbitrary named task/pipeline                 |
| `migrate` | Move an existing system to a new shape in place      |
| `compare` | Diff two things and report, changing neither         |
| `list`    | Enumerate what exists and print it, changing nothing |
| `create`  | Produce a new artifact from existing inputs          |

`create` vs `new`: `new` scaffolds from nothing (`mysql-new-database.sh`),
`create` builds an artifact out of inputs you already have
(`archive-create.sh` tars files that exist).

`migrate` vs `convert`: `convert` writes a new thing and leaves the
original alone; `migrate` changes the thing in place, and is therefore
the one that needs a confirmation gate.

## Function prefixes

Derived mechanically from the filename: hyphens become underscores.
Library functions are `lib::<filename>::<function>` without exception --
`test/lib/naming.bats` enforces it, so the full set of provided functions
can be enumerated by grepping for the prefix. Library _filenames_ are
short but never abbreviated: `permissions.sh`, not `perm.sh`.

| File                       | Prefix                    |
| -------------------------- | ------------------------- |
| `mysql-backup.sh`          | `mysql_backup::`          |
| `mysql-migrate-charset.sh` | `mysql_migrate_charset::` |
| `dns-compare-zones.sh`     | `dns_compare_zones::`     |

Every script keeps the same three-function shape: `::prerequisites`,
`::exec`, and `main`.

## Rename table

| Current                    | New                         | Status                                    |
| -------------------------- | --------------------------- | ----------------------------------------- |
| `backup-mysql.sh`          | `mysql-backup.sh`           | done                                      |
| `restore-mysql.sh`         | `mysql-restore.sh`          | done                                      |
| `mysql-migrate-charset.sh` | _(unchanged)_               | already conformed                         |
| `tar-archive.sh`           | `archive-create.sh`         | done; retired to `secrets/scripts/`       |
| _(new)_                    | `archive-extract.sh`        | done; the counterpart tar-archive lacked  |
| _(new)_                    | `ubuntu-update-packages.sh` | done                                      |
| _(new)_                    | `ubuntu-update-mirrors.sh`  | done                                      |
| `dig-compare-zones.sh`     | `dns-compare-zones.sh`      | done; retired to `secrets/scripts/`       |
| `arch-packages.sh`         | `arch-update-packages.sh`   | done; split from the `update` subcommand  |
| `arch-packages.sh`         | `arch-update-mirrors.sh`    | done; split from the `mirrors` subcommand |

Each rename lands in the same PR as the update to its external call
sites (cron, CI, docs), so the two names never coexist. A replaced script
moves to `secrets/scripts/` rather than being deleted outright.

## Open questions

- `archive-create.sh` vs `archive-new.sh` -- the `create`/`new` split
  above is a judgement call, not an established convention.
- Whether `bin/libtree` and `bin/install` follow this scheme at all, or
  stay as bare entry-point names (they are commands, not resource
  operations, so probably the latter).
