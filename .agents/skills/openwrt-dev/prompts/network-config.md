# 幫我設定網路

## 使用時機

當你需要在 OpenWrt 路由器上設定網路拓撲時使用此提示詞。涵蓋 WAN/LAN 設定、VLAN（DSA 或 swconfig）、防火牆規則（firewall4/nftables）、Wi-Fi、VPN 隧道等場景。

## 提示詞模板

---

我需要在 OpenWrt 路由器上設定網路，請幫我產生完整設定：

- **OpenWrt 版本**：[如 23.05.3]
- **硬體型號**：[如 Xiaomi AX3600、x86/64 虛擬機]
- **網路拓撲需求**：
  - WAN：[DHCP / PPPoE / 靜態 IP]
  - LAN：[子網段，如 192.168.1.0/24]
  - Guest Network：[是/否，子網段]
  - VLAN：[需要哪些 VLAN 和用途]
- **防火牆需求**：
  - 埠轉發：[列出需要轉發的埠，如 80→192.168.1.100:8080]
  - 允許/封鎖規則：[特殊規則]
  - NAT 設定：[是否需要 masquerade]
- **Wi-Fi 需求**：
  - SSID：[名稱]
  - 加密：[WPA2-PSK / WPA3-SAE / OWE]
  - 頻段：[2.4G / 5G / 雙頻]
- **其他需求**：[DNS、DHCP 保留、QoS 等]

請幫我產生：
1. `/etc/config/network` 完整設定
2. `/etc/config/firewall` 完整設定
3. `/etc/config/wireless` 完整設定 (如需要)
4. `/etc/config/dhcp` 調整 (如需要)
5. 驗證指令（如何確認設定正確）
6. 套用和回復指令

要求：
- 使用 UCI 指令格式，方便複製貼上執行
- 使用 firewall4（nftables 後端），不用 iptables
- 如涉及 VLAN，使用 DSA（21.02+ 標準）
- 加繁體中文註解

---

## 期望輸出

- UCI 設定檔或 UCI 指令序列
- 驗證設定正確的命令
- 錯誤時的回復方法

## 範例對話

**User**: 我有一台 x86 OpenWrt 23.05 路由器，WAN 用 PPPoE（帳號 user@isp.net），LAN 用 192.168.10.0/24。要加一個 Guest Wi-Fi（192.168.20.0/24），Guest 只能上網不能訪問 LAN。需要轉發 443 埠到 192.168.10.50。

**Assistant**: 了解，以下是完整設定：

**1. 網路設定 `/etc/config/network`**
```
# WAN PPPoE 撥號
uci set network.wan=interface
uci set network.wan.proto='pppoe'
uci set network.wan.device='eth1'
uci set network.wan.username='user@isp.net'
uci set network.wan.password='你的密碼'

# LAN 主網段
uci set network.lan=interface
uci set network.lan.proto='static'
uci set network.lan.device='br-lan'
uci set network.lan.ipaddr='192.168.10.1'
uci set network.lan.netmask='255.255.255.0'

# Guest 網段
uci set network.guest=interface
uci set network.guest.proto='static'
uci set network.guest.device='br-guest'
uci set network.guest.ipaddr='192.168.20.1'
uci set network.guest.netmask='255.255.255.0'

uci commit network
```

**2. 防火牆設定（firewall4 / nftables）**
```
# Guest Zone — 只允許 WAN 轉發
uci add firewall zone
uci set firewall.@zone[-1].name='guest'
uci set firewall.@zone[-1].input='REJECT'
uci set firewall.@zone[-1].output='ACCEPT'
uci set firewall.@zone[-1].forward='REJECT'
uci add_list firewall.@zone[-1].network='guest'

# Guest → WAN 允許（上網）
uci add firewall forwarding
uci set firewall.@forwarding[-1].src='guest'
uci set firewall.@forwarding[-1].dest='wan'

# Guest DNS/DHCP 允許
uci add firewall rule
uci set firewall.@rule[-1].name='Guest DNS'
uci set firewall.@rule[-1].src='guest'
uci set firewall.@rule[-1].dest_port='53'
uci set firewall.@rule[-1].proto='tcp udp'
uci set firewall.@rule[-1].target='ACCEPT'

uci add firewall rule
uci set firewall.@rule[-1].name='Guest DHCP'
uci set firewall.@rule[-1].src='guest'
uci set firewall.@rule[-1].dest_port='67-68'
uci set firewall.@rule[-1].proto='udp'
uci set firewall.@rule[-1].target='ACCEPT'

# 埠轉發 443 → 192.168.10.50
uci add firewall redirect
uci set firewall.@redirect[-1].name='HTTPS Forward'
uci set firewall.@redirect[-1].src='wan'
uci set firewall.@redirect[-1].src_dport='443'
uci set firewall.@redirect[-1].dest='lan'
uci set firewall.@redirect[-1].dest_ip='192.168.10.50'
uci set firewall.@redirect[-1].dest_port='443'
uci set firewall.@redirect[-1].proto='tcp'
uci set firewall.@redirect[-1].target='DNAT'

uci commit firewall
/etc/init.d/firewall restart
```

（接著提供 Wi-Fi 設定、DHCP 設定、驗證和回復指令）
