'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require ui';
'require owrtpc.devices as devices';

var callStatus = rpc.declare({ object: 'owrtpc', method: 'status', expect: { '': {} } });
var callCapabilities = rpc.declare({ object: 'owrtpc', method: 'capabilities', expect: { '': {} } });
var callSetEnabled = rpc.declare({ object: 'owrtpc', method: 'set_enabled', params: [ 'profile', 'enabled' ], expect: { '': {} } });
var callSetBlock = rpc.declare({ object: 'owrtpc', method: 'set_block', params: [ 'profile', 'blocked' ], expect: { '': {} } });
var callAddTime = rpc.declare({ object: 'owrtpc', method: 'add_time', params: [ 'profile', 'minutes' ], expect: { '': {} } });
var callRefresh = rpc.declare({ object: 'owrtpc', method: 'refresh', expect: { '': {} } });
var callFullReset = rpc.declare({ object: 'owrtpc', method: 'reset', params: [ 'confirmation' ], expect: { '': {} } });
var callResetAccess = rpc.declare({ object: 'session', method: 'access', params: [ 'scope', 'object', 'function' ], expect: { access: false } });
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

function periodValue(sectionId, period, compatibilitySchedule, option, legacyOption, fallback) {
	var value = uci.get('owrtpc', sectionId, period + '_' + option);
	return value == null || value === ''
		? scheduleValue(sectionId, compatibilitySchedule, option, legacyOption, fallback)
		: value;
}

function validateTime(value, example) {
	return !value || /^([01][0-9]|2[0-3]):[0-5][0-9]$/.test(value) ||
		_('Use HH:MM, for example %s.').format(example);
}

function queueNotification(message) {
	try {
		window.sessionStorage.setItem('owrtpc-notification', message);
	}
	catch (error) {
		ui.addNotification(null, E('p', {}, [ message ]), 'info');
	}
}

function reloadWithNotification(message) {
	queueNotification(message);
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
		ui.addNotification(null, E('p', {}, [ message ]), 'info');
}

function setQuickActionDisabled(control, disabled) {
	control.disabled = disabled;
	if (disabled) {
		control.setAttribute('disabled', '');
		control.setAttribute('aria-disabled', 'true');
	}
	else {
		control.removeAttribute('disabled');
		control.removeAttribute('aria-disabled');
	}
}

function runQuickAction(control, request, successMessage) {
	setQuickActionDisabled(control, true);
	return request.then(function(result) {
		if (!result.success)
			throw new Error(result.error || _('The quick action failed.'));
		reloadWithNotification(successMessage);
	}).catch(function(error) {
		setQuickActionDisabled(control, false);
		ui.addNotification(null, E('p', {}, [ error.message ]), 'error');
	});
}

