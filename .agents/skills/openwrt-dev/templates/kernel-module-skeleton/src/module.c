/* ============================================================
 * 核心模組骨架 — 範例原始碼
 * ============================================================
 * 使用說明：
 *   1. 將 {{MOD_NAME}} 替換為模組名稱
 *   2. 在 init/exit 函式中加入你的邏輯
 *   3. 適用核心版本：5.15+
 * ============================================================ */

#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/init.h>

MODULE_LICENSE("GPL");
MODULE_AUTHOR("{{YOUR_NAME}}");
MODULE_DESCRIPTION("{{MOD_DESCRIPTION}}");
MODULE_VERSION("1.0");

static int __init mod_init(void)
{
    pr_info("{{MOD_NAME}}: 模組已載入\n");
    /* 在此初始化你的功能 */
    return 0;
}

static void __exit mod_exit(void)
{
    pr_info("{{MOD_NAME}}: 模組已卸載\n");
    /* 在此cleanup */
}

module_init(mod_init);
module_exit(mod_exit);
