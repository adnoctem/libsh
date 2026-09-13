# `libsh` API reference

Bash 4.0 or newer is required, including on macOS; Apple's bundled Bash 3.2 is
unsupported. This reference covers every public function in `lib/` and
`extensions/`. Private `__libsh_*` helpers are implementation details.

## Loading and installation

The default installation contains core only. Extensions are installed addons;
loading an addon never downloads it. Install during the build stage when making
container images, then source the installed library during build or startup.
See [installation and selective bundles](../bin/README.md).

```bash
source /usr/local/lib/libsh/lib.sh
lib::load_extensions secret git # Both addons must already be installed.
```

Sourcing `lib.sh` loads all adjacent core modules. The loader records the physical
module directory in `LIBSH_LIB_DIR`, the module count in `LIBSH_LOADED`, and the
release tag in `LIBSH_LOADED_VERSION` (`development` for a checkout). Repeated
loads of the same directory reuse loaded functions. Addons live in the sibling
`extensions/` directory. `LIBSH_DIR` is the consumer's discovery path containing
`lib.sh`; setting it alone does not source anything. Resolve that path physically
once before sourcing so a manager update cannot mix releases within one shell.

Only the loader uses `lib::<function>`. Other core APIs use
`lib::<module>::<function>` and addons use `ext::<name>::<function>`.

## Shared contracts

Quote variable arguments. Uppercase words in signatures are placeholders;
`[...]` denotes optional arguments and `...` denotes repetition. Supply option
values as separate arguments. A function accepting options does not necessarily
accept `--help`; the parser only recognizes the options that its caller declares.

New value-producing APIs generally return `0` for success, `1` for operational
failure and `2` for invalid arguments. Predicates generally use `0` for true,
`1` for false and `2` for invalid input. The per-function return contract takes
precedence: comparisons, HTTP probes, account lookups, and older wrappers have
explicit differences. In particular, the legacy TCP probes can **exit the
calling shell**. Use `tcp_wait` for recoverable failures.

Sizes and comparisons use nonnegative integer bytes, bounded by
`9223372036854775807`. Display conversions are explicit. Bash strings cannot
contain NUL bytes. Output descriptions specify whether a result has a trailing
newline; command substitution strips trailing newlines, so use output-variable
APIs when those bytes matter. New library errors go to stderr; progress and
requested values go to stdout. Shell options, traps, privilege escalation and
application failure policy remain the caller's responsibility unless an entry
explicitly says otherwise. No package installation or account mutation happens
merely by loading a module.

### Output variables and secrets

For `STORE`, `OUT`, `URI_VAR`, `HOST_OUT` and `PORT_OUT` arguments documented as
references, pass an ordinary scalar **name**, not its value. Declare local
outputs in the caller before invoking the function. Otherwise an assignment may
create a global. Arrays, subscripts, expressions, namerefs, integer/case-converting
variables and readonly outputs are rejected. Shell-owned names such as `PATH`,
`IFS`, `RANDOM`, `BASH_*`, and the internal `__libsh_` prefix are reserved.
Failures preserve existing output values. Existing export attributes remain;
these functions do not automatically export values.

Disable shell tracing (`set -x`, `set -v`) and secret-observing debug traps before
handling credentials. The library does not change them. Do not print generated
or resolved secrets. URI component parsers deliberately print the requested
component, which can itself be a credential.

```bash
source /usr/local/lib/libsh/lib.sh
lib::load_extensions secret

configure_database() {
  local password db_host db_port
  ext::secret::resolve password --value-var DB_PASSWORD \
    --file-var DB_PASSWORD_FILE --mode first-line || return
  lib::net::endpoint_from_uri DB_URI db_host db_port --default-port 5432 || return
  lib::net::tcp_wait "$db_host" "$db_port" --attempts 30 --label database || return
  # Pass password to the application through its chosen configuration mechanism.
}
```

Resolution can succeed with no source and leave `password` unset. Check
`${password+x}` before using it when absence is permitted. Configuration schemas,
merging, exports, application defaults and URI construction belong to the caller.

## Module index

