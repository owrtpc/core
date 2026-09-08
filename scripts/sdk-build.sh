#!/bin/sh
# SPDX-License-Identifier: Apache-2.0
# Run inside an initialized OpenWrt SDK; caller provides package directories.
set -eu
case "${1:-}" in
	'') full_build=0 ;;
	--full) full_build=1 ;;
	*) echo 'Usage: sdk-build.sh [--full]' >&2; exit 1 ;;
esac

for package in base/rpcd base/firewall4 base/nftables base/libubox base/jsonfilter base/uci base/ubus luci/rpcd-mod-luci luci/luci-base; do
	[ -f "package/feeds/$package/Makefile" ] || {
		echo "Missing SDK package definition: $package; run scripts/setup-sdk.sh first" >&2
		exit 1
	}
done
touch .config
for option in ALL ALL_NONSHARED ALL_KMODS LUCI_JSMIN LUCI_CSSTIDY; do
	sed -i "/^CONFIG_$option=/d; /^# CONFIG_$option is not set/d" .config
	printf '# CONFIG_%s is not set\n' "$option" >> .config
done
if [ "$full_build" -eq 1 ]; then
	# SDK archives and reused volumes can retain selections for hundreds of
	# unrelated kernel modules. Let Kconfig select only our real dependencies.
	sed -i '/^CONFIG_PACKAGE_/d; /^# CONFIG_PACKAGE_/d' .config
	sed -i '/^# CONFIG_LUCI_JSMIN is not set/d' .config
	printf 'CONFIG_LUCI_JSMIN=y\n' >> .config
fi
for package in owrtpc luci-app-owrtpc; do
	grep -q "^CONFIG_PACKAGE_$package=m$" .config ||
		printf 'CONFIG_PACKAGE_%s=m\n' "$package" >> .config
done
make defconfig
make package/owrtpc/clean package/luci-app-owrtpc/clean
# These packages contain only shell/JS/data (no native objects or translations
# to compile). NO_DEPS avoids rebuilding firmware dependencies in a packaging
# SDK; it does not remove DEPENDS from metadata. The package lifecycle tests
# install the results with dependency checking enabled on real OpenWrt.
if [ "$full_build" -eq 1 ]; then
	make package/owrtpc/compile package/luci-app-owrtpc/compile V=s -j1
else
	make package/owrtpc/compile package/luci-app-owrtpc/compile NO_DEPS=1 V=s -j1
fi
