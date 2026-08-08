'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';
'require owrtpc.devices as devices';

var callStatus = rpc.declare({ object: 'owrtpc', method: 'status', expect: { '': {} } });
var callSetBlock = rpc.declare({ object: 'owrtpc', method: 'set_block', params: [ 'profile', 'blocked' ], expect: { '': {} } });
var callAddTime = rpc.declare({ object: 'owrtpc', method: 'add_time', params: [ 'profile', 'minutes' ], expect: { '': {} } });
var callRefresh = rpc.declare({ object: 'owrtpc', method: 'refresh', expect: { '': {} } });
var callDHCPLeases = rpc.declare({ object: 'luci-rpc', method: 'getDHCPLeases', expect: { '': {} } });
var callHostHints = rpc.declare({ object: 'luci-rpc', method: 'getHostHints', expect: { '': {} } });

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
	return devices.canonicalMac(value);
}

function deviceLabel(device) {
	return [ device.name ].concat(device.hostnames, device.addresses, [ device.mac ]).filter(Boolean).join(' — ');
}

function configuredDevices() {
	var result = [];
	uci.sections('owrtpc', 'profile').forEach(function(profile) {
		var values = Array.isArray(profile.device) ? profile.device : [ profile.device ];
		values.filter(Boolean).forEach(function(mac) { result.push(canonicalMac(mac)); });
	});
	return result;
}

function bindDeviceAutocomplete(option, deviceMap, assignments) {
	var inheritedRenderWidget = option.renderWidget;
	option.renderWidget = function(sectionId, optionIndex, cfgvalue) {
		var node = inheritedRenderWidget.call(this, sectionId, optionIndex, cfgvalue);
		var dropdown = node.querySelector('.cbi-dropdown');
		var input = node.querySelector('.create-item-input');
		if (!dropdown || !input)
			return node;

		input.placeholder = _('Search by name, IP or MAC');
		var searchItem = input.closest('li');
		if (searchItem && searchItem.parentNode)
			searchItem.parentNode.insertBefore(searchItem, searchItem.parentNode.firstChild);

		var filter = function() {
			var query = input.value;
			dropdown.querySelectorAll('ul:not(.preview) > li[data-value]').forEach(function(item) {
				var mac = canonicalMac(item.getAttribute('data-value'));
				if (!mac || mac === '-')
					return;
				item.style.display = deviceMap[mac] &&
					devices.isAvailable(mac, sectionId, assignments) &&
					devices.matchesPrefix(deviceMap[mac], query) ? '' : 'none';
			});
		};

		input.addEventListener('input', filter);
		input.addEventListener('keydown', function(event) {
			if (event.key !== 'Enter')
				return;
			event.preventDefault();
			event.stopImmediatePropagation();
			var match = Array.prototype.find.call(
				dropdown.querySelectorAll('ul:not(.preview) > li[data-value]'),
				function(item) {
					return item.getAttribute('data-value') !== '-' &&
						item.style.display !== 'none' && !item.hasAttribute('unselectable');
				});
			if (match)
				match.click();
		}, true);
		node.addEventListener('cbi-dynlist-change', function() {
			input.value = '';
			filter();
		});
		filter();
		return node;
	};
}

function scheduleValue(sectionId, schedule, option, legacyOption, fallback) {
	var value = uci.get('owrtpc', sectionId, schedule + '_' + option);
	if (value == null || value === '')
		value = uci.get('owrtpc', sectionId, legacyOption);
	return value == null || value === '' ? fallback : value;
}

function validateTime(value, example) {
	return !value || /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(value) ||
		_('Use HH:MM, for example %s.').format(example);
}

function reloadWithNotification(message) {
	try {
		window.sessionStorage.setItem('owrtpc-notification', message);
	}
	catch (error) {
		ui.addNotification(null, E('p', {}, message), 'info');
	}
	window.location.reload();
}

function showQueuedNotification() {
	var message = null;
	try {
		message = window.sessionStorage.getItem('owrtpc-notification');
		window.sessionStorage.removeItem('owrtpc-notification');
	}
	catch (error) {}
	if (message)
		ui.addNotification(null, E('p', {}, message), 'info');
}

function runQuickAction(button, request, successMessage) {
	button.disabled = true;
	return request.then(function(result) {
		if (!result.success)
			throw new Error(result.error || _('The quick action failed.'));
		reloadWithNotification(successMessage);
	}).catch(function(error) {
		button.disabled = false;
		ui.addNotification(null, E('p', {}, error.message), 'error');
	});
}

