'use strict';
// SPDX-License-Identifier: Apache-2.0
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname,
	'../luci-app-owrtpc/htdocs/luci-static/resources/view/owrtpc/profiles-v2.js'), 'utf8');
String.prototype.format = function(value) { return this.replace('%s', value); };

function harness({ writable = true, changes = {}, response = { success: true }, reject = false } = {}) {
	const state = { calls: [], notifications: [], reloads: 0, modal: null, hidden: 0 };
	const E = (tag, attrs, children) => ({
		tag, ...attrs, children, value: '', focus() { this.focused = true; }
	});
	const ui = {
		showModal(title, children) { state.modal = { title, children }; },
		hideModal() { state.hidden++; },
		addNotification(title, content, level) { state.notifications.push({ content, level }); },
		createHandlerFn(ctx, name) { return ctx[name].bind(ctx); }
	};
	const rpc = { declare: spec => async (...args) => {
		state.calls.push({ spec, args });
		if (reject) throw new Error('Connection lost');
		return response;
	} };
	class FormMap {
		section() { return { option: () => ({ value() {} }) }; }
		async render() { return E('div', {}, []); }
	}
	const page = new Function('view', 'form', 'uci', 'rpc', 'ui', 'devices', 'L', 'E', '_', 'window', 'document', source)(
		{ extend: value => value }, { Map: FormMap }, { changes: async () => changes, sections: () => [] }, rpc, ui,
		{ mergeDeviceSources: () => [] }, { bind: (fn, self) => fn.bind(self) }, E, value => value,
		{ setTimeout() {}, sessionStorage: { setItem() {} }, location: { reload() { state.reloads++; } } },
		{ addEventListener() {} }
	);
	state.page = page;
	page.canReset = writable;
	page.handleFullReset();
	if (state.modal) {
		state.input = state.modal.children.find(node => node.tag === 'input');
		const actions = state.modal.children.find(node => node.tag === 'div').children;
		[state.cancel, , state.confirm] = actions;
		state.type = value => { state.input.value = value; state.input.input(); };
	}
	return state;
}

(async () => {
	const denied = harness({ writable: false });
	assert.equal(denied.modal, null, 'read-only users cannot open reset');
	assert.equal(denied.calls.length, 0);
	for (const access of [true, false, null]) {
		const rendered = await denied.page.render([{}, {}, { profiles: [] }, {}, {}, null, access,
			{ backend_version: '0.1.0-r1' }]);
		const button = rendered.children[1].children[2];
		assert.equal(button.disabled, access === true ? null : true,
			'HTML disabled attribute is omitted only with an explicit RPC grant');
		assert.deepEqual(rendered.children[2].children[0].children, ['OWRTPC core version 0.1.0-r1']);
	}
	const cancel = harness();
	assert.equal(cancel.confirm.disabled, true);
	cancel.cancel.click();
	assert.equal(cancel.calls.length, 0, 'cancel does not make a reset request');
	assert.equal(cancel.hidden, 1);
	const ok = harness();
	ok.type('RESET');
	assert.equal(ok.confirm.disabled, true);
	await ok.confirm.click();
	assert.equal(ok.calls.length, 0, 'partial confirmation cannot reset');
	ok.type('RESET OWRTPC');
	assert.equal(ok.confirm.disabled, false);
	const pending = ok.confirm.click();
	assert.equal(ok.cancel.disabled, true, 'cannot cancel an operation already sent');
	await ok.confirm.click();
	await pending;
	assert.equal(ok.calls.length, 1, 'double click sends exactly one reset');
	assert.equal(ok.calls[0].spec.method, 'reset');
	assert.deepEqual(ok.calls[0].args, ['RESET OWRTPC']);
	assert.equal(ok.reloads, 1);
	for (const options of [
		{ changes: { owrtpc: [['set', 'main', 'enabled', '0']] } },
		{ response: { success: false, error: 'Reset blocked' } },
		{ reject: true }
	]) {
		const failed = harness(options);
		failed.type('RESET OWRTPC');
		await failed.confirm.click();
		assert.equal(failed.reloads, 0, 'failure is not reported as success');
		assert.equal(failed.notifications[0].level, 'error');
		if (options.changes) assert.equal(failed.calls.length, 0, 'staged edits prevent reset');
	}
	const unrelated = harness({ changes: { network: [['set', 'lan', 'mtu', '1400']] } });
	unrelated.type('RESET OWRTPC');
	await unrelated.confirm.click();
	assert.equal(unrelated.calls.length, 1, 'unrelated staged config is neither applied nor discarded');
	console.log('ok - reset confirmation, cancel, permissions, double click, pending edits and RPC errors');
})().catch(error => { console.error(error); process.exitCode = 1; });
