# 交叉編譯與目標平台（Cross-Compilation）

## 概述

交叉編譯是指在一個平台（Host，如 x86_64 Linux PC）上產出另一個平台（Target，如 MIPS/ARM 路由器）可執行的二進位檔。OpenWrt 建構系統自動處理大部分交叉編譯細節，但在移植複雜軟體或除錯編譯問題時，理解底層的工具鏈與目標平台架構至關重要。

## 前置條件

- 已搭建 OpenWrt Buildroot 或 SDK 環境
- 了解基本的編譯器概念（compiler、linker、sysroot）
- 了解目標裝置的 CPU 架構

## 核心概念

### 工具鏈（Toolchain）組成

| 元件 | 說明 |
|------|------|
| **gcc/g++** | 交叉編譯器（如 mipsel-openwrt-linux-musl-gcc） |
| **binutils** | 連結器(ld)、彙編器(as)、工具(ar, nm, objdump) |
| **musl libc** | OpenWrt 預設 C 函式庫（體積小、安全） |
| **gdb** | 遠端除錯器 |
| **kernel headers** | 目標平台核心標頭檔 |

### 目標平台架構

| 架構 | 常見裝置 | 註記 |
|------|---------|------|
| `mipsel_24kc` | MediaTek MT7621 路由器 | MIPS 小端序 |
| `mips_24kc` | Atheros/Qualcomm 路由器 | MIPS 大端序 |
| `aarch64_cortex-a53` | Raspberry Pi 3/4、MT7986 | ARM 64 位 |
| `arm_cortex-a7_neon-vfpv4` | Allwinner, Broadcom | ARM 32 位 |
| `x86_64` | 軟路由、虛擬機 | 標準 PC |
| `aarch64_generic` | Apple Silicon、通用 ARM64 | 通用 |

### 建構目錄結構

```
staging_dir/
├── host/             # Host 工具（在編譯機上執行的工具）
├── toolchain-*/      # 交叉編譯工具鏈
│   ├── bin/          # 编译器（mipsel-openwrt-linux-musl-gcc 等）
│   ├── lib/          # 工具鏈函式庫
│   └── include/      # 標頭檔
├── target-*/         # 目標平台 sysroot
│   ├── usr/lib/      # 目標平台的 .so/.a
│   ├── usr/include/  # 目標平台的標頭檔
│   └── root-*/       # 映像檔根目錄結構
└── hostpkg/          # 在 host 上安裝的公共工具
```

### musl vs glibc

| 面向 | musl（OpenWrt 預設） | glibc |
|------|---------------------|-------|
| 二進位大小 | 很小 | 較大 |
| 記憶體使用 | 低 | 較高 |
| 功能完整度 | 涵蓋 POSIX | 更完整 |
| locale 支援 | 有限 | 完整 |
| 相容性 | 大部分軟體可用 | 最廣泛 |
| 安全性 | 設計注重安全 | 歷史觀較深 |

## 操作流程

### 手動使用交叉編譯器

```bash
# 設定環境變數
export STAGING_DIR=$(pwd)/staging_dir
export TOOLCHAIN=$(pwd)/staging_dir/toolchain-mipsel_24kc_gcc-12.3.0_musl
export TARGET=$(pwd)/staging_dir/target-mipsel_24kc_musl
export PATH=$TOOLCHAIN/bin:$PATH

# 交叉編譯一個簡單程式
mipsel-openwrt-linux-musl-gcc \
    -o hello hello.c \
    --sysroot=$TARGET \
    -I$TARGET/usr/include \
    -L$TARGET/usr/lib
```

### 在 OpenWrt Makefile 中使用預定義變數

```makefile
# 建構系統自動設定這些變數，無需手動定義
define Build/Compile
	$(MAKE) -C $(PKG_BUILD_DIR) \
		CC="$(TARGET_CC)" \
		CXX="$(TARGET_CXX)" \
		CFLAGS="$(TARGET_CFLAGS)" \
		CXXFLAGS="$(TARGET_CXXFLAGS)" \
		CPPFLAGS="$(TARGET_CPPFLAGS)" \
		LDFLAGS="$(TARGET_LDFLAGS)" \
		AR="$(TARGET_AR)" \
		RANLIB="$(TARGET_RANLIB)"
endef
```

### 常用建構框架變數

