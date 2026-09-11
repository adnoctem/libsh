# `libsh` API Documentation

## Modules

This first pass covers the container configuration APIs and their compatibility
counterparts. Excerpts reproduce source doc comments and declaration lines;
function bodies are omitted. Private helpers are not consumer APIs.

### [Networking](../lib/networking.sh)

#### `lib::networking::endpoint_from_uri`

[Source](../lib/networking.sh#L176)

```bash
#######################################
# Extract a TCP endpoint from a restricted single-host database URI.
# Globals:
#   URI variable (read), host/port output variables (written on success).
# Arguments:
#   URI_VAR HOST_OUT PORT_OUT [--default-port PORT]
# Outputs:
#   Sanitized errors on stderr; no stdout. See docs/API.md.
# Returns:
#   0 success, 2 invalid reference/URI/port. Never exits.
#######################################
lib::networking::endpoint_from_uri() {
```

Pass the URI **variable name**, not its value; all three references must differ.
The Bash-only grammar is `scheme://[userinfo@]host[:port][/path][?query][#fragment]`.
Schemes start with a letter and then allow letters, digits, `+`, `.`, and `-`;
consumers choose supported schemes and default ports.

Hosts support ASCII DNS labels (letters/digits/hyphens, optional final dot),
IPv4, and bracketed IPv6 including IPv4 tails; output omits IPv6 brackets.
Userinfo permits URI unreserved characters, sub-delimiters, colon, and `%HH`
escapes. Escapes are checked everywhere and never decoded. Path/query/fragment
are opaque suffixes, not connection overrides; raw whitespace/control bytes
and malformed escapes are rejected throughout.

Multi-host/socket authorities, empty userinfo, missing hosts, unbracketed IPv6,
zone identifiers, host escapes, and malformed brackets are unsupported.
Ports must be decimal 1..65535; leading zeroes normalize as decimal. A supplied
default must be valid and applies only when the port is omitted, never when
explicitly empty. Omission without a default fails.

#### `lib::networking::tcp_wait`

[Source](../lib/networking.sh#L274)

```bash
#######################################
# Wait for TCP acceptance, returning control to the caller on failure.
# Globals:
#   None
# Arguments:
#   HOST PORT [--attempts N] [--timeout SECONDS] [--interval SECONDS] [--label LABEL]
# Outputs:
#   Progress on stdout, sanitized errors on stderr. Labels must contain no secrets.
# Returns:
#   0 connected, 1 dependency/connection/sleep failure, 2 invalid arguments.
#   Budget: attempts*timeout + (attempts-1)*interval, excluding DNS and overhead.
#######################################
lib::networking::tcp_wait() {
```

Defaults are 60 attempts, a 5-second timeout, and a 1-second interval.
Attempts/timeouts are positive decimal integers; interval may be zero, and all
three accept up to 999999999. One attempt invokes `nc` once; there is no sleep
after success or exhaustion, zero interval skips sleep, and sleep failure aborts.
Inputs and dependencies are checked before connecting.

Requires `nc`, `sleep`, and `uname`: use `netcat-openbsd` on Debian or system
`nc` on macOS, where the connection timeout also uses `-G`. Other netcat
implementations are unsupported. The budget is not a hard wall-clock deadline:
process overhead and platform DNS resolution (including multiple addresses)
can add time. TCP acceptance proves neither database authentication nor schema
readiness nor TLS trust; hosts and labels must be safe to log.

#### `lib::networking::tcp_probe`

[Source](../lib/networking.sh#L13)

```bash
#######################################
# Block until 'host:port' accepts a TCP connection, retrying on a fixed
# interval, or exit 1 after the retry budget is exhausted.
# Globals:
#   None
# Arguments:
#   1 - Host to connect to
#   2 - Port to connect to
#   3 - Label to use in log output (optional, defaults to "host:port")
#   4 - Number of retries before giving up (optional, default 60)
#   5 - Per-attempt connect timeout in seconds (optional, default 5)
# Outputs:
#   Progress/result via lib::log::*.
# Returns:
#   0 once the connection succeeds. Exits 1 if it never does.
#######################################
function lib::networking::tcp_probe() {
```

Compatibility wrapper retaining its positional arguments and fatal failure
behavior. Use `tcp_wait` when the consumer needs to recover or clean up.

#### `lib::networking::tcp_dsn_probe`

[Source](../lib/networking.sh#L38)

```bash
#######################################
# Convenience wrapper around lib::networking::tcp_probe: parse host/port out
# of a DSN with 'trurl' first. Kept separate from lib::networking::tcp_probe
# itself so this module carries no hard dependency on trurl being installed
# -- only callers of THIS function need it on PATH.
# Deprecated: credentials reach trurl argv. New callers should use
# endpoint_from_uri (variable reference) followed by tcp_wait instead.
# Globals:
#   None
# Arguments:
#   1 - DSN/URL to parse (e.g. "mysql://user:pass@host:3306/db")
#   2 - Default port to use if the DSN doesn't specify one
#   3 - Label to use in log output (optional, defaults to the DSN's host)
#   4 - Number of retries before giving up (optional, default 60)
#   5 - Per-attempt connect timeout in seconds (optional, default 5)
# Outputs:
#   Same as lib::networking::tcp_probe.
# Returns:
#   Same as lib::networking::tcp_probe.
#######################################
function lib::networking::tcp_dsn_probe() {
```

Retains the broader `trurl` grammar and fatal behavior for compatibility.
Migrate to `endpoint_from_uri` followed by `tcp_wait` to keep credentials out of
external argv and remove the parser dependency.

### Secret

#### `lib::secret::read_file`

[Source](../lib/secret.sh#L52)

```bash
#######################################
# Read a text secret into an ordinary caller variable.
# Globals:
#   Named output variable (written only on success).
# Arguments:
#   OUT PATH [--mode text|first-line] [--allow-empty]
# Outputs:
#   Sanitized errors on stderr; no stdout.
# Returns:
#   0 success, 1 I/O/dependency failure, 2 invalid input.
#######################################
lib::secret::read_file() {
```

Default `text` mode preserves every non-NUL byte, including trailing newlines,
whitespace, quotes, backslashes, and UTF-8. `first-line` returns bytes before
the first newline without stripping carriage returns or other whitespace.
Both modes reject NUL anywhere in the file. Empty selections require
`--allow-empty`; a newline-only file is nonempty in text mode.

Requires POSIX `od` (GNU coreutils on Debian, included on macOS). Readable
symlinks to regular files, including group-readable projected Secrets, are
supported without permission changes or warnings. Non-regular, missing,
unreadable inputs and read errors fail before output assignment. Raw secret
text never enters command substitution, temporary files, or external argv.
Memory scales with the encoded file size: use stable secret files or atomically
replaced symlink targets, not large streams, concurrent rewrites, or hostile paths.

#### `lib::secret::resolve`

[Source](../lib/secret.sh#L151)

```bash
#######################################
# Resolve explicitly named direct/file variables without exporting the result.
# Globals:
#   Named input variables (read) and output variable (written/unset on success).
# Arguments:
#   OUT --value-var NAME --file-var NAME [--mode text|first-line]
#   [--allow-empty] [--precedence presence|nonempty]
# Outputs:
#   Sanitized errors on stderr; no stdout.
# Returns:
#   0 success (including absence), 1 I/O/dependency failure, 2 invalid input.
#######################################
lib::secret::resolve() {
```

Default `presence` precedence selects a set direct value, including an empty
string, before the named file companion. An empty direct value fails unless
`--allow-empty` is supplied; it never falls back to a file. Overridden files are
not opened or checked for readability, and mode affects only file input.

Explicit legacy policy `nonempty` treats empty direct values as absent, allowing
file fallback. With neither eligible source, resolution succeeds and unsets
any stale output; an empty selected file path always fails. Selected files use
`read_file` semantics. Output may alias the direct variable but not the file-path
variable; exporting and application-level precedence remain consumer choices.

#### `lib::secret::from_file`

[Source](../lib/secret.sh#L6)

```bash
#######################################
# Read a secret from the first line of a file.
#
# Only the first line is used: a trailing newline is an editor artifact,
# not part of the secret.
# Globals:
#   None
# Arguments:
#   1 - Path to the file holding the secret
# Outputs:
#   The secret to stdout. Warnings and errors go to stderr, so callers can
#   capture the value with a command substitution without catching them.
# Returns:
#   0 on success, 1 if the file is missing, unreadable or empty.
#######################################
function lib::secret::from_file() {
```

Compatibility reader retaining first-line/nonempty behavior and permission
warnings. Prefer `read_file` for exact multiline text and projected Secret mounts.

### apt

TODO: Document this and the remaining modules after the naming review; see
[planned documentation work](TODO.md).

## Container Configuration

Source the installed `lib.sh` to load these APIs. The four new primitives require
Bash 4.0 or newer, return rather than exit, and preserve caller shell options
and traps. The compatibility probes above retain their fatal behavior.

### Variable references and failures

Use ordinary application scalar identifiers such as `DB_URI`. Declare
caller-local outputs before calling; otherwise assignment creates a global.
The `__libsh_` prefix and shell-owned names such as `IFS`, `PATH`, `RANDOM`,
and `BASH_*` are reserved. Arrays, namerefs, integer/case-transforming variables,
readonly outputs, subscripts, and expressions are rejected. Failures leave
outputs unchanged; no value is implicitly exported, but existing export
attributes remain.

For the new APIs, status `0` means success (including resolver absence), `1`
means an operational/dependency failure, and `2` means invalid input, including
NUL or a disallowed empty value. Unknown/duplicate options and missing arguments
are rejected. Readers/resolver/extractor produce no stdout; errors omit secret
values, selected paths, and original URIs. Wait progress goes to stdout.

Disable `set -x`, `set -v`, and secret-observing debug traps **before** handling
secrets; the library does not toggle them. Use explicit failure checks under
`set -euo pipefail` so the consumer can clean up. Do not log resolved values.

### Startup example

```bash
#!/usr/bin/env bash
set -euo pipefail
. /usr/local/lib/libsh/lib.sh

if lib::secret::resolve DB_PASSWORD --value-var DB_PASSWORD --file-var DB_PASSWORD_FILE \
  --mode first-line --precedence nonempty; then
  if [[ ${DB_PASSWORD+x} ]]; then export DB_PASSWORD; fi
else
  exit 1 # Or perform application-specific cleanup first.
fi

if lib::secret::resolve TLS_CA --value-var TLS_CA --file-var TLS_CA_FILE --mode text; then
  if [[ ${TLS_CA+x} ]]; then export TLS_CA; fi
else
  exit 1
fi

# DB_URI is already resolved; choose the default port in the consumer.
if lib::networking::endpoint_from_uri DB_URI db_host db_port --default-port 5432; then
  if lib::networking::tcp_wait "$db_host" "$db_port" --attempts 30 --label database; then
    : # Continue startup.
  else
    exit 1 # Consumer owns cleanup and failure policy.
  fi
else
  exit 1
fi
```

Lossless shell text cannot prevent downstream coercion of `000123` or `false`.
Field allowlists, schemas, configuration merging, CLI/configuration precedence,
and database/TLS integration belong to the consumer. URI construction is deferred.

### Installation and validation

Install the normal `lib` bundle during image construction with `bin/install`,
pinning an actual published tag containing these APIs. Set
`LIBSH_NO_MODIFY_PROFILE=1` if desired and explicitly source
`/usr/local/lib/libsh/lib.sh`; do not depend on PAM reading `/etc/environment`.
Runtime installation, root privileges, and a writable root filesystem are unnecessary.

The installer needs Bash, curl, tar/gzip, standard file/text utilities, and
`sha256sum` or `shasum`. The new runtime path needs Bash, `od`, `nc`, `sleep`,
and `uname`, without Node, Python, or trurl.

Use `make test-container` to build and run the installed-bundle tests on
bookworm Bash and Bash 4.0 as UID/GID 10001 with a read-only root and writable
`/tmp`. Docker and a running daemon are required; `make build-test-image`
builds only. Both targets accept `TEST_IMAGE=<tag>` (default
`libsh-container-test`) and `PRINT_HELP=y`. The test mount permits execution
for BATS fake commands; the library needs no executable temporary files.

The fixture uses a local checksummed test bundle, not a published release.
`make test WHAT=lib` and `make test` currently run the same library suite;
`make lint` checks the repository, and CI also runs real TCP checks on Linux/macOS.
See [Contributing](CONTRIBUTING.md) for the test workflow. Application typing
and real database/TLS integration remain separate consumer tests.
