# 幫我除錯編譯錯誤

## 使用時機

當 OpenWrt 原始碼建構（`make`）失敗，或套件編譯出現錯誤時使用此提示詞。適用於 Buildroot 全量編譯、SDK 套件編譯、以及 ImageBuilder 映像產生的情境。

## 提示詞模板

---

我在編譯 OpenWrt 時遇到錯誤，請幫我診斷和修復：

- **OpenWrt 版本**：[如 23.05.3 / main branch snapshot]
- **目標平台**：[如 x86/64、mt7621、ath79]
- **操作指令**：[如 `make -j$(nproc) V=s`、`make package/xxx/compile V=s`]
- **建構方式**：[Buildroot / SDK / ImageBuilder]

**完整錯誤訊息**（最後 50 行 log）：
```
[在此貼上錯誤訊息]
```

**我已經嘗試過**：
- [列出你做過的排查步驟]

請幫我：
1. 分析錯誤根本原因
2. 提供具體的修復步驟（含指令）
3. 說明如何避免此類錯誤
4. 如果是上游 bug，說明如何提交 patch

---

## 期望輸出

- 錯誤根因分析（一段話）
- 具體修復指令（step-by-step）
- 預防建議

## 範例對話

**User**: 我在編譯 OpenWrt 23.05 for mt7621 時，`make package/luci/compile V=s` 出現以下錯誤：

```
Package/luci-base/compile missing
collect2: error: ld returned 1 exit status
make[3]: *** [Makefile:123: jshn.o] Error 1
```

我已經跑過 `make clean` 但沒用。

**Assistant**: 這個錯誤通常是 toolchain 不完整或 staging_dir 損壞所致。以下是診斷步驟：

**1. 確認 toolchain 狀態**
```bash
# 檢查 staging_dir 是否完整
ls staging_dir/toolchain-*/bin/
# 應看到 mipsel-openwrt-linux-musl-gcc 等工具
```

**2. 清理並重建有問題的依賴**
```bash
# 清理 jshn 的建構目錄
make package/libjson-c/clean V=s
make package/libjson-c/compile V=s

# 再重新編譯 luci
make package/luci/compile V=s
```

**3. 如果仍失敗，完整重建 toolchain**
```bash
make toolchain/clean
make toolchain/install V=s
# 然後重新編譯
make package/luci/compile V=s
```

**預防建議**：
- 不要在 build 過程中手動修改 staging_dir
- 使用 `make -j$(nproc)` 時，偶爾的並行競爭問題可用 `make -j1 V=s` 單核驗證
- 定期 `git pull && ./scripts/feeds update -a && ./scripts/feeds install -a`
