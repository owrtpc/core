# SPDX-License-Identifier: Apache-2.0

include $(TOPDIR)/rules.mk

PKG_VERSION:=0.1.0_alpha1
PKG_RELEASE:=14
PKG_LICENSE:=Apache-2.0

LUCI_TITLE:=OWRTPC parental control
LUCI_DESCRIPTION:=Profile-based parental control with shared daily allowances
# Runtime-only dependencies: OWRTPC ships interpreted JS and shell code and
# does not need these packages staged in the SDK while it is being built.
LUCI_EXTRA_DEPENDS:=luci-base (>=0), rpcd (>=0), firewall4 (>=0), nftables-json (>=0), jshn (>=0), jsonfilter (>=0)
LUCI_PKGARCH:=all
LUCI_URL:=https://github.com/desmofab/owrt-parental-control
LUCI_MAINTAINER:=Fabrizio Pellegrini <desmofab@gmail.com>

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
