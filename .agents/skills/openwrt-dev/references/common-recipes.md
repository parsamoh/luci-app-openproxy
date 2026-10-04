# 常用操作速查（Common Recipes）

## 概述

本文件收集 OpenWrt 日常開發和維運中最常用的操作指令和程式碼片段，方便快速查閱。所有指令均適用於 OpenWrt 23.05+ 環境。

## 系統管理

### 基本操作

```bash
# 查看韌體版本
cat /etc/openwrt_release
ubus call system board

# 查看正常運行時間
uptime

# 查看系統資源
free -h           # 記憶體
df -h             # 磁碟
top -b -n1        # CPU 使用

# 重啟裝置
reboot
# 安全關機（先寫回快閃記憶體）
sync && reboot
```

### 套件管理

```bash
# 更新套件列表
opkg update

# 搜尋套件
opkg list | grep "keyword"
opkg find "*keyword*"

# 安裝/移除
opkg install <package>
opkg remove <package>

# 查看已安裝套件
opkg list-installed

# 查看套件提供的檔案
opkg files <package>

# 查看檔案屬於哪個套件
opkg search /usr/bin/some-binary
```

### UCI 快速操作

```bash
# 匯出完整設定
uci export network > /tmp/network-backup.txt

# 匯入設定
uci import network < /tmp/network-backup.txt

# 批次修改
uci batch << EOF
set network.lan.ipaddr='192.168.2.1'
set network.lan.netmask='255.255.255.0'
commit network
EOF

# 還原到上次 commit
uci revert network
```

## 網路操作

### 連線測試

```bash
# Ping 測試
ping -c 4 8.8.8.8
ping6 -c 4 2001:4860:4860::8888

# DNS 測試
nslookup google.com
# 指定 DNS 伺服器
nslookup google.com 1.1.1.1

# 路由追蹤
traceroute 8.8.8.8

# 查看目前路由
ip route show table all
ip -6 route show

# 查看介面狀態
ifstatus wan          # UCI 介面
ip addr show          # Linux 介面
```

### WiFi 操作

```bash
# 重啟 WiFi
wifi reload
wifi down && wifi up

# 掃描可用 AP
iwinfo wlan0 scan

# 查看連線客戶端
iwinfo wlan0 assoclist

# 查看 WiFi 晶片資訊
iwinfo wlan0 info

# 臨時停用/啟用 WiFi
uci set wireless.radio0.disabled='1'
uci commit wireless
wifi reload
```

### 封包擷取

```bash
# 基本擷取
tcpdump -i br-lan -n

# 擷取特定 IP
tcpdump -i eth1 host 192.168.1.100

# 擷取特定端口
tcpdump -i br-lan port 53

# 儲存並傳輸到開發機分析
tcpdump -i eth1 -w /tmp/capture.pcap -c 1000
scp root@192.168.1.1:/tmp/capture.pcap .

# 即時串流到 Wireshark
ssh root@192.168.1.1 'tcpdump -i eth1 -w -' | wireshark -k -i -
```

## 建構系統操作

### 常用 Make 指令

```bash
# 完整建構
make -j$(nproc)

# 僅建構核心
make target/linux/compile V=s

# 僅建構某個套件
make package/<name>/compile V=s

# 清理某個套件
make package/<name>/clean

# 產生映像檔（不重新編譯套件）
make target/linux/install V=s

# 更新 .config 中的相依性
make defconfig

# 產生 diffconfig（最小化 .config）
./scripts/diffconfig.sh > diffconfig

# 從 diffconfig 還原
cp diffconfig .config
make defconfig

# 下載所有需要的源碼（離線建構前）
make -j$(nproc) download
```

### 清理指令

```bash
# 清理套件編譯產物（保留核心和工具鏈）
make clean

# 清理一切（含核心，不含工具鏈）
make targetclean

# 完全清理（含工具鏈，幾乎等於全新建構）
make dirclean

# 清理下載的源碼
make distclean
```

### Feeds 操作

```bash
# 更新所有 feeds
./scripts/feeds update -a

# 只更新某個 feed
./scripts/feeds update packages

# 安裝某個套件（建立符號連結）
./scripts/feeds install <package>

# 搜尋 feed 中的套件
./scripts/feeds search <keyword>

# 列出某個 feed 的所有套件
./scripts/feeds list -r packages
```

