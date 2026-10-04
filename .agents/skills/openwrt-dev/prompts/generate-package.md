# 幫我建立一個 OpenWrt 套件

## 使用時機

當你需要將一個自訂程式（C/C++、Go、Python 腳本等）打包為 OpenWrt `.ipk` 套件時使用此提示詞。涵蓋 autotools、CMake、Meson 及純 Makefile 專案。

## 提示詞模板

---

我要為 OpenWrt 23.05+ 建立一個套件，需求如下：

- **套件名稱**：[填入名稱]
- **版本號**：[填入版本]
- **原始碼位置**：[GitHub URL / 本地目錄 / tar.gz URL]
- **建構系統**：[autotools / CMake / Meson / 純 Makefile]
- **依賴項**：[列出 build 與 runtime 依賴，如 libubox、libuci、libcurl]
- **是否需要 procd init 腳本**：[是/否]
- **是否需要 UCI 設定檔**：[是/否]
- **安裝到哪個 feeds**：[packages / custom / 本地 package 目錄]

請幫我產生：
1. 完整的 `Makefile`（包含 PKG_* 變數、Build/ 步驟、Package/ 定義）
2. 如需 init 腳本，產生 `files/{{name}}.init`（procd 格式）
3. 如需 UCI 設定，產生 `files/{{name}}.conf`（含預設值和註解）
4. 說明如何將套件加入 feeds 或 package 目錄
5. 編譯指令（`make package/{{name}}/compile V=s`）

要求：
- 使用 `include $(TOPDIR)/rules.mk` 與 `include $(INCLUDE_DIR)/package.mk` 標準格式
- 所有路徑和變數用實際值
- 程式碼加繁體中文註解

---

## 期望輸出

- 一份可直接使用的 OpenWrt 套件 Makefile
- 相關的安裝與設定檔案
- 編譯和安裝的完整指令

## 範例對話

**User**: 我要把一個叫 `myapp` 的 Go 程式打包成 OpenWrt 套件，它本身沒有其他依賴，原始碼在 https://github.com/user/myapp，需要 procd 守護程式管理。

**Assistant**: 了解。以下是為你的 Go 程式 `myapp` 建立 OpenWrt 套件的完整檔案：

```makefile
include $(TOPDIR)/rules.mk

PKG_NAME:=myapp
PKG_VERSION:=1.0.0
PKG_RELEASE:=1

PKG_SOURCE_PROTO:=git
PKG_SOURCE_URL:=https://github.com/user/myapp.git
PKG_SOURCE_VERSION:=HEAD
PKG_MIRROR_HASH:=skip

PKG_BUILD_DEPENDS:=golang/host
PKG_BUILD_PARALLEL:=1

GO_PKG:=github.com/user/myapp

include $(INCLUDE_DIR)/package.mk
include ../../lang/golang/golang-package.mk

define Package/myapp
  SECTION:=utils
  CATEGORY:=Utilities
  TITLE:=My Application
  DEPENDS:=$(GO_ARCH_DEPENDS)
endef

define Package/myapp/install
	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) $(GO_PKG_BUILD_BIN_DIR)/myapp $(1)/usr/bin/
	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./files/myapp.init $(1)/etc/init.d/myapp
endef

$(eval $(call GoBinPackage,myapp))
$(eval $(call BuildPackage,myapp))
```

（接著提供 procd init 腳本和部署指令）
