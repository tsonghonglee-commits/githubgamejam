# 项目协作约定

- 与用户使用简体中文沟通。先读 README.md、docs/DESIGN.md 和 docs/JAM_CHECKLIST.md。
- 固定使用本机 Godot 4.7.2 stable 标准版和 GDScript。不要自行换引擎版本或引入 C#。
- 本机可执行文件从 `.local/godot.psd1` 或 `GODOT4` 读取；不要把本机路径和凭据写进跟踪文件。
- 目前只建立了工程骨架，游戏名称、类型和核心玩法尚未确定。先遵循用户后续创意。
- 保持项目简单，先完成一个核心机制和一段可玩流程。Compatibility 渲染器支持后续 Web 导出。
- 场景放 scenes/，脚本放 scripts/，素材放 assets/。采用 snake_case 文件名；GDScript 使用 Tab 缩进。
- 保留并提交 Godot 生成的 `.uid` 和 `.import` 文件；不要提交 `.godot/`、导出产物、密钥或 `.local/`。
- 引入第三方素材前核对许可，更新 CREDITS.md；不要擅自把用户已有素材改成 MIT。
- 修改场景或脚本后运行 tools/godot.ps1 的 Check。涉及导出时验证对应导出预设。
- 导出预设仅包含主场景、图标及其依赖；添加动态加载且无法自动识别的资源时，更新两个预设的 export_files。
- GitHub 仓库须保持公开。不要强制推送或覆盖用户修改。提交游戏到 itch.io 与推送源码是两个独立步骤。
- 官方截止：2026-12-01 13:37 PST，即 2026-12-02 05:37 Asia/Shanghai。
