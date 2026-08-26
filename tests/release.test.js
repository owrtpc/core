'use strict';
// SPDX-License-Identifier: Apache-2.0

const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const crypto = require('node:crypto');
const { spawnSync } = require('node:child_process');

const project = path.resolve(__dirname, '..');
const root = fs.mkdtempSync(path.join(os.tmpdir(), 'owrtpc-release-tests-'));
const repo = path.join(root, 'checkout with spaces');
const remote = path.join(root, 'origin.git');
const bin = path.join(root, 'bin');
const key = path.join(root, 'test-key.pem');
const env = { ...process.env, PATH: bin + path.delimiter + process.env.PATH,
	GIT_CONFIG_NOSYSTEM: '1', GIT_CONFIG_GLOBAL: '/dev/null' };
let passed = 0;

function git(cwd, ...args) {
	const result = spawnSync('git', ['-c', 'core.hooksPath=/dev/null', '-C', cwd, ...args],
		{ env, encoding: 'utf8' });
	assert.equal(result.status, 0, result.stderr);
	return result.stdout.trim();
}
function write(relative, value) {
	const target = path.join(repo, relative);
	fs.mkdirSync(path.dirname(target), { recursive: true });
	fs.writeFileSync(target, value);
}
function check() {
	return spawnSync('sh', [path.join(repo, 'scripts/check-release.sh'), repo],
		{ env, encoding: 'utf8' });
}
function blocked(result, reason) {
	assert.notEqual(result.status, 0);
	assert.match(result.stderr, reason);
	passed++;
}
function allowed() {
	const result = check();
	assert.equal(result.status, 0, result.stderr);
	assert.equal(result.stdout.trim(), git(repo, 'rev-parse', 'HEAD'));
	passed++;
}
function commit(cwd, message) {
	git(cwd, 'add', '.');
	git(cwd, 'commit', '--signoff', '-qm', message);
}
function identity(cwd) {
	git(cwd, 'config', 'user.name', 'Release Test');
	git(cwd, 'config', 'user.email', 'release@example.invalid');
}
function build(extra = {}) {
	return spawnSync('sh', [path.join(repo, 'scripts/build-signed-apk.sh')],
		{ cwd: repo, encoding: 'utf8', env: { ...env, PATH: bin + path.delimiter + env.PATH,
			OWRTPC_SIGNING_KEY: key, FIXTURE_REPO: repo, ...extra } });
}

