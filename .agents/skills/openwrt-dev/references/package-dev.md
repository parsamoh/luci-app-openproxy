# 套件開發（Package Development）

## 概述

OpenWrt 套件開發的核心是撰寫一個特定格式的 Makefile，告訴建構系統如何下載、編譯、安裝你的軟體。每個套件最終會被打包為 ipk（傳統 opkg）或 apk（新版 APK 套件管理器）格式，可透過套件管理器安裝到路由器上。

## 前置條件

- 已搭建 OpenWrt Buildroot 或 SDK 環境（參見 build-system.md）
- 熟悉 GNU Make 基本語法
- 了解你要打包的上游軟體的編譯方式（autotools / cmake / plain make）

## 核心概念

### 套件 Makefile 結構

一個標準的 OpenWrt 套件 Makefile 包含以下區塊：

| 區塊 | 說明 |
|------|------|
| `include $(TOPDIR)/rules.mk` | 引入全域規則（必須在最前面） |
| `PKG_*` 變數 | 定義套件元資料（名稱、版本、來源等） |
| `include $(INCLUDE_DIR)/package.mk` | 引入套件建構框架 |
| `Package/xxx` | 定義套件描述、分類、相依性 |
| `Package/xxx/install` | 定義安裝步驟 |
| `Build/*` | 覆寫預設的編譯步驟（可選） |
| `$(eval $(call BuildPackage,xxx))` | 觸發建構流程（必須在最後面） |

### 套件來源方式

| 變數 | 用途 |
|------|------|
| `PKG_SOURCE` | 來源壓縮檔名 |
| `PKG_SOURCE_URL` | 下載 URL（支援 @GITHUB、@SF 等巨集） |
| `PKG_HASH` | SHA256 雜湊（驗證完整性） |
| `PKG_SOURCE_PROTO=git` | 從 Git 倉庫取得源碼 |
| `PKG_SOURCE_VERSION` | Git commit hash |

### Feeds 系統

Feeds 是外部套件來源的管理機制：

```bash
# 在 feeds.conf.default 中定義
src-git packages https://git.openwrt.org/feed/packages.git;openwrt-23.05

# 更新與安裝
./scripts/feeds update packages
./scripts/feeds install -a -p packages
```

## 操作流程

### 1. 建立套件目錄

```bash
# 在建構目錄中建立套件
mkdir -p package/my-app
```

### 2. 撰寫 Makefile

```makefile
# package/my-app/Makefile
# SPDX-License-Identifier: GPL-2.0-only

include $(TOPDIR)/rules.mk

PKG_NAME:=my-app
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

# 從 GitHub 下載源碼
PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/example/my-app.git
PKG_SOURCE_VERSION:=v$(PKG_VERSION)
PKG_MIRROR_HASH:=skip

PKG_LICENSE:=MIT
PKG_LICENSE_FILES:=LICENSE
PKG_MAINTAINER:=Your Name <your@email.com>

include $(INCLUDE_DIR)/package.mk

# 定義套件資訊
define Package/my-app
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=My Application
  DEPENDS:=+libubox +libubus
  URL:=https://github.com/example/my-app
endef

define Package/my-app/description
  這是一個範例應用程式，展示如何建立 OpenWrt 套件。
endef

# 覆寫編譯步驟（使用 plain make 的情況）
define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)"
endef

# 定義安裝步驟
define Package/my-app/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/my-app $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_CONF) ./files/my-app.config $(1)/etc/config/my-app
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/my-app.init $(1)/etc/init.d/my-app
endef

# UCI 設定檔保護（升級時不覆蓋）
define Package/my-app/conffiles
/etc/config/my-app
endef

# 安裝後腳本
define Package/my-app/postinst
#!/bin/sh
[ -n "$${IPKG_INSTROOT}" ] || /etc/init.d/my-app enable
endef

$(eval $(call BuildPackage,my-app))
```

### 3. 加入初始化腳本

```bash
mkdir -p package/my-app/files
```

```bash
#!/bin/sh /etc/rc.common
# package/my-app/files/my-app.init
# 使用 procd 管理服務

START=90
STOP=10
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/my-app
    procd_set_param respawn
    procd_set_param stdout 1
    procd_set_param stderr 1
    procd_close_instance
}
```

