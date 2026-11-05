# Game Off 2026 — SHIFT

使用 **Godot 4.7.2 stable / GDScript** 制作的 Game Off 2026 参赛项目。
当前方向为 **3D 第一人称自动奔跑 + 太刀斩击**。玩家固定横向位置、无法换道，迎击四条敌人跑道；包含四档速度、振刀加速、慢动作轨迹斩击和关键部位体素切断。
当前工程为 **v0.7.3 Voxel Blast 电脑版：三倍体素喷射**。每次热体素发射量为 v0.7.2 的三倍，初速度参数 ×1.8，喷流扇面与纵深扩大、阻尼降低。主体仍是有厚度、硬面差和三维翻滚的暖白 / 金橙方块。保留重型逐层切割、十二式轻击、真实窄刃线、连续长斩、残骸再切和一次计分；默认全屏、4× MSAA 与垂直同步。手机版停止后续工作，游戏名称未定。

v0.7.3 已通过 Check 与 126 项行为检查；与实际旧 PCK 的同一首断相比，发射量 97→291 颗，实际剩余材料同为 1054 格。已查看首断 / 再切 GPU 画面，实际发行 PCK 完成 speed 60 秒 / basic 20 秒正常路线加 Boss，独立 EXE 启动与显示设置读回通过。量化和完整包校验范围见 DESIGN 第 22 节；粒子数值与回放不代替人工试玩的爽感评价。

