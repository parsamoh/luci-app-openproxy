# 建構系統（Build System）

## 概述

OpenWrt 建構系統是一套基於 GNU Make 的自動化框架，能從源碼交叉編譯完整的 Linux 韌體映像檔。它整合了工具鏈（Toolchain）生成、核心編譯、套件打包與映像檔組裝等流程。理解建構系統是所有 OpenWrt 開發的基礎。

## 前置條件

- **作業系統：** GNU/Linux（推薦 Ubuntu 22.04+）、macOS（需區分大小寫檔案系統）
- **磁碟空間：** 至少 15 GB（完整建構需 50 GB+）
- **記憶體：** 建議 8 GB+ RAM
- **必要套件（Ubuntu/Debian）：**

```bash
# OpenWrt 23.05+ 建構依賴（適用 Ubuntu 22.04+）
sudo apt update
sudo apt install -y build-essential clang flex bison g++ gawk \
  gcc-multilib g++-multilib gettext git libncurses5-dev libssl-dev \
  python3-setuptools rsync swig unzip zlib1g-dev file wget
```

## 核心概念

| 元件 | 說明 |
|------|------|
| **Buildroot** | 完整的建構環境，從源碼編譯所有元件 |
| **SDK** | 預編譯的工具鏈，僅用於編譯個別套件（不重建核心） |
| **ImageBuilder** | 從預編譯的套件組裝韌體映像檔（不編譯任何源碼） |
| **Toolchain** | 交叉編譯器（gcc/musl-libc），由 Buildroot 自動生成 |
| **Feeds** | 外部套件來源定義，透過 feeds.conf.default 管理 |
| **staging_dir** | 編譯中間產物目錄，含工具鏈和目標平台 sysroot |
| **build_dir** | 套件解壓與編譯的工作目錄 |
| **bin/** | 最終產出：韌體映像檔與 ipk/apk 套件 |

### 三種建構模式比較

| 模式 | 用途 | 需編譯核心 | 需編譯工具鏈 | 適合場景 |
|------|------|-----------|-------------|---------|
| Buildroot | 完整建構 | 是 | 是 | 客製化韌體、核心修改 |
| SDK | 套件開發 | 否 | 否 | 第三方套件開發與測試 |
| ImageBuilder | 映像組裝 | 否 | 否 | 快速產出含特定套件的韌體 |

## 操作流程

### 1. 取得源碼

```bash
# 複製 OpenWrt 主倉庫（23.05 穩定分支）
git clone -b openwrt-23.05 https://github.com/openwrt/openwrt.git
cd openwrt

# 或使用最新開發版
git clone https://github.com/openwrt/openwrt.git
cd openwrt
```

### 2. 更新與安裝 Feeds

```bash
# 更新所有 feed 定義
./scripts/feeds update -a

# 安裝所有套件的符號連結到 package/feeds/
./scripts/feeds install -a
```

### 3. 設定建構目標

```bash
# 開啟圖形化組態選單
make menuconfig
```

關鍵設定項：
- **Target System：** 選擇目標晶片架構（如 MediaTek Ralink MIPS, x86）
- **Subtarget：** 具體子平台
- **Target Profile：** 具體裝置型號
- **套件選取：** `<*>` 編入韌體, `<M>` 編為獨立套件, `< >` 不編譯

### 4. 開始建構

```bash
# 首次建構（單執行緒，方便除錯）
make -j1 V=s

# 後續建構（多執行緒加速）
make -j$(nproc)

# 僅建構某個套件
make package/network/utils/iperf3/compile V=s

# 清理某個套件後重建
make package/network/utils/iperf3/{clean,compile} V=s
```

### 5. 產出位置

```bash
# 韌體映像檔
ls bin/targets/<target>/<subtarget>/

# 編譯好的套件（ipk 或 apk）
ls bin/packages/<arch>/
```

### 使用 SDK 開發套件

```bash
# 下載對應版本的 SDK
wget https://downloads.openwrt.org/releases/23.05.5/targets/x86/64/openwrt-sdk-23.05.5-x86-64_gcc-12.3.0_musl.Linux-x86_64.tar.xz

tar -xf openwrt-sdk-*.tar.xz
cd openwrt-sdk-*

# 更新 feeds 並安裝
./scripts/feeds update -a
./scripts/feeds install -a

# 放入你的套件目錄
cp -r ~/my-package package/

# 啟用套件
make menuconfig  # 找到並勾選你的套件

# 編譯
make package/my-package/compile V=s
```

### 使用 ImageBuilder 組裝韌體

```bash
# 下載 ImageBuilder
wget https://downloads.openwrt.org/releases/23.05.5/targets/x86/64/openwrt-imagebuilder-23.05.5-x86-64.Linux-x86_64.tar.xz

tar -xf openwrt-imagebuilder-*.tar.xz
cd openwrt-imagebuilder-*

# 列出可用的 profile
make info

# 建構含額外套件的韌體
make image PROFILE=generic PACKAGES="luci luci-app-opkg nano htop"

# 加入自訂檔案
make image PROFILE=generic PACKAGES="luci" FILES=files/
```

## 範例代碼

### feeds.conf.default 結構

```bash
# OpenWrt 23.05+ 預設 feeds 設定
src-git packages https://git.openwrt.org/feed/packages.git;openwrt-23.05
src-git luci https://git.openwrt.org/project/luci.git;openwrt-23.05
src-git routing https://git.openwrt.org/feed/routing.git;openwrt-23.05
src-git telephony https://git.openwrt.org/feed/telephony.git;openwrt-23.05

# 新增自訂 feed（範例）
src-git custom https://github.com/your-org/openwrt-feed.git;main
```

### .config 節錄（x86/64 目標）

```bash
CONFIG_TARGET_x86=y
CONFIG_TARGET_x86_64=y
CONFIG_TARGET_x86_64_DEVICE_generic=y
CONFIG_PACKAGE_luci=y
CONFIG_PACKAGE_luci-app-opkg=y
```

## 常見錯誤與解法

### 問題：首次建構失敗在下載階段
**原因：** 網路問題導致源碼下載失敗
**解法：**
```bash
# 使用 V=s 查看詳細日誌
make -j1 V=s download
# 或嘗試使用映射站
make -j1 V=s download MIRROR=https://mirror2.openwrt.org
```

### 問題：`staging_dir/host/bin` 不在 PATH
**原因：** 部分 host 工具未正確安裝
**解法：**
```bash
export PATH="$(pwd)/staging_dir/host/bin:$PATH"
```

### 問題：空間不足
**原因：** 完整建構可能需要 50 GB+
**解法：**
```bash
# 清理所有建構產物
make dirclean
# 僅清理套件產物（保留工具鏈）
make clean
```

### 問題：make menuconfig 顯示不完整
**原因：** feeds 未正確更新
**解法：**
```bash
./scripts/feeds update -a
./scripts/feeds install -a
make menuconfig
```

## 參考來源

- https://github.com/openwrt/openwrt/blob/main/README.md
- https://openwrt.org/docs/guide-developer/toolchain/use-buildsystem
- https://openwrt.org/docs/guide-developer/toolchain/install-buildsystem
- https://openwrt.org/docs/guide-user/additional-software/imagebuilder
- https://openwrt.org/docs/guide-developer/using_the_sdk
