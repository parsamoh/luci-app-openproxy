# 核心模組開發（Kernel Module Development）

## 概述

OpenWrt 核心模組（kmod）是在 Linux 核心空間執行的程式碼，用於提供裝置驅動、檔案系統支援、網路協議等功能。在 OpenWrt 中，核心模組被打包為 kmod-xxx 套件，透過建構系統與核心版本緊密綁定。如果你需要操作硬體或在核心層級處理封包，就需要開發核心模組。

## 前置條件

- 已搭建完整的 OpenWrt Buildroot 環境（SDK 不適用於核心模組開發）
- 基本的 Linux 核心模組知識（module_init/module_exit）
- 了解目標裝置的硬體架構

## 核心概念

### OpenWrt 核心模組 vs 原生 Linux 核心模組

| 面向 | OpenWrt 方式 | 原生 Linux 方式 |
|------|-------------|----------------|
| 建構方式 | 透過 OpenWrt 建構系統 | 使用 kernel source tree 直接編譯 |
| Makefile | OpenWrt package Makefile + 核心 Kconfig | 標準 Kbuild Makefile |
| 打包 | 自動打包為 kmod-xxx ipk | 手動部署 .ko 檔 |
| 版本綁定 | 與韌體核心版本嚴格對應 | 使用者自行管理 |

### 核心模組類型

| 類型 | 說明 | 範例 |
|------|------|------|
| 裝置驅動 | 控制硬體設備 | kmod-usb-serial, kmod-i2c-core |
| 網路模組 | 網路協議/過濾 | kmod-nft-core, kmod-wireguard |
| 檔案系統 | 檔案系統支援 | kmod-fs-ext4, kmod-fs-ntfs |
| 加密 | 硬體加速加密 | kmod-crypto-aes |
| 自訂 | 使用者自行開發 | kmod-my-driver |

## 操作流程

### 1. 建立模組來源目錄

```bash
# 在建構樹中建立套件目錄
mkdir -p package/kernel/my-kmod/src
```

### 2. 撰寫核心模組 C 原始碼

```c
/* package/kernel/my-kmod/src/my_module.c */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

/* 模組參數：可從 insmod/modprobe 傳入 */
static int debug_level = 0;
module_param(debug_level, int, 0644);
MODULE_PARM_DESC(debug_level, "除錯等級 (0=關閉, 1=基本, 2=詳細)");

static int __init my_module_init(void)
{
    pr_info("my_module: 模組已載入, debug_level=%d\n", debug_level);
    return 0;
}

static void __exit my_module_exit(void)
{
    pr_info("my_module: 模組已卸載\n");
}

module_init(my_module_init);
module_exit(my_module_exit);

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Your Name");
MODULE_DESCRIPTION("OpenWrt 範例核心模組");
MODULE_VERSION("1.0");
```

### 3. 撰寫 Kbuild Makefile

```makefile
# package/kernel/my-kmod/src/Makefile
# 標準 Kbuild 格式
obj-m += my_module.o

# 如果模組由多個原始檔組成：
# my_module-objs := main.o utils.o hw.o
```

### 4. 撰寫 OpenWrt 套件 Makefile

```makefile
# package/kernel/my-kmod/Makefile
include $(TOPDIR)/rules.mk

PKG_NAME:=my-kmod
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=GPL-2.0-only

include $(INCLUDE_DIR)/kernel.mk
include $(INCLUDE_DIR)/package.mk

define KernelPackage/my-kmod
  SUBMENU:=Other modules
  TITLE:=My Custom Kernel Module
  FILES:=$(PKG_BUILD_DIR)/my_module.ko
  AUTOLOAD:=$(call AutoLoad,90,my_module)
  DEPENDS:=@!LINUX_5_4
endef

define KernelPackage/my-kmod/description
  這是一個自訂核心模組範例，展示如何在 OpenWrt 中開發和打包 kmod。
endef

define Build/Compile
	$(KERNEL_MAKE) \
		M="$(PKG_BUILD_DIR)" \
		modules
endef

# 從 src/ 複製源碼到建構目錄
define Build/Prepare
	mkdir -p $(PKG_BUILD_DIR)
	$(CP) ./src/* $(PKG_BUILD_DIR)/
endef

$(eval $(call KernelPackage,my-kmod))
```

### 5. 編譯與部署

