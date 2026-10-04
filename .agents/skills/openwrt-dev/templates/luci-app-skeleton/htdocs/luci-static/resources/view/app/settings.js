// ============================================================
// LuCI App 骨架 — 主設定頁面 JavaScript
// ============================================================
// 使用說明：
//   1. 將 {{APP_NAME}} 替換為你的應用名稱（如 myapp）
//   2. 將 {{APP_TITLE}} 替換為顯示標題（如 "我的應用程式"）
//   3. 將 {{UCI_CONFIG}} 替換為 UCI 設定名稱
//   4. 檔案路徑: htdocs/luci-static/resources/view/{{APP_NAME}}/settings.js
//   5. 適用版本：OpenWrt 21.02+（LuCI JavaScript API）
// ============================================================

'use strict';
'require view';
'require form';
'require uci';
'require rpc';
'require tools.widgets as widgets';

return view.extend({
    load: function() {
        return Promise.all([
            uci.load('{{UCI_CONFIG}}')
        ]);
    },

    render: function(data) {
        var m, s, o;

        m = new form.Map('{{UCI_CONFIG}}', _('{{APP_TITLE}}'),
            _('{{APP_TITLE}} 的設定頁面。'));

        // ===== 基本設定 Section =====
        s = m.section(form.TypedSection, 'settings', _('基本設定'));
        s.anonymous = true;

        o = s.option(form.Flag, 'enabled', _('啟用服務'));
        o.rmempty = false;
        o.default = '0';

        // 在此新增更多選項...
        // o = s.option(form.Value, 'port', _('監聽埠'));
        // o.datatype = 'port';
        // o.default = '8080';

        return m.render();
    }
});