try {
	fs.mkdirSync(repo);
	fs.mkdirSync(bin);
	// Mock only the network CI query. The production gate has no bypass.
	fs.writeFileSync(path.join(bin, 'python3'),
		'#!/bin/sh\n[ -z "$FAIL_CI" ] || exit 1\necho https://github.com/owrtpc/core/actions/runs/1\n',
		{ mode: 0o755 });
	git(root, 'init', '--bare', '-q', remote);
	git(repo, 'init', '-q', '-b', 'main');
	identity(repo);
	write('.gitignore', 'dist/\ntmp/\n*.ignored\n');
	write('luci-app-owrtpc/Makefile', 'PKG_VERSION:=0.1.0_alpha1\nPKG_RELEASE:=1\n');
	write('luci-app-owrtpc/payload', 'initial payload\n');
	write('owrtpc/Makefile', 'PKG_VERSION:=0.1.0_alpha1\nPKG_RELEASE:=1\n');
	write('owrtpc/payload', 'backend payload\n');
	write('scripts/sdk-build.sh', 'exit 0\n');
	write('scripts/check-ci.py', '# network query mocked by test python3\n');
	write('keys/owrtpc-release.pem', 'public key fixture\n');
	for (const name of ['check-release.sh', 'build-signed-apk.sh'])
		write('scripts/' + name, fs.readFileSync(path.join(project, 'scripts', name)));
	commit(repo, 'initial fixture');
	git(repo, 'commit', '--allow-empty', '-qm', 'unsigned fixture');
	blocked(check(), /lacks a DCO/);
	git(repo, 'commit', '--amend', '--allow-empty', '--no-edit', '--signoff');
	blocked(check(), /cannot verify origin\/main/);
	git(repo, 'remote', 'add', 'origin', remote);
	git(repo, 'push', '-q', '-u', 'origin', 'main');
	allowed();

	write('luci-app-owrtpc/payload', 'next payload\n');
	blocked(check(), /uncommitted changes/);
	// The builder must reject this before Docker or signing-key access.
	blocked(build(), /uncommitted changes/);
	git(repo, 'add', 'luci-app-owrtpc/payload');
	blocked(check(), /uncommitted changes/);
	commit(repo, 'unpushed fixture');
	blocked(check(), /HEAD differs from origin\/main/);
	git(repo, 'push', '-q', 'origin', 'main');
	allowed();

	write('untracked', 'not committed');
	blocked(check(), /uncommitted changes/);
	fs.unlinkSync(path.join(repo, 'untracked'));
	write('luci-app-owrtpc/local.ignored', 'must not be packaged');
	allowed();

	git(repo, 'checkout', '-qb', 'review');
	blocked(check(), /must use main/);
	git(repo, 'checkout', '-q', 'main');
	git(repo, 'checkout', '-q', '--detach');
	blocked(check(), /detached HEAD/);
	git(repo, 'checkout', '-q', 'main');

	// Prove the gate does not depend on cached remote-tracking refs.
	git(repo, 'update-ref', '-d', 'refs/remotes/origin/main');
	allowed();
	git(repo, 'fetch', '-q', 'origin');
	const peer = path.join(root, 'peer');
	git(root, 'clone', '-q', '-b', 'main', remote, peer);
	identity(peer);
	fs.writeFileSync(path.join(peer, 'peer-change'), 'remote ahead\n');
	commit(peer, 'advance remote');
	git(peer, 'push', '-q', 'origin', 'main');
	// Local origin/main still equals local HEAD, but the live remote differs.
	assert.equal(git(repo, 'rev-parse', 'HEAD'), git(repo, 'rev-parse', 'origin/main'));
	blocked(check(), /HEAD differs from origin\/main/);
	git(repo, 'fetch', '-q', 'origin');
	git(repo, 'merge', '-q', '--ff-only', 'origin/main');
	allowed();

	git(repo, 'remote', 'set-url', 'origin', path.join(root, 'unavailable.git'));
	blocked(check(), /cannot verify origin\/main/);
	git(repo, 'remote', 'set-url', 'origin', remote);
	blocked(build(), /Signing key not found/);
	blocked(build({ FAIL_CI: '1' }), /CI must pass/);

	// Mock only Docker: exercise the real preflight, archive, provenance and
	// overwrite protections without an SDK or access to the real signing key.
	fs.writeFileSync(key, 'private key fixture, not a real key\n');
	fs.writeFileSync(path.join(bin, 'docker'), [
		'#!/bin/sh',
		'set -eu',
		'if [ "@{FAIL_BUILD:-0}" = 1 ]; then exit 3; fi',
		'while [ "$#" -gt 0 ]; do',
		'  if [ "$1" = -v ]; then',
		'    case "$2" in',
		'      *:/output) output="@{2%:/output}" ;;',
		'      *:/build/*/package/owrtpc:ro) backend="@{2%%:/build/*}" ;;',
		'      *:/build/*/package/luci-app-owrtpc:ro) source="@{2%%:/build/*}" ;;',
		'    esac',
		'    shift',
		'  fi',
		'  shift',
		'done',
		'[ ! -e "$source/local.ignored" ]',
		'if [ "@{FAIL_SECOND:-0}" = 1 ]; then',
		'  cp "$backend/payload" "$output/owrtpc-0.1.0_alpha1-r1.apk"',
		'  exit 3',
		'fi',
		'printf "changed during build\\n" > "$FIXTURE_REPO/luci-app-owrtpc/payload"',
		'cp "$source/payload" "$output/luci-app-owrtpc-0.1.0_alpha1-r1.apk"',
		'cp "$backend/payload" "$output/owrtpc-0.1.0_alpha1-r1.apk"',
		''
	].join('\n').replace(/@\{/g, '$' + '{'), { mode: 0o755 });

	const filename = 'luci-app-owrtpc-0.1.0_alpha1-r1.apk';
	const dist = path.join(repo, 'dist');
	fs.mkdirSync(dist);
	const lock = path.join(dist, '.release.lock');
	fs.mkdirSync(lock);
	blocked(build(), /already in progress/);
	assert.ok(fs.existsSync(lock));
	fs.rmdirSync(lock);

	assert.equal(build({ FAIL_BUILD: '1' }).status, 3);
	assert.equal(fs.existsSync(path.join(dist, filename)), false);
	assert.equal(fs.existsSync(lock), false);
	passed++;
	// A first built package must not leak into dist when its companion fails.
	assert.equal(build({ FAIL_SECOND: '1' }).status, 3);
	assert.deepEqual(fs.readdirSync(dist), []);
	passed++;

	const sourceCommit = git(repo, 'rev-parse', 'HEAD');
	const result = build();
	assert.equal(result.status, 0, result.stderr);
	const backendName = 'owrtpc-0.1.0_alpha1-r1.apk';
	assert.equal(fs.readFileSync(path.join(dist, backendName), 'utf8'), 'backend payload\n');
	assert.ok(fs.existsSync(path.join(dist, backendName + '.buildinfo')));
	assert.ok(fs.existsSync(path.join(dist, backendName + '.sha256')));
	const apk = fs.readFileSync(path.join(dist, filename));
	assert.equal(apk.toString(), 'next payload\n');
	assert.equal(fs.existsSync(lock), false);
	passed++;
	const info = fs.readFileSync(path.join(dist, filename + '.buildinfo'), 'utf8');
	assert.ok(info.includes('source_commit=' + sourceCommit + '\n'));
	const digest = crypto.createHash('sha256').update(apk).digest('hex');
	assert.equal(fs.readFileSync(path.join(dist, filename + '.sha256'), 'utf8').trim(),
		digest + '  ' + filename);
	passed++;

	// Restore only the fixture content deliberately changed by the mock build.
	write('luci-app-owrtpc/payload', 'next payload\n');
	blocked(build(), /already exists; bump PKG_RELEASE/);
	assert.equal(fs.readFileSync(path.join(dist, filename), 'utf8'), 'next payload\n');
	fs.unlinkSync(path.join(dist, filename));
	blocked(build(), /already exists; bump PKG_RELEASE/);
	fs.unlinkSync(path.join(dist, filename + '.sha256'));
	fs.unlinkSync(path.join(dist, filename + '.buildinfo'));
	fs.unlinkSync(path.join(dist, backendName));
	blocked(build(), /already exists; bump PKG_RELEASE/);
	console.log('ok - ' + passed + ' release safeguards (real local Git remotes, mocked Docker)');
} finally {
	fs.rmSync(root, { recursive: true, force: true });
}
