# 除錯與效能調校（Debugging & Performance）

## 概述

在資源受限的嵌入式路由器上除錯，與桌面開發截然不同。OpenWrt 提供了 logread、procd、遠端 GDB 等工具鏈，以及核心層級的除錯選項。掌握這些工具能大幅提升開發效率，快速定位和修復問題。

## 前置條件

- 已部署 OpenWrt 裝置（可 SSH 登入）
- 建構環境中已建構對應的核心/套件（含除錯符號）
- 基本的 GDB 操作經驗（可選，用於進階除錯）

## 核心概念

### 除錯工具總覽

| 工具 | 層級 | 用途 |
|------|------|------|
| `logread` | 系統 | 查看系統日誌（syslog） |
| `dmesg` | 核心 | 查看核心日誌 |
| `procd` | 服務 | 服務管理、自動重啟、追蹤 |
| `gdbserver` | 應用 | 遠端除錯使用者空間程式 |
| `strace` | 應用 | 追蹤系統呼叫 |
| `ltrace` | 應用 | 追蹤函式庫呼叫 |
| `perf` | 核心/應用 | 效能分析 |
| `top`/`htop` | 系統 | 即時資源監控 |
| `tcpdump` | 網路 | 封包擷取 |

### 日誌系統架構

```
應用程式 ──syslog()──▶ procd/logd ──▶ 環狀緩衝區（RAM）
                                        │
                                   logread 讀取
                                        │
                              （可選）寫入 /tmp/log
```

## 操作流程

### 系統日誌

```bash
# 即時追蹤系統日誌
logread -f

# 只顯示特定服務的日誌
logread | grep 'my-app'

# 顯示核心日誌
dmesg

# 即時追蹤核心日誌
dmesg -w

# 設定 syslog 遠端伺服器（在 /etc/config/system 中）
uci set system.@system[0].log_ip='192.168.1.100'
uci set system.@system[0].log_port='514'
uci set system.@system[0].log_proto='udp'
uci commit system
/etc/init.d/log restart
```

### procd 服務管理與除錯

```bash
# 查看服務狀態
/etc/init.d/my-app status

# 啟動/停止/重啟服務
/etc/init.d/my-app start
/etc/init.d/my-app stop
/etc/init.d/my-app restart

# 查看所有 procd 管理的服務
ubus call service list

# 查看特定服務的詳細資訊
ubus call service list '{"name":"my-app"}'
```

procd init 腳本中的除錯選項：

```bash
#!/bin/sh /etc/rc.common
START=90
USE_PROCD=1

start_service() {
    procd_open_instance
    procd_set_param command /usr/bin/my-app

    # 重啟策略：失敗後自動重啟
    # respawn <threshold_sec> <timeout_sec> <max_retries>
    procd_set_param respawn 3600 5 5

    # 將 stdout/stderr 導入 syslog
    procd_set_param stdout 1
    procd_set_param stderr 1

    # 設定核心轉儲
    procd_set_param limits core="unlimited"

    # 監視設定檔變更
    procd_set_param file /etc/config/my-app

    procd_close_instance
}

# 設定檔變更後自動觸發
service_triggers() {
    procd_add_reload_trigger "my-app"
}
```

### 遠端 GDB 除錯

```bash
# 1. 在路由器上安裝 gdbserver
opkg install gdbserver

# 2. 在路由器上啟動 gdbserver
gdbserver :9000 /usr/bin/my-app
# 或附加到正在運行的行程
gdbserver --attach :9000 $(pidof my-app)

# 3. 在開發機上（使用交叉編譯版 GDB）
# 確保有除錯符號版本（在建構時啟用 CONFIG_DEBUG=y）
./staging_dir/toolchain-*/bin/mipsel-openwrt-linux-musl-gdb \
    ./build_dir/target-*/my-app-*/my-app

# 在 GDB 中
(gdb) set sysroot ./staging_dir/target-mipsel_24kc_musl
(gdb) target remote 192.168.1.1:9000
(gdb) break main
(gdb) continue
```

### 使用 strace 追蹤系統呼叫

```bash
# 安裝 strace
opkg install strace

# 追蹤程式的所有系統呼叫
strace -f /usr/bin/my-app

# 只追蹤檔案相關呼叫
strace -e trace=file /usr/bin/my-app

# 只追蹤網路相關呼叫
strace -e trace=network /usr/bin/my-app

# 附加到正在運行的行程
strace -p $(pidof my-app)

# 計時統計
strace -c /usr/bin/my-app
```