| Core                                  | Purpose                                        |
| ------------------------------------- | ---------------------------------------------- |
| [Loader](#loader)                     | Core and explicit addon loading                |
| [Core](#core)                         | SemVer, bounded retries, operation results     |
| [Data](#data)                         | Arrays and exact byte conversion               |
| [Filesystem](#filesystem)             | Paths, inspection, text editing, ownership     |
| [Hashing](#hashing)                   | String MD5 and SHA-2                           |
| [Comparison](#comparison)             | Version, size, metadata and content comparison |
| [Logging](#logging)                   | Terminal messages and file appends             |
| [Networking](#networking)             | Addresses, URI/DSN parsing, DNS and probes     |
| [Options](#options)                   | Caller-defined flag parsing                    |
| [Operating system](#operating-system) | Platform paths, Linux facts and accounts       |

| Addon                       | Purpose and invocation dependencies                          |
| --------------------------- | ------------------------------------------------------------ |
| [apk](#apk-extension)       | Alpine installed/update queries; `apk`                       |
| [apt](#apt-extension)       | Debian/Ubuntu simulations and parsers; APT, dpkg, `awk`      |
| [dnf](#dnf-extension)       | RPM installed/update queries; `rpm`, DNF 4/5 `repoquery`     |
| [`git`](#git-extension)     | Git repository inspection; `git`, `grep`                     |
| [py](#py-extension)         | Python environment creation and current-shell activation     |
| [secret](#secret-extension) | File/direct-value resolution and random generation; `od`     |
| [shell](#shell-extension)   | History-file discovery and scrubbing; `grep`, file utilities |
| [ui](#ui-extension)         | Confirmation, spinner and banners                            |

## Core reference

### Loader

[Source](../lib/lib.sh)

#### `lib::load`

```text
lib::load
```

Load core modules from this physically resolved library directory.

**Outputs:** Errors on stderr.

**Returns:** 0 success, 1 missing/unreadable sources, 2 unexpected arguments. Source failures propagate their
status. Successfully loaded core is reused.

**Globals:** LIBSH_LIB_DIR (read), LIBSH_LOADED, LIBSH_LOADED_VERSION (written) \_\_libsh_lib_core_dir,
\_\_libsh_lib_extensions (internal load state)

#### `lib::load_extensions`

```text
lib::load_extensions [NAME ...]
```

Load explicitly requested installed addons after ensuring core is loaded.

**Arguments:**

- 1+ - Zero or more extension names, e.g. `secret`, `git`, `apt`.

**Outputs:** Errors on stderr. Never installs or downloads extensions.

**Returns:** 0 success, 1 unavailable source, 2 invalid name; source failures propagate. Repeated loads are
harmless. Failed sources may have partial shell effects and are never marked loaded. Preflight
checks every requested addon first.

**Globals:** LIBSH_LIB_DIR, \_\_libsh_lib_extensions (read/write via loader)

### Core

[Source](../lib/core.sh)

SemVer accepts complete `MAJOR.MINOR.PATCH[-PRERELEASE][+BUILD]` strings,
without a leading `v`, whitespace, or leading zeroes in numeric identifiers.
Numeric components have no integer-size limit. Build metadata does not affect
precedence. [SemVer 2.0.0](https://semver.org/spec/v2.0.0.html) defines the grammar.
Retries have a bounded attempt count, not a wall-clock deadline.

```bash
lib::core::retry 2 5 -- lib::net::http_probe https://example.org/health

results=''
lib::core::results_add results database pending
lib::core::results_add results database success # Updates the same operation ID.
lib::core::results_list results success
lib::core::results_remove results database
```

Result IDs start with an ASCII letter, digit or underscore; subsequent characters
may also include dots, colons and hyphens. Treat the store serialization as opaque.

#### `lib::core::semver_validate`

```text
lib::core::semver_validate VERSION
```

Validate one complete SemVer 2.0.0 string, without numeric coercion. Specification:
https://semver.org/spec/v2.0.0.html

**Arguments:**

- 1 - Version (no leading v or surrounding whitespace)

**Outputs:** Invocation errors on stderr; otherwise none.

**Returns:** 0 valid, 1 invalid version, 2 incorrect argument count.

#### `lib::core::semver_parse`

```text
lib::core::semver_parse VERSION FIELD
```

Extract a field from a complete, validated SemVer string.

**Arguments:**

- 1 - Complete version

- 2 - Field: major, minor, patch, prerelease or build

**Outputs:** Field and newline on stdout; absent prerelease/build prints an empty line. Original numeric strings
are preserved without integer-size limits.

**Returns:** 0 success, 2 invalid version, field, or argument count.

#### `lib::core::retry`

```text
lib::core::retry INTERVAL ATTEMPTS -- COMMAND [ARG ...]
```

Retry an argv command with a fixed interval and bounded number of attempts. Interval is whole
nonnegative seconds; attempts is a positive integer. This is not a deadline and does not terminate a
hung command. Check command failures explicitly inside shell functions: invocation is in an if
context.

**Arguments:**

- 1 - Interval in whole nonnegative seconds

- 2 - Positive attempt count

- 3 - Literal -- separator

- 4 - Command to run

- 5+ - Command arguments (optional)

**Outputs:** Command stdout/stderr unchanged; library diagnostics on stderr.

**Returns:** 0 command succeeded, 1 all attempts failed or sleep failed, 2 invalid invocation. No sleep after
success or the final failed attempt.

**Globals:** None; each command runs in a subshell to isolate its shell changes.

#### `lib::core::results_add`

```text
lib::core::results_add STORE ID STATUS
```

Add or update one operation in a caller-owned result store. Declare a local scalar first to keep the
store local. Treat its serialization as opaque; results_list supplies stable tab-separated output.
IDs contain ASCII letters/digits/underscore, then optionally dot, colon or hyphen.

**Arguments:**

- 1 - Caller-owned scalar store name

- 2 - Operation ID

- 3 - Status: pending, success or failure

**Outputs:** None on success; errors on stderr.

**Returns:** 0 added/updated, 2 invalid input/store. Failures preserve the store.

**Globals:** Named ordinary scalar STORE (written on success); no hidden store.

#### `lib::core::results_remove`

```text
lib::core::results_remove STORE ID
```

Remove an operation from a caller-owned result store; absent IDs are a no-op.

**Arguments:**

- 1 - Caller-owned scalar store name

- 2 - Operation ID

**Outputs:** Errors on stderr only.

**Returns:** 0 removed/absent, 2 invalid input/store. Failures preserve the store.

**Globals:** Named scalar STORE (written on success).

#### `lib::core::results_list`

```text
lib::core::results_list STORE [STATUS]
```

List operations sorted by ID in ASCII order, optionally filtered by status.

**Arguments:**

- 1 - Caller-owned scalar store name

- 2 - Status filter: pending, success or failure (optional)

**Outputs:** ID&lt;TAB&gt;STATUS per line. Empty stores/selections produce no stdout.

**Returns:** 0 success, 1 sort failure, 2 invalid reference/content/filter.

**Globals:** Named scalar STORE (read only).

**Dependencies:** sort, only for nonempty output.

### Data

[Source](../lib/data.sh)

SI units use powers of 1000 (`KB` through `EB`); IEC units use powers of
1024 (`KiB` through `EiB`). Units are case-sensitive. Input conversion takes
whole units only; output conversion truncates rather than rounds. Defaults are
IEC and two decimal places when formatting automatically.

```bash
bytes=$(lib::data::bytes_from 2 MiB) # 2097152
lib::data::bytes_to "$bytes" KB 3   # 2097.152
lib::data::bytes_format "$bytes"    # 2.00 MiB

items=('a b' '[x]' '')
lib::data::array_contains '[x]' "${items[@]}"
```

#### `lib::data::array_is_empty`

```text
lib::data::array_is_empty [ELEMENT ...]
```

Determine if an array is empty

**Arguments:**

- 1+ - Array elements (zero or more)

**Outputs:** None

**Returns:** 0 if empty, 1 otherwise.

#### `lib::data::array_contains`

```text
lib::data::array_contains NEEDLE [ELEMENT ...]
```

Test literal membership in the supplied array elements.

**Arguments:**

- 1 - Needle

- 2+ - Array elements (zero or more)

**Outputs:** Errors on stderr.

**Returns:** 0 found, 1 absent, 2 missing needle.

#### `lib::data::bytes_from`

```text
lib::data::bytes_from AMOUNT UNIT
```

Convert a whole number of explicit units to bytes without rounding.

**Arguments:**

- 1 - Whole nonnegative amount

- 2 - Unit: B, KB..EB or KiB..EiB (case sensitive)

**Outputs:** Decimal bytes on stdout; errors on stderr.

**Returns:** 0 success, 2 invalid arguments, fractions, or signed 64-bit overflow.

#### `lib::data::bytes_to`

```text
lib::data::bytes_to BYTES UNIT [PRECISION]
```

Convert bytes to a numeric display value in explicit units.

**Arguments:**

- 1 - Bytes

- 2 - Unit: B, KB..EB or KiB..EiB (case sensitive)

- 3 - Precision, 0..6 (optional, default 2)

**Outputs:** Fixed-point value on stdout, truncated (never rounded up).

**Returns:** 0 success, 2 invalid arguments or bytes outside signed 64-bit range.

#### `lib::data::bytes_format`

```text
lib::data::bytes_format BYTES [iec|si] [PRECISION]
```

Format bytes using the largest applicable SI or IEC unit.

**Arguments:**

- 1 - Bytes

- 2 - System: iec or si (optional, default iec)

- 3 - Precision, 0..6 (optional, default 2)

**Outputs:** Fixed-point number, space, unit and newline. Fractions are truncated.

**Returns:** 0 success, 2 invalid arguments or signed 64-bit overflow.

### Filesystem

[Source](../lib/fs.sh)

Inspection supports GNU/Linux and macOS utilities. Lexical path operations do
not require paths to exist. Directory sizes mean logical regular-file bytes,
not allocated blocks or device capacity. Recursive inspections are not atomic
snapshots of concurrently changing trees.

Text editing uses `sed -E` under locale C. Use portable POSIX extended regular
expressions; `-E` selects that dialect but does not reject every backend-specific
extension. The multiline helper also supports `\n` in its pattern. Replacement
text uses sed syntax (`&`, `\1` through `\9`, `\\`, `\&`); other backslash escapes
are rejected. Pass actual tab/newline bytes when required. Insertion text is
literal. No match returns `1` and leaves the file unchanged.

Edits require a readable regular text file without NUL bytes, a writable parent
for staging, and permission to preserve mode, UID and GID. Final symlinks are
followed by default; `-n`/`--no-dereference` refuses them. Parent path components
resolve normally. Hard-linked targets are refused in either mode. A successful
edit replaces the target inode after staging beside it. Ordinary concurrent
changes are checked, but this is not a defense against hostile path races. ACLs,
extended attributes and timestamps are not preservation guarantees. The helper
uses `sed`, `stat`, `readlink`, `mktemp`, `cp`, `mv`, `rm`, `chmod`, `chown`, `cmp`,
`tr`, `tail`, `od`, `head`, and `uname`; no Perl dependency is needed.

```bash
lib::fs::ensure_directory ./config
printf 'workers=2\n' > ./config/app.conf
lib::fs::file_replace_content ./config/app.conf '^(workers=)[0-9]+$' '\14'
lib::fs::file_append_content_after_last_match ./config/app.conf '^workers=' $'enabled=yes\n'
lib::fs::dir_size ./config
```

#### `lib::fs::relativize`

```text
lib::fs::relativize PATH BASE
```

Compute a lexical relative path; neither operand needs to exist. Collapses repeated / and dot
components. Symlinks are never resolved.

**Arguments:**

- 1 - Nonempty path to express relatively

- 2 - Nonempty base directory path

**Outputs:** Relative path and newline; identical paths produce '.'; errors stderr.

**Returns:** 0 success, 2 invalid invocation or unavailable absolute PWD.

**Globals:** PWD (read as the logical base for relative operands)

#### `lib::fs::owner_get`

```text
lib::fs::owner_get PATH [uid|gid|user|group]
```

Read ownership, following a symlink supplied as PATH.

**Arguments:**

- 1 - Path

- 2 - Field: uid, gid, user or group (optional, default uid)

**Outputs:** Numeric UID/GID or resolved user/group name and newline; errors stderr.

**Returns:** 0 success, 1 lookup failure, 2 invalid invocation.

**Globals:** PATH (read)

**Dependencies:** uname and platform stat. Name lookup follows the host stat policy.

#### `lib::fs::dir_exists`

```text
lib::fs::dir_exists PATH
```

Test for a directory, following symlinks as Bash file tests do.

**Arguments:**

- 1 - PATH

**Outputs:** Invocation errors on stderr; otherwise none.

**Returns:** 0 directory, 1 absent/not a directory, 2 invalid invocation.

#### `lib::fs::file_exists`

```text
lib::fs::file_exists PATH
```

Test for a regular file, following symlinks as Bash file tests do.

**Arguments:**

- 1 - PATH

**Outputs:** Invocation errors on stderr; otherwise none.

**Returns:** 0 regular file, 1 absent/not regular, 2 invalid invocation.

#### `lib::fs::file_empty`

```text
lib::fs::file_empty PATH
```

Test whether an existing regular file has zero logical bytes.

**Arguments:**

- 1 - PATH (symlinks followed)

**Outputs:** Invocation errors on stderr; otherwise none.

**Returns:** 0 empty file, 1 absent/wrong type/nonempty, 2 invalid invocation.

#### `lib::fs::dir_empty`

```text
lib::fs::dir_empty PATH
```

Test whether a directory contains no entries, including hidden entries.

**Arguments:**

- 1 - PATH (explicit root symlink followed)

**Outputs:** Errors on stderr; otherwise none.

**Returns:** 0 empty directory, 1 absent/wrong type/nonempty, 2 invalid/unreadable.

**Globals:** None; glob options are changed only inside a subshell.

#### `lib::fs::dir_writable`

```text
lib::fs::dir_writable PATH
```

Test whether the current user can write/search an existing directory. Uses effective access tests;
does not probe read-only mounts by writing.

**Arguments:**

- 1 - PATH (symlinks followed)

**Outputs:** Invocation errors on stderr; otherwise none.

**Returns:** 0 writable/searchable directory, 1 false, 2 invalid invocation.

#### `lib::fs::file_writable`

```text
lib::fs::file_writable PATH
```

Test whether the current user can write an existing regular file. This is an access test, not a
guarantee that a future write succeeds.

**Arguments:**

- 1 - PATH (symlinks followed)

**Outputs:** Invocation errors on stderr; otherwise none.

**Returns:** 0 writable regular file, 1 false, 2 invalid invocation.

#### `lib::fs::file_executable`

```text
lib::fs::file_executable PATH
```

Test execute access to an existing regular file, without running it.

**Arguments:**

- 1 - PATH (symlinks followed)

**Outputs:** Invocation errors on stderr; otherwise none.

**Returns:** 0 executable regular file, 1 false, 2 invalid invocation.

#### `lib::fs::file_size`

```text
lib::fs::file_size PATH
```

Read logical file length in bytes, including sparse holes.

**Arguments:**

- 1 - PATH (must resolve to a regular file; symlinks followed)

**Outputs:** Nonnegative decimal bytes and newline; errors stderr.

**Returns:** 0 success, 1 missing/wrong type/stat failure/overflow, 2 invalid args.

**Globals:** PATH (read)

**Dependencies:** uname and platform stat. Maximum is signed 64-bit bytes.

#### `lib::fs::dir_size`

```text
lib::fs::dir_size PATH
```

Sum logical regular-file bytes recursively, including hidden entries. Counts each hard-linked path;
skips symlinks and special files below the root; crosses mount boundaries. Unreadable directories
fail. File data is not read. This is not allocated disk usage or an atomic snapshot of a changing
tree.

**Arguments:**

- 1 - PATH (explicit root symlink followed)

**Outputs:** Nonnegative decimal bytes and newline, only after full success.

**Returns:** 0 success, 1 missing/unreadable tree/stat failure/overflow, 2 bad args.

**Globals:** PATH (read); glob options change only in a subshell.

**Dependencies:** uname and platform stat.

#### `lib::fs::ensure_existence`

```text
lib::fs::ensure_existence FILE_PATH
```

Ensure the parent directory of a file path exists, without creating the file.

**Arguments:**

- 1 - PATH

**Outputs:** Errors stderr; otherwise none.

**Returns:** 0 success, 1 mkdir failure, 2 invalid invocation.

**Globals:** PATH (read)

**Dependencies:** mkdir. Symlinks in the parent path are followed.

#### `lib::fs::ensure_directory`

```text
lib::fs::ensure_directory PATH
```

Ensure a directory itself exists.

**Arguments:**

- 1 - PATH

**Outputs:** Errors stderr; otherwise none.

**Returns:** 0 success, 1 mkdir failure, 2 invalid invocation.

**Globals:** PATH (read)

**Dependencies:** mkdir. Existing directory symlinks are accepted.

#### `lib::fs::file_replace_content`

```text
lib::fs::file_replace_content FILE PATTERN REPLACEMENT [-n|--no-dereference]
```

Replace all ERE matches within each line using sed -E replacement syntax. Use & for the match,
\\1..\\9 for captures, \\\\ for a backslash and \\& for &. Supply actual tabs/newlines rather than
nonportable replacement escapes. Unmodified bytes and the original terminal newline are preserved.
Symlinks are followed by default; hard-linked and NUL-containing files are refused.

**Arguments:**

- 1 - File path

- 2 - Nonempty POSIX extended regular expression

- 3 - sed replacement text

- 4+ - Optional -n or --no-dereference to refuse a final symlink

**Outputs:** Edited file; errors to stderr. No stdout.

**Returns:** 0 on success, 1 on no match/operational failure, 2 on invalid invocation.

**Dependencies:** See the filesystem module dependency list above.

#### `lib::fs::file_replace_content_multiline`

```text
lib::fs::file_replace_content_multiline FILE PATTERN REPLACEMENT [-n|--no-dereference]
```

Replace all ERE matches across the complete file using sed -E. The whole file is held in sed pattern
space; dot matches embedded newlines, ^/$ address file boundaries, and \\n matches newline.
Replacement syntax and metadata/link handling are the same as file_replace_content.

**Arguments:**

- 1 - File path

- 2 - Nonempty POSIX extended regular expression

- 3 - sed replacement text

- 4+ - Optional -n or --no-dereference to refuse a final symlink

**Outputs:** Edited file; errors to stderr. No stdout.

**Returns:** 0 on success, 1 on no match/operational failure, 2 on invalid invocation.

**Dependencies:** See the filesystem module dependency list above.

#### `lib::fs::file_remove_content`

```text
lib::fs::file_remove_content FILE PATTERN [-n|--no-dereference]
```

Remove every complete line matching an ERE, including its terminator. Unmatched bytes keep their
original line endings. Metadata and link handling are the same as file_replace_content.

**Arguments:**

- 1 - File path

- 2 - Nonempty POSIX extended regular expression

- 3+ - Optional -n or --no-dereference to refuse a final symlink

**Outputs:** Edited file; errors to stderr. No stdout.

**Returns:** 0 on success, 1 on no match/operational failure, 2 on invalid invocation.

**Dependencies:** See the filesystem module dependency list above.

#### `lib::fs::file_append_content_after_last_match`

```text
lib::fs::file_append_content_after_last_match FILE PATTERN TEXT [-n|--no-dereference]
```

Insert literal text after the last line matching an ERE. Add a separator newline after an
unterminated matching line and, when needed, before remaining original lines. At EOF the inserted
text determines the final newline. Empty insertion text is a no-op only if the pattern matches.
Metadata and link handling are the same as file_replace_content.

**Arguments:**

- 1 - File path

- 2 - Nonempty POSIX extended regular expression

- 3 - Literal text to insert (not sed replacement syntax)

- 4+ - Optional -n or --no-dereference to refuse a final symlink

**Outputs:** Edited file; errors to stderr. No stdout.

**Returns:** 0 on success, 1 on no match/operational failure, 2 on invalid invocation.

**Dependencies:** See the filesystem module dependency list above.

#### `lib::fs::owner_set`

```text
lib::fs::owner_set PATH OWNER [-n|--no-dereference]
```

Set ownership of one path, following a final symlink by default. No recursion or automatic privilege
elevation is performed.

**Arguments:**

- 1 - Path

- 2 - USER, USER:GROUP or :GROUP; names or numeric IDs

- 3 - Optional -n or --no-dereference to change the link itself

**Outputs:** Errors to stderr; no stdout.

**Returns:** 0 success, 1 chown/path failure, 2 invalid invocation.

**Globals:** PATH (read)

**Dependencies:** chown; caller must have the required ownership-changing privileges.

### Hashing

[Source](../lib/hash.sh)

Hashes cover exact Bash string bytes without adding a newline. GNU checksum
commands are preferred when present; macOS `md5`/`shasum` are fallbacks. Backend
failure publishes no partial digest. MD5 is a checksum, not a password-storage
or security primitive.

```bash
lib::hash::string_sha 'exact input' 256
```

#### `lib::hash::string_md5`

```text
lib::hash::string_md5 STRING
```

Compute an MD5 checksum of a string (not a password/security primitive).

**Arguments:**

- 1 - String to hash

**Outputs:** Lowercase hexadecimal digest and newline; errors on stderr.

**Returns:** 0 success, 1 backend failure, 2 incorrect argument count.

**Globals:** PATH (read)

**Dependencies:** md5sum (GNU) or md5 (macOS), checked at invocation.

#### `lib::hash::string_sha`

```text
lib::hash::string_sha STRING [224|256|384|512]
```

Compute a SHA-2 digest of a string, without an implicit newline.

**Arguments:**

- 1 - String to hash

- 2 - SHA-2 algorithm: 224, 256, 384 or 512 (optional, default 256)

**Outputs:** Lowercase hexadecimal digest and newline; errors on stderr.

**Returns:** 0 success, 1 backend failure, 2 invalid invocation.

**Globals:** PATH (read)

**Dependencies:** sha\*sum (GNU) or shasum (macOS), checked at invocation.

### Comparison

[Source](../lib/cmp.sh)

Ordered comparisons print `-1`, `0` or `1` while returning success. Equality
and diff functions instead use exit status `0` equal, `1` different, `2` error.
Metadata equality includes size, mode, numeric UID/GID and whole-second mtime;
it says nothing about file contents. Tree comparison also checks relative paths
and entry types, excludes directory inode sizes, and compares symlink text.
Child symlinks are not traversed. Unsupported special files produce an error.

```bash
lib::cmp::semver_compare 1.2.0-rc.1 1.2.0 # Prints -1, returns 0.
if lib::cmp::file_diff old.conf new.conf; then
  lib::log::plain 'Same contents'
else
  status=$?
  [[ $status == 1 ]] || exit "$status"
fi
```

#### `lib::cmp::semver_compare`

```text
lib::cmp::semver_compare LEFT RIGHT
```

Compare complete SemVer 2.0.0 versions by precedence, ignoring build metadata. Specification:
https://semver.org/spec/v2.0.0.html#spec-item-11

**Arguments:**

- 1 - Left operand

- 2 - Right operand

**Outputs:** -1 (left older), 0 (equal precedence), 1 (left newer); errors stderr.

**Returns:** 0 compared, 2 invalid invocation/version. No integer-size limit.

#### `lib::cmp::size_compare`

```text
lib::cmp::size_compare LEFT_BYTES RIGHT_BYTES
```

Compare logical byte counts; use data helpers to convert explicit units first.

**Arguments:**

- 1 - Left byte count (nonnegative signed 64-bit range)

- 2 - Right byte count (nonnegative signed 64-bit range)

**Outputs:** -1, 0 or 1 and newline; errors stderr.

**Returns:** 0 compared, 2 invalid invocation/byte count.

#### `lib::cmp::file_compare`

```text
lib::cmp::file_compare LEFT RIGHT
```

Test equality of regular-file attributes, following explicit symlink inputs. Compares size, mode
(including special bits), numeric UID/GID, whole-second mtime. Ignores contents, inode, atime,
ctime, ACLs, xattrs, and subsecond times.

**Arguments:**

- 1 - Left operand

- 2 - Right operand

**Outputs:** Errors stderr; no comparison data on stdout.

**Returns:** 0 equal, 1 different, 2 invalid input or metadata failure.

**Globals:** PATH (read)

**Dependencies:** uname and platform stat. Use file_diff for content differences.

#### `lib::cmp::file_diff`

```text
lib::cmp::file_diff LEFT RIGHT
```

Print a unified content diff of two regular files, including binary detection.

**Arguments:**

- 1 - Left operand

- 2 - Right operand

**Outputs:** Diff on stdout, errors stderr. A literal '-' is a filename, not stdin.

**Returns:** 0 same contents, 1 different, 2 invalid input or diff failure.

**Globals:** PATH (read)

**Dependencies:** diff (GNU or macOS). No ignore or whitespace normalization flags.

#### `lib::cmp::dir_compare`

```text
lib::cmp::dir_compare LEFT RIGHT
```

Test recursive equality of relative paths, entry types and attributes. Includes root and child
mode/UID/GID/whole-second mtime and file/link size. Ignores directory inode sizes. Compares symlink
text without following links; counts hard-linked paths independently; crosses mounts; includes
hidden files. Excludes file contents, ACLs, xattrs and subsecond timestamps. Not a snapshot.

**Arguments:**

- 1 - Left operand

- 2 - Right operand

**Outputs:** Errors stderr; no comparison data on stdout.

**Returns:** 0 equal, 1 different, 2 invalid/inaccessible/unsupported entries.

**Globals:** PATH (read)

**Dependencies:** uname, platform stat and readlink.

#### `lib::cmp::dir_diff`

```text
lib::cmp::dir_diff LEFT RIGHT
```

Compare directory contents recursively without following child symlinks. Includes hidden entries,
empty directories and symlink text; crosses mounts; ignores ownership, modes, times and hardlink
topology. Never opens special files.

**Arguments:**

- 1 - Left operand

- 2 - Right operand

**Outputs:** Unified file diffs and escaped path/type/link mismatches on stdout; errors stderr. Output may be
partial on an operational failure.

**Returns:** 0 same contents/tree, 1 different, 2 invalid/unreadable/special entry.

**Globals:** PATH (read)

**Dependencies:** diff and readlink. No snapshot guarantee for concurrent changes.

### Logging

[Source](../lib/log.sh)

Intent emitters produce `[YYYY-MM-DDTHH:MM:SSZ] INTENT: MESSAGE` followed by one
newline. They all obtain UTC time from `lib::os::date`. Message text remains
literal, including percent signs, backslashes, empty strings and embedded
newlines; the prefix appears once per call. Exactly one message argument is
accepted, not a printf format or a list of words.

| Intent  | Color  | `print_*` destination |
| ------- | ------ | --------------------- |
| INFO    | White  | stdout                |
| SUCCESS | Green  | stdout                |
| NOTICE  | Yellow | stdout                |
| DEBUG   | Cyan   | stderr, when enabled  |
| WARN    | Yellow | stderr                |
| ERROR   | Red    | stderr                |

Use info for progress, success for a completed successful outcome, notice for
significant normal events, warn for recoverable concerns, and error for failures.
Only the label is colored, and only when the destination is a terminal, `TERM`
is not `dumb`, and `NO_COLOR` is unset or empty. Redirected intent output and
`write_*` files receive no added ANSI codes. Applications emitting machine-readable
stdout should use file logging or redirect progress messages.

`LIBSH_DEBUG=1` or case-insensitive `true` enables debug at call time. Every other
value, including unset, empty, false and unknown values, disables it. No reload is
needed. Ordinary variables and one-call assignments work; export for child Bash
processes. There is no `LIBSH_LOG_LEVEL` alias or severity threshold in this API.

Disabled debug emitters return 0 immediately, before validating arguments, obtaining
a timestamp, checking terminal color or accessing a file. Invalid disabled calls
are therefore ignored; active calls validate normally. Bash still expands arguments
before calling a function: guard expensive command substitutions with `debug_enabled`.

Active intent emitters return 0 on successful output, 1 on timestamp/open/write
failure and 2 on invalid arguments. Timestamp failure produces no partial record
and does not create a file. File emitters append to the explicit destination;
existing symlinks to regular files are followed. Missing parent directories,
dangling symlinks and nonregular destinations fail. New files use the caller's
umask. There is no locking, rotation or rollback of partially failed appends.
Logger backend diagnostics may use plain stderr text to avoid recursively logging
a logging failure. Intent logging requires `date`, even for ordinary error messages.

```bash
lib::log::print_info 'Updating configuration'
lib::log::print_success 'Configuration ready'
lib::log::write_notice ./app.log 'Restart required'
LIBSH_DEBUG=true lib::log::print_debug 'Managed block already present'

if lib::log::debug_enabled; then
  bytes=$(lib::fs::file_size "$config") || exit
  lib::log::print_debug "Configuration size: $bytes bytes"
fi
```

The raw `print`, `plain` and `write` APIs below remain for unstructured output.
Raw `print` intentionally emits caller-selected ANSI codes even when redirected;
raw `write` timestamps only when requested. Neither is debug-gated.

**Migration:** The color convenience functions `red`, `green`, `yellow`, `cyan`,
`timed` and all `timed_*` helpers have been removed. Select an intent by message
meaning, rather than translating colors mechanically. For example, use
`print_success` for completed work and `print_info` for work in progress. WARN now
uses stderr; NOTICE uses stdout. All intent emitters include a UTC timestamp, so
consumers that parse old color-only or local-time output must update accordingly.

#### `lib::log::print`

```text
lib::log::print COLOR MESSAGE
```

Write a message to stdout in the given color.

**Arguments:**

- 1 - The Bash color code, including its trailing 'm' (e.g. '31m')

- 2 - The string to log

**Outputs:** The given string, in the given color.

**Returns:** The final output command status.

#### `lib::log::plain`

```text
lib::log::plain MESSAGE
```

Write a message to stdout without any color.

**Arguments:**

- 1 - The string to log

**Outputs:** The given string, verbatim.

**Returns:** The final output command status.

#### `lib::log::print_info`

```text
lib::log::print_info MESSAGE
```

Print a timestamped INFO record.

**Arguments:** One message string, which may be empty.

**Outputs:** Record and newline to stdout; backend errors to stderr.

**Returns:** 0 success, 1 timestamp/output failure, 2 invalid arguments.

**Globals:** TERM, NO_COLOR, PATH (read).

**Dependencies:** date, through lib::os::date.

#### `lib::log::print_success`

```text
lib::log::print_success MESSAGE
```

Print a timestamped SUCCESS record.

**Arguments:** One message string, which may be empty.

**Outputs:** Record and newline to stdout; backend errors to stderr.

**Returns:** 0 success, 1 timestamp/output failure, 2 invalid arguments.

**Globals:** TERM, NO_COLOR, PATH (read).

**Dependencies:** date, through lib::os::date.

#### `lib::log::print_notice`

```text
lib::log::print_notice MESSAGE
```

Print a timestamped NOTICE record.

**Arguments:** One message string, which may be empty.

**Outputs:** Record and newline to stdout; backend errors to stderr.

**Returns:** 0 success, 1 timestamp/output failure, 2 invalid arguments.

**Globals:** TERM, NO_COLOR, PATH (read).

**Dependencies:** date, through lib::os::date.

#### `lib::log::print_debug`

```text
lib::log::print_debug MESSAGE
```

Print a timestamped DEBUG record only when debug is enabled.

**Arguments:** One message string, which may be empty.

**Outputs:** Record and newline to stderr; backend errors to stderr.

**Returns:** 0 success or disabled, 1 timestamp/output failure, 2 invalid arguments when enabled.

Disabled calls skip validation and all output work. See the shared logging contract above.

**Globals:** LIBSH_DEBUG, TERM, NO_COLOR, PATH (read).

**Dependencies:** date only when enabled, through lib::os::date.

#### `lib::log::print_warn`

```text
lib::log::print_warn MESSAGE
```

Print a timestamped WARN record.

**Arguments:** One message string, which may be empty.

**Outputs:** Record and newline to stderr; backend errors to stderr.

**Returns:** 0 success, 1 timestamp/output failure, 2 invalid arguments.

**Globals:** TERM, NO_COLOR, PATH (read).

**Dependencies:** date, through lib::os::date.

#### `lib::log::print_error`

```text
lib::log::print_error MESSAGE
```

Print a timestamped ERROR record.

**Arguments:** One message string, which may be empty.

**Outputs:** Record and newline to stderr; backend errors to stderr.

**Returns:** 0 success, 1 timestamp/output failure, 2 invalid arguments.

**Globals:** TERM, NO_COLOR, PATH (read).

**Dependencies:** date, through lib::os::date.

#### `lib::log::write_info`

```text
lib::log::write_info FILE MESSAGE
```

Append a timestamped INFO record.

**Arguments:** A nonempty file path and one message string, which may be empty.

**Outputs:** Record and newline to the explicit file, appended without added ANSI codes; backend errors to stderr.

**Returns:** 0 success, 1 timestamp/output failure, 2 invalid arguments.

**Globals:** PATH (read); caller umask governs new files.

**Dependencies:** date, through lib::os::date.

#### `lib::log::write_success`

```text
lib::log::write_success FILE MESSAGE
```

Append a timestamped SUCCESS record.

**Arguments:** A nonempty file path and one message string, which may be empty.

**Outputs:** Record and newline to the explicit file, appended without added ANSI codes; backend errors to stderr.

**Returns:** 0 success, 1 timestamp/output failure, 2 invalid arguments.

**Globals:** PATH (read); caller umask governs new files.

**Dependencies:** date, through lib::os::date.

#### `lib::log::write_notice`

```text
lib::log::write_notice FILE MESSAGE
```

Append a timestamped NOTICE record.

**Arguments:** A nonempty file path and one message string, which may be empty.

**Outputs:** Record and newline to the explicit file, appended without added ANSI codes; backend errors to stderr.

**Returns:** 0 success, 1 timestamp/output failure, 2 invalid arguments.

**Globals:** PATH (read); caller umask governs new files.

**Dependencies:** date, through lib::os::date.

#### `lib::log::write_debug`

```text
lib::log::write_debug FILE MESSAGE
```

Append a timestamped DEBUG record only when debug is enabled.

**Arguments:** A nonempty file path and one message string, which may be empty.

**Outputs:** Record and newline to the explicit file, appended without added ANSI codes; backend errors to stderr.

**Returns:** 0 success or disabled, 1 timestamp/output failure, 2 invalid arguments when enabled.

Disabled calls skip validation and all output work. See the shared logging contract above.

**Globals:** LIBSH_DEBUG, PATH (read); caller umask governs new files.

**Dependencies:** date only when enabled, through lib::os::date.

#### `lib::log::write_warn`

```text
lib::log::write_warn FILE MESSAGE
```

Append a timestamped WARN record.

**Arguments:** A nonempty file path and one message string, which may be empty.

**Outputs:** Record and newline to the explicit file, appended without added ANSI codes; backend errors to stderr.

**Returns:** 0 success, 1 timestamp/output failure, 2 invalid arguments.

**Globals:** PATH (read); caller umask governs new files.

**Dependencies:** date, through lib::os::date.

#### `lib::log::write_error`

```text
lib::log::write_error FILE MESSAGE
```

Append a timestamped ERROR record.

**Arguments:** A nonempty file path and one message string, which may be empty.

**Outputs:** Record and newline to the explicit file, appended without added ANSI codes; backend errors to stderr.

**Returns:** 0 success, 1 timestamp/output failure, 2 invalid arguments.

**Globals:** PATH (read); caller umask governs new files.

**Dependencies:** date, through lib::os::date.

#### `lib::log::debug_enabled`

```text
lib::log::debug_enabled
```

Check the current debug switch using Bash-only operations. This predicate is useful
when preparing a message would itself require expensive work.

**Arguments:** None.

**Outputs:** Nothing.

**Returns:** 0 enabled, 1 disabled, 2 unexpected arguments. Use in a conditional
under errexit; disabled emitters themselves return 0.

**Globals:** LIBSH_DEBUG (read).

#### `lib::log::write`

```text
lib::log::write FILE MESSAGE [--timestamp]
```

Append one plain-text log entry to a file, creating it when absent. Message bytes are preserved and
followed by one newline. Existing symlinks to regular files are followed; missing parents are not
created. This does not lock concurrent writers or roll back a partially failed append.

**Arguments:**

- 1 - Log file path

- 2 - Message (may be empty or contain embedded newlines)

- 3 - Optional --timestamp, prefixing UTC time as [YYYY-MM-DDTHH:MM:SSZ]

**Outputs:** Entry to the file; errors to stderr. No stdout.

**Returns:** 0 on success, 1 on timestamp/open/write failure, 2 on invalid arguments.

**Globals:** PATH (read when timestamping); the caller's umask governs new files.

**Dependencies:** date, only with --timestamp.

### Networking

[Source](../lib/net.sh)

Adapter inspection uses Linux `ip` (iproute2) or macOS `route`/`ifconfig`, plus
standard text utilities. `dns_servers` reads `/etc/resolv.conf`, which may not
represent every macOS per-domain resolver. Address validators do not resolve
names and reject IPv6 zone identifiers and CIDR suffixes.

URI parsing accepts absolute hierarchical and opaque URIs, preserving encoded
components. DSNs here mean single-host connection URIs such as
`mysql://user:pass@host:3306/db`; driver keyword strings, socket authorities and
multiple hosts are unsupported. URI validation can accept a port that is not a
usable service port; DSN validation restricts explicit ports to `1..65535` and
rejects fragments. Neither assigns scheme-specific default ports.

`endpoint_from_uri` has a deliberately narrower host grammar: ASCII DNS names,
IPv4, or bracketed IPv6; no escaped hosts, IPvFuture or scope identifiers. Its
scheme begins with a letter and allows letters, digits, `+`, `-`, `.`. Userinfo
and suffixes retain valid `%HH` escapes without decoding. Whitespace, controls,
malformed escapes, empty userinfo and explicitly empty ports fail. Host output
omits IPv6 brackets. The input and both output references must be distinct. A
missing port requires an explicit `--default-port`; invalid explicit ports never
fall back to it.

`tcp_wait` defaults to 60 attempts, a five-second connect timeout and a
one-second interval. Attempts/timeouts are positive decimal integers; interval
may be zero, with a maximum of 999999999 for each. It uses OpenBSD-compatible
`nc` (including macOS `-G`), `sleep` and `uname`. There is no sleep after success
or the final attempt. DNS resolution and command overhead are outside the retry
budget. `http_probe` requires `curl`, verifies TLS, and discards response bodies.
Redirects are opt-in, capped at five and cannot downgrade HTTPS to HTTP.

```bash
uri='https://example.org:8443/status?ready=1'
lib::net::uri_parse "$uri" host # example.org, without a newline
lib::net::dns_lookup example.org
lib::net::http_probe "$uri" --timeout 10 --follow-redirects
```

#### `lib::net::tcp_probe`

```text
lib::net::tcp_probe HOST PORT [LABEL] [RETRIES] [TIMEOUT]
```

Block until 'host:port' accepts a TCP connection, retrying on a fixed interval, or exit 1 after the
retry budget is exhausted.

**Arguments:**

- 1 - Host to connect to

- 2 - Port to connect to

- 3 - Label to use in log output (optional, defaults to "host:port")

- 4 - Number of retries before giving up (optional, default 60)

- 5 - Per-attempt connect timeout in seconds (optional, default 5)

**Outputs:** Progress/result via lib::log::\*.

**Returns:** 0 once the connection succeeds. Exits 1 if it never does.

#### `lib::net::tcp_dsn_probe`

```text
lib::net::tcp_dsn_probe DSN DEFAULT_PORT [LABEL] [RETRIES] [TIMEOUT]
```

Convenience wrapper around lib::net::tcp_probe: parse host/port out of a DSN with 'trurl' first.
Kept separate from lib::net::tcp_probe itself so this module carries no hard dependency on trurl
being installed -- only callers of THIS function need it on PATH. Deprecated: credentials reach
trurl argv. New callers should use endpoint_from_uri (variable reference) followed by tcp_wait
instead.

**Arguments:**

- 1 - DSN/URL to parse (e.g. "mysql://user:pass@host:3306/db")

- 2 - Default port to use if the DSN doesn't specify one

- 3 - Label to use in log output (optional, defaults to the DSN's host)

- 4 - Number of retries before giving up (optional, default 60)

- 5 - Per-attempt connect timeout in seconds (optional, default 5)

**Outputs:** Same as lib::net::tcp_probe.

**Returns:** Same as lib::net::tcp_probe.

#### `lib::net::endpoint_from_uri`

```text
lib::net::endpoint_from_uri URI_VAR HOST_OUT PORT_OUT [--default-port PORT]
```

Extract a TCP endpoint from a restricted single-host database URI.

**Arguments:**

- 1 - URI input variable name

- 2 - Host output variable name

- 3 - Port output variable name

- 4+ - Optional --default-port PORT

**Outputs:** Sanitized errors on stderr; no stdout. See docs/API.md.

**Returns:** 0 success, 2 invalid reference/URI/port. Never exits.

**Globals:** URI variable (read), host/port output variables (written on success).

#### `lib::net::tcp_wait`

```text
lib::net::tcp_wait HOST PORT [--attempts N] [--timeout SECONDS] [--interval SECONDS] [--label LABEL]
```

Wait for TCP acceptance, returning control to the caller on failure.

**Arguments:**

- 1 - Host

- 2 - Port

- 3+ - Optional --attempts N, --timeout SECONDS, --interval SECONDS, and --label LABEL

**Outputs:** Progress on stdout, sanitized errors on stderr. Labels must contain no secrets.

**Returns:** 0 connected, 1 dependency/connection/sleep failure, 2 invalid arguments. Budget: attempts\*timeout +
(attempts-1)\*interval, excluding DNS and overhead.

#### `lib::net::default_adapter`

```text
lib::net::default_adapter
```

Resolve the interface name of the default network adapter, via the lowest-metric IPv4 default route.

**Outputs:** The interface name to stdout. An error to stderr on failure.

**Returns:** 0 on success, 1 if no default route/adapter was found.

#### `lib::net::ip_address`

```text
lib::net::ip_address [ipv4|ipv6] [INTERFACE]
```

Resolve the IP address of an adapter. For IPv6, a global/unique-local address is preferred over
link-local; falls back to link-local if no routable address is assigned.

**Arguments:**

- 1 - Address family: `ipv4` or `ipv6` (optional, default `ipv4`)

- 2 - Interface name (optional; resolved via default_adapter if omitted)

**Outputs:** The address to stdout. An error to stderr on failure.

**Returns:** 0 on success, 1 if no address of that family was found.

#### `lib::net::subnet_mask`

```text
lib::net::subnet_mask [INTERFACE]
```

Resolve the IPv4 subnet mask of an adapter, in dotted-decimal form.

**Arguments:**

- 1 - Interface name (optional; resolved via default_adapter if omitted)

**Outputs:** The mask to stdout. An error to stderr on failure.

**Returns:** 0 on success, 1 if no IPv4 mask was found.

#### `lib::net::default_gateway`

```text
lib::net::default_gateway [ipv4|ipv6] [INTERFACE]
```

Resolve the default gateway of an adapter.

**Arguments:**

- 1 - Address family: `ipv4` or `ipv6` (optional, default `ipv4`)

- 2 - Interface name (optional; resolved via default_adapter if omitted)

**Outputs:** The gateway address to stdout. An error to stderr on failure.

**Returns:** 0 on success, 1 if no gateway of that family was found.

#### `lib::net::dns_servers`

```text
lib::net::dns_servers [ipv4|ipv6]
```

List the configured DNS servers, read from /etc/resolv.conf -- this isn't adapter-scoped the way
PSFoundation's CimConfig.DNSServerSearchOrder is, so unlike the other functions here there is no
interface-name argument.

**Arguments:**

- 1 - Address family to filter by: `ipv4` or `ipv6` (optional, default both)

**Outputs:** One server per line to stdout. An error to stderr on failure.

**Returns:** 0 on success, 1 if no matching DNS servers were found.

#### `lib::net::mac_address`

```text
lib::net::mac_address [INTERFACE]
```

Resolve the MAC address of an adapter.

**Arguments:**

- 1 - Interface name (optional; resolved via default_adapter if omitted)

**Outputs:** The MAC address to stdout. An error to stderr on failure.

**Returns:** 0 on success, 1 if no MAC address was found.

#### `lib::net::network_prefix`

```text
lib::net::network_prefix [ipv4|ipv6] [INTERFACE]
```

Resolve the network address (IPv4) or network prefix (IPv6) of an adapter.

**Arguments:**

- 1 - Address family: `ipv4` or `ipv6` (optional, default `ipv4`)

- 2 - Interface name (optional; resolved via default_adapter if omitted)

**Outputs:** The network address to stdout. An error to stderr on failure.

**Returns:** 0 on success, 1 on failure.

#### `lib::net::network_prefix_cidr`

```text
lib::net::network_prefix_cidr [ipv4|ipv6] [INTERFACE]
```

Resolve the network prefix of an adapter in CIDR notation.

**Arguments:**

- 1 - Address family: `ipv4` or `ipv6` (optional, default `ipv4`)

- 2 - Interface name (optional; resolved via default_adapter if omitted)

**Outputs:** The CIDR-notation prefix to stdout. An error to stderr on failure.

**Returns:** 0 on success, 1 on failure.

#### `lib::net::broadcast_address`

```text
lib::net::broadcast_address [INTERFACE]
```

Resolve the IPv4 broadcast address of an adapter.

**Arguments:**

- 1 - Interface name (optional; resolved via default_adapter if omitted)

**Outputs:** The broadcast address to stdout. An error to stderr on failure.

**Returns:** 0 on success, 1 on failure.

#### `lib::net::multicast_address`

```text
lib::net::multicast_address [INTERFACE]
```

Resolve the solicited-node multicast address for an adapter's IPv6 address, per RFC 4291 section
2.7.1 (the ff02::1:ff00:0/104 prefix combined with the address's lower 24 bits). Used by Neighbor
Discovery as the IPv6 replacement for ARP.

**Arguments:**

- 1 - Interface name (optional; resolved via default_adapter if omitted)

**Outputs:** The multicast address to stdout. An error to stderr on failure.

**Returns:** 0 on success, 1 on failure.

#### `lib::net::ipv4_validate`

```text
lib::net::ipv4_validate ADDRESS
```

Check whether a string is a valid IPv4 address per RFC 791: four dot-separated decimal octets, each
0-255, no leading zeros. Arithmetic decomposition with bounded decimal octets.

**Arguments:**

- 1 - The string to validate

**Outputs:** None

**Returns:** 0 valid, 1 invalid, 2 incorrect argument count.

#### `lib::net::ipv6_validate`

```text
lib::net::ipv6_validate ADDRESS
```

Validate an unbracketed IPv6 address, including embedded IPv4 tails. Zone identifiers and CIDR
suffixes are not accepted.

**Arguments:**

- 1 - Address

**Outputs:** None

**Returns:** 0 valid, 1 invalid, 2 incorrect argument count.

#### `lib::net::ip_validate`

```text
lib::net::ip_validate ADDRESS
```

Validate either an IPv4 or an unbracketed IPv6 address.

**Arguments:**

- 1 - Address, without CIDR suffix or zone identifier

**Outputs:** None

**Returns:** 0 valid, 1 invalid, 2 incorrect argument count.

#### `lib::net::port_validate`

```text
lib::net::port_validate PORT
```

Validate a decimal remote service port; leading zeros are accepted. Port zero is reserved for local
automatic allocation and is rejected here.

**Arguments:**

- 1 - Port in the range 1 through 65535

**Outputs:** None

**Returns:** 0 valid, 1 invalid, 2 incorrect argument count.

#### `lib::net::uri_validate`

```text
lib::net::uri_validate URI
```

Validate an absolute URI without resolving or decoding it. Accepts hierarchical and opaque URIs.
IPvFuture/scoped IPv6 are unsupported. Generic URI ports may be empty or arbitrary decimal digits;
use dsn_validate for a usable service endpoint. Relative references are not absolute URIs.

**Arguments:**

- 1 - URI value

**Outputs:** None

**Returns:** 0 valid, 1 invalid, 2 incorrect argument count.

#### `lib::net::uri_parse`

```text
lib::net::uri_parse URI COMPONENT
```

Parse one encoded component from an absolute URI. No decoding or normalization is performed;
bracketed IPv6 hosts lose only their brackets. Absent and explicitly empty components both produce
empty output. Input never reaches external command arguments or diagnostics.

**Arguments:**

- 1 - URI value

- 2 - scheme, authority, userinfo, username, password, host, port, path, query or fragment

**Outputs:** Requested component without an added newline; sanitized errors to stderr.

**Returns:** 0 success, 1 invalid URI, 2 invalid invocation/component selector.

#### `lib::net::dsn_validate`

```text
lib::net::dsn_validate DSN
```

Validate a single-host connection URI, without scheme-specific defaults. Requires a DNS/IP host,
optional service port 1..65535, and no fragment. Driver keyword strings, socket paths and multi-host
authorities are rejected.

**Arguments:**

- 1 - DSN value

**Outputs:** None

**Returns:** 0 valid, 1 invalid, 2 incorrect argument count.

#### `lib::net::dsn_parse`

```text
lib::net::dsn_parse DSN COMPONENT
```

Parse an encoded component from a single-host connection URI. Uses the same selectors/output rules
as uri_parse and grammar as dsn_validate. For secret-bearing endpoint extraction into variables,
use endpoint_from_uri.

**Arguments:**

- 1 - DSN value

- 2 - Component selector accepted by uri_parse

**Outputs:** Component without an added newline; sanitized errors to stderr.

**Returns:** 0 success, 1 invalid DSN, 2 invalid invocation/component selector.

#### `lib::net::dns_lookup`

```text
lib::net::dns_lookup HOSTNAME
```

Look up a hostname with getent, or nslookup when getent is unavailable. Pass a hostname, not a
URI/DSN; parsing belongs to the caller. getent uses the system name-service configuration, while
nslookup queries DNS directly. Resolver timeouts follow system/tool defaults.

**Arguments:**

- 1 - Hostname

**Outputs:** Unique IP addresses, one per line; sanitized errors to stderr.

**Returns:** 0 addresses found, 1 missing resolver/lookup failure, 2 invalid invocation.

**Globals:** PATH (read)

**Dependencies:** getent or nslookup, checked only at invocation.

#### `lib::net::http_probe`

```text
lib::net::http_probe URL [--timeout SECONDS] [-f|--follow-redirects]
```

Probe HTTP(S) with one GET, accepting only 2xx responses. TLS verification stays enabled. Redirects
are opt-in, capped at five, and cannot downgrade HTTPS to HTTP. The total timeout includes
redirects. The URL is supplied to curl on stdin; response bodies and curl diagnostics are discarded.
Proxy and trust-store environment settings remain effective.

**Arguments:**

- 1 - HTTP(S) URL

- 2+ - Optional --timeout SECONDS (positive integer, default 10), -f or --follow-redirects

**Outputs:** Final HTTP status without a newline on HTTP completion, even if rejected; sanitized errors on
stderr. No status on transport failure.

**Returns:** 0 accepted 2xx, 1 rejected HTTP status, 2 invalid invocation/URL, 3 missing curl or
transport/TLS/timeout failure. Never exits.

**Globals:** PATH and curl proxy/trust environment (read)

**Dependencies:** curl, checked only at invocation.

### Options

[Source](../lib/opt.sh)

Define `OPTS`, `OPTS_HELP` and `OPTS_VALUES` before parsing. Each specification
entry is `"<short>,<long>:<key>:<0|1>:<required|optional>"`; include the leading
hyphens in flag names. Either spelling may be omitted. `1` consumes the next
argument; `0` records `1` when the flag is present. Repeated flags overwrite their
previous value. Combined short flags, `--key=value`, positional arguments and a
bare `--` separator are not supported. Values beginning with `-` are accepted
as the next argument. Results reset at each parse, even when parsing fails.

A flag whose key is `help` prints usage, sets `OPTS_VALUES[help]=1` and returns
success before required-flag validation. The caller must then return. Within a
function, declare all three arrays locally to preserve outer parser state.

```bash
configure() {
  local -a OPTS=('-p,--port:port:1:required' '-h,--help:help:0:optional')
  local -A OPTS_HELP=([port]='Service port' [help]='Show help') OPTS_VALUES=()

  lib::opt::parse "$@" || return
  [[ ${OPTS_VALUES[help]:-} != 1 ]] || return 0
  lib::net::port_validate "${OPTS_VALUES[port]}"
}
configure --port 8080
```

#### `lib::opt::usage`

```text
lib::opt::usage
```

Print usage/help text derived entirely from OPTS + OPTS_HELP, so the help output can never drift
out of sync with what's actually parsed.

**Outputs:** Writes usage to stdout

**Returns:** The status of the final usage-output operation.

**Globals:** OPTS, OPTS_HELP (read)

#### `lib::opt::parse`

```text
lib::opt::parse [FLAG [VALUE] ...]
```

Parse "$@" against the OPTS spec into OPTS_VALUES.

**Arguments:**

- 1+ - The script's original "$@"

**Outputs:** Nothing on success. Errors to stderr via lib::log::print_error on failure. On help, prints usage, sets
OPTS_VALUES["help"]=1, and returns 0. Library callers should locally declare all three OPTS arrays.

**Returns:** 0 on success. 1 on an unknown flag, a value flag missing its value, or a required flag not supplied
(each case prints an error first).

**Globals:** OPTS (read) -- spec, defined by the calling script OPTS_HELP (read) -- descriptions,
defined by the calling script OPTS_VALUES (write, reset at the start of every call)

### Operating system

[Source](../lib/os.sh)

Platform directory helpers support Linux and macOS and never create their
returned paths. Nonempty `XDG_*_HOME` values override defaults. Linux defaults
are `~/.config`, `~/.local/share`, `~/.cache` and `~/.local/state`, with an optional
app name appended. macOS defaults are `~/Library/Application Support[/APP]`,
`~/Library/APP/Data`, `~/Library/Caches[/APP]` and `~/Library/APP/State`.
Without an app name, the macOS data/state helpers return `~/Library`. All four
path helpers print without a trailing newline and use `uname` to select defaults.
`rc` sources only `$HOME/.bashrc`; `root_exec` invokes `sudo` when EUID is nonzero.

Boot time, machine ID, memory, disk inspection, distribution metadata and account
operations are Linux-only. Unsupported-platform failures are explicit. Memory
and boot time describe exposed kernel state, not container lifetime or cgroup
limits. A root filesystem on overlay storage need not have a block device.
`disk_device_id` returns the mounted partition/logical device, not an inferred
physical parent. `disk_capacity` reads the caller-supplied device's `fdisk -l`
byte header without privilege escalation.

Metadata selectors map to `ID`, `VERSION_ID`, `BRANCH`, `VERSION_CODENAME`, `NAME`
and `PRETTY_NAME`. Missing `BRANCH` falls back to `VERSION_ID` before its first
dot. Metadata is parsed as data, never sourced as shell code.

Account lookup requires `getent`; mutations use `useradd`, `groupadd`, `usermod`
and `groupmod`. Names are conservative ASCII account names; numeric identifiers
belong in ID options. Ensure functions report an existing account and leave it
unchanged. Explicit update functions change only requested attributes.
`--system` delegates allocation policy to the backend. Supplementary groups are
appended; `--home` does not request directory creation or migration. Run mutations
with the required privileges; these helpers do not invoke `sudo`.

`recursive_configure` supports Linux/macOS `find`, `chmod` and `chown`. It includes
the root, follows links by default (even outside the root), and changes directories
after their contents. With `-n`, links receive ownership changes only and targets
are not visited. Modes are octal. Traversal is collected before mutation, but
failed changes are not rolled back and concurrent path replacement is unsupported.

```bash
lib::os::config_home myapp
lib::os::memory available

device=$(lib::os::disk_device_id) && lib::os::disk_capacity "$device"

# Administrative examples; invoke only when account changes are intended.
lib::os::group_ensure app --system
lib::os::user_ensure app --system --group app --home /srv/app
lib::os::user_update app --append-groups logs
lib::os::recursive_configure /srv/app --file-mode 640 --dir-mode 750 --user app --group app -n
```

#### `lib::os::date`

```text
lib::os::date
```

Return the current UTC time at second precision as `YYYY-MM-DDTHH:MM:SSZ`.
This is the shared logging timestamp API, not a frontend for arbitrary date flags.
The format is supported on Linux and macOS and is independent of the caller's timezone.

**Arguments:** None.

**Outputs:** Timestamp and newline to stdout; backend errors to stderr.

**Returns:** 0 success, 1 date/output failure, 2 unexpected arguments.

**Globals:** PATH (read).

**Dependencies:** date.

#### `lib::os::config_home`

```text
lib::os::config_home [APP]
```

Resolve the user's XDG config directory. XDG_CONFIG_HOME always wins when set; otherwise falls
back to the platform-native default -- macOS doesn't follow the XDG spec, so Darwin gets
~/Library/Application Support instead of ~/.config, matching Go's os.UserConfigDir() (and gopskit's
own Config field, which wraps it).

**Arguments:**

- 1 - App name to nest under the base directory (optional)

**Outputs:** The resolved path to stdout.

**Returns:** The final output command status.

**Globals:** HOME, XDG_CONFIG_HOME

#### `lib::os::data_home`

```text
lib::os::data_home [APP]
```

Resolve the user's XDG data directory. XDG_DATA_HOME always wins when set; otherwise falls back to
the platform-native default. On Darwin, gopskit's own Data path (~/Library/&lt;app&gt;/Data) nests
the app name before a fixed 'Data' leaf, the reverse of config/cache's app-last shape -- kept as-is
here for parity rather than smoothed over.

**Arguments:**

- 1 - App name to nest under the base directory (optional)

**Outputs:** The resolved path to stdout.

**Returns:** The final output command status.

**Globals:** HOME, XDG_DATA_HOME

#### `lib::os::cache_home`

```text
lib::os::cache_home [APP]
```

Resolve the user's XDG cache directory. XDG_CACHE_HOME always wins when set; otherwise falls back
to the platform-native default -- Darwin gets ~/Library/Caches, matching Go's os.UserCacheDir() (and
gopskit's own Cache field, which wraps it).

**Arguments:**

- 1 - App name to nest under the base directory (optional)

**Outputs:** The resolved path to stdout.

**Returns:** The final output command status.

**Globals:** HOME, XDG_CACHE_HOME

#### `lib::os::state_home`

```text
lib::os::state_home [APP]
```

Resolve the user's XDG state directory. XDG_STATE_HOME always wins when set; otherwise falls back
to the platform-native default. gopskit has no equivalent of its own (no State field anywhere in its
PlatformPaths) -- ~/Library/&lt;app&gt;/State on Darwin is this module's own extrapolation from
data_home's shape, not sourced from gopskit.

**Arguments:**

- 1 - App name to nest under the base directory (optional)

**Outputs:** The resolved path to stdout.

**Returns:** The final output command status.

**Globals:** HOME, XDG_STATE_HOME

#### `lib::os::is_executable`

```text
lib::os::is_executable COMMAND
```

Check whether the shell can resolve a command without changing caller state.

**Arguments:**

- 1 - One command name (including builtins/functions).

**Outputs:** Errors on stderr for incorrect argument count; otherwise none.

**Returns:** 0 available, 1 unavailable/empty, 2 incorrect argument count.

**Globals:** PATH (read)

#### `lib::os::root_check`

```text
lib::os::root_check
```

Check if the current user is root

**Outputs:** None

**Returns:** 0 for root, 1 otherwise.

**Globals:** EUID (read)

#### `lib::os::root_exec`

```text
lib::os::root_exec [-e|--preserve-environment] [--] COMMAND [ARG ...]
```

Run a command directly when already root, otherwise through `sudo`.
`-e`/`--preserve-environment` requests `sudo -E`. Without that option, sudo uses
its normal environment policy. When already root, the option is consumed and
execution remains direct; there is no additional environment change.

**Arguments:**

- Optional leading `-e` or `--preserve-environment`; repeated occurrences are harmless.
- Optional `--` ends wrapper-option parsing.
- A nonempty command followed by its arguments, passed without splitting or evaluation.

Parsing stops at the command. For example, `root_exec command -e` passes `-e`
to the command. Unsupported leading options fail; this is not a general sudo
option passthrough. Sudo receives its own `--` before the command.

Preservation applies to exported environment variables, subject to sudo policy:
policy may filter variables or reject the request. It does not export shell-local
variables, carry sourced functions into a new process, or remove the need to
source libsh inside an elevated Bash process. See the
[sudo option contract](https://github.com/sudo-project/sudo/blob/main/docs/sudo.man.in).

```bash
export LIBSH_DIR=/usr/local/lib/libsh
lib::os::root_exec -e -- bash -c 'source "$LIBSH_DIR/lib.sh" || exit; lib::os::root_check'
```

**Outputs:** Command stdout and stderr unchanged; invocation errors on stderr.

**Returns:** Command or sudo exit status, including environment-policy rejection;
`2` for invalid wrapper options or a missing/empty command.

**Globals:** `EUID`, `PATH` and the exported environment (read).

#### `lib::os::rc`

```text
lib::os::rc
```

Reload Bash configuration in the current shell. Zsh configuration is not read.

**Outputs:** Whatever the Bash configuration prints; invocation errors on stderr.

**Returns:** 0 when absent, otherwise the source status; 2 for unexpected arguments.

**Globals:** HOME (read); the sourced Bash configuration may change caller state.

#### `lib::os::boot_time`

```text
lib::os::boot_time
```

Read the kernel boot timestamp from /proc/stat, not /proc inode times. In a container this describes
the exposed kernel, not container startup.

**Outputs:** Unix epoch seconds without a newline; errors to stderr.

**Returns:** 0 success, 1 unavailable/malformed data, 2 invalid invocation.

**Globals:** PATH (read)

#### `lib::os::machine_id`

```text
lib::os::machine_id
```

Read the Linux machine ID, falling back to the D-Bus path if unreadable. Does not create an ID.
Container images may expose a shared or unset ID.

**Outputs:** 32 lowercase hexadecimal digits without a newline; errors to stderr.

**Returns:** 0 success, 1 missing/invalid ID, 2 invalid invocation.

**Globals:** PATH (read)

#### `lib::os::memory`

```text
lib::os::memory [COUNTER]
```

Read a Linux memory counter in bytes from /proc/meminfo. These are the exposed kernel counters, not
cgroup memory limits. Available memory requires MemAvailable; no estimate is substituted on older
kernels.

**Arguments:**

- 1 - total (default), available, free, buffers, cached, swap-total, swap-free

**Outputs:** Integer bytes without a newline; errors to stderr.

**Returns:** 0 success, 1 missing/malformed/overflowing counter, 2 invalid invocation.

**Globals:** PATH (read)

#### `lib::os::disk_device_id`

```text
lib::os::disk_device_id
```

Identify the block-device source mounted at / on Linux. Returns the mounted partition/logical
device, not an inferred physical parent. Overlay, network and other non-device roots fail. The
device node need not be visible inside the caller's mount namespace.

**Outputs:** /dev path without a newline; errors to stderr.

**Returns:** 0 success, 1 unavailable/non-device root, 2 invalid invocation.

**Globals:** PATH (read)

**Dependencies:** findmnt from util-linux.

#### `lib::os::disk_capacity`

```text
lib::os::disk_capacity DEVICE
```

Read a device's byte capacity from its fdisk -l Disk header. No partition changes are made. Access
privileges belong to the caller; no sudo is invoked. Human-readable fdisk output is parsed under
locale C.

**Arguments:**

- 1 - Device path, typically returned by disk_device_id

**Outputs:** Integer bytes without a newline; errors to stderr.

**Returns:** 0 success, 1 fdisk/unrecognized output failure, 2 invalid invocation.

**Globals:** PATH (read)

**Dependencies:** fdisk from util-linux.

#### `lib::os::metadata`

```text
lib::os::metadata SELECTOR
```

Read one allowlisted Linux os-release field without sourcing shell code. Prefer /etc/os-release,
with /usr/lib/os-release as the fallback. Later duplicate keys win. Branch uses BRANCH, falling back
to VERSION_ID before its first dot. Other missing/empty fields fail.

**Arguments:**

- 1 - --id, --version, --branch, --codename, --name or --pretty-name

**Outputs:** Decoded field without a newline; errors to stderr.

**Returns:** 0 success, 1 missing/malformed data, 2 invalid invocation/selector.

**Globals:** PATH (read)

#### `lib::os::group_exists`

```text
lib::os::group_exists NAME
```

Check whether a named Linux group exists through NSS.

**Arguments:**

- 1 - Group name

**Outputs:** Backend errors to stderr; no stdout.

**Returns:** 0 exists, 1 absent, 2 invalid invocation/name, 3 lookup failure.

**Globals:** PATH (read)

#### `lib::os::user_exists`

```text
lib::os::user_exists NAME
```

Check whether a named Linux user exists through NSS.

**Arguments:**

- 1 - Username

**Outputs:** Backend errors to stderr; no stdout.

**Returns:** 0 exists, 1 absent, 2 invalid invocation/name, 3 lookup failure.

**Globals:** PATH (read)

#### `lib::os::group_ensure`

```text
lib::os::group_ensure NAME [-i|--id GID] [-s|--system]
```

Create a Linux group only when it does not already exist. Existing groups are reported and left
unchanged, regardless of requested ID. --system forwards groupadd's configured system-account
allocation policy.

**Arguments:**

- 1 - Group name

- 2+ - Optional -i/--id GID, -s/--system

**Outputs:** Already-exists message on stdout; tool diagnostics to stderr.

**Returns:** 0 created/already exists, 1 backend failure, 2 invalid invocation.

**Globals:** PATH (read)

#### `lib::os::user_ensure`

```text
lib::os::user_ensure NAME [OPTIONS]
```

Create a Linux user only when it does not already exist. Existing users are reported and left
unchanged. Allocation and home creation follow useradd policy; --home supplies its home-directory
argument only.

**Arguments:**

- 1 - Username

- 2+ - Optional -i/--id UID, -g/--group NAME_OR_GID, -a/--append-groups COMMA_LIST, -h/--home ABSOLUTE_PATH, -s/--system

**Outputs:** Already-exists message on stdout; tool diagnostics to stderr.

**Returns:** 0 created/already exists, 1 backend failure, 2 invalid invocation.

**Globals:** PATH (read)

#### `lib::os::group_update`

```text
lib::os::group_update NAME -i|--id GID
```

Update the GID of an existing Linux group through groupmod. File ownership migration and other
groupmod side effects follow the backend; this function does not recursively change files owned by
the previous GID.

**Arguments:**

- 1 - Group name

- 2+ - Required -i/--id GID

**Outputs:** Diagnostics to stderr; no stdout.

**Returns:** 0 updated, 1 absent group/backend failure, 2 invalid invocation.

**Globals:** PATH (read)

#### `lib::os::user_update`

```text
lib::os::user_update NAME OPTIONS
```

Update explicit attributes of an existing Linux user through usermod. Supplementary groups are
appended, never replaced. --home changes the account path without requesting a move. --system is a
creation-only option.

**Arguments:**

- 1 - Username

- 2+ - At least one of -i/--id UID, -g/--group NAME_OR_GID, -a/--append-groups COMMA_LIST, -h/--home ABSOLUTE_PATH

**Outputs:** Diagnostics to stderr; no stdout.

**Returns:** 0 updated, 1 absent user/backend failure, 2 invalid invocation.

**Globals:** PATH (read)

#### `lib::os::recursive_configure`

```text
lib::os::recursive_configure PATH OPTIONS
```

Configure ownership and octal modes for a root path and its descendants. Follows links by default,
including targets outside the root. With -n, links receive ownership changes only and their targets
are never visited. Parent path components are resolved normally. Special files receive ownership
only. Traversal is staged with NUL delimiters before mutation; directories are changed after their
contents. Failed mutations are not rolled back, and concurrent path replacement is outside the
contract.

**Arguments:**

- 1 - One path (not a newline-separated list)

- 2+ - -f/--file-mode OCTAL, -d/--dir-mode OCTAL, -u/--user USER, -g/--group GROUP, -n/--no-dereference; at least one change required

**Outputs:** Errors to stderr; no stdout.

**Returns:** 0 success, 1 traversal/mutation failure, 2 invalid options/modes.

**Globals:** PATH, TMPDIR (read); traps and parser arrays remain in this subshell.

**Dependencies:** find, mktemp, rm, chmod, chown. Required privileges belong to the caller.

## Extension reference

### apk extension

[Source](../extensions/libapk.sh)

Load with `lib::load_extensions apk`. Queries use installed state and existing
repository indices only; stale indices give stale answers. No index refresh,
package transaction or implicit installation helper is provided.

```bash
lib::load_extensions apk
ext::apk::is_installed bash
ext::apk::pending_packages
```

#### `ext::apk::is_installed`

```text
ext::apk::is_installed PACKAGE
```

Check whether one literal Alpine package name is installed.

**Arguments:**

- 1 - Package name, without version constraints or globs

**Outputs:** None

**Returns:** 0 installed, 1 absent/backend failure, 2 invalid invocation.

**Globals:** PATH (read)

**Dependencies:** apk, only at invocation.

#### `ext::apk::pending_packages`

```text
ext::apk::pending_packages
```

List installed packages older than their locally cached repository versions. Does not refresh
indices or modify packages; stale indices give stale results.

**Outputs:** Package names, one per line; errors to stderr. No partial output on failure.

**Returns:** 0 success (including no updates), 1 backend/parse failure, 2 invalid invocation.

**Globals:** PATH (read)

**Dependencies:** apk, only at invocation.

### apt extension

[Source](../extensions/libapt.sh)

Load with `lib::load_extensions apt`. These read-only Debian/Ubuntu helpers
preserve the existing simulation pipeline: `pending_packages`, `security_packages`
and `summary_line` parse stdin, unlike APK/DNF's direct queries. Capture and check
the simulation first so a failed producer cannot look like an empty update list.
Parsers expect APT's English output; choose locale C when producing it.

```bash
lib::load_extensions apt
simulation=$(LC_ALL=C ext::apt::simulate upgrade) || exit 1
printf '%s\n' "$simulation" | ext::apt::pending_packages
printf '%s\n' "$simulation" | ext::apt::security_packages
```

Simulation requires `apt-get`; installed lookup uses `dpkg-query`; parsers use
`awk`; list age uses `stat` and `date`. No refresh or package mutation is performed.

#### `ext::apt::simulate`

```text
ext::apt::simulate [ACTION]
```

Simulate an apt-get action.

**Arguments:**

- 1 - The action to simulate (default: upgrade)

**Outputs:** apt-get's simulation output to stdout.

**Returns:** The return value of 'apt-get'.

#### `ext::apt::pending_packages`

```text
ext::apt::pending_packages
```

List the packages a simulation would install or upgrade.

**Inputs:** An apt-get simulation on stdin.

**Outputs:** One package name per line.

**Returns:** The `awk` exit status.

#### `ext::apt::security_packages`

```text
ext::apt::security_packages
```

List the packages a simulation would take from a security pocket. apt names the origin in
parentheses, e.g. Inst libssl3 [3.0.13] (3.0.14 Ubuntu:24.04/noble-security [amd64]) so the suite
suffix is what identifies a security update, independent of the release codename.

**Inputs:** An apt-get simulation on stdin.

**Outputs:** One package name per line.

**Returns:** The `awk` exit status.

#### `ext::apt::summary_line`

```text
ext::apt::summary_line
```

Extract apt-get's own one-line summary from a simulation.

**Inputs:** An apt-get simulation on stdin.

**Outputs:** The "N upgraded, N newly installed, ..." line, if there is one.

**Returns:** The `awk` exit status.

#### `ext::apt::lists_age_days`

```text
ext::apt::lists_age_days
```

Report how long ago the package lists were refreshed.

**Outputs:** The age in whole days to stdout, or "-1" when it cannot be determined.

**Returns:** 0 on success, 1 when no timestamp was found.

#### `ext::apt::is_installed`

```text
ext::apt::is_installed PACKAGE
```

Check whether a package is installed.

**Arguments:**

- 1 - Package name

**Outputs:** None

**Returns:** 0 if the package is installed, 1 otherwise.

#### `ext::apt::reboot_required`

```text
ext::apt::reboot_required
```

Check whether the system wants a reboot. The file is written by the kernel and libc packages
themselves.

**Outputs:** None

**Returns:** 0 if a reboot is required, 1 otherwise.

### dnf extension

[Source](../extensions/libdnf.sh)

Load with `lib::load_extensions dnf`. Installed queries use RPM; upgrade
inspection uses DNF 4/5 `repoquery --upgrades` with existing metadata and no
refresh. Install repoquery support separately if your DNF packaging requires it.
Results retain architecture (`name.arch`), with duplicate records removed.

```bash
lib::load_extensions dnf
ext::dnf::is_installed bash
ext::dnf::pending_packages
```

#### `ext::dnf::is_installed`

```text
ext::dnf::is_installed PACKAGE
```

Check whether one literal RPM package name is installed.

**Arguments:**

- 1 - Package name, optionally with architecture; no globs or file paths

**Outputs:** None

**Returns:** 0 installed, 1 absent/backend failure, 2 invalid invocation.

**Globals:** PATH (read)

**Dependencies:** rpm, only at invocation.

#### `ext::dnf::pending_packages`

```text
ext::dnf::pending_packages
```

List upgrades from existing DNF metadata without refreshing it. Missing metadata fails instead of
refreshing. Uses the DNF 4/5 repoquery interface and preserves architecture suffixes; no
transactions are performed.

**Outputs:** name.arch records, one per line; errors to stderr. No partial error output.

**Returns:** 0 success (including no updates), 1 backend/parse failure, 2 invalid invocation.

**Globals:** PATH (read)

**Dependencies:** dnf with repoquery support (DNF 4 or 5), only at invocation.

### Git extension

[Source](../extensions/libgit.sh)

Load with `lib::load_extensions git`. These older helpers inspect the current
Git working directory. Remote/branch arguments are extended regular expressions,
not literal-name predicates, and matching lines are printed. They retain the
listed global-variable writes and pipeline-dependent statuses; `toplevel` does
not reliably propagate a Git failure. Callers needing strict behavior should
check Git directly rather than infer it from an empty successful result.

```bash
lib::load_extensions git
ext::git::remote_exists '^origin$'
```

#### `ext::git::toplevel`

```text
ext::git::toplevel
```

Obtain the toplevel directory of a Git repository. Return the repository's root path

**Outputs:** The absolute directory path.

**Returns:** The final echo status; Git failure is not explicitly propagated.

**Globals:** path (written)

#### `ext::git::remote_exists`

```text
ext::git::remote_exists PATTERN
```

Check if a remote exists

**Arguments:**

- 1 - Extended regular expression to match remote names

**Outputs:** Matching remote names to stdout; command errors to stderr.

**Returns:** The grep status: 0 match, 1 no match, 2 error (subject to pipefail).

**Globals:** remote, rc (written)

#### `ext::git::branch_exists`

```text
ext::git::branch_exists PATTERN
```

Check if a branch exists

**Arguments:**

- 1 - Extended regular expression to match local branch names

**Outputs:** Matching branch lines to stdout; command errors to stderr.

**Returns:** The grep status: 0 match, 1 no match, 2 error (subject to pipefail).

**Globals:** branch, rc (written)

### py extension

[Source](../extensions/libpy.sh)

Load with `lib::load_extensions py`. Creation requires a Python interpreter with
its `venv` module installed. Activation sources the selected environment's trusted
`bin/activate` in the current shell, so do not invoke it through command
substitution. An existing incomplete directory is an error; creation does not
repair or overwrite it. Existing valid environments ignore `--python`.

```bash
lib::load_extensions py
ext::py::venv ./project-env --python python3
```

#### `ext::py::venv`

```text
ext::py::venv [PATH] [--python COMMAND_OR_PATH]
```

Activate a Python venv in this shell, creating an absent path first. Existing incomplete paths are
refused rather than overwritten. --python selects the creation interpreter only; existing
environments are activated as-is. Failed creation can leave a partial directory for caller
inspection.

**Arguments:**

- 1 - Optional venv path (default .venv in the current directory)

- 2+ - Optional --python COMMAND_OR_PATH (default python3, then python)

**Outputs:** Python/activation output; errors to stderr.

**Returns:** Creation/activation status; 1 incomplete path/missing interpreter, 2 invalid invocation. Activation
failures may partially change the shell.

**Globals:** Activation may modify PATH, VIRTUAL_ENV, the prompt and shell functions.

### secret extension

[Source](../extensions/libsecret.sh)

Load with `lib::load_extensions secret`. Prefer `read_file` and `resolve` to the
legacy stdout reader. Default `text` mode preserves all non-NUL bytes, including
trailing newlines. `first-line` selects bytes before the first newline, retaining
carriage returns. Both reject NUL anywhere in the file. Empty selections require
`--allow-empty`; a newline-only file is nonempty in text mode.

Readers accept readable regular files and symlinks to them, including projected
secret mounts, without changing permissions. `od` is required at invocation.
Raw secret text does not enter temporary files, command substitution or external
argv. Memory grows with the encoded file size; inputs should be stable text
files rather than large streams or concurrently rewritten files.

`resolve` takes explicitly named direct and file-path variables. Default
`presence` precedence selects any set direct value, including an empty string,
without checking the overridden file. A selected empty value fails unless allowed;
it does not trigger file fallback. `nonempty` treats empty direct values as absent.
With neither eligible source, success unsets stale output. An empty selected file
path fails. Output may alias the direct variable, but not the file-path variable.

Generation uses `/dev/urandom` and rejection sampling. `alphanumeric` means ASCII
letters and digits; `numeric` means digits; `ascii`/`ASCII` means bytes 32–126,
including space and excluding controls. Defaults are 32 alphanumeric characters.
The accepted length range is 1–65536. Output is assigned only after full success.

```bash
lib::load_extensions secret
ext::secret::read_file certificate /run/secrets/certificate --mode text
ext::secret::generate token --length 48 --type alphanumeric
# Use the values without printing them.
```

#### `ext::secret::from_file`

```text
ext::secret::from_file PATH
```

Read a secret from the first line of a file. Only the first line is used: a trailing newline is an
editor artifact, not part of the secret.

**Arguments:**

- 1 - Path to the file holding the secret

**Outputs:** The secret to stdout. Warnings and errors go to stderr, so callers can capture the value with a
command substitution without catching them.

**Returns:** 0 on success, 1 if the file is missing, unreadable or empty.

#### `ext::secret::read_file`

```text
ext::secret::read_file OUT PATH [--mode text|first-line] [--allow-empty]
```

Read a text secret into an ordinary caller variable.

**Arguments:**

- 1 - Output variable name

- 2 - File path

- 3+ - Optional --mode text|first-line and --allow-empty

**Outputs:** Sanitized errors on stderr; no stdout.

**Returns:** 0 success, 1 I/O/dependency failure, 2 invalid input.

**Globals:** Named output variable (written only on success).

#### `ext::secret::resolve`

```text
ext::secret::resolve OUT --value-var NAME --file-var NAME [OPTIONS]
```

Resolve explicitly named direct/file variables without exporting the result.

**Arguments:**

- 1 - Output variable name

- 2+ - --value-var NAME and --file-var NAME; optional --mode text|first-line, --allow-empty and --precedence presence|nonempty

**Outputs:** Sanitized errors on stderr; no stdout.

**Returns:** 0 success (including absence), 1 I/O/dependency failure, 2 invalid input.

**Globals:** Named input variables (read) and output variable (written/unset on success).

#### `ext::secret::generate`

```text
ext::secret::generate OUT [-t|--type TYPE] [-l|--length N]
```

Generate a secret into a caller-owned scalar using /dev/urandom. Rejection sampling avoids modulo
bias. ASCII means bytes 32..126, including space but no controls; alphanumeric means A-Z, a-z and
0-9. Output is assigned only on complete success and is never printed or included in diagnostics.

**Arguments:**

- 1 - Output scalar variable name

- 2+ - -t/--type alphanumeric (default), numeric, `ascii` or ASCII; -l/--length 1..65536 (default 32)

**Outputs:** Sanitized errors to stderr; no stdout.

**Returns:** 0 generated, 1 random-source/tool failure, 2 invalid invocation/reference.

**Globals:** Named output scalar (written on success); PATH (read).

**Dependencies:** od and /dev/urandom, only at invocation.

### shell extension

[Source](../extensions/libshell.sh)

Load with `lib::load_extensions shell`. History-file lookup uses a visible
`HISTFILE` first, otherwise the login shell's default. Scrubbing is a literal
substring rewrite of the on-disk history file, not a change to another shell's
in-memory history. Short secrets may remove unrelated commands; later shell
history writes can restore removed entries. The rewritten file uses mode 600. This older scrubber passes its pattern to
external `grep` arguments; it is not a secret-safe replacement for avoiding
credentials in command history in the first place.

```bash
lib::load_extensions shell
ext::shell::history_file
```

#### `ext::shell::history_file`

```text
ext::shell::history_file
```

Resolve the path of the shell history file. A nonempty `HISTFILE` in the calling
shell wins. Otherwise use `~/.zsh_history` for a Zsh login shell and
`~/.bash_history` for other shells. The result has no trailing newline.

**Outputs:** The history file path to stdout.

**Returns:** The final output command status.

**Globals:** HISTFILE, SHELL (read)

#### `ext::shell::history_scrub`

```text
ext::shell::history_scrub SECRET
```

Remove every line of the shell history file that contains the given secret. Matching is a plain
substring match, so a short or dictionary-word secret can take unrelated commands with it -- the
length warning below exists for exactly that case.

**Arguments:**

- 1 - The secret to scrub. An empty value is a no-op.

**Outputs:** A summary and the in-memory caveat to stdout. The rewritten history file is left mode 600.

**Returns:** 0 on success or when there is nothing to do, 1 if the file exists but could not be rewritten.

**Globals:** HISTFILE, SHELL (read, via ext::shell::history_file)

### ui extension

[Source](../extensions/libui.sh)

Load with `lib::load_extensions ui`. Confirmation without a default refuses
noninteractive input. An explicit `y` or `n` default permits unattended use.
The spinner waits for a child PID started by the current shell and returns its
status; when stdout is not a terminal it emits no animation. It uses `sleep`;
file/backend output is not suppressed.

```bash
lib::load_extensions ui
if ext::ui::confirm 'Proceed with maintenance?' n; then
  ext::ui::print_banner 'Maintenance' 'https://example.org/project'
fi
```

#### `ext::ui::spinner`

```text
ext::ui::spinner PID [MESSAGE]
```

Run a spinner while a background PID is alive. No-ops to a plain `wait` when stdout isn't a
terminal, so cron/CI logs stay clean.

**Arguments:**

- 1 - PID to watch

- 2 - Message to display (optional)

**Outputs:** Spinner to stdout when attached to a terminal; process errors unchanged.

**Returns:** The watched process's exit code.

#### `ext::ui::confirm`

```text
ext::ui::confirm PROMPT [y|n]
```

Ask a yes/no question. Refuses to silently proceed when not attached to a terminal (cron/CI) unless
a default is explicitly given, so an unattended run never sails past a destructive confirmation by
accident.

**Arguments:**

- 1 - Prompt text

- 2 - Default: "y" or "n" (optional, no default = require a TTY)

**Outputs:** Interactive prompt and refusal diagnostics to stderr.

**Returns:** 0 for yes, 1 for no.

#### `ext::ui::print_banner`

```text
ext::ui::print_banner TITLE [URL]
```

Print a bordered startup banner.

**Arguments:**

- 1 - Title to display (e.g. the image/app name)

- 2 - Source URL to display (optional)

**Outputs:** The banner.

**Returns:** The final output command status.

#### `ext::ui::print_banner_divider`

```text
ext::ui::print_banner_divider
```

Print a divider line.

**Outputs:** The divider.

**Returns:** The final output command status.

## Migration from the longer module names

This prerelease rework has no compatibility aliases for renamed namespaces.
Update source paths and function calls together, then select the addons your
application actually needs. The [README.md notice](../README.md) describes the
0.x breaking-change policy; this reference does not change release versioning.

| Previous surface                                             | Current surface                                                  |
| ------------------------------------------------------------ | ---------------------------------------------------------------- |
| `lib::lib::load`                                             | `lib::load`; addons use `lib::load_extensions`                   |
| `lib/networking.sh`, `lib::networking::*`                    | `lib/net.sh`, `lib::net::*`                                      |
| `lib/opts.sh`, `lib::opts::*`                                | `lib/opt.sh`, `lib::opt::*`                                      |
| `lib/array.sh`, `lib::array::*`                              | `lib/data.sh`, `lib::data::*`                                    |
| Path, executable and root-permission helpers                 | Consolidated under `lib::os::*`                                  |
| Core APT, secret, Git, Python, shell and UI helpers          | Explicitly installed `extensions/lib<name>.sh`, `ext::<name>::*` |
| `lib::os::ensure_existence`, `lib::os::ensure_directory`     | `lib::fs::ensure_existence`, `lib::fs::ensure_directory`         |
| `lib::net::is_ipv4`, `lib::net::is_ipv6`                     | `lib::net::ipv4_validate`, `lib::net::ipv6_validate`             |
| Fatal `tcp_probe`/`tcp_dsn_probe` use                        | Prefer `endpoint_from_uri` and returning `tcp_wait`              |
| Implicit repair of an existing incomplete Python environment | Explicitly repair/remove it before `ext::py::venv`               |

Legacy Git helpers and fatal TCP wrappers retain their documented behavior for
now. Their presence is not a recommendation to copy those patterns into new
APIs. See [contributor requirements](CONTRIBUTING.md) and
[naming conventions](NOMENCLATURE.md). The API coverage test requires every public
function to have exactly one entry here; behavior changes must update its
contract, examples and tests in the same change.