v0.7.2 已通过 Check 与 126 项行为检查；96 个重型首轻击样本均真实局部受损且存活，26 例实际输入 / GPU 精度夹具覆盖小划与连续结构切断。实际发行 PCK 已完成 basic / speed 两轮正常 60 秒路线加 Boss 回放，并独立启动 EXE、读回全屏 / 抗锯齿 / 垂直同步设置，范围见 [设计草案第 21 节](docs/DESIGN.md#21-v072-armor-cut-重型逐层切割与体素火花2026-11-05)。回放不代替人工试玩，不代表最终手感或平衡已获认可。

2026-11-05 已将 v0.7.1 记录为可恢复的原型里程碑，索引见 [v0.7.1.json](docs/milestones/v0.7.1.json)，保留原始源码、试玩包与当时缺陷。最终渲染和四类敌人重设计仍见 [设计草案第 19 / 20 节](docs/DESIGN.md#19-v071-原型里程碑2026-11-05)；当前先修复原型，再做视觉样片。概念草图尚未实现，具体视觉风格仍待定。

- 赛事：[Game Off 2026](https://itch.io/jam/game-off-2026)
- 主题：**SHIFT**
- 源码：[tsonghonglee-commits/githubgamejam](https://github.com/tsonghonglee-commits/githubgamejam)（公开仓库）
- 游戏页面：待创建 itch.io 项目后补充
- 截止：**2026-12-01 13:37 PST = 2026-12-02 05:37 北京时间**

## 打开项目

1. 使用 Godot **4.7.2 标准版**，在项目管理器导入根目录的 `project.godot`。
2. 打开后按 **F5** 运行主场景。
3. 在开始界面按 **Enter** 开始；死亡后可按 **Enter** 重开。

电脑版默认全屏，保留 **4× MSAA 抗锯齿**和**垂直同步**。当前可运行 [v0.7.3 EXE](builds/windows-v073/githubgamejam.exe)，完整包为 [v0.7.3 ZIP](builds/SHIFT-CUT-v0.7.3-Windows.zip)，EXE 与 PCK 须放在同一目录。上一版 [v0.7.2 ZIP](builds/SHIFT-CUT-v0.7.2-Windows.zip) 保留原喷射强度；更早的 [v0.7.1 ZIP](builds/SHIFT-CUT-v0.7.1-Windows.zip) 保留旧版重型贯穿与针形火花表现。

文中 `builds/` 下的试玩包、录像与验证记录属于本机产物，未提交到 GitHub；以上包链接在开发电脑上使用。克隆仓库后可用 Godot 4.7.2 运行源码，或按下文命令自行导出 Windows 包。

## 原型操作与验证目标

| 输入 | 行为 |
| --- | --- |
| 鼠标移动 | 常态小幅转头；长斩从当前实体刀姿接管，握点固定在刀柄中央；刀柄领向移动方向、刀尖拖后，实际刃腹留下一条窄切口，镜头 / FOV 和停鼠刀姿不回正 |
| 左键按下 / 连续短按 | 按下立即轻击，十二式大幅过刀、依次衔接且相邻不重复；允许刀身短暂出屏，快速连点不吞刀；不奖励速度 |
| 左键保持或按住拖动 | 进入慢动作轨迹斩击；拖动可立即进入，持续耗速；到最低速度自动收刀 |
| 右键短按 | 振刀；同一短窗口可挡多道同步攻击，每次振刀只奖励一次速度 |
| Shift 按住 | 提速，第四档封顶；与长斩同时使用仍然净耗速 |
| Esc | 暂停 / 继续 |

为方便单独验证原型，保留以下调试快捷键：

| 输入 | 原型调试功能 |
| --- | --- |
| F2 | 切换练习模式，生命至少保留一格；可用于连续练习切割和振刀 |
| F3 | 游戏进行中直接进入 Boss 测试 |
| F4 | 静止体素切割实验场，保留切割速度资源；再次 F4 重置目标，Enter 返回正常挑战 |
| F5 | 游戏运行中显示 / 隐藏敌人时间与文字调试提示；默认隐藏 |

练习模式不代表正式难度。正常验证死亡与通关流程时，先确认练习模式已关闭。

玩家自动前进，不能用 A / D 换道。任意跑道漏过的敌人均会结算伤害，受击只扣生命，不降低速度。
击杀由关键体素部位被实际切断 / 破坏触发，不能用普通血量归零替代切割判定。
本轮先以五格生命、约 180 秒固定路线后接 Boss 为调试目标；这些不是最终平衡数值。
v0.2 调试速度为初始 18、最低 4、最高 60；长斩每实际秒消耗 10，同时按 Shift 时净消耗 8。初始状态可以直接长斩。
切割范围暂为 32m。正常战斗通过敌人武器动作、枪口充能与声音预告攻击，临近命中时仅补充小型危险图标；F5 可显示目标状态和时间用于调试。敌人到接敌范围后先蓄势、再挥击并结算伤害，不在跨过距离阈值的瞬间扣血。肉盾左右手先后出招，振刀后有可见的受阻与退身；切断当前攻击所需的手臂可取消该次攻击，并不自动算击杀。
鼠标慢划与快速往返均完整生成实际刃腹接触轨迹，握点本身不充当伤害线，也不会把整根刀扫出的面积当作伤害。松开 / 振刀 / 耗速前的 1px 最后刀路也提交。命中停顿只冻结世界，握点、刀路和实际耗速仍继续更新。
关键结构断开后，大块保留体素数据并可再次切割，正常战斗中迅速掠过镜头；F4 仍保留低速反复切割。Boss 被切断后保留约 2.4 实际秒收尾，再结算通关，期间残敌不再攻击。
首发验证 Windows，Web 导出与最终美术随后验证。

渲染器采用 **Compatibility**，便于之后提供浏览器试玩版；后续按 3D 第一人称方向开发。

## 本机快捷操作

本机 Godot 路径保存在被 Git 忽略的 `.local/godot.psd1`。
在仓库目录使用 PowerShell：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\godot.ps1 -Task Editor
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\godot.ps1 -Task Run
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\godot.ps1 -Task Check
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\godot.ps1 -Task Verify
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\godot.ps1 -Task ExportWindows
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\godot.ps1 -Task ExportWeb
powershell -NoProfile -ExecutionPolicy Bypass -File .\tools\godot.ps1 -Task ExportAndroid
```

换电脑后可以设置环境变量 `GODOT4` 为 4.7.2 可执行文件的完整路径，或自行创建 `.local/godot.psd1`：

```powershell
@{ Executable = 'D:\Tools\Godot\Godot_v4.7.2-stable_win64_console.exe' }
```

`Check` 会导入项目并短暂启动主场景，检查资源导入和脚本错误。
默认开发分支为 `main`；源码、场景、资源导入设置和 `.uid` 文件应一起提交。

v0.2 已在 Godot 4.7.2 通过 **54 项自动行为检查**，并使用实际 InputEvent 路径复测镜头保持、慢速鼠标输入、快速往返、按下普攻、振刀以及最后刀路提交。
另以 `tools/feel_replay.gd` 进行了三组真实时间输入回放：初始状态长按、侧视后长斩和 Boss 交战。前后画面与观察报告保存在本机 `builds/feel-review/`。
这些结果用于核对具体行为，不能证明主观手感、正式难度或持续渲染帧率已达标。详细前后对比见 [设计草案](docs/DESIGN.md) 与 [参赛清单](docs/JAM_CHECKLIST.md)。

v0.3 新增 `tools/normal_combat_replay.gd`，通过真实时间的鼠标 / 按键事件，从正常路线开始回放 basic、speed、mixed 三种攻防策略；关闭练习保护和静止实验场，不直接调用伤害或切割。回放会记录生命、攻防事件、敌人动作阶段、输入与截图。可缩短正常路线时长来覆盖 Boss，但这不等于完整 180 秒流程通关；控制器读取可见目标和动作状态，也不等于人工玩家判断。

```powershell
& $env:GODOT4 --path . --script tools/normal_combat_replay.gd -- --combat-round=mixed --route-duration=60 --run-label=mixed-realtime
```

命令需先设置 `GODOT4`。默认结果目录为 `builds/normal-combat/`；`--fast` 仅用于行为筛查，不能替代有实际画面与真实时间的战斗回放。

v0.3 已通过 Godot 4.7.2 Check 与 **68 项行为回归**。最终三轮 GPU 真实时间回放均关闭练习 / 实验场：basic 60 秒路线 5 血 15 杀，speed 60 秒路线 5 血 15 杀，mixed 完整 180 秒路线 5 血 57 杀，均经历 Boss 两次出招后通关。mixed 另实际完成同一肉盾左右手两击的振刀后才击杀。日志、输入记录、源文件校验值及动作截图位于本机 `builds/combat-review-v03/`；结果不等于人工玩家对难度或手感的评价。

v0.3 Windows release 曾完成导出与独立启动，历史包为 `builds/SHIFT-CUT-v0.3-Windows.zip`。具体缺点、修复与各轮数据见 [设计草案第 11 节](docs/DESIGN.md#11-v03-动作与正常战斗复核2026-11-03)。

v0.4 已通过 Godot 4.7.2 Check 与 **78 项行为回归**；另完成三轮本版 GPU 正常输入回放：basic 60 秒 15 杀、speed 60 秒 15 杀、mixed 完整 180 秒 57 杀，均关闭练习 / 实验场并通关。B / C 的握点及刃端连续投影误差均小于 0.01px；斩断、120 / 300 / 550ms 后续画面已实际检查，确认残块迎面掠过。报告与源文件校验值位于 `builds/combat-review-v04/`。回放不等于人工手感认可；完整过程与边界见 [设计草案第 12 节](docs/DESIGN.md#12-v04-握柄斩击与迎面破碎复核2026-11-04)。

历史回退版 v0.7.1 可直接运行 **[githubgamejam.exe](builds/windows-v071/githubgamejam.exe)**，完整包为 **[SHIFT-CUT-v0.7.1-Windows.zip](builds/SHIFT-CUT-v0.7.1-Windows.zip)**，窗口标题含 **Spark Surge v0.7.1**；独立启动、实际 PCK 攻防与显示设置已验证，包包含操作说明与许可。后续定位的重型贯穿 / 火花形态问题见第 21 节，不反写旧版验收记录。

v0.7.0 及更早版本保留为历史记录，不能代替本轮验收。v0.7.0 可启动 **[githubgamejam.exe](builds/windows-v070/githubgamejam.exe)**，窗口标题含 **Rush v0.7.0**；独立 EXE 在发行目录中的 headless / OpenGL 启动通过。历史试玩包为 **[SHIFT-CUT-v0.7.0-Windows-Fullscreen.zip](builds/SHIFT-CUT-v0.7.0-Windows-Fullscreen.zip)**，包含 EXE、PCK、操作说明与许可；旧窗口版 ZIP 也保留。

v0.4.2 Check、83 项回归与两个 60 秒正常路线输入回放通过。相同有效接触手势对照真实 v0.3 / v0.4 历史包：修订版恢复 v0.3 的局部擦伤和窄腰切结果，准确腰切保留 1054/1122 格、4 大块，v0.4 同手势会擦掉全部 1122 格。定点精度图 / 报告位于 `builds/slash-precision-review/`，正常回放位于 `builds/combat-review-v042/`。这些证据用于确认具体缺陷修复，不代替用户对跟手感的判断。

v0.5.0 采用相同 74 个真实输入事件录制新旧连续动作，实际拒收并改进首稿的竖刀抖动 / 过急起手，继续修复模式跳变、收刀等待及刀面剔除。最终演示为 `builds/weapon-animation-review/v050-final/v050-final.mp4`。91 项行为回归覆盖具体规则，最后一次渲染修复后 Check 与全部逐帧运动一致对照通过。另完成 basic / speed 两轮 60 秒正常路线、mixed 完整 180 秒路线，各经过 Boss 两次出招后通关；日志与画面在 `builds/combat-review-v050-final/`。Windows 独立 EXE 的 headless 与 OpenGL 启动均验证无脚本 / 资源错误。动作参考、被拒稿与实际边界见 [设计草案第 15 节](docs/DESIGN.md#15-v050-太刀动作参考与实现2026-11-04)；这些结果不代表已经达到 3A 或用户认可手感。

v0.6.0 十二式、快速连按、刀柄领先及切口彩粒通过对应行为与实际画面复核；最终约 14 秒演示为 `builds/combo-cut-review/v060-final/v060-final.mp4`。已修向上拖刀时顶部速度条遮柄，保留速度 / 档位文字。另做两轮正常 60 秒路线加 Boss 回放，覆盖全部十二式和高速长斩，记录在 `builds/combat-review-v060/`；它们不代表本版完整 180 秒流程或人工手感认可。Windows release 已独立启动，具体范围见 [设计草案第 16 节](docs/DESIGN.md#16-v060-十二式刀柄领刀与彩色体素2026-11-04)。

v0.7.0 已阅读官方开发资料，并实际查看 Ghostrunner、Neon White 官方实机片段及《合金装备崛起：复仇》官方预告的火花造型。首录因主切过短、刀面暗和火花太淡被拒收，随后调整动作时序 / 展面，并修复 Compatibility 的 unshaded 火花未输出热色亮度的问题。最终 Check、118 项行为检查与 verbose 干净退出通过；20.07 秒连续演示为 [v070-final.mp4](builds/rush-review-v070/final-hot/v070-final.mp4)，包含十二式、38 次即时出刀、八向握点、18 / 60 速度流动和真实切口 / 再切。录制前后源码一致；固定帧录像不作性能测量。实际 PCK 在隔离发行目录完成 basic / speed 两轮正常 60 秒路线加 Boss 回放，分别 5 血 / 15 杀、5 血 / 14 杀，均经过 Boss 两次出招后通关。官方来源、被拒稿、回放数据与验证边界见 [设计草案第 17 节](docs/DESIGN.md#17-v070-大幅挥斩奔跑流动与金属火花2026-11-04)，这些证据不代表人工手感认可。

v0.7.1 将首次真实结构切断单独标记为 `sever`，每敌人仅触发一次较强喷发；擦伤和再切保持不同强度，切口源、真实残块、一次计分及有限粒子池不变。参数、实际画面和验证范围见 [设计草案第 18 节](docs/DESIGN.md#18-v071-spark-surge-斩断火花强化2026-11-05)。本轮未改长斩输入或伤害几何，未新增第三方素材。

旧版的 37 项功能检查和 `builds/SHIFT-CUT-prototype-20261103-Windows.zip` 保留为历史记录；它们遗漏了多项真实输入缺陷，不作为 v0.2 或 v0.3 的验收依据。
v0.2 已完成 Windows release 导出和独立包启动检查，试玩包为 `builds/SHIFT-CUT-v0.2-Windows.zip`。运行后窗口标题应包含 `Slice Lab v0.2`。

行为检查脚本为 `tools/prototype_verify.gd`。需要复查时，可使用本机 Godot 4.7.2 执行：

```powershell
& $env:GODOT4 --headless --path . --script tools/prototype_verify.gd -- --verify-prototype
```

上述命令需先设置 `GODOT4`；也可直接使用 `tools/godot.ps1 -Task Verify` 读取本机配置并运行行为检查。

## 导出

已预设以下目标，导出文件保存在不会提交到 Git 的 `builds/` 中：

| 预设 | 输出 | 当前验证状态 |
| --- | --- | --- |
| Windows Desktop | `builds/windows-v073/githubgamejam.exe` 与同目录 `.pck` | v0.7.3 release 验证范围见 DESIGN 第 22 节；v0.7.2 及更早发行记录保留 |
| Web | `builds/web/index.html` 与同目录文件 | 尚未安装 4.7.2 Web 模板 |
| Android | `builds/android/SHIFT-CUT-v0.4.1-Android.apk` | 本轮配置标准 APK 导出与触屏操作 |

Web 使用单线程。需要时先在 Godot 的“编辑器 → 管理导出模板”安装 **4.7.2** 对应模板。
三个预设已明确列入主场景、图标及全部原型脚本；以后添加独立资源或脚本时，在各预设的“资源”页补选，并启动导出包核对依赖完整性。
上传 itch.io 时将 Web 导出目录内的全部文件压缩为 ZIP，确保 `index.html` 位于 ZIP 根目录。
Windows 包也需要包含同目录的 `.pck` 文件，不能只发 `.exe`。

## Android 触屏试玩（v0.4.1）

此为历史记录。根据用户后续要求，当前只继续电脑版斩击修复，不再为本轮更新 APK。

手机横屏游玩，点击画面开始 / 重开。左下按住“提速”相当于 Shift，“普攻”和“振刀”为独立按钮；右侧空白拖动小幅转头。按住右下“斩击”并拖动这根手指操刀，抬起收刀；可以另一根手指同时提速或振刀。握点仍在刀柄，有限刀刃扫掠参与切割。顶部按钮或系统返回键暂停；切到后台时自动暂停并清空触点。

手机 HUD 将速度条移至顶部，按钮与中央敌人分开，保留多点触控与安全区。实际 Android 关闭主光阴影、缩短远裁面并限制 60fps；桌面模式继续保留原画面设置。`--touch-preview` 可在桌面查看触控界面。

安装包为 **[SHIFT-CUT-v0.4.1-Android.apk](builds/android/SHIFT-CUT-v0.4.1-Android.apk)**，约 86.5MB，传到手机后直接打开安装。APK 使用本机调试签名，包含 ARMv7 / ARM64 / x86_64；密钥和本机 SDK / Java 路径留在本机设置中。

已通过 Godot 4.7.2 Check、78 项原有行为回归、24 项真实触控事件检查，以及 APK v2 / v3 签名与包内触控脚本依赖校验。实际查看了 1280×720、1600×720 窗口的手机预览画面；宽屏保留 16:9 游戏画面和侧边留白，触控坐标换算正常。截图位于 `builds/mobile-review-v041/`。未连接实体手机、没有现成模拟器镜像，尚未完成 Android 设备安装 / 启动和实体手机帧率验证。

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
