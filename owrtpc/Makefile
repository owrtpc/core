# SPDX-License-Identifier: Apache-2.0

include $(TOPDIR)/rules.mk

PKG_NAME:=owrtpc
PKG_VERSION:=0.3.0
PKG_RELEASE:=2
PKG_LICENSE:=Apache-2.0
PKG_MAINTAINER:=Fabrizio Pellegrini <desmofab@gmail.com>

include $(INCLUDE_DIR)/package.mk

define Package/owrtpc
  SECTION:=net
  CATEGORY:=Network
  TITLE:=OWRTPC parental control service and APIs
  URL:=https://github.com/owrtpc/core
  PKGARCH:=all
  DEPENDS:=+rpcd +rpcd-mod-luci +firewall4 +nftables-json +jshn +jsonfilter +uci +ubus
  # APK negative dependency: the old monolith owns this package's files.
  EXTRA_DEPENDS:=!luci-app-owrtpc (<0.1.0_alpha1-r22)
endef

define Package/owrtpc/description
 Profile-based parental control with shared daily allowances, UCI configuration,
 local CLI and authenticated rpcd APIs. No LuCI web interface is required.
endef

define Package/owrtpc/conffiles
/etc/config/owrtpc
/etc/owrtpc/state/
endef

define Build/Compile
endef

define Package/owrtpc/preinst
#!/bin/sh
# Also reject a single transaction containing both new APKs while the old
# monolith still owns backend files. Do not rely on APK's installation order.
if grep -qx '/usr/sbin/owrtpcctl' "$${IPKG_INSTROOT}/lib/apk/packages/luci-app-owrtpc.list" 2>/dev/null; then
	echo 'Migrate the monolith first: see owrtpc/core docs/INSTALL.md' >&2
	exit 1
fi
exit 0
endef

define Package/owrtpc/install
	$(INSTALL_DIR) $(1)/etc/config $(1)/etc/init.d $(1)/etc/uci-defaults
	$(INSTALL_CONF) ./files/etc/config/owrtpc $(1)/etc/config/owrtpc
	$(INSTALL_BIN) ./files/etc/init.d/owrtpc $(1)/etc/init.d/owrtpc
	$(INSTALL_BIN) ./files/etc/uci-defaults/90-owrtpc $(1)/etc/uci-defaults/90-owrtpc
	$(INSTALL_DIR) $(1)/usr/sbin $(1)/usr/libexec/rpcd
	$(INSTALL_BIN) ./files/usr/sbin/* $(1)/usr/sbin/
	$(INSTALL_BIN) ./files/usr/libexec/rpcd/owrtpc $(1)/usr/libexec/rpcd/owrtpc
	$(INSTALL_BIN) ./files/usr/libexec/owrtpc-reset $(1)/usr/libexec/owrtpc-reset
	$(INSTALL_DIR) $(1)/usr/share/owrtpc $(1)/usr/share/rpcd/acl.d
	$(INSTALL_BIN) ./files/usr/share/owrtpc/firewall.include $(1)/usr/share/owrtpc/
	$(INSTALL_DATA) ./files/usr/share/owrtpc/lock.sh $(1)/usr/share/owrtpc/
	$(INSTALL_DIR) $(1)/usr/share/owrtpc/defaults
	$(INSTALL_DATA) ./files/etc/config/owrtpc $(1)/usr/share/owrtpc/defaults/owrtpc
	$(INSTALL_DATA) ./files/usr/share/rpcd/acl.d/owrtpc.json $(1)/usr/share/rpcd/acl.d/
endef

define Package/owrtpc/postinst
#!/bin/sh
[ -n "$$IPKG_INSTROOT" ] || /etc/init.d/rpcd reload
endef

$(eval $(call BuildPackage,owrtpc))
