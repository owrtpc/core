'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';

var callStatus = rpc.declare({ object: 'owrtpc', method: 'status', expect: { '': {} } });
var callSetBlock = rpc.declare({ object: 'owrtpc', method: 'set_block', params: [ 'profile', 'blocked' ], expect: { '': {} } });
var callRefresh = rpc.declare({ object: 'owrtpc', method: 'refresh', expect: { '': {} } });
var callDHCPLeases = rpc.declare({ object: 'luci-rpc', method: 'getDHCPLeases', expect: { '': {} } });

function formatDuration(seconds) {
	seconds = Math.max(0, Number(seconds) || 0);
	var hours = Math.floor(seconds / 3600);
	var minutes = Math.floor((seconds % 3600) / 60);
	if (hours && minutes)
		return _('%dh %dm').format(hours, minutes);
	if (hours)
		return _('%dh').format(hours);
	return _('%dm').format(minutes);
}

function reasonLabel(reason) {
	return ({
		none: _('Allowed'), disabled: _('Profile disabled'), manual: _('Manually blocked'),
		bedtime: _('Bedtime'), quota: _('Daily allowance exhausted')
	})[reason] || reason;
}

function canonicalMac(value) {
	return String(value || '').toUpperCase();
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('owrtpc'), uci.load('firewall'), callStatus(),
			callDHCPLeases().catch(function() { return {}; })
		]);
	},

	render: function(data) {
		var status = {};
		(data[2].profiles || []).forEach(function(profile) { status[profile.section] = profile; });
		var leases = (data[3].dhcp_leases || []).concat(data[3].dhcp6_leases || []);
		var firewallDefaults = uci.sections('firewall', 'defaults')[0] || {};
		var flowOffloading = firewallDefaults.flow_offloading === '1' || firewallDefaults.flow_offloading_hw === '1';
		var m = new form.Map('owrtpc', _('OWRTPC Parental Control'),
			_('Daily time belongs to a profile and is cumulative across all of its devices. Two active devices consume twice as fast.'));
		var g = m.section(form.NamedSection, 'main', 'globals', _('Engine settings'));
		g.addremove = false;
		var o = g.option(form.Flag, 'enabled', _('Enable OWRTPC'));
		o.default = o.enabled;
		o.rmempty = false;
		if (flowOffloading)
			o.description = _('Warning: firewall flow offloading is enabled. Disable software and hardware flow offloading or usage accounting and blocking will be incomplete.');
		o = g.option(form.Value, 'sample_interval', _('Sampling interval (seconds)'));
		o.datatype = 'range(15,300)';
		o.default = '60';
		o.rmempty = false;
		o = g.option(form.Value, 'activity_threshold_bytes', _('Activity threshold (bytes)'));
		o.datatype = 'uinteger';
		o.default = '1024';
		o.rmempty = false;
		o.description = _('A device consumes an interval only after transferring at least this many bytes.');
		o = g.option(form.Value, 'checkpoint_interval', _('State checkpoint (seconds)'));
		o.datatype = 'range(300,86400)';
		o.default = '900';
		o.rmempty = false;
		o.description = _('Longer intervals reduce flash writes but can lose more usage after a sudden power loss.');
		o = g.option(form.DynamicList, 'monitored_network', _('Internet networks'));
		o.default = [ 'wan', 'wan6' ];
		o.rmempty = false;
		o.description = _('Logical OpenWrt network interfaces whose outgoing traffic is controlled.');
		o = g.option(form.DynamicList, 'monitored_device', _('Additional output devices'));
		o.rmempty = true;
		o.description = _('Optional Linux device names used when no logical OpenWrt network exists, mainly for testing.');

		var s = m.section(form.GridSection, 'profile', _('Profiles'));
		s.anonymous = true;
		s.addremove = true;
		s.sortable = true;
		s.nodescriptions = true;
		s.sectiontitle = function(sectionId) { return uci.get('owrtpc', sectionId, 'name') || _('New profile'); };
		o = s.option(form.Value, 'name', _('Name'));
		o.rmempty = false;
		o.placeholder = _('Children');
		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = o.enabled;
		o.rmempty = false;

		o = s.option(form.DynamicList, 'device', _('Devices'));
		o.datatype = 'macaddr';
		o.rmempty = true;
		o.description = _('A device may belong to one profile only. Disable MAC randomization for this network on the client.');
		leases.forEach(function(lease) {
			var mac = canonicalMac(lease.macaddr);
			if (!mac)
				return;
			o.value(mac, [ lease.hostname, lease.ipaddr || lease.ip6addr, mac ].filter(Boolean).join(' — '));
		});
		o.validate = function(sectionId, value) {
			var values = Array.isArray(value) ? value : [ value ];
			var profiles = uci.sections('owrtpc', 'profile');
			for (var i = 0; i < values.length; i++) {
				var mac = canonicalMac(values[i]);
				for (var j = 0; j < profiles.length; j++) {
					if (profiles[j]['.name'] === sectionId)
						continue;
					var other = profiles[j].device || [];
					if (!Array.isArray(other))
						other = [ other ];
					if (other.map(canonicalMac).indexOf(mac) !== -1)
						return _('This device is already assigned to profile "%s".').format(profiles[j].name || profiles[j]['.name']);
				}
			}
			return true;
		};

		o = s.option(form.Value, 'daily_minutes', _('Daily allowance (minutes)'));
		o.datatype = 'uinteger';
		o.default = '0';
		o.rmempty = false;
		o.description = _('Cumulative across the profile devices. Use 0 for unlimited.');
		o = s.option(form.Value, 'bedtime_start', _('Bedtime starts'));
		o.placeholder = '21:30';
		o.description = _('Router local time in HH:MM. Leave both bedtime fields empty to disable.');
		o.validate = function(sectionId, value) {
			return !value || /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(value) || _('Use HH:MM, for example 21:30.');
		};
		o = s.option(form.Value, 'bedtime_end', _('Bedtime ends'));
		o.placeholder = '07:00';
		o.validate = function(sectionId, value) {
			return !value || /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(value) || _('Use HH:MM, for example 07:00.');
		};

		o = s.option(form.DummyValue, '_usage', _('Used today'));
		o.cfgvalue = function(sectionId) { return status[sectionId] ? formatDuration(status[sectionId].used_seconds) : '—'; };
		o = s.option(form.DummyValue, '_remaining', _('Remaining'));
		o.cfgvalue = function(sectionId) {
			if (!status[sectionId])
				return '—';
			return status[sectionId].limit_seconds ? formatDuration(status[sectionId].remaining_seconds) : _('Unlimited');
		};
		o = s.option(form.DummyValue, '_state', _('State'));
		o.cfgvalue = function(sectionId) { return reasonLabel(status[sectionId] ? status[sectionId].reason : 'none'); };

		o = s.option(form.Button, '_quick_block', _('Quick action'));
		o.inputtitle = _('Block / unblock');
		o.inputstyle = 'action';
		o.onclick = function(sectionId) {
			var profile = status[sectionId] || {};
			return callSetBlock(sectionId, !profile.manual_blocked).then(function(result) {
				if (!result.success)
					throw new Error(result.error || _('The quick action failed.'));
				window.location.reload();
			}).catch(function(error) { ui.addNotification(null, E('p', {}, error.message), 'error'); });
		};

		m.on_after_commit = function() {
			return callRefresh().then(function(result) {
				if (!result.success)
					ui.addNotification(null, E('p', {}, result.error || _('Configuration was saved but policy refresh failed.')), 'warning');
			});
		};
		return m.render();
	}
});