### 4. 加入 UCI 預設設定

```bash
# package/my-app/files/my-app.config
config settings 'main'
    option enabled '1'
    option port '8080'
    option log_level 'info'
```

### 5. 編譯與測試

```bash
# 啟用套件
make menuconfig  # 找到 Utilities → My Application → <*> 或 <M>

# 編譯
make package/my-app/compile V=s

# 產出位置
ls bin/packages/*/base/my-app_*.ipk
```

### 6. 安裝到裝置

```bash
# 複製到路由器
scp bin/packages/*/base/my-app_*.ipk root@192.168.1.1:/tmp/

# 在路由器上安裝
ssh root@192.168.1.1
opkg install /tmp/my-app_*.ipk
```

## 範例代碼

### CMake 專案的 Makefile

```makefile
include $(TOPDIR)/rules.mk

PKG_NAME:=my-cmake-app
PKG_VERSION:=2.0.0
PKG_RELEASE:=1

PKG_SOURCE:=$(PKG_NAME)-$(PKG_VERSION).tar.gz
PKG_SOURCE_URL:=https://example.com/releases/
PKG_HASH:=abc123...

PKG_LICENSE:=GPL-2.0-only
PKG_BUILD_FLAGS:=lto

include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

define Package/my-cmake-app
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=My CMake Application
  DEPENDS:=+libpthread +libopenssl
endef

# CMake 選項（透過 CMAKE_OPTIONS 傳遞）
CMAKE_OPTIONS += \
	-DBUILD_TESTS=OFF \
	-DENABLE_SSL=ON

define Package/my-cmake-app/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_INSTALL_DIR)/usr/bin/my-cmake-app $(1)/usr/bin/
endef

$(eval $(call BuildPackage,my-cmake-app))
```

### 含多個子套件的 Makefile

```makefile
include $(TOPDIR)/rules.mk

PKG_NAME:=my-suite
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
# ... 來源定義 ...

include $(INCLUDE_DIR)/package.mk

# 主程式
define Package/my-suite
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=My Suite - 主程式
endef

define Package/my-suite/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(PKG_BUILD_DIR)/main $(1)/usr/bin/my-suite
endef

# 函式庫
define Package/libmy-suite
  SECTION:=libs
  CATEGORY:=Libraries
  TITLE:=My Suite - 共享函式庫
endef

define Package/libmy-suite/install
	$(INSTALL_DIR) $(1)/usr/lib
	$(CP) $(PKG_BUILD_DIR)/libmy.so* $(1)/usr/lib/
endef

$(eval $(call BuildPackage,my-suite))
$(eval $(call BuildPackage,libmy-suite))
```

## 常見錯誤與解法

### 問題：`Package/xxx is missing the VERSION field`
**原因：** Makefile 中缺少 `PKG_VERSION` 定義
**解法：** 確認 `PKG_VERSION:=` 在 `include $(TOPDIR)/rules.mk` 之後

### 問題：`PKG_HASH does not match`
**原因：** 上游源碼有變更或 hash 計算錯誤
**解法：**
```bash
# 重新計算 hash
make package/my-app/download V=s
# 查看正確的 hash 值
sha256sum dl/my-app-1.0.0.tar.gz
```

### 問題：找不到標頭檔（如 `uci.h`）
**原因：** `DEPENDS` 未列出對應的開發套件
**解法：** 在 `Package/xxx` 的 `DEPENDS` 中加入 `+libuci`

### 問題：`INSTALL_DIR` 權限錯誤
**原因：** 安裝路徑前綴缺少 `$(1)`
**解法：** 確認所有安裝路徑以 `$(1)/` 開頭，而非絕對路徑

### 問題：套件在 menuconfig 中看不到
**原因：** feeds 未更新或 Makefile 語法錯誤
**解法：**
```bash
./scripts/feeds update -a
./scripts/feeds install -a
make menuconfig
# 按 `/` 搜尋你的套件名稱
```

## 參考來源

- https://openwrt.org/docs/guide-developer/packages
- https://openwrt.org/docs/guide-developer/helloworld/chapter3
- https://github.com/openwrt/packages/blob/master/CONTRIBUTING.md
- https://github.com/openwrt/openwrt/blob/main/include/package.mk
