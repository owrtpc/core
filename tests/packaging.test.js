'use strict';
// SPDX-License-Identifier: Apache-2.0
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const { spawnSync } = require('node:child_process');
const root = path.resolve(__dirname, '..');
const read = file => fs.readFileSync(path.join(root, file), 'utf8');
const core = read('owrtpc/Makefile');
const ui = read('luci-app-owrtpc/Makefile');
assert.match(core, /include \$\(INCLUDE_DIR\)\/package.mk/);
for (const dep of ['rpcd', 'rpcd-mod-luci', 'firewall4', 'nftables-json', 'jshn', 'jsonfilter', 'uci', 'ubus'])
	assert.ok(core.match(/^  DEPENDS:=(.*)$/m)[1].split(/\s+/).includes('+' + dep), dep);
assert.doesNotMatch(core.match(/^  DEPENDS:=(.*)$/m)[1], /\+luci-/);
assert.match(ui, /LUCI_DEPENDS:=\+luci-base \+owrtpc/);
assert.match(core, /EXTRA_DEPENDS:=!luci-app-owrtpc \(<0.1.0_alpha1-r22\)/);
assert.match(core, /define Package\/owrtpc\/preinst/);
assert.match(core, /\/etc\/config\/owrtpc\n\/etc\/owrtpc\/state\//);
function files(dir) {
	return fs.readdirSync(path.join(root, dir), { recursive: true })
		.filter(f => fs.statSync(path.join(root, dir, f)).isFile()).sort();
}
assert.deepEqual(files('luci-app-owrtpc/root'), ['usr/share/luci/menu.d/luci-app-owrtpc.json']);
const backendFiles = files('owrtpc/files');
assert.ok(backendFiles.includes('usr/libexec/rpcd/owrtpc'));
assert.ok(backendFiles.includes('etc/init.d/owrtpc'));
assert.ok(!backendFiles.some(f => f.includes('luci/') || f.includes('htdocs/')));
const acl = JSON.parse(read('owrtpc/files/usr/share/rpcd/acl.d/owrtpc.json'));
assert.deepEqual(acl.owrtpc.read, acl['luci-app-owrtpc'].read);
assert.deepEqual(acl.owrtpc.write, acl['luci-app-owrtpc'].write);
assert.deepEqual(acl.owrtpc.write.uci, ['owrtpc']);
assert.ok(acl.owrtpc.read.ubus['luci-rpc'].includes('getHostHints'));
assert.ok(acl.owrtpc.read.ubus.owrtpc.includes('capabilities'));
assert.ok(acl.owrtpc.write.ubus.owrtpc.includes('reset'));
assert.ok(!acl.owrtpc.read.ubus.owrtpc.includes('reset'));
const rpcPlugin = read('owrtpc/files/usr/libexec/rpcd/owrtpc');
for (const value of [
	"json_add_string api 'owrtpc-mobile'",
	'json_add_int major 1',
	'json_add_int minor 0',
	"json_add_string '' 'profiles.read'",
	"json_add_string '' 'profiles.write'",
	"json_add_string '' 'quick-actions'",
	"json_add_string '' 'device-discovery'",
	"json_add_string '' 'uci-apply-confirm'"
]) assert.ok(rpcPlugin.includes(value), value);
assert.match(ui, /LUCI_EXTRA_DEPENDS:=owrtpc \(>=0.1.0_alpha1-r24\)/);
for (const [dir, prefix] of [['owrtpc/files', ''], ['scripts', ''], ['docker', '']]) {
	for (const file of files(dir)) {
		const text = read(dir + '/' + file);
		if (!text.startsWith('#!/bin/sh')) continue;
		const result = spawnSync('sh', ['-n', path.join(root, dir, prefix, file)], { encoding: 'utf8' });
		assert.equal(result.status, 0, result.stderr);
	}
}
const ciTest = spawnSync('python3', ['-B', '-c', `
import importlib.util
spec = importlib.util.spec_from_file_location('ci', 'scripts/check-ci.py')
ci = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ci)
sha = 'a' * 40
ok = dict(head_sha=sha, head_branch='main', event='push', path='.github/workflows/ci.yml',
          run_number=1, status='completed', conclusion='success', html_url='https://github.com/owrtpc/core/actions/runs/1')
assert ci.verify({'workflow_runs': [ok]}, sha) == ok['html_url']
for runs in ([], [dict(ok, head_sha='b'*40)], [dict(ok, event='pull_request')],
             [dict(ok, status='in_progress')], [dict(ok, conclusion='failure')],
             [ok, dict(ok, run_number=2, conclusion='failure')],
             [ok, dict(ok, run_attempt=2, conclusion=None)]):
    try:
        ci.verify({'workflow_runs': runs}, sha)
    except ValueError:
        pass
    else:
        raise AssertionError(runs)
`], { cwd: root, encoding: 'utf8' });
assert.equal(ciTest.status, 0, ciTest.stderr);
// Refuse unsupported runtime hosts before downloads/builds. A Docker failure
// must also propagate, rather than masquerading as an architecture mismatch.
fs.mkdirSync(path.join(root, 'tmp'), { recursive: true });
const hostTest = fs.mkdtempSync(path.join(root, 'tmp', 'ci-host-test.'));
try {
	for (const [body, status, error] of [
		['echo x86_64', 1, /require a native ARM64 Docker host/],
		['echo "Docker unavailable" >&2; exit 42', 42, /Docker unavailable/]
	]) {
		fs.writeFileSync(path.join(hostTest, 'docker'), '#!/bin/sh\n' + body + '\n', { mode: 0o755 });
		const result = spawnSync('sh', ['scripts/ci-packages.sh'], {
			cwd: root, encoding: 'utf8', env: { ...process.env, PATH: hostTest + ':' + process.env.PATH }
		});
		assert.equal(result.status, status, result.stderr);
		assert.match(result.stderr, error);
	}
} finally {
	fs.rmSync(hostTest, { recursive: true, force: true });
}
console.log('ok - package boundaries, dependency declarations, ACLs, shell syntax and CI gate');
