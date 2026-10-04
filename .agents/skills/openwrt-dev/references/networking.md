# 網路子系統（Networking）

## 概述

OpenWrt 的網路設定以 UCI（Unified Configuration Interface）為核心，透過 netifd（網路介面守護程式）管理所有網路介面、路由與位址，firewall4 則使用 nftables 實現防火牆功能。三者搭配提供了完整的路由器網路功能。理解這個子系統是管理和客製化 OpenWrt 路由器的關鍵。

## 前置條件

- 已安裝 OpenWrt 的裝置或虛擬機
- 基本的 TCP/IP 與 Linux 網路知識
- 了解 UCI 設定語法（config/option/list）

## 核心概念

### UCI 設定系統

UCI 是 OpenWrt 的統一設定格式，所有設定檔位於 `/etc/config/` 目錄：

```
/etc/config/
├── network      # 網路介面、路由、交換機
├── wireless     # 無線網路設定
├── firewall     # 防火牆規則
├── dhcp         # DHCP/DNS（dnsmasq）
└── ...          # 其他服务設定
```

UCI 語法結構：
```bash
config interface 'lan'         # 型別 + 名稱
    option proto 'static'      # 鍵值對
    option ipaddr '192.168.1.1'
    option netmask '255.255.255.0'
    list dns '8.8.8.8'         # 列表值
    list dns '1.1.1.1'
```

### 元件關係圖

```
UCI 設定檔 (/etc/config/*)
         │
    ┌────┴────┐
    ▼         ▼
 netifd    firewall4
 (網路)    (防火牆)
    │         │
    ▼         ▼
 Linux     nftables
 iproute2  核心規則
```

### 關鍵網路元件

| 元件 | 用途 | 設定檔 |
|------|------|--------|
| netifd | 管理介面/路由/DNS | `/etc/config/network` |
| firewall4 | nftables 防火牆 | `/etc/config/firewall` |
| dnsmasq | DHCP + DNS | `/etc/config/dhcp` |
| hostapd | WiFi AP 服務 | `/etc/config/wireless` |
| odhcpd | DHCPv6 + RA | `/etc/config/dhcp` |
| pppd | PPPoE/3G 撥號 | `/etc/config/network` |

## 操作流程

### UCI 基本操作

```bash
# 讀取設定
uci show network              # 顯示整個 network 設定
uci get network.lan.ipaddr    # 取得特定值
uci show network.lan          # 顯示某個 section

# 修改設定
uci set network.lan.ipaddr='192.168.2.1'
uci set network.lan.netmask='255.255.255.0'
uci add_list network.lan.dns='8.8.8.8'
uci del_list network.lan.dns='1.1.1.1'

# 提交變更
uci commit network

# 套用設定（重啟相關服務）
/etc/init.d/network restart
# 或使用 reload（較溫和）
/etc/init.d/network reload
```

### 網路介面設定

#### 靜態 IP

```bash
# /etc/config/network
config interface 'lan'
    option device 'br-lan'
    option proto 'static'
    option ipaddr '192.168.1.1'
    option netmask '255.255.255.0'
    option ip6assign '60'

config interface 'wan'
    option device 'eth1'
    option proto 'dhcp'

config interface 'wan6'
    option device 'eth1'
    option proto 'dhcpv6'
```

#### PPPoE

```bash
config interface 'wan'
    option device 'eth1'
    option proto 'pppoe'
    option username 'user@isp.com'
    option password 'secret'
    option ipv6 'auto'
```

#### VLAN 設定（DSA，OpenWrt 21.02+）

```bash
# DSA（Distributed Switch Architecture）取代了舊的 swconfig
config device
    option name 'br-lan'
    option type 'bridge'
    list ports 'lan1'
    list ports 'lan2'
    list ports 'lan3'
    list ports 'lan4'

# VLAN 設定
config bridge-vlan
    option device 'br-lan'
    option vlan '10'
    list ports 'lan1:t'   # tagged
    list ports 'lan2:u'   # untagged

config interface 'vlan10'
    option device 'br-lan.10'
    option proto 'static'
    option ipaddr '10.10.10.1'
    option netmask '255.255.255.0'
```

### 防火牆設定（firewall4 / nftables）

