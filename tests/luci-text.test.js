'use strict';
// SPDX-License-Identifier: Apache-2.0
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const source = fs.readFileSync(path.join(__dirname,
	'../luci-app-owrtpc/htdocs/luci-static/resources/view/owrtpc/profiles-v2.js'), 'utf8');
const payload = '<img src=x onerror="globalThis.owrtpcInjected=true">';
String.prototype.format = function(...values) {
	let i = 0;
	return this.replace(/%[sd]/g, () => values[i++]);
};
const htmlSinks = [];
// LuCI.dom.append treats a scalar string as innerHTML, array strings as text.
// Model that documented distinction rather than treating every E() call as safe.
const E = (tag, attrs = {}, children = []) => {
	if (typeof children === 'string' && children.includes(payload)) htmlSinks.push(tag);
	return { tag, ...attrs, children, value: '', focus() {}, setAttribute() {}, removeAttribute() {} };
};
const options = {};
class FormMap {
	section() {
		return { option(_type, name) {
			const option = { choices: [], value(key, label) { this.choices.push([key, label]); } };
			options[name] = option;
			return option;
		} };
	}
	async render() { return E('div'); }
}
const events = {};
let stored = payload, modal, storageFailure = false;
const control = () => E('button');
const ui = {
	showModal(_title, nodes) { modal = nodes; }, hideModal() {}, addNotification() {},
	createHandlerFn(ctx, name) { return ctx[name].bind(ctx); }
};
const uci = {
	sections: () => [], changes: async () => ({}),
	get(_config, _section, name) { return name === 'device' ? ['02:00:00:00:00:01'] : null; }
};
const devices = {
	canonicalMac: value => value, isMacAddress: () => true,
	mergeDeviceSources: () => [{ mac: '02:00:00:00:00:01', name: payload, hostnames: [], addresses: [] }]
};
const rpc = { declare: () => async () => ({ success: false, error: payload }) };
const window = { location: { reload() {} }, setTimeout() {}, sessionStorage: {
	setItem(_key, value) { if (storageFailure) throw new Error('Unavailable'); stored = value; },
	getItem() { return stored; }, removeItem() { stored = null; }
} };
const api = new Function('view', 'form', 'uci', 'rpc', 'ui', 'devices', 'L', 'E', '_', 'window', 'document',
	source.replace('return view.extend(', 'const page = view.extend(') +
	';return {page, runQuickAction, queueNotification, showQueuedNotification};')(
	{ extend: x => x }, { Map: FormMap }, uci, rpc, ui, devices,
	{ bind: (fn, self) => fn.bind(self) }, E, x => x, window,
	{ addEventListener(name, callback) { events[name] = callback; } }
);
(async () => {
	await api.page.render([{}, {}, { profiles: [] }, {}, {}, null, true, { backend_version: payload }]);
	const deviceRows = options.device.textvalue('test');
	assert.ok(JSON.stringify(deviceRows).includes(payload.replaceAll('"', '\\"')));
	// DynamicList's selected-item span can receive the choice label directly.
	for (const [, label] of options.device.choices) E('span', {}, label);
	api.showQueuedNotification();
	storageFailure = true;
	api.queueNotification(payload);
	await api.runQuickAction(control(), Promise.resolve({ success: false, error: payload }), 'unused');
	await api.runQuickAction(control(), Promise.resolve({ success: true }), payload);
	events['uci-applied']();
	await new Promise(resolve => setImmediate(resolve));
	api.page.handleFullReset();
	const confirmation = modal.find(node => node.tag === 'input');
	confirmation.value = 'RESET OWRTPC';
	confirmation.input();
	const actions = modal.find(node => node.tag === 'div').children;
	await actions[2].click();
	assert.deepEqual(htmlSinks, [], 'untrusted names, labels, versions and RPC messages must remain text');
	console.log('ok - LuCI untrusted text remains inert across device labels and notifications');
})().catch(error => { console.error(error); process.exitCode = 1; });
