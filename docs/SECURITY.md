# `libsh` Security Policy

## Reporting a Vulnerability

Report suspected vulnerabilities privately to the [info+libsh@adnoctem.co][report_contact]. Do not open a public issue
with exploit details, credentials or private system information before maintainers have had an opportunity to
assess the report.

Useful reports include:

- The affected release or commit, operating system and Bash version.
- The affected function, executable or installation path.
- A minimal reproduction using synthetic data, expected behavior and observed behavior.
- The likely impact, required privileges and relevant configuration.
- A contact address for follow-up and your disclosure or acknowledgement preferences.

Remove passwords, tokens, private keys and unrelated personal information from examples and logs. If a credential
has already been exposed, revoke or rotate it through the service that issued it; removing a log entry alone does
not invalidate the credential.

Maintainers will assess the report, discuss reproduction or mitigation as needed, and coordinate a fix and public
disclosure when appropriate. Please coordinate publication while the issue is being addressed. This project is
maintained on a best-effort basis and does not promise a fixed response or remediation deadline.

If a problem originates in a third-party dependency, report it to that project as well. Let libsh maintainers
know when it affects a libsh installation or documented workflow so mitigations can be coordinated.

## Versions and Fixes

`libsh` is in pre-1.0 development. Reports should identify an exact version; maintainers may ask whether the issue
also reproduces on the latest release or current development code. Fixes normally target current development and
an upcoming release. Backports to older versions are not guaranteed.

Breaking changes may occur in `0.x` without a major version bump. Pin releases for reproducible deployments and
review release notes when updating; pinning also means that updates must be applied deliberately. See the
[contribution guide][contributing] for the current release policy.

## Trust and Privilege Boundaries

Sourcing Bash code executes it with the caller's permissions. Core and extensions are not sandboxed plugins;
load them only from trusted locations. Loading core does not itself install packages or elevate privileges,
but individual operations can modify files, accounts or system configuration when explicitly called.

The bootstrap, manager, release repository and downloaded assets are part of the installation trust chain.
`libman` verifies assets against the release's SHA-256 manifest before activation. This checks consistency with
that manifest; it is not an independent publisher signature and does not protect against an attacker replacing
both an asset and its manifest. A piped installer also executes before it can verify later release downloads.
Review the installer and choose a trusted release source appropriate to your environment.

`lib::os::root_exec` invokes sudo only when needed and requested by the consumer. Its environment-preservation
option remains subject to sudo policy; review exported variables before preserving them across a privilege change.
A new privileged Bash process must still source its own functions.

Filesystem staging and link checks have operation-specific limits. They do not provide a general sandbox,
a transaction across files, or protection against every concurrent path replacement. Consult the relevant
[API contract][api] before using an editing operation on paths another user can modify.

## Secrets and Diagnostics

The secret APIs do not make Bash a secure-memory store. Values remain shell data and may be exposed by tracing,
debug traps, exported environments, command arguments or caller-generated logs. Use the documented output-variable
interfaces when exact bytes matter, and avoid exporting or logging secret values unnecessarily.

`LIBSH_DEBUG` enables diagnostic output; it does not redact messages. Callers are responsible for choosing safe
message content. The library's log writers do not add encryption or choose restrictive permissions on the caller's
behalf: new log files inherit the caller's umask. Select suitable file ownership, permissions and retention.

<!-- File references -->

[contributing]: CONTRIBUTING.md
[api]: API.md

<!-- Contact links -->

[report_contact]: mailto:info+libsh@adnoctem.co
