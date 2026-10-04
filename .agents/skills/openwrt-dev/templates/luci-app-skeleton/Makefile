# ============================================================
# LuCI App 骨架 — 套件 Makefile
# ============================================================
# 使用說明：
#   1. 將 {{APP_NAME}} 替換為應用名稱
#   2. 將 {{APP_TITLE}} 替換為顯示標題
#   3. 將 {{DEPENDS}} 替換為後端套件依賴（如 +myapp）
#   4. 適用版本：OpenWrt 21.02+
# ============================================================

include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for {{APP_TITLE}}
LUCI_DEPENDS:={{DEPENDS}}
LUCI_PKGARCH:=all

include ../../luci.mk

$(eval $(call BuildPackage,luci-app-{{APP_NAME}}))
