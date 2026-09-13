# Linter configuration

`make lint` and pre-commit are the primary checks. SuperLinter adds independent
checks using the pinned workflow image. Generated `CHANGELOG.md`, build output,
local planning notes and vendored BATS sources are excluded from repository linting.

- Bash executable checks ignore sourced files without shebangs. Test entry points
  with shebangs are executable; library modules do not need executable permission.
- `shfmt` owns shell indentation, including literal heredoc bodies. EditorConfig
  checker still checks other properties, but its indentation check is disabled
  because it cannot distinguish shell code from embedded fixture data.
- Prettier owns JSON formatting. Biome formatting is disabled to avoid conflicting
  defaults; Biome lint checks remain enabled.
- JSCPD ignores comments, tests, documentation and generated/local files. Its
  seven-percent ceiling accommodates the reviewed 6.70% baseline, primarily
  standalone script discovery, flag handling and database setup. Shared code
  should be reviewed rather than raising this ceiling for future duplication.
- Textlint retains project terminology: `blank line`, `TODO`, the `curl` command,
  and historical AngularJS references. Other terminology rules remain enabled.
- The finite container test runner is not a service. Only its missing-health-check
  finding is suppressed: Checkov's inline `CKV_DOCKER_2` annotation and Trivy's
  path-scoped `DS-0026` entry. Other container findings remain checked.

Pre-commit also runs in the dedicated lint job. When testing SuperLinter against
an isolated local file snapshot without Git metadata, disable only its nested
`PRE_COMMIT` invocation and run `pre-commit run --all-files` in the checkout.