return view.extend({
	load: function() {
		return Promise.all([
			uci.load('owrtpc'), uci.load('firewall'), callStatus(),
			callDHCPLeases().catch(function() { return {}; }),
			callHostHints().catch(function() { return {}; }),
			uci.load('gl-client').catch(function() { return null; })
		]);
	},

	render: function(data) {
		window.setTimeout(showQueuedNotification, 0);
		var status = {};
		(data[2].profiles || []).forEach(function(profile) { status[profile.section] = profile; });
		var leases = (data[3].dhcp_leases || []).concat(data[3].dhcp6_leases || []);
		var aliases = {};
		uci.sections('gl-client', 'client').forEach(function(client) {
			var mac = canonicalMac(client.mac);
			if (devices.isMacAddress(mac) && client.alias)
				aliases[mac] = client.alias;
		});
		var deviceList = devices.mergeDeviceSources(data[4], leases, configuredDevices(), aliases);
		var deviceMap = {};
		deviceList.forEach(function(device) { deviceMap[device.mac] = device; });
		var assignments = {};
		uci.sections('owrtpc', 'profile').forEach(function(profile) {
			var values = Array.isArray(profile.device) ? profile.device : [ profile.device ];
			values.filter(Boolean).forEach(function(mac) {
				assignments[canonicalMac(mac)] = profile['.name'];
			});
		});
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
		o = g.option(form.Value, 'activity_threshold_bytes', _('Activity threshold per sample (bytes)'));
		o.datatype = 'range(1,4294967295)';
		o.default = '131072';
		o.rmempty = false;
		o.description = _('Traffic below this threshold is treated as standby activity. The default is 128 KiB per sample.');
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
		o = s.option(form.Value, 'name', _('Name'));
		o.rmempty = false;
		o.placeholder = _('Children');
		o = s.option(form.Flag, 'enabled', _('Enabled'));
		o.default = o.enabled;
		o.rmempty = false;

		o = s.option(form.DynamicList, 'device', _('Devices'));
		o.rmempty = true;
		o.description = _('A device may belong to one profile only. Disable MAC randomization for this network on the client.');
		deviceList.forEach(function(device) {
			o.value(device.mac, deviceLabel(device));
		});
		bindDeviceAutocomplete(o, deviceMap, assignments);
		o.textvalue = function(sectionId) {
			var values = uci.get('owrtpc', sectionId, 'device') || [];
			if (!Array.isArray(values))
				values = [ values ];
			var rows = values.filter(Boolean).map(function(value) {
				var mac = canonicalMac(value);
				var device = deviceMap[mac];
				var name = device && (device.name || device.hostnames[0]);
				return E('div', {}, name ? name + ' — ' + mac : mac);
			});
			return rows.length ? E('div', {}, rows) : E('em', {}, _('none'));
		};

		o = s.option(form.ListValue, 'activity_threshold_bytes', _('Activity detection'));
		o.value('', _('Use engine default'));
		o.value('32768', _('Sensitive (32 KiB/sample)'));
		o.value('131072', _('Standard (128 KiB/sample)'));
		o.value('262144', _('Low sensitivity (256 KiB/sample)'));
		o.rmempty = true;
		o.modalonly = true;
		o.description = _('Advanced fallback for unusually noisy or quiet profiles. Automatic session detection normally handles standby traffic and buffering gaps.');

		o = s.option(form.DummyValue, '_schedule', _('Today'));
		o.cfgvalue = function(sectionId) {
			return status[sectionId] && status[sectionId].schedule === 'weekend' ? _('Weekend') : _('Weekday');
		};
		o = s.option(form.DummyValue, '_allowance', _('Today\'s allowance'));
		o.cfgvalue = function(sectionId) {
			var schedule = status[sectionId] ? status[sectionId].schedule : 'weekday';
			var minutes = Number(scheduleValue(sectionId, schedule, 'daily_minutes', 'daily_minutes', '0')) || 0;
			var profileStatus = status[sectionId] || {};
			if (profileStatus.all_day === true)
				return _('Unlimited today');
			var label = minutes ? _('%d min').format(minutes) : _('Unlimited');
			var bonus = Number(profileStatus.bonus_seconds) || 0;
			return bonus ? _('%s (+%s extra)').format(label, formatDuration(bonus)) : label;
		};
		o = s.option(form.DummyValue, '_bedtime', _('Today\'s bedtime'));
		o.cfgvalue = function(sectionId) {
			var schedule = status[sectionId] ? status[sectionId].schedule : 'weekday';
			var start = scheduleValue(sectionId, schedule, 'bedtime_start', 'bedtime_start', '');
			var end = scheduleValue(sectionId, schedule, 'bedtime_end', 'bedtime_end', '');
			return start && end ? '%s–%s'.format(start, end) : _('Disabled');
		};

		o = s.option(form.Value, 'weekday_daily_minutes', _('Weekday allowance (minutes)'));
		o.datatype = 'uinteger';
		o.default = '0';
		o.rmempty = false;
		o.modalonly = true;
		o.description = _('Monday through Friday. Cumulative across the profile devices; use 0 for unlimited.');
		o.cfgvalue = function(sectionId) { return scheduleValue(sectionId, 'weekday', 'daily_minutes', 'daily_minutes', '0'); };
		o = s.option(form.Value, 'weekend_daily_minutes', _('Weekend allowance (minutes)'));
		o.datatype = 'uinteger';
		o.default = '0';
		o.rmempty = false;
		o.modalonly = true;
		o.description = _('Saturday and Sunday. Cumulative across the profile devices; use 0 for unlimited.');
		o.cfgvalue = function(sectionId) { return scheduleValue(sectionId, 'weekend', 'daily_minutes', 'daily_minutes', '0'); };

		o = s.option(form.Value, 'weekday_bedtime_start', _('Weekday bedtime starts'));
		o.placeholder = '21:30';
		o.modalonly = true;
		o.description = _('Router local time. Leave both weekday bedtime fields empty to disable.');
		o.cfgvalue = function(sectionId) { return scheduleValue(sectionId, 'weekday', 'bedtime_start', 'bedtime_start', ''); };
		o.validate = function(sectionId, value) { return validateTime(value, '21:30'); };
		o = s.option(form.Value, 'weekday_bedtime_end', _('Weekday bedtime ends'));
		o.placeholder = '07:00';
		o.modalonly = true;
		o.cfgvalue = function(sectionId) { return scheduleValue(sectionId, 'weekday', 'bedtime_end', 'bedtime_end', ''); };
		o.validate = function(sectionId, value) { return validateTime(value, '07:00'); };
		o = s.option(form.Value, 'weekend_bedtime_start', _('Weekend bedtime starts'));
		o.placeholder = '23:00';
		o.modalonly = true;
		o.description = _('Router local time. Leave both weekend bedtime fields empty to disable.');
		o.cfgvalue = function(sectionId) { return scheduleValue(sectionId, 'weekend', 'bedtime_start', 'bedtime_start', ''); };
		o.validate = function(sectionId, value) { return validateTime(value, '23:00'); };
		o = s.option(form.Value, 'weekend_bedtime_end', _('Weekend bedtime ends'));
		o.placeholder = '09:00';
		o.modalonly = true;
		o.cfgvalue = function(sectionId) { return scheduleValue(sectionId, 'weekend', 'bedtime_end', 'bedtime_end', ''); };
		o.validate = function(sectionId, value) { return validateTime(value, '09:00'); };

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

		var gridSection = s;
		s.renderRowActions = function(sectionId) {
			var actions = form.GridSection.prototype.renderRowActions.call(gridSection, sectionId, _('Edit'));
			var profile = status[sectionId] || {};
			var profileName = profile.name || uci.get('owrtpc', sectionId, 'name') || sectionId;
			var isBlocked = profile.manual_blocked === true;
			var timeActionsDisabled = [ 'disabled', 'manual', 'bedtime' ].indexOf(profile.reason) !== -1;
			var disabledTitle = profile.reason === 'bedtime' ? _('Extra time is unavailable during bedtime') :
				profile.reason === 'manual' ? _('Unblock the profile before adding extra time') :
				_('Enable the profile before adding extra time');
			var buttons = [
				[ 60, '+1h' ],
				[ 240, '+4h' ],
				[ 'all-day', 'All Day' ]
			].map(function(increment) {
				var isAllDay = increment[0] === 'all-day';
				var title = timeActionsDisabled ? disabledTitle : isAllDay ?
					_('Allow unlimited time until bedtime or the end of today') :
					_('Set today\'s extra time to %s').format(increment[1].substring(1));
				return E('button', {
					'class': 'cbi-button cbi-button-action',
					'disabled': timeActionsDisabled ? '' : null,
					'title': title,
					'click': function(event) {
						event.preventDefault();
						var successMessage = isAllDay ?
							_('Profile "%s" has unlimited time until bedtime or the end of today.').format(profileName) :
							_('Extra time for profile "%s" set to %s.').format(profileName, increment[1].substring(1));
						return runQuickAction(event.currentTarget, callAddTime(sectionId, increment[0]), successMessage);
					}
				}, increment[1]);
			});
			buttons.push(E('button', {
				'class': 'cbi-button cbi-button-%s'.format(isBlocked ? 'positive' : 'negative'),
				'title': isBlocked ? _('Remove the manual block') : _('Block this profile immediately'),
				'click': function(event) {
					event.preventDefault();
					return runQuickAction(event.currentTarget, callSetBlock(sectionId, !isBlocked),
						isBlocked ? _('Profile "%s" unblocked.').format(profileName) : _('Profile "%s" blocked.').format(profileName));
				}
			}, isBlocked ? _('Unblock') : _('Block')));
			var container = actions.querySelector('div');
			if (container) {
				var dragHandle = container.querySelector('.drag-handle');
				var reference = dragHandle ? dragHandle.nextSibling : container.firstChild;
				buttons.forEach(function(button) { container.insertBefore(button, reference); });
			}
			return actions;
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