return view.extend({
	handleFullReset: function() {
		if (!this.canReset)
			return;
		var busy = false;
		var confirmation = E('input', {
			'type': 'text', 'class': 'cbi-input-text', 'autocomplete': 'off',
			'aria-label': _('Type RESET OWRTPC to confirm'),
			'input': function() {
				reset.disabled = busy || confirmation.value !== 'RESET OWRTPC';
			}
		});
		var cancel = E('button', {
			'type': 'button', 'class': 'btn cbi-button', 'click': ui.hideModal
		}, _('Cancel'));
		var reset = E('button', {
			'type': 'button', 'class': 'btn cbi-button cbi-button-negative', 'disabled': true,
			'click': function() {
				if (busy || confirmation.value !== 'RESET OWRTPC')
					return;
				busy = true;
				reset.disabled = cancel.disabled = confirmation.disabled = true;
				return uci.changes().then(function(changes) {
					if (changes.owrtpc && changes.owrtpc.length)
						throw new Error(_('Apply or discard pending OWRTPC changes before resetting.'));
					ui.showModal(_('Resetting OWRTPC…'), [
						E('p', { 'class': 'spinning' }, _('Please wait while OWRTPC resets its data and restarts.'))
					]);
					return callFullReset(confirmation.value);
				}).then(function(result) {
					if (!result.success)
						throw new Error(result.error || _('OWRTPC reset failed.'));
					ui.hideModal();
					reloadWithNotification(_('OWRTPC has been reset. Create new profiles to enable parental-control rules.'));
				}).catch(function(error) {
					ui.hideModal();
					ui.addNotification(null, E('p', {}, [
						_('Reset could not be confirmed. Check the current OWRTPC status before trying again. Details: %s').format(error.message) ]), 'error');
				});
			}
		}, _('Reset all OWRTPC data'));
		ui.showModal(_('Reset all OWRTPC data?'), [
			E('p', {}, _('This permanently deletes all OWRTPC profiles, device assignments, usage counters and extra time, and restores the default OWRTPC settings. Unsaved edits on this page will be discarded.')),
			E('p', {}, _('OWRTPC will briefly stop and restart. No parental-control blocks will remain until you create new profiles. Router network, Wi-Fi, passwords, DHCP names and other services are not reset.')),
			E('p', {}, _('This cannot be undone. Export a backup first if you may need the current data.')),
			E('p', {}, _('Existing backups and system logs are not deleted.')),
			E('p', {}, _('Type RESET OWRTPC to confirm')),
			confirmation,
			E('div', { 'class': 'right' }, [ cancel, ' ', reset ])
		]);
		confirmation.focus();
	},

	load: function() {
		return Promise.all([
			uci.load('owrtpc'), uci.load('firewall'), callStatus(),
			callDHCPLeases().catch(function() { return {}; }),
			callHostHints().catch(function() { return {}; }),
			uci.load('gl-client').catch(function() { return null; }),
			callResetAccess('ubus', 'owrtpc', 'reset').catch(function() { return false; }),
			callCapabilities().catch(function() { return {}; })
		]);
	},

	render: function(data) {
		this.canReset = data[6] === true;
		var coreVersion = (data[7] || {}).backend_version || '—';
		window.setTimeout(showQueuedNotification, 0);
		document.addEventListener('uci-applied', function() {
			callRefresh().then(function(result) {
				if (!result.success)
					ui.addNotification(null, E('p', {}, [ result.error || _('Configuration was applied but policy refresh failed.') ]), 'warning');
			}).catch(function(error) {
				ui.addNotification(null, E('p', {}, [ error.message ]), 'warning');
			});
		}, { once: true });
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

		var s = m.section(form.GridSection, 'profile', _('Profiles'),
			_('Save closes the profile dialog and stages its changes. Use Save & Apply to make all pending changes permanent.'));
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
			o.value(device.mac, E('span', {}, [ deviceLabel(device) ]));
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
				return E('div', {}, [ name ? name + ' — ' + mac : mac ]);
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

		o = s.option(form.DummyValue, '_allowance_period', _('Today\'s allowance group'));
		o.cfgvalue = function(sectionId) {
			return status[sectionId] && status[sectionId].allowance_period === 'fri_sun'
				? _('Friday–Sunday') : _('Monday–Thursday');
		};
		o = s.option(form.DummyValue, '_allowance', _('Today\'s allowance'));
		o.cfgvalue = function(sectionId) {
			var profileStatus = status[sectionId] || {};
			var period = profileStatus.allowance_period || 'mon_thu';
			var compatibilitySchedule = period === 'fri_sun' ? 'weekend' : 'weekday';
			var minutes = Number(periodValue(sectionId, period, compatibilitySchedule, 'daily_minutes', 'daily_minutes', '0')) || 0;
			if (profileStatus.all_day === true)
				return _('Unlimited today');
			var label = minutes ? _('%d min').format(minutes) : _('Unlimited');
			var bonus = Number(profileStatus.bonus_seconds) || 0;
			return bonus ? _('%s (temporary extension active)').format(label) : label;
		};
		o = s.option(form.DummyValue, '_bedtime', _('Today\'s bedtime'));
		o.cfgvalue = function(sectionId) {
			var period = status[sectionId] ? status[sectionId].bedtime_period : 'sun_thu';
			var compatibilitySchedule = period === 'fri_sat' ? 'weekend' : 'weekday';
			var start = periodValue(sectionId, period, compatibilitySchedule, 'bedtime_start', 'bedtime_start', '');
			var end = periodValue(sectionId, period, compatibilitySchedule, 'bedtime_end', 'bedtime_end', '');
			var group = period === 'fri_sat' ? _('Friday–Saturday nights') : _('Sunday–Thursday nights');
			return start && end ? _('%s–%s (%s)').format(start, end, group) : _('Disabled (%s)').format(group);
		};

		o = s.option(form.Value, 'mon_thu_daily_minutes', _('Allowance Monday–Thursday (minutes)'));
		o.datatype = 'uinteger';
		o.default = '0';
		o.rmempty = false;
		o.modalonly = true;
		o.description = _('Monday through Thursday. Cumulative across the profile devices; use 0 for unlimited.');
		o.cfgvalue = function(sectionId) { return periodValue(sectionId, 'mon_thu', 'weekday', 'daily_minutes', 'daily_minutes', '0'); };
		o = s.option(form.Value, 'fri_sun_daily_minutes', _('Allowance Friday–Sunday (minutes)'));
		o.datatype = 'uinteger';
		o.default = '0';
		o.rmempty = false;
		o.modalonly = true;
		o.description = _('Friday through Sunday. Cumulative across the profile devices; use 0 for unlimited.');
		o.cfgvalue = function(sectionId) { return periodValue(sectionId, 'fri_sun', 'weekend', 'daily_minutes', 'daily_minutes', '0'); };

		o = s.option(form.Value, 'sun_thu_bedtime_start', _('Bedtime Sunday–Thursday starts'));
		o.placeholder = '21:30';
		o.modalonly = true;
		o.description = _('The day identifies the evening when bedtime starts. Router local time; leave both Sunday–Thursday fields empty to disable.');
		o.cfgvalue = function(sectionId) { return periodValue(sectionId, 'sun_thu', 'weekday', 'bedtime_start', 'bedtime_start', ''); };
		o.validate = function(sectionId, value) { return validateTime(value, '21:30'); };
		o = s.option(form.Value, 'sun_thu_bedtime_end', _('Bedtime Sunday–Thursday ends'));
		o.placeholder = '07:00';
		o.modalonly = true;
		o.cfgvalue = function(sectionId) { return periodValue(sectionId, 'sun_thu', 'weekday', 'bedtime_end', 'bedtime_end', ''); };
		o.validate = function(sectionId, value) { return validateTime(value, '07:00'); };
		o = s.option(form.Value, 'fri_sat_bedtime_start', _('Bedtime Friday–Saturday starts'));
		o.placeholder = '23:00';
		o.modalonly = true;
		o.description = _('The day identifies the evening when bedtime starts. Router local time; leave both Friday–Saturday fields empty to disable.');
		o.cfgvalue = function(sectionId) { return periodValue(sectionId, 'fri_sat', 'weekend', 'bedtime_start', 'bedtime_start', ''); };
		o.validate = function(sectionId, value) { return validateTime(value, '23:00'); };
		o = s.option(form.Value, 'fri_sat_bedtime_end', _('Bedtime Friday–Saturday ends'));
		o.placeholder = '09:00';
		o.modalonly = true;
		o.cfgvalue = function(sectionId) { return periodValue(sectionId, 'fri_sat', 'weekend', 'bedtime_end', 'bedtime_end', ''); };
		o.validate = function(sectionId, value) { return validateTime(value, '09:00'); };

		o = s.option(form.DummyValue, '_usage', _('Used today'));
		o.cfgvalue = function(sectionId) { return status[sectionId] ? formatDuration(status[sectionId].used_seconds) : '—'; };
		o = s.option(form.DummyValue, '_remaining', _('Remaining'));
		o.cfgvalue = function(sectionId) {
			if (!status[sectionId])
				return '—';
			if (status[sectionId].all_day === true)
				return _('Unlimited today');
			return status[sectionId].limit_seconds ? formatDuration(status[sectionId].remaining_seconds) : _('Unlimited');
		};
		o = s.option(form.DummyValue, '_state', _('State'));
		o.cfgvalue = function(sectionId) { return reasonLabel(status[sectionId] ? status[sectionId].reason : 'none'); };

		var gridSection = s;
		s.renderRowActions = function(sectionId) {
			var actions = form.GridSection.prototype.renderRowActions.call(gridSection, sectionId, _('Edit'));
			var profile = status[sectionId] || {};
			var profileName = profile.name || uci.get('owrtpc', sectionId, 'name') || sectionId;
			var isEnabled = uci.get('owrtpc', sectionId, 'enabled') !== '0';
			var isBlocked = profile.manual_blocked === true;
			var timeActionsDisabled = !isEnabled || isBlocked || profile.reason === 'bedtime';
			var disabledTitle = profile.reason === 'bedtime' ? _('Extra time is unavailable during bedtime') :
				isBlocked ? _('Unblock the profile before adding extra time') :
				_('Enable the profile before adding extra time');
			var timeChoices = {
				'60': '+1h',
				'240': '+4h',
				'all-day': _('All Day')
			};
			var executeTimeAction = function(control, value) {
				if (timeActionsDisabled || control.hasAttribute('disabled'))
					return Promise.resolve();
				var isAllDay = value === 'all-day';
				var label = timeChoices[value];
				var successMessage = isAllDay ?
					_('Profile "%s" has unlimited time until bedtime or the end of today.').format(profileName) :
					_('Extra time for profile "%s" set to %s.').format(profileName, label.substring(1));
				return runQuickAction(control, callAddTime(sectionId, value), successMessage);
			};
			var timeButton = new ui.ComboButton('60', timeChoices, {
				sort: [ '60', '240', 'all-day' ],
				classes: {
					'60': 'btn cbi-button cbi-button-action',
					'240': 'btn cbi-button cbi-button-action',
					'all-day': 'btn cbi-button cbi-button-action'
				},
				click: function(event, value) {
					event.preventDefault();
					return executeTimeAction(this, value);
				}
			}).render();
			timeButton.title = timeActionsDisabled ? disabledTitle : _('Add time to this profile');
			if (timeActionsDisabled) {
				setQuickActionDisabled(timeButton, true);
				timeButton.addEventListener('click', function(event) {
					event.preventDefault();
					event.stopImmediatePropagation();
				}, true);
			}
			else {
				timeButton.addEventListener('cbi-dropdown-change', function(event) {
					var choice = event.detail && event.detail.value;
					if (choice && choice.value != null)
						executeTimeAction(timeButton, String(choice.value));
				});
			}

			var enabledButton = E('button', {
				'class': 'cbi-button cbi-button-%s'.format(isEnabled ? 'negative' : 'positive'),
				'title': isEnabled ? _('Disable this profile') : _('Enable this profile'),
				'click': function(event) {
					event.preventDefault();
					return runQuickAction(event.currentTarget, callSetEnabled(sectionId, !isEnabled),
						isEnabled ? _('Profile "%s" disabled.').format(profileName) : _('Profile "%s" enabled.').format(profileName));
				}
			}, isEnabled ? _('Disable') : _('Enable'));

			var blockButton = E('button', {
				'class': 'cbi-button cbi-button-%s'.format(isBlocked ? 'positive' : 'negative'),
				'disabled': !isEnabled ? '' : null,
				'title': !isEnabled ? _('Enable the profile before changing its block state') :
					isBlocked ? _('Remove the manual block') : _('Block this profile immediately'),
				'click': function(event) {
					event.preventDefault();
					if (!isEnabled)
						return;
					return runQuickAction(event.currentTarget, callSetBlock(sectionId, !isBlocked),
						isBlocked ? _('Profile "%s" unblocked.').format(profileName) : _('Profile "%s" blocked.').format(profileName));
				}
			}, isBlocked ? _('Unblock') : _('Block'));

			var buttons = [ timeButton, enabledButton, blockButton ];
			var container = actions.querySelector('div');
			if (container) {
				var dragHandle = container.querySelector('.drag-handle');
				var reference = dragHandle ? dragHandle.nextSibling : container.firstChild;
				buttons.forEach(function(button) { container.insertBefore(button, reference); });
			}
			return actions;
		};

		return m.render().then(L.bind(function(node) {
			return E('div', {}, [ node, E('div', { 'class': 'cbi-section' }, [
				E('h3', {}, _('Reset OWRTPC')),
				E('p', {}, _('Delete all OWRTPC data and restore its default settings. This does not reset the router.')),
				E('button', {
					'type': 'button', 'class': 'btn cbi-button cbi-button-negative',
					'disabled': !this.canReset || null,
					'click': ui.createHandlerFn(this, 'handleFullReset')
				}, _('Reset all OWRTPC data'))
			]), E('div', { 'class': 'cbi-section-descr' }, [
				E('p', {}, [ _('OWRTPC core version %s').format(coreVersion) ]),
				E('p', {}, [ _('Free software. Local control.'), E('br'),
					_('Developed by Fabrizio Pellegrini and OWRTPC contributors.'), ' ',
					E('a', { 'href': 'https://github.com/desmofab', 'target': '_blank',
						'rel': 'noopener noreferrer' }, [ '@desmofab' ]), E('br'),
					_('Thanks to the OpenWrt and LuCI communities.') ]),
				E('p', {}, [
					E('a', { 'href': 'https://github.com/owrtpc/core', 'target': '_blank',
						'rel': 'noopener noreferrer' }, [ _('Source code') ]), ' · ',
					E('a', { 'href': 'https://github.com/owrtpc/core/blob/main/LICENSE',
						'target': '_blank', 'rel': 'noopener noreferrer' }, [ _('Apache-2.0 licence') ]),
					E('br'), _('Independent project, not affiliated with OpenWrt.'), E('br'),
					_('OpenWrt is a registered trademark of Software Freedom Conservancy (SFC).'), ' ',
					E('a', { 'href': 'https://openwrt.org', 'target': '_blank',
						'rel': 'noopener noreferrer' }, [ 'openwrt.org' ]) ]) ]) ]);
		}, this));
	}
});
