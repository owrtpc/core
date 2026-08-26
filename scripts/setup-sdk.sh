#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Run from the SDK root. feeds.conf.default pins feeds to the firmware release.
set -eu
./scripts/feeds update base luci
./scripts/feeds install -p base rpcd firewall4 nftables-json jshn jsonfilter uci ubus
./scripts/feeds install -p luci rpcd-mod-luci luci-base
