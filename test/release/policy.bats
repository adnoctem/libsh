#!/usr/bin/env bats

setup() {
	REPO_ROOT=$(cd "$BATS_TEST_DIRNAME/../.." && pwd)
	load "$REPO_ROOT/test/bats/plugins/bats-support/load"
	load "$REPO_ROOT/test/bats/plugins/bats-assert/load"
}

@test "release check accepts 0.x without changing the Makefile" {
	local before
	before=$(cat "$REPO_ROOT/Makefile")
	run bash "$REPO_ROOT/tools/release-prepare.sh" --version 0.6.0 --check-version
	assert_success
	assert_output ''
	[[ $(cat "$REPO_ROOT/Makefile") == "$before" ]]
}

@test "release verification blocks major versions before preparation" {
	local version
	for version in 1.0.0 2.0.0 10.0.0; do
		run bash "$REPO_ROOT/tools/release-prepare.sh" --version "$version" --check-version
		assert_failure 1
		assert_output --partial 'only 0.x releases are enabled'
	done
}

@test "preparation also refuses major versions without invoking build tools" {
	local fake="$BATS_TEST_TMPDIR/bin" marker="$BATS_TEST_TMPDIR/build-ran" before
	mkdir -p "$fake"
	# shellcheck disable=SC2016 # expanded by the fake build command
	printf '#!/usr/bin/env bash\nprintf ran >"$BUILD_MARKER"\n' >"$fake/make"
	chmod +x "$fake/make"
	before=$(cat "$REPO_ROOT/Makefile")
	run env PATH="$fake:$PATH" BUILD_MARKER="$marker" bash "$REPO_ROOT/tools/release-prepare.sh" --version 1.0.0
	assert_failure 1
	assert_output --partial 'only 0.x releases are enabled'
	[[ ! -e $marker && $(cat "$REPO_ROOT/Makefile") == "$before" ]]
}

@test "malformed versions cannot pass release verification" {
	local version
	for version in 00.6.0 0.06.0 0.6 0.6.0-rc.1 v0.6.0 '0.6.0; false'; do
		run bash "$REPO_ROOT/tools/release-prepare.sh" --version "$version" --check-version
		assert_failure 1
	done
}

@test "JSON configuration wires the minor rule and the release verification hook" {
	run node --input-type=module -e '
		import assert from "node:assert/strict";
		import { readFileSync, existsSync } from "node:fs";
		const root = process.argv[1];
		const config = JSON.parse(readFileSync(root + "/.releaserc", "utf8"));
		const analyzer = config.plugins.find(([name]) => name === "@semantic-release/commit-analyzer")[1];
		assert.deepEqual(analyzer.releaseRules, [{ breaking: true, release: "minor" }]);
		const exec = config.plugins.find(([name]) => name === "@semantic-release/exec")[1];
		assert.equal(exec.verifyReleaseCmd, exec.prepareCmd + " --check-version");
		assert.ok(!existsSync(root + "/.releaserc.cjs"));
	' "$REPO_ROOT"
	assert_success
}
