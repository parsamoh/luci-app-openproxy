# ============================================================
# 核心模組骨架 — Makefile
# ============================================================
# 使用說明：
#   1. 將 {{MOD_NAME}} 替換為模組名稱（如 my-netfilter）
#   2. 將 {{MOD_TITLE}} 替換為顯示標題
#   3. 將 {{MOD_DESCRIPTION}} 替換為模組說明
#   4. 將 {{MOD_FILES}} 替換為核心模組 .ko 路徑
#   5. src/ 目錄放入 C 原始碼和 Kbuild 檔案
#   6. 適用版本：OpenWrt 23.05+（核心 5.15+）
# ============================================================

include $(TOPDIR)/rules.mk
include $(INCLUDE_DIR)/kernel.mk

PKG_NAME:=kmod-{{MOD_NAME}}
PKG_VERSION:=1.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0

include $(INCLUDE_DIR)/package.mk

define KernelPackage/{{MOD_NAME}}
  SUBMENU:=Other modules
  TITLE:={{MOD_TITLE}}
  FILES:=$(PKG_BUILD_DIR)/{{MOD_NAME}}.ko
  AUTOLOAD:=$(call AutoLoad,90,{{MOD_NAME}})
  DEPENDS:={{KMOD_DEPENDS}}
endef

define KernelPackage/{{MOD_NAME}}/description
  {{MOD_DESCRIPTION}}
endef

define Build/Compile
	$(KERNEL_MAKE) M=$(PKG_BUILD_DIR) modules
endef

$(eval $(call KernelPackage,{{MOD_NAME}}))