| 變數 | 說明 |
|------|------|
| `$(TARGET_CC)` | 目標平台 C 編譯器 |
| `$(TARGET_CXX)` | 目標平台 C++ 編譯器 |
| `$(TARGET_CFLAGS)` | C 編譯旗標（含最佳化與安全選項） |
| `$(TARGET_LDFLAGS)` | 連結旗標 |
| `$(TARGET_AR)` | 靜態庫打包工具 |
| `$(CONFIGURE_ARGS)` | autotools 的 --host=xxx --build=xxx 等 |
| `$(CMAKE_OPTIONS)` | CMake 交叉編譯設定 |
| `$(HOSTCC)` | Host 平台編譯器（編譯建構時工具用） |

### 使用 autotools 的套件

```makefile
# autotools 專案大多只需正確引入 package.mk
# 建構系統會自動設定 --host, --build, --prefix 等
include $(INCLUDE_DIR)/package.mk

# 如需額外 configure 選項
CONFIGURE_ARGS += \
	--disable-static \
	--enable-shared \
	--with-ssl=$(STAGING_DIR)/usr
```

### 使用 CMake 的套件

```makefile
include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/cmake.mk

# CMake 工具鏈檔自動由建構系統產生
CMAKE_OPTIONS += \
	-DBUILD_TESTING=OFF \
	-DCMAKE_FIND_ROOT_PATH="$(STAGING_DIR)/usr"
```

### 使用 Meson 的套件

```makefile
include $(INCLUDE_DIR)/package.mk
include $(INCLUDE_DIR)/meson.mk

MESON_ARGS += \
	-Dtests=disabled \
	-Dexamples=disabled
```

## 範例代碼

### 靜態連結小型工具

```makefile
# 靜態連結：適合體積小且不依賴共享庫的工具
define Build/Compile
	$(TARGET_CC) $(TARGET_CFLAGS) -static \
		-o $(PKG_BUILD_DIR)/mytool \
		$(PKG_BUILD_DIR)/mytool.c
endef
```

### 跨架構條件編譯

```makefile
# 根據目標架構調整編譯選項
ifeq ($(CONFIG_TARGET_x86),y)
  TARGET_CFLAGS += -msse4.2
endif

ifeq ($(CONFIG_SOFT_FLOAT),y)
  TARGET_CFLAGS += -DUSE_SOFT_FLOAT
endif
```

### 檢查目標二進位檔

```bash
# 確認編譯出的是正確架構
file staging_dir/target-mipsel_24kc_musl/root-ramips/usr/bin/my-app
# 預期輸出: ELF 32-bit LSB executable, MIPS, MIPS-I version 1 (SYSV)

# 查看動態連結依賴
mipsel-openwrt-linux-musl-readelf -d bin/my-app | grep NEEDED
# 預期看到: [NEEDED] Shared library: [libc.so]
```

## 常見錯誤與解法

### 問題：`cannot find -lxxx`
**原因：** 目標平台缺少對應的函式庫
**解法：** 在套件的 `DEPENDS` 中加入該函式庫（如 `+libopenssl`），建構系統會自動將其放入 staging_dir

### 問題：`exec format error` 在路由器上執行時
**原因：** 二進位檔是 host 架構而非 target 架構
**解法：** 確認使用 `$(TARGET_CC)` 而非 `$(HOSTCC)` 編譯；用 `file` 指令檢查

### 問題：undefined reference to `__stack_chk_fail`
**原因：** SSP（Stack Smashing Protection）相關，目標 libc 版本不匹配
**解法：** 確認清理後重新建構：`make package/xxx/clean` 再 `make package/xxx/compile`

### 問題：CMake 找到 host 平台的函式庫
**原因：** CMake 搜尋路徑洩漏到 host 系統
**解法：** 使用 `CMAKE_FIND_ROOT_PATH` 限制搜尋範圍在 sysroot 內

### 問題：`STAGING_DIR` 環境變數警告
**原因：** 建構系統需要 STAGING_DIR 來定位工具鏈
**解法：**
```bash
export STAGING_DIR=$(pwd)/staging_dir
```

## 參考來源

- https://openwrt.org/docs/guide-developer/toolchain/crosscompile
- https://openwrt.org/docs/techref/buildroot
- https://musl.libc.org/
- https://github.com/openwrt/openwrt/tree/main/toolchain
- https://cmake.org/cmake/help/latest/manual/cmake-toolchains.7.html
