# 安全加固與 CVE 修補（Security）

## 概述

路由器作為網路邊界設備，是攻擊者的首要目標。OpenWrt 提供多層安全加固機制：從編譯期的記憶體保護（ASLR、SSP、FORTIFY_SOURCE）到運行期的存取控制（防火牆、SECCOMP、SELinux）。理解這些機制並正確啟用，是建構安全路由器韌體的關鍵。

## 前置條件

- 已搭建 OpenWrt Buildroot 環境
- 了解基本的資安概念（緩衝區溢出、特權提升等）
- 熟悉 OpenWrt 建構組態（make menuconfig）

## 核心概念

### 編譯期安全選項

OpenWrt 在 `Config-build.in` 中提供以下安全加固選項：

| 選項 | 說明 | 建議等級 |
|------|------|---------|
| **ASLR/PIE** | 位址空間隨機化 + 位置無關執行檔 | All（所有套件） |
| **SSP** | 堆疊溢出保護（Stack Smashing Protection） | Strong 或 All |
| **FORTIFY_SOURCE** | 危險函式（memcpy、strcpy 等）邊界檢查 | Level 2 |
| **RELRO** | 防止 GOT/PLT 被覆寫 | Full |
| **-fformat-security** | 格式字串漏洞警告 | 啟用 |

### 各安全選項等級

#### PIE（Position Independent Executable）
```
None     → 不啟用
Regular  → 僅核心套件使用 PIE
All      → 所有套件使用 PIE（推薦）
```

#### SSP（Stack Smashing Protection）
```
None     → 不啟用
Regular  → -fstack-protector（僅保護使用 alloca 或大緩衝區的函式）
Strong   → -fstack-protector-strong（保護更多函式類型，推薦）
All      → -fstack-protector-all（所有函式，效能影響最大）
```

#### FORTIFY_SOURCE
```
None     → 不啟用
Level 1  → 編譯期檢查已知大小的緩衝區
Level 2  → Level 1 + 更嚴格的執行期檢查（推薦）
Level 3  → Level 2 + 更多情境（GCC 12+）
```

#### RELRO（Relocation Read-Only）
```
None     → 不啟用
Partial  → 部分 GOT 唯讀
Full     → 完整 GOT/PLT 唯讀 + BIND_NOW（推薦）
```

### 運行期安全機制

| 機制 | 說明 |
|------|------|
| **防火牆** | firewall4 / nftables（預設啟用） |
| **SECCOMP** | 系統呼叫過濾（限制行程可用的系統呼叫） |
| **SELinux** | 強制存取控制（可選，需核心支援） |
| **SSH 金鑰認證** | 取代密碼認證 |
| **UCI ACL** | LuCI 權限控制 |
| **TLS/HTTPS** | 加密管理介面 |

## 操作流程

### 啟用編譯期安全選項

```bash
make menuconfig

# 導航到：Global build settings → Security Options
# 建議設定：
#   → ASLR/PIE:         All
#   → SSP:              Strong
#   → FORTIFY_SOURCE:   Level 2
#   → RELRO:            Full
#   → Format Security:  [*] (啟用)
```

### 驗證安全選項已生效

```bash
# 檢查 PIE
file usr/bin/my-app
# 應顯示 "LSB pie executable" 而非 "LSB executable"

# 檢查 SSP（readelf 查看符號）
readelf -s usr/bin/my-app | grep stack_chk
# 應看到 __stack_chk_fail 符號

# 檢查 RELRO
readelf -l usr/bin/my-app | grep GNU_RELRO
# Full RELRO 應看到 GNU_RELRO segment 且 BIND_NOW

# 使用 checksec 工具（需在 host 上安裝）
checksec --file=usr/bin/my-app
```

### SSH 安全加固

```bash
# 在路由器上設定 SSH 金鑰認證

# 1. 在開發機上產生金鑰（如果沒有）
ssh-keygen -t ed25519

# 2. 上傳公鑰到路由器
ssh-copy-id -i ~/.ssh/id_ed25519.pub root@192.168.1.1

# 3. 停用密碼認證
uci set dropbear.@dropbear[0].PasswordAuth='off'
uci set dropbear.@dropbear[0].RootPasswordAuth='off'
uci commit dropbear
/etc/init.d/dropbear restart

# 4. 改用非標準端口
uci set dropbear.@dropbear[0].Port='22222'
uci commit dropbear
/etc/init.d/dropbear restart
```

### LuCI HTTPS 設定

```bash
# 安裝 HTTPS 支援
opkg install luci-ssl

# 或使用 Let's Encrypt（需要公開域名）
opkg install acme acme-dnsapi luci-app-acme

# 手動產生自簽憑證（快速方案）
opkg install openssl-util
openssl req -new -newkey ec -pkeyopt ec_paramgen_curve:prime256v1 \
    -x509 -nodes -days 3650 \
    -keyout /etc/uhttpd.key -out /etc/uhttpd.crt \
    -subj "/CN=OpenWrt"

# 設定 uhttpd 強制 HTTPS
uci set uhttpd.main.redirect_https='1'
uci commit uhttpd
/etc/init.d/uhttpd restart
```

### 防火牆安全強化

