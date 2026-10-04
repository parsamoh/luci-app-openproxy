# 幫我建立 LuCI 介面

## 使用時機

當你需要為 OpenWrt 套件建立 Web 管理介面時使用此提示詞。使用 LuCI JavaScript client-side API（現代做法，適用 OpenWrt 21.02+）。

## 提示詞模板

---

我要為 OpenWrt 23.05+ 建立一個 LuCI Web 管理介面，需求如下：

- **應用名稱**：[填入名稱，如 luci-app-myapp]
- **管理的 UCI 設定檔**：[填入 config 路徑，如 /etc/config/myapp]
- **選單位置**：[Services / Network / System / VPN / NAS 等]
- **需要的設定欄位**：
  - [欄位1]：[類型，如 text/bool/list/textarea/IP 地址]
  - [欄位2]：[類型]
  - ...
- **是否需要狀態頁面**：[是/否，顯示什麼資訊]
- **是否需要多 section**：[是/否，如多介面或多規則]
- **需呼叫的 rpcd/ubus 服務**：[列出需要存取的 ubus 路徑]

請幫我產生：
1. 完整的 `Makefile`（使用 luci.mk 建構）
2. JavaScript view 檔案（ES module 格式，繼承 form.Map）
3. 選單定義 JSON（`menu.d/luci-app-*.json`）
4. ACL 權限定義 JSON（`acl.d/luci-app-*.json`）
5. 對應的 UCI 預設設定檔
6. 編譯和安裝指令

要求：
- 使用 JavaScript client-side API（非 Lua CBI）
- 使用 `'require form'`、`'require uci'`、`'require ui'` 等標準模組
- 所有 UI 文字用英文（可在 po/ 中加翻譯）
- 程式碼加繁體中文註解

---

## 期望輸出

- LuCI 應用的完整目錄結構及所有檔案
- UCI 設定檔範例
- 編譯、安裝、測試的完整流程

## 範例對話

**User**: 我有一個 VPN 服務叫 `myvpn`，UCI 設定在 `/etc/config/myvpn`。需要設定：enabled (bool)、server_addr (text)、port (number)、protocol (選單：tcp/udp)。放在 VPN 選單下。

**Assistant**: 了解，以下為 `luci-app-myvpn` 的完整檔案：

**Makefile**
```makefile
include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for MyVPN
LUCI_DEPENDS:=+myvpn
LUCI_PKGARCH:=all

include ../../luci.mk
```

**htdocs/luci-static/resources/view/myvpn/settings.js**
```javascript
'use strict';
'require form';
'require uci';
'require view';

return view.extend({
    render: function() {
        var m, s, o;

        // 建立 form.Map 綁定 UCI 設定檔 myvpn
        m = new form.Map('myvpn', _('MyVPN 設定'),
            _('管理 MyVPN 連線參數'));

        s = m.section(form.TypedSection, 'global', _('全域設定'));
        s.anonymous = true;

        o = s.option(form.Flag, 'enabled', _('啟用'));
        o.default = '0';

        o = s.option(form.Value, 'server_addr', _('伺服器位址'));
        o.datatype = 'host';
        o.rmempty = false;

        o = s.option(form.Value, 'port', _('連接埠'));
        o.datatype = 'port';
        o.default = '1194';

        o = s.option(form.ListValue, 'protocol', _('協定'));
        o.value('tcp', 'TCP');
        o.value('udp', 'UDP');
        o.default = 'udp';

        return m.render();
    }
});
```

（接著提供 menu.d JSON、ACL JSON、UCI 預設設定和部署指令）