### 網路除錯

```bash
# 封包擷取
opkg install tcpdump
tcpdump -i br-lan -n -vv port 53    # DNS 查詢
tcpdump -i eth1 -w /tmp/wan.pcap    # 儲存為 pcap 檔
# 透過 SSH 即時傳輸到開發機的 Wireshark
ssh root@192.168.1.1 'tcpdump -i eth1 -w -' | wireshark -k -i -

# 檢查路由表
ip route show
ip -6 route show

# 查看 ARP/鄰居表
ip neigh show

# 防火牆規則檢查
nft list ruleset         # 顯示完整 nftables 規則
fw4 print               # 顯示 OpenWrt 防火牆設定
fw4 check               # 驗證防火牆設定

# conntrack 追蹤
cat /proc/net/nf_conntrack | head -20
conntrack -L             # 需安裝 conntrack-tools
```

### 效能監控

```bash
# 即時系統資源
top -d 1

# 記憶體使用
free -h
cat /proc/meminfo

# CPU 使用明細
cat /proc/stat

# 儲存空間
df -h

# 網路介面流量
cat /proc/net/dev
ifconfig eth0    # 查看封包統計

# 行程記憶體映射
cat /proc/$(pidof my-app)/maps
cat /proc/$(pidof my-app)/status
```

### 建構時除錯選項

在 `make menuconfig` 中啟用除錯功能：

```bash
# 全域除錯設定
Global build settings → Compile packages with debugging info  [*]

# 核心除錯
Kernel modules → Kernel debugging options
    → CONFIG_DEBUG_INFO         # 核心除錯符號
    → CONFIG_KASAN              # 核心位址消毒器
    → CONFIG_UBSAN              # 未定義行為偵測

# GDB 支援
Development → gdb               # 完整 GDB
Development → gdbserver          # 輕量遠端除錯
```

## 範例代碼

### 簡易效能計時腳本

```bash
#!/bin/sh
# 量測服務啟動時間
START_TIME=$(date +%s%N)

/etc/init.d/my-app start

END_TIME=$(date +%s%N)
ELAPSED=$(( (END_TIME - START_TIME) / 1000000 ))
echo "服務啟動耗時: ${ELAPSED} ms"
```

### 使用 ubus 監聽事件

```bash
# 監聽所有 ubus 事件（用於追蹤系統行為）
ubus listen &

# 監聽特定事件
ubus listen network.interface

# 程式化發送事件
ubus send my-app.status '{"state":"running","uptime":3600}'
```

### 核心 oops 分析

```bash
# 當核心 oops 發生時，從 dmesg 取得 call trace
dmesg | grep -A 30 "Oops"

# 使用 addr2line 將位址轉換為原始碼行號
# （需要帶除錯符號的 vmlinux）
./staging_dir/toolchain-*/bin/mipsel-openwrt-linux-musl-addr2line \
    -e build_dir/target-*/linux-*/vmlinux \
    0xffffffff80123456
```

## 常見錯誤與解法

### 問題：服務不斷重啟（respawn loop）
**原因：** procd 偵測到服務反覆崩潰
**解法：**
```bash
# 查看日誌找出崩潰原因
logread | grep my-app
# 暫時停用 respawn 測試
# 直接在命令列手動執行，觀察錯誤輸出
/usr/bin/my-app
```

### 問題：記憶體不足（OOM）
**原因：** 嵌入式裝置通常只有 64-256 MB RAM
**解法：**
```bash
# 查看記憶體使用前幾名
ps -o rss,pid,comm | sort -rn | head -10
# 考慮啟用 swap 或減少常駐服務
```

### 問題：`ptrace: Operation not permitted`（strace 失敗）
**原因：** 核心安全設定禁止 ptrace
**解法：**
```bash
echo 0 > /proc/sys/kernel/yama/ptrace_scope
```

### 問題：GDB 斷點不命中
**原因：** 二進位檔被 strip 過，無除錯符號
**解法：** 在建構時啟用 `CONFIG_DEBUG=y`，使用 build_dir 中未 strip 的版本

## 參考來源

- https://openwrt.org/docs/guide-developer/gdb
- https://openwrt.org/docs/guide-developer/procd
- https://openwrt.org/docs/guide-user/troubleshooting/start
- https://www.sourceware.org/gdb/documentation/
