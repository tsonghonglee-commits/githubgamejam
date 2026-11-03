# Game Off 2026 — SHIFT

使用 **Godot 4.7.2 stable / GDScript** 制作的 Game Off 2026 参赛项目。
目前是已验证可启动的项目骨架；游戏名称、玩法和对 SHIFT 的诠释待确定。

- 赛事：[Game Off 2026](https://itch.io/jam/game-off-2026)
- 主题：**SHIFT**
- 源码：[tsonghonglee-commits/githubgamejam](https://github.com/tsonghonglee-commits/githubgamejam)（公开仓库）
- 游戏页面：待创建 itch.io 项目后补充
- 截止：**2026-12-01 13:37 PST = 2026-12-02 05:37 北京时间**

## 打开项目

1. 使用 Godot **4.7.2 标准版**，在项目管理器导入根目录的 `project.godot`。
2. 打开后按 **F6** 运行当前场景，或按 **F5** 运行主场景。
3. 初始页面显示赛事和主题；这只是开发起点。

渲染器采用 **Compatibility**，便于之后提供浏览器试玩版；当前不预设 2D / 3D 玩法。

## 本机快捷操作

本机 Godot 路径保存在被 Git 忽略的 `.local/godot.psd1`。
在仓库目录使用 PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\godot.ps1 -Task Editor
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\godot.ps1 -Task Run
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\godot.ps1 -Task Check
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\godot.ps1 -Task ExportWindows
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\godot.ps1 -Task ExportWeb
```

换电脑后可以设置环境变量 `GODOT4` 为 4.7.2 可执行文件的完整路径，或自行创建 `.local/godot.psd1`：

```powershell
@{ Executable = 'D:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }
```

`Check` 会导入项目并短暂启动主场景，检查资源导入和脚本错误。
默认开发分支为 `main`；源码、场景、资源导入设置和 `.uid` 文件应一起提交。

初始化验证已通过：Godot 4.7.2 导入、主场景启动、Windows release 导出与导出包启动。

## 导出

已预设以下目标，导出文件保存在不会提交到 Git 的 `builds/` 中：

| 预设 | 输出 | 初始化时的本机状态 |
| --- | --- | --- |
| Windows Desktop | `builds/windows/githubgamejam.exe` 与同目录 `.pck` | 4.7.2 模板已安装 |
| Web | `builds/web/index.html` 与同目录文件 | 尚未安装 4.7.2 Web 模板 |

Web 使用单线程。需要时先在 Godot 的“编辑器 → 管理导出模板”安装 **4.7.2** 对应模板。
两个预设按主场景及其依赖导出；以后添加动态加载的独立资源时，在导出预设的“资源”页补选。
上传 itch.io 时将 Web 导出目录内的全部文件压缩为 ZIP，确保 `index.html` 位于 ZIP 根目录。
Windows 包也需要包含同目录的 `.pck` 文件，不能只发 `.exe`。

## 目录

```text
project.godot        项目设置
scenes/             场景
scripts/            GDScript
assets/             图像、音频、字体
docs/               设计和参赛清单（不打包进游戏）
tools/              本机启动、检查、导出工具（不打包进游戏）
builds/             本地导出产物（不上传源码仓库）
```

## 参赛和许可

参赛步骤、当前状态见 [docs/JAM_CHECKLIST.md](docs/JAM_CHECKLIST.md)。
玩法方案记录在 [docs/DESIGN.md](docs/DESIGN.md)，素材来源记录在 [CREDITS.md](CREDITS.md)。

原创代码采用 [MIT License](LICENSE)。第三方素材须保留其原有许可，并记录来源和署名。
MIT 是本项目的许可选择；赛事页面没有指定必须使用哪一种开源许可证。

参考：[Godot 版本控制说明](https://docs.godotengine.org/en/stable/tutorials/best_practices/version_control_systems.html)、[Web 导出说明](https://docs.godotengine.org/en/stable/tutorials/export/exporting_for_web.html)。