```bash
# /etc/config/firewall

# 基本區域定義
config defaults
    option syn_flood '1'
    option input 'REJECT'
    option output 'ACCEPT'
    option forward 'REJECT'

config zone
    option name 'lan'
    list network 'lan'
    option input 'ACCEPT'
    option output 'ACCEPT'
    option forward 'ACCEPT'

config zone
    option name 'wan'
    list network 'wan'
    list network 'wan6'
    option input 'REJECT'
    option output 'ACCEPT'
    option forward 'REJECT'
    option masq '1'        # NAT 啟用
    option mtu_fix '1'

# 區域間轉發
config forwarding
    option src 'lan'
    option dest 'wan'

# 端口轉發
config redirect
    option name 'SSH-Server'
    option src 'wan'
    option src_dport '2222'
    option dest 'lan'
    option dest_ip '192.168.1.100'
    option dest_port '22'
    option proto 'tcp'

# 自訂防火牆規則
config rule
    option name 'Allow-ICMP'
    option src 'wan'
    option proto 'icmp'
    option target 'ACCEPT'

# 流量限制
config rule
    option name 'Rate-Limit-SSH'
    option src 'wan'
    option dest_port '22'
    option proto 'tcp'
    option extra '--limit 5/min --limit-burst 10'
    option target 'ACCEPT'
```

### 自訂 nftables 規則

```bash
# 可在 /etc/nftables.d/ 放入自訂規則
cat > /etc/nftables.d/90-custom.nft << 'EOF'
chain custom_forward {
    type filter hook forward priority 0; policy accept;
    ip saddr 192.168.1.50 tcp dport 80 counter accept comment "允許特定 IP 的 HTTP"
}
EOF

# 重新載入防火牆
fw4 reload
```

### 無線網路設定

```bash
# /etc/config/wireless

config wifi-device 'radio0'
    option type 'mac80211'
    option channel '36'
    option band '5g'
    option htmode 'HE80'     # WiFi 6 (802.11ax)
    option country 'TW'

config wifi-iface 'default_radio0'
    option device 'radio0'
    option network 'lan'
    option mode 'ap'
    option ssid 'MyNetwork'
    option encryption 'sae-mixed'   # WPA3/WPA2 混合
    option key 'your-password'
    option ieee80211w '1'           # 管理幀保護(可選)

# 訪客網路（獨立 VLAN）
config wifi-iface 'guest_radio0'
    option device 'radio0'
    option network 'guest'
    option mode 'ap'
    option ssid 'Guest-Network'
    option encryption 'sae'
    option key 'guest-pass'
    option isolate '1'              # 客戶端隔離
```

## 範例代碼

### 使用 ubus 查詢網路狀態

```bash
# 列出所有網路介面
ubus call network.interface dump

# 查詢特定介面狀態
ubus call network.interface.wan status

# 查看裝置資訊
ubus call network.device status '{"name":"br-lan"}'

# WiFi 掃描
ubus call iwinfo scan '{"device":"wlan0"}'
```

### Shell 腳本：動態新增防火牆規則

```bash
#!/bin/sh
# 根據外部黑名單動態封鎖 IP

BLACKLIST_URL="https://example.com/blacklist.txt"
TMPFILE="/tmp/blacklist.txt"

wget -q "$BLACKLIST_URL" -O "$TMPFILE" || exit 1

# 清除舊的黑名單規則
while uci -q delete firewall.@rule[-1]; do :; done 2>/dev/null

# 逐行新增規則
while IFS= read -r ip; do
    [ -z "$ip" ] && continue
    uci add firewall rule
    uci set firewall.@rule[-1].name="Block-$ip"
    uci set firewall.@rule[-1].src='wan'
    uci set firewall.@rule[-1].src_ip="$ip"
    uci set firewall.@rule[-1].target='DROP'
done < "$TMPFILE"

uci commit firewall
fw4 reload
```

## 常見錯誤與解法

### 問題：修改設定後網路未生效
**原因：** 只執行了 `uci commit` 但未重啟服務
**解法：**
```bash
uci commit network
/etc/init.d/network reload  # 或 restart
```

### 問題：VLAN 設定在 23.05 上不工作
**原因：** 23.05+ 使用 DSA，舊版 swconfig 語法不適用
**解法：** 使用 `config bridge-vlan` + `config device` 語法取代舊的 `switch_vlan`

### 問題：防火牆規則順序問題
**原因：** UCI 防火牆規則按配置檔案順序匹配
**解法：** 將更特定的規則（如允許特定 IP）放在更通用的規則之前

### 問題：WiFi 不出現或無法連線
**原因：** 可能是國家碼或頻道設定問題
**解法：**
```bash
uci set wireless.radio0.disabled='0'
uci set wireless.radio0.country='TW'
uci commit wireless
wifi reload
```

## 參考來源

- https://openwrt.org/docs/guide-user/network/network_configuration
- https://openwrt.org/docs/guide-user/firewall/firewall_configuration
- https://openwrt.org/docs/guide-user/network/wifi/start
- https://openwrt.org/docs/techref/netifd
- https://github.com/openwrt/openwrt/tree/main/package/network
