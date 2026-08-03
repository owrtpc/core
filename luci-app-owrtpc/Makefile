# SPDX-License-Identifier: Apache-2.0

include $(TOPDIR)/rules.mk

LUCI_TITLE:=OWRTPC parental control
LUCI_DESCRIPTION:=Profile-based parental control with shared daily allowances
LUCI_DEPENDS:=+luci-base +rpcd +firewall4 +nftables-json +libubox +jsonfilter
LUCI_PKGARCH:=all
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Fabrizio Pellegrini <desmofab@gmail.com>

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
