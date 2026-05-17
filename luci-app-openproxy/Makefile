include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-openproxy
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_MAINTAINER:=vxiaov <https://github.com/vxiaov/OpenProxy>
PKG_LICENSE:=GPL-3.0

PKG_BUILD_DIR:=$(BUILD_DIR)/$(PKG_NAME)

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
	CATEGORY:=LuCI
	SUBMENU:=3. Applications
	TITLE:=Luci support for OpenProxy(driven by Clash)
	PKGARCH:=all
	DEPENDS:=+yq +kmod-nft-nat +kmod-nft-socket +kmod-nft-tproxy +luci-compat +luci +luci-base
	MAINTAINER:=vxiaov
endef

define Package/$(PKG_NAME)/description
    A LuCI support for OpenProxy
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/openproxy
/etc/openproxy/
endef

define Build/Prepare
	$(CP) $(CURDIR)/../root $(PKG_BUILD_DIR)
	$(CP) $(CURDIR)/../luasrc $(PKG_BUILD_DIR)
	$(CP) $(CURDIR)/../po $(PKG_BUILD_DIR)
	chmod 0755 $(PKG_BUILD_DIR)/root/etc/init.d/openproxy
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/i18n
	$(INSTALL_DATA) $(PKG_BUILD_DIR)/po/*.lmo $(1)/usr/lib/lua/luci/i18n/
	$(CP) $(PKG_BUILD_DIR)/root/* $(1)/
	$(CP) $(PKG_BUILD_DIR)/luasrc/* $(1)/usr/lib/lua/luci/
endef

define Package/$(PKG_NAME)/preinst
#!/bin/sh
# Back up UCI config
if [ -f "/etc/config/openproxy" ]; then
	cp -f /etc/config/openproxy /etc/config/openproxy.bak >/dev/null 2>&1
fi
# Back up user data inside /etc/openproxy that would be overwritten
if [ -d "/etc/openproxy" ]; then
	cp -rf /etc/openproxy /etc/openproxy.bak >/dev/null 2>&1
fi
exit 0
endef

define Package/$(PKG_NAME)/postinst
#!/bin/sh
# Restore user data that was in place before the update
if [ -d "/etc/openproxy.bak" ]; then
	# Restore user-created files but don't overwrite package-provided files
	# (config.yaml, custom_proxy, custom_rule are user data)
	for d in config custom_proxy custom_rule; do
		if [ -d "/etc/openproxy.bak/$d" ]; then
			cp -rf /etc/openproxy.bak/$d /etc/openproxy/ >/dev/null 2>&1
		fi
	done
	# Restore config.yaml if it existed
	if [ -f "/etc/openproxy.bak/config.yaml" ]; then
		cp -f /etc/openproxy.bak/config.yaml /etc/openproxy/config.yaml >/dev/null 2>&1
	fi
	rm -rf /etc/openproxy.bak >/dev/null 2>&1
fi
/etc/init.d/openproxy enable >/dev/null 2>&1
enable=$(uci -q get openproxy.config.enable 2>/dev/null)
if [ "$enable" == "1" ]; then
	/etc/init.d/openproxy restart 2>/dev/null
fi
exit 0
endef

define Package/$(PKG_NAME)/prerm
#!/bin/sh
uci set openproxy.config.enable=0
uci commit openproxy
/etc/init.d/openproxy stop
/etc/init.d/openproxy disable
exit 0
endef

define Package/$(PKG_NAME)/postrm
#!/bin/sh
# Only wipe /etc/openproxy on full uninstall (not on upgrade/reinstall).
# opkg passes "upgrade" as $1 during reinstalls; apk sets UPGRADE=1.
if [ "$1" != "upgrade" ] && [ "${UPGRADE}" != "1" ]; then
	rm -rf /etc/openproxy >/dev/null 2>&1
fi
rm -rf /tmp/openproxy.log >/dev/null 2>&1
rm -rf /usr/lib/lua/luci/view/openproxy
rm -rf /usr/lib/lua/luci/controller/openproxy.lua
rm -f  /usr/lib/lua/luci/i18n/openproxy.*.lmo
exit 0
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
