# LuCI Web 介面開發（LuCI App Development）

## 概述

LuCI（Lua Unified Configuration Interface）是 OpenWrt 的標準 Web 管理介面。現代 LuCI（OpenWrt 21.02+）已從 Lua MVC 架構轉向 **JavaScript 客戶端框架**，搭配 ubus/rpcd 後端 API。新開發的介面模組應優先使用 JavaScript 方式；Lua 僅用於維護舊有模組。

## 前置條件

- OpenWrt Buildroot 或 SDK 環境
- 基本的 JavaScript / HTML 知識
- 了解 UCI（Unified Configuration Interface）設定系統
- 裝置或虛擬機已安裝 LuCI（`luci` 套件）

## 核心概念

### LuCI 架構（現代 JavaScript 版）

```
瀏覽器端                          路由器端
┌─────────────────┐              ┌──────────────┐
│  LuCI JS 框架    │  ──ubus──▶  │  rpcd/uhttpd  │
│  (luci-base)    │  ◀──JSON──  │  ubus 服務    │
│                 │              │  UCI 存取     │
│  你的 JS 模組    │              │  系統命令     │
└─────────────────┘              └──────────────┘
```

| 元件 | 說明 |
|------|------|
| `luci-base` | 核心框架，提供 UI widget、表單、RPC 呼叫 |
| `LuCI.form` | 表單 API（Map、Section、Option） |
| `LuCI.rpc` | ubus RPC 呼叫封裝 |
| `LuCI.ui` | UI 元件（Textfield、Dropdown、DynamicList 等） |
| `LuCI.network` | 網路設定 helper |
| `rpcd` | 路由器端 RPC 守護程式 |
| `uhttpd` | Web 伺服器，處理靜態文件與 CGI |

### JavaScript vs Lua（選擇指南）

| 面向 | JavaScript（推薦） | Lua（遺留） |
|------|-------------------|------------|
| 適用版本 | 21.02+ | 所有版本 |
| 執行位置 | 瀏覽器端 | 伺服器端 |
| 效能 | 不佔路由器 CPU | 佔用路由器資源 |
| API 文件 | http://openwrt.github.io/luci/jsapi/ | 較少文件 |
| 開發體驗 | 現代、模組化 | MVC、模板引擎 |

## 操作流程

### 1. 建立套件結構

```bash
mkdir -p luci-app-myapp/htdocs/luci-static/resources/view/myapp
mkdir -p luci-app-myapp/root/usr/share/luci/menu.d
mkdir -p luci-app-myapp/root/usr/share/rpcd/acl.d
```

### 2. 定義選單項（Menu Entry）

```json
// root/usr/share/luci/menu.d/luci-app-myapp.json
{
    "admin/services/myapp": {
        "title": "My Application",
        "order": 30,
        "action": {
            "type": "view",
            "path": "myapp/settings"
        },
        "depends": {
            "acl": ["luci-app-myapp"],
            "uci": {"myapp": true}
        }
    }
}
```

### 3. 設定 ACL 權限

```json
// root/usr/share/rpcd/acl.d/luci-app-myapp.json
{
    "luci-app-myapp": {
        "description": "Grant access to My Application",
        "read": {
            "uci": ["myapp"],
            "ubus": {
                "service": ["list"],
                "luci": ["getInitList", "getLocaltime"]
            },
            "file": {
                "/etc/config/myapp": ["read"]
            }
        },
        "write": {
            "uci": ["myapp"],
            "ubus": {
                "luci": ["setInitAction"]
            }
        }
    }
}
```

### 4. 撰寫 JavaScript View

```javascript
// htdocs/luci-static/resources/view/myapp/settings.js
'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require tools.widgets as widgets';

// 自訂 RPC 呼叫（可選）
var callServiceList = rpc.declare({
    object: 'service',
    method: 'list',
    params: ['name'],
    expect: { '': {} }
});

return view.extend({
    // 頁面載入前的資料預取
    load: function() {
        return Promise.all([
            uci.load('myapp'),
            callServiceList('myapp')
        ]);
    },

    // 渲染表單
    render: function(data) {
        var m, s, o;

        // 建立 UCI Map（對應 /etc/config/myapp）
        m = new form.Map('myapp', _('My Application'),
            _('這是 My Application 的設定頁面。'));

        // 建立 Section（對應 config 區塊）
        s = m.section(form.TypedSection, 'settings', _('基本設定'));
        s.anonymous = true;

        // 啟用開關
        o = s.option(form.Flag, 'enabled', _('啟用服務'));
        o.rmempty = false;
        o.default = '0';

        // 監聽埠
        o = s.option(form.Value, 'port', _('監聽埠'));
        o.datatype = 'port';
        o.default = '8080';
        o.placeholder = '8080';

        // 下拉選單
        o = s.option(form.ListValue, 'log_level', _('日誌等級'));
        o.value('error', _('錯誤'));
        o.value('warn', _('警告'));
        o.value('info', _('資訊'));
        o.value('debug', _('除錯'));
        o.default = 'info';

        // 網路介面選擇器
        o = s.option(widgets.DeviceSelect, 'interface', _('綁定介面'));
        o.multiple = false;
        o.noaliases = true;

        // 動態列表
        o = s.option(form.DynamicList, 'allowed_ips', _('允許的 IP'));
        o.datatype = 'ipaddr';

        return m.render();
    }
});
```

