'use strict';

const fs = require('fs');
const path = require('path');

const source = fs.readFileSync(path.join(__dirname,
	'../luci-app-owrtpc/htdocs/luci-static/resources/owrtpc/devices.js'), 'utf8');
const devices = new Function('baseclass', source)({ extend: value => value });
let passed = 0;

function assert(condition, message) {
	if (!condition)
		throw new Error(message);
	passed++;
}

const merged = devices.mergeDeviceSources({
	'CC:B0:B3:1B:C9:9A': {
		name: 'desmoXBOX.lan',
		ipaddrs: [ '192.168.8.88' ],
		ip6addrs: []
	},
	'CC:64:1A:74:7E:7C': {
		name: 'XEROX',
		ipaddrs: [],
		ip6addrs: []
	}
}, [
	{ macaddr: 'cc:b0:b3:1b:c9:9a', hostname: 'xbox-network', ipaddr: '192.168.8.88' },
	{ macaddr: '08:7c:39:cd:9d:4d', hostname: 'AmazonPlug0WLR.lan', ipaddr: '192.168.10.144' }
], [ 'DA:CE:95:F9:3A:8E' ], {
	'CC:B0:B3:1B:C9:9A': 'Console salotto',
	'00:F3:61:F9:30:5A': 'PS4'
});

const byMac = Object.fromEntries(merged.map(device => [ device.mac, device ]));
assert(byMac['CC:B0:B3:1B:C9:9A'].name === 'Console salotto', 'a GL.iNet alias should have highest priority');
assert(byMac['CC:B0:B3:1B:C9:9A'].hostnames.includes('desmoXBOX'), 'the LuCI host hint should be retained as an alternate name');
assert(byMac['CC:B0:B3:1B:C9:9A'].hostnames.includes('xbox-network'), 'different lease hostname should be retained');
assert(byMac['00:F3:61:F9:30:5A'].name === 'PS4', 'an alias-only device should be included');
assert(byMac['08:7C:39:CD:9D:4D'].name === 'AmazonPlug0WLR', 'lease-only device should be included');
assert(byMac['DA:CE:95:F9:3A:8E'].mac === 'DA:CE:95:F9:3A:8E', 'configured offline device should be retained');
assert(devices.matchesPrefix(byMac['CC:B0:B3:1B:C9:9A'], 'desmo'), 'name prefix should match');
assert(devices.matchesPrefix(byMac['CC:B0:B3:1B:C9:9A'], '192.168.8'), 'IP prefix should match');
assert(devices.matchesPrefix(byMac['CC:B0:B3:1B:C9:9A'], 'cc:b0'), 'MAC prefix should be case insensitive');
assert(!devices.matchesPrefix(byMac['CC:B0:B3:1B:C9:9A'], 'B0:B3'), 'matching should use startsWith, not contains');
assert(devices.canonicalMac('') === '', 'an optional empty device value should remain empty');
assert(devices.isMacAddress('cc:b0:b3:1b:c9:9a'), 'a canonical device MAC should be accepted case insensitively');
assert(!devices.isMacAddress('192.168.8.88'), 'an IP search term must not be accepted as a selected MAC');
assert(devices.isAvailable('CC:B0:B3:1B:C9:9A', 'profile_a', {}), 'an unassigned device should be available');
assert(devices.isAvailable('cc:b0:b3:1b:c9:9a', 'profile_a', {
	'CC:B0:B3:1B:C9:9A': 'profile_a'
}), 'a device should remain available in its current profile');
assert(!devices.isAvailable('CC:B0:B3:1B:C9:9A', 'profile_b', {
	'CC:B0:B3:1B:C9:9A': 'profile_a'
}), 'a device assigned to another profile should not be offered');

console.log(`ok - ${passed} device autocomplete assertions`);