## 裝置管理

### Failsafe 模式

```bash
# 進入 failsafe 模式（裝置啟動時按特定按鈕或按鍵）
# failsafe 模式下：
#   - IP: 192.168.1.1
#   - 無密碼
#   - 僅載入最小系統

# 在 failsafe 模式中：
mount_root                    # 掛載 overlay
firstboot                     # 重置為出廠設定
reboot -f                     # 重啟
```

### 韌體升級

```bash
# 保留設定升級（推薦）
sysupgrade /tmp/openwrt-*-sysupgrade.bin

# 不保留設定升級（全新安裝）
sysupgrade -n /tmp/openwrt-*-sysupgrade.bin

# 備份設定
sysupgrade -b /tmp/backup-$(date +%Y%m%d).tar.gz

# 還原設定
sysupgrade -r /tmp/backup-*.tar.gz
```

### UART 序列埠存取

```bash
# 在開發機上使用 screen 連接
screen /dev/ttyUSB0 115200

# 或使用 minicom
minicom -D /dev/ttyUSB0 -b 115200

# 或使用 picocom
picocom -b 115200 /dev/ttyUSB0
```

## 開發常用

### 快速部署腳本

```bash
#!/bin/sh
# deploy.sh — 快速部署套件到路由器
ROUTER="root@192.168.1.1"
PKG_NAME="my-app"

# 編譯
make package/${PKG_NAME}/{clean,compile} V=s || exit 1

# 找到 ipk 檔
IPK=$(find bin/packages/ -name "${PKG_NAME}_*.ipk" | head -1)
[ -z "$IPK" ] && { echo "找不到 ipk"; exit 1; }

# 部署
scp "$IPK" ${ROUTER}:/tmp/
ssh ${ROUTER} "opkg install --force-reinstall /tmp/$(basename $IPK) && /etc/init.d/${PKG_NAME} restart"
echo "部署完成"
```

### ubus 常用呼叫

```bash
# 系統資訊
ubus call system board        # 硬體資訊
ubus call system info         # 記憶體/負載

# 網路資訊
ubus call network.interface dump              # 所有介面
ubus call network.interface.wan status        # WAN 狀態
ubus call network.device status '{"name":"br-lan"}'

# 服務管理
ubus call service list                        # 列出所有服務
ubus call service list '{"name":"dropbear"}'  # 特定服務

# WiFi
ubus call iwinfo info '{"device":"wlan0"}'
ubus call iwinfo scan '{"device":"wlan0"}'
ubus call iwinfo assoclist '{"device":"wlan0"}'

# DHCP 租約
ubus call dhcp ipv4leases
ubus call dhcp ipv6leases

# 事件監聽
ubus listen                        # 所有事件
ubus listen network.interface      # 網路事件
```

### Cron 排程工作

```bash
# 編輯 cron
crontab -e

# 每日凌晨三點重啟 WiFi
0 3 * * * /sbin/wifi reload

# 每小時同步 NTP
0 * * * * /usr/sbin/ntpd -q -p pool.ntp.org

# 啟用 cron 服務
/etc/init.d/cron enable
/etc/init.d/cron start
```

### 建構系統環境變數速查

```bash
# 在套件 Makefile 中可用的變數
$(TOPDIR)            # 建構根目錄
$(INCLUDE_DIR)       # include/ 目錄
$(STAGING_DIR)       # staging 目錄
$(PKG_BUILD_DIR)     # 套件解壓/編譯目錄
$(PKG_INSTALL_DIR)   # 套件 make install 的目標
$(TARGET_CC)         # 交叉編譯器
$(TARGET_CFLAGS)     # 目標平台 CFLAGS
$(TARGET_LDFLAGS)    # 目標平台 LDFLAGS
$(INSTALL_DIR)       # install -d -m0755
$(INSTALL_BIN)       # install -m0755
$(INSTALL_DATA)      # install -m0644
$(INSTALL_CONF)      # install -m0600
$(CP)                # cp -fpR
$(1)                 # 安裝路徑的根（install 步驟中）
```

## 參考來源

- https://openwrt.org/docs/guide-user/start
- https://openwrt.org/docs/guide-quick-start/sshadministration
- https://openwrt.org/docs/techref/ubus
- https://github.com/openwrt/openwrt/blob/main/README.md