```bash
# /etc/config/firewall 安全最佳實踐

# 啟用 SYN flood 保護
config defaults
    option syn_flood '1'
    option synflood_rate '25/s'
    option synflood_burst '50'
    option input 'REJECT'
    option output 'ACCEPT'
    option forward 'REJECT'
    option drop_invalid '1'   # 丟棄無效封包

# WAN 區域 — 最小化開放
config zone
    option name 'wan'
    list network 'wan'
    list network 'wan6'
    option input 'DROP'       # 使用 DROP 而非 REJECT（不回應）
    option output 'ACCEPT'
    option forward 'DROP'
    option masq '1'
    option mtu_fix '1'

# 限制管理介面存取
config rule
    option name 'Allow-LuCI-LAN-Only'
    option src 'lan'
    option dest_port '443'
    option proto 'tcp'
    option target 'ACCEPT'

# 限制 SSH 存取頻率
config rule
    option name 'Limit-SSH'
    option src 'wan'
    option dest_port '22'
    option proto 'tcp'
    option extra '-m conntrack --ctstate NEW -m limit --limit 3/min'
    option target 'ACCEPT'
```

### SECCOMP 應用

```bash
# 在自訂服務中啟用 SECCOMP（需核心支援）
# make menuconfig → Global build settings → [*] Enable SECCOMP support

# 範例：使用 seccomp-bpf 限制系統呼叫（C 程式碼片段）
```

```c
/* 簡化的 SECCOMP 過濾器範例 */
#include <linux/seccomp.h>
#include <linux/filter.h>
#include <sys/prctl.h>

void enable_seccomp(void) {
    /* 僅允許 read, write, exit, sigreturn */
    struct sock_filter filter[] = {
        BPF_STMT(BPF_LD | BPF_W | BPF_ABS,
                 offsetof(struct seccomp_data, nr)),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_read, 3, 0),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_write, 2, 0),
        BPF_JUMP(BPF_JMP | BPF_JEQ | BPF_K, __NR_exit_group, 1, 0),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_KILL),
        BPF_STMT(BPF_RET | BPF_K, SECCOMP_RET_ALLOW),
    };
    struct sock_fprog prog = {
        .len = sizeof(filter) / sizeof(filter[0]),
        .filter = filter,
    };

    prctl(PR_SET_NO_NEW_PRIVS, 1, 0, 0, 0);
    prctl(PR_SET_SECCOMP, SECCOMP_MODE_FILTER, &prog);
}
```

### CVE 修補流程

```bash
# 1. 追蹤 OpenWrt 安全公告
# https://openwrt.org/advisory/start

# 2. 更新到最新穩定版
cd openwrt
git pull
./scripts/feeds update -a

# 3. 檢查特定 CVE 修補
git log --oneline --grep="CVE-2024"

# 4. 為個別套件建立補丁
mkdir -p package/my-app/patches
# 補丁命名格式：NNN-description.patch
# 例如：001-fix-buffer-overflow.patch

# 5. 產生補丁
cd build_dir/target-*/my-app-*/
# 修改原始碼修復漏洞
diff -urN my-app-1.0.orig/ my-app-1.0/ > \
    ~/openwrt/package/my-app/patches/001-fix-CVE-2024-XXXX.patch
```

## 範例代碼

### 安全加固檢查腳本

```bash
#!/bin/sh
# 檢查路由器安全狀態

echo "=== OpenWrt 安全檢查 ==="

# 1. 檢查 SSH 設定
echo -n "SSH 密碼認證: "
PASS_AUTH=$(uci -q get dropbear.@dropbear[0].PasswordAuth)
[ "$PASS_AUTH" = "off" ] && echo "已停用 (安全)" || echo "啟用中 (建議停用)"

# 2. 檢查防火牆
echo -n "防火牆: "
FW_STATUS=$(/etc/init.d/firewall status 2>/dev/null)
echo "$FW_STATUS"

# 3. 檢查 WAN 開放端口
echo "WAN 開放端口:"
nft list chain inet fw4 input_wan 2>/dev/null | grep accept

# 4. 檢查密碼強度（是否為預設）
echo -n "Root 密碼: "
ROOT_HASH=$(awk -F: '/^root:/{print $2}' /etc/shadow)
[ -z "$ROOT_HASH" ] && echo "未設定 (危險!)" || echo "已設定"

# 5. 韌體版本
echo "韌體版本: $(cat /etc/openwrt_release | grep DISTRIB_RELEASE)"
```

## 常見錯誤與解法

### 問題：啟用 PIE 後套件編譯失敗
**原因：** 某些使用內聯彙編的套件不支援 PIE
**解法：** 對該套件使用 `PKG_BUILD_FLAGS:=-pie` 來個別關閉

### 問題：啟用 Full RELRO 後程式變慢
**原因：** BIND_NOW 導致所有動態符號在啟動時解析
**解法：** 對效能敏感的大型程式可降級為 Partial RELRO

### 問題：SSH 金鑰登入後無法使用密碼備用
**原因：** 停用密碼認證後沒有備份金鑰
**解法：** 在停用密碼認證前，先確認金鑰登入正常。保留 UART/序列埠存取作為緊急後門

### 問題：安全更新後裝置無法啟動
**原因：** 核心或關鍵套件的補丁引入了相容性問題
**解法：** 保留前一版韌體映像檔，使用雙分區或 failsafe 模式還原

## 參考來源

- https://openwrt.org/docs/guide-user/security/start
- https://openwrt.org/advisory/start
- https://github.com/openwrt/openwrt/blob/main/config/Config-build.in
- https://wiki.debian.org/Hardening
- https://man7.org/linux/man-pages/man2/seccomp.2.html