```bash
# 啟用模組
make menuconfig
# 導航到：Kernel modules → Other modules → kmod-my-kmod

# 編譯
make package/kernel/my-kmod/compile V=s

# 部署到裝置
scp bin/targets/*/kmod-my-kmod_*.ipk root@192.168.1.1:/tmp/
ssh root@192.168.1.1 opkg install /tmp/kmod-my-kmod_*.ipk

# 手動載入/卸載
insmod my_module debug_level=1
rmmod my_module

# 查看核心日誌
dmesg | tail
logread | grep my_module
```

## 範例代碼

### Netfilter Hook 模組（封包過濾）

```c
/* 攔截並記錄所有 TCP 封包的核心模組 */
#include <linux/module.h>
#include <linux/netfilter.h>
#include <linux/netfilter_ipv4.h>
#include <linux/ip.h>
#include <linux/tcp.h>

static struct nf_hook_ops nf_hook;

static unsigned int my_hook_func(void *priv,
    struct sk_buff *skb,
    const struct nf_hook_state *state)
{
    struct iphdr *iph;
    struct tcphdr *tcph;

    if (!skb)
        return NF_ACCEPT;

    iph = ip_hdr(skb);
    if (iph->protocol != IPPROTO_TCP)
        return NF_ACCEPT;

    tcph = tcp_hdr(skb);
    pr_debug("TCP: %pI4:%d -> %pI4:%d\n",
        &iph->saddr, ntohs(tcph->source),
        &iph->daddr, ntohs(tcph->dest));

    return NF_ACCEPT;
}

static int __init my_nf_init(void)
{
    nf_hook.hook = my_hook_func;
    nf_hook.hooknum = NF_INET_PRE_ROUTING;
    nf_hook.pf = PF_INET;
    nf_hook.priority = NF_IP_PRI_FIRST;

    nf_register_net_hook(&init_net, &nf_hook);
    pr_info("my_nf: Netfilter hook 已註冊\n");
    return 0;
}

static void __exit my_nf_exit(void)
{
    nf_unregister_net_hook(&init_net, &nf_hook);
    pr_info("my_nf: Netfilter hook 已移除\n");
}

module_init(my_nf_init);
module_exit(my_nf_exit);
MODULE_LICENSE("GPL");
```

### KernelPackage 關鍵參數

```makefile
define KernelPackage/my-kmod
  # 在 menuconfig 中的子選單位置
  SUBMENU:=Other modules

  # 顯示名稱
  TITLE:=My Custom Kernel Module

  # 編譯產出的 .ko 檔案路徑
  FILES:=$(PKG_BUILD_DIR)/my_module.ko

  # 自動載入設定（優先級, 模組名）
  # 數字越小越早載入，一般 50=設備驅動, 90=應用層模組
  AUTOLOAD:=$(call AutoLoad,90,my_module)

  # 佔用在 /lib/modules/<kernel>/ 的相對路徑
  MODPATH:=$(MODULES_SUBDIR)

  # 核心版本相依性
  DEPENDS:=@LINUX_6_6

  # 額外的套件相依性
  DEPENDS+=+kmod-nf-conntrack
endef
```

## 常見錯誤與解法

### 問題：`version magic` 不匹配
**原因：** 模組編譯時的核心組態與運行中的核心不一致
**解法：** 必須使用與目標韌體完全相同的建構環境編譯核心模組。不要混用不同版本的 SDK/Buildroot。

### 問題：`Unknown symbol` 載入失敗
**原因：** 模組引用了核心未匯出的符號
**解法：** 確認 `DEPENDS` 中列出了提供該符號的核心模組（如需 netfilter 符號，加上 `+kmod-nf-conntrack`）

### 問題：編譯時找不到核心標頭檔
**原因：** 核心源碼未正確準備
**解法：**
```bash
# 先確保核心已編譯
make target/linux/compile V=s
# 再編譯模組
make package/kernel/my-kmod/compile V=s
```

### 問題：`KERNEL_MAKE` 未定義
**原因：** 缺少 `include $(INCLUDE_DIR)/kernel.mk`
**解法：** 確認在 `include $(INCLUDE_DIR)/package.mk` 之前加入 `include $(INCLUDE_DIR)/kernel.mk`

## 參考來源

- https://openwrt.org/docs/guide-developer/helloworld/chapter5
- https://openwrt.org/docs/guide-developer/kernelmodules
- https://www.kernel.org/doc/html/latest/kbuild/modules.html
- https://github.com/openwrt/openwrt/tree/main/package/kernel