### 5. 撰寫 OpenWrt 套件 Makefile

```makefile
# luci-app-myapp/Makefile
include $(TOPDIR)/rules.mk

LUCI_TITLE:=LuCI support for My Application
LUCI_DEPENDS:=+myapp
LUCI_PKGARCH:=all

include ../../luci.mk

# call BuildPackage - OpenWrt 套件建構
# call LuciBuild/... - LuCI 專用建構擴展
$(eval $(call BuildPackage,luci-app-myapp))
```

### 6. 測試開發

```bash
# 編譯
make package/luci-app-myapp/compile V=s

# 部署到裝置
scp bin/packages/*/luci/luci-app-myapp_*.ipk root@192.168.1.1:/tmp/
ssh root@192.168.1.1

# 安裝並重啟 Web 伺服器
opkg install /tmp/luci-app-myapp_*.ipk
/etc/init.d/uhttpd restart
# 或清除瀏覽器快取後重新整理
```

## 範例代碼

### 自訂 CBI View（含狀態顯示）

```javascript
// 帶有服務狀態和控制按鈕的完整頁面
'use strict';
'require view';
'require form';
'require rpc';
'require uci';
'require fs';
'require ui';

var callInitAction = rpc.declare({
    object: 'luci',
    method: 'setInitAction',
    params: ['name', 'action'],
    expect: { result: false }
});

return view.extend({
    load: function() {
        return Promise.all([
            uci.load('myapp'),
            fs.exec('/usr/bin/my-app', ['--version']).catch(function() {
                return { stdout: 'unknown' };
            })
        ]);
    },

    render: function(data) {
        var version = data[1].stdout.trim();
        var m, s, o;

        m = new form.Map('myapp', _('My Application'),
            _('版本: ') + version);

        // 服務控制按鈕
        s = m.section(form.NamedSection, '_control');
        s.render = function() {
            var el = E('div', { 'class': 'cbi-section' }, [
                E('h3', {}, _('服務控制')),
                E('div', {}, [
                    E('button', {
                        'class': 'btn cbi-button-apply',
                        'click': function() {
                            return callInitAction('myapp', 'restart')
                                .then(function() { ui.addNotification(null,
                                    E('p', _('服務已重啟')), 'info'); });
                        }
                    }, _('重啟服務'))
                ])
            ]);
            return el;
        };

        // 設定表單
        s = m.section(form.TypedSection, 'settings');
        s.anonymous = true;

        o = s.option(form.Flag, 'enabled', _('啟用'));
        o.rmempty = false;

        return m.render();
    }
});
```

## 常見錯誤與解法

### 問題：頁面顯示 404 或選單不出現
**原因：** menu.d JSON 格式錯誤或路徑不匹配
**解法：** 確認 `menu.d/*.json` 中的 `path` 與 JS 檔案路徑吻合：`view/myapp/settings` 對應 `resources/view/myapp/settings.js`

### 問題：UCI 設定讀取/寫入失敗
**原因：** ACL 未正確設定
**解法：** 確認 `acl.d/*.json` 包含了所需的 uci/ubus 讀寫權限，並重新登入 LuCI

### 問題：`_()` 翻譯函式不可用
**原因：** 未引入 base 模組
**解法：** `_()` 由 luci-base 全域注入，確認 `'require view'` 在檔案開頭

### 問題：表單資料型別驗證無效
**原因：** datatype 名稱拼寫錯誤
**解法：** 常用 datatype：`port`、`ipaddr`、`ip4addr`、`ip6addr`、`macaddr`、`hostname`、`uinteger`、`range(min,max)`

## 參考來源

- http://openwrt.github.io/luci/jsapi/LuCI.html
- http://openwrt.github.io/luci/jsapi/LuCI.form.html
- https://github.com/openwrt/luci/blob/master/CONTRIBUTING.md
- https://github.com/openwrt/luci/wiki/ModulesHowTo
- https://openwrt.org/docs/guide-developer/luci
