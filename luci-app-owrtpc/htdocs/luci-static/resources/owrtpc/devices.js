'use strict';
'require baseclass';

function canonicalMac(value) {
	return String(value || '').trim().toUpperCase();
}

function isMacAddress(value) {
	return /^([0-9A-F]{2}:){5}[0-9A-F]{2}$/.test(canonicalMac(value));
}

function cleanName(value) {
	return String(value || '').trim().replace(/\.lan$/i, '');
}

function appendUnique(values, value) {
	value = String(value || '').trim();
	if (value && values.indexOf(value) === -1)
		values.push(value);
}

function ensureDevice(devices, mac) {
	mac = canonicalMac(mac);
	if (!isMacAddress(mac))
		return null;
	if (!devices[mac]) {
		devices[mac] = {
			mac: mac,
			hintName: '',
			hostnames: [],
			addresses: []
		};
	}
	return devices[mac];
}

function mergeDeviceSources(hostHints, leases, configuredMacs, aliases) {
	var devices = {};

	Object.keys(hostHints || {}).forEach(function(mac) {
		var hint = hostHints[mac] || {};
		var device = ensureDevice(devices, mac);
		if (!device)
			return;
		device.hintName = cleanName(hint.name);
		(hint.ipaddrs || hint.ipv4 || []).forEach(function(ip) { appendUnique(device.addresses, ip); });
		(hint.ip6addrs || hint.ipv6 || []).forEach(function(ip) { appendUnique(device.addresses, ip); });
	});

	(leases || []).forEach(function(lease) {
		var device = ensureDevice(devices, lease.macaddr);
		if (!device)
			return;
		appendUnique(device.hostnames, cleanName(lease.hostname));
		appendUnique(device.addresses, lease.ipaddr);
		appendUnique(device.addresses, lease.ip6addr);
	});

	Object.keys(aliases || {}).forEach(function(mac) {
		var device = ensureDevice(devices, mac);
		if (device)
			device.aliasName = cleanName(aliases[mac]);
	});

	(configuredMacs || []).forEach(function(mac) { ensureDevice(devices, mac); });

	return Object.keys(devices).map(function(mac) {
		var device = devices[mac];
		var name = device.aliasName || device.hintName || device.hostnames[0] || '';
		var hostnames = [ device.hintName ].concat(device.hostnames).filter(function(hostname, index, values) {
			return hostname.toLowerCase() !== name.toLowerCase();
		}).filter(function(hostname, index, values) {
			return hostname && values.indexOf(hostname) === index;
		});
		var search = [ name ].concat(hostnames, device.addresses, [ mac ]).filter(Boolean);
		return {
			mac: mac,
			name: name,
			hostnames: hostnames,
			addresses: device.addresses,
			search: search
		};
	}).sort(function(a, b) {
		var aKey = (a.name || a.mac).toLowerCase();
		var bKey = (b.name || b.mac).toLowerCase();
		return aKey < bKey ? -1 : aKey > bKey ? 1 : a.mac.localeCompare(b.mac);
	});
}

function matchesPrefix(device, query) {
	query = String(query || '').trim().toLowerCase();
	return !query || device.search.some(function(value) {
		return String(value).toLowerCase().startsWith(query);
	});
}

function isAvailable(mac, sectionId, assignments) {
	var owner = (assignments || {})[canonicalMac(mac)];
	return !owner || owner === sectionId;
}

return baseclass.extend({
	canonicalMac: canonicalMac,
	isMacAddress: isMacAddress,
	cleanName: cleanName,
	mergeDeviceSources: mergeDeviceSources,
	matchesPrefix: matchesPrefix,
	isAvailable: isAvailable
});
