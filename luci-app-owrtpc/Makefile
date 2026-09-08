# SPDX-License-Identifier: Apache-2.0

include $(TOPDIR)/rules.mk

PKG_VERSION:=0.4.0
PKG_RELEASE:=6
PKG_LICENSE:=Apache-2.0

LUCI_TITLE:=OWRTPC parental control
LUCI_DESCRIPTION:=LuCI interface for the OWRTPC parental control service
LUCI_DEPENDS:=+luci-base +owrtpc
LUCI_EXTRA_DEPENDS:=owrtpc (>=0.4.0-r6)
LUCI_PKGARCH:=all
LUCI_URL:=https://github.com/owrtpc/core
LUCI_MAINTAINER:=Fabrizio Pellegrini <desmofab@gmail.com>

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
