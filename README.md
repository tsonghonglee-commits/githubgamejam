# Slay the highway / 杀路

使用 **Godot 4.7.2 stable / GDScript** 制作的 Game Off 2026 参赛项目。
当前方向为 **3D 第一人称自动奔跑 + 太刀斩击**。玩家固定横向位置、无法换道，迎击四条敌人跑道与三条仅供飞行怪使用的天空道；包含四档速度、振刀加速、慢动作轨迹斩击和关键部位体素切断。
电脑版 **v0.12.11** 将提速奖励限定为精准振刀，奖励翻倍，最佳时机最高加 34 m/s，速度上限为 60 m/s。长按可架刀挡下一击。

历史 **v0.12.10** 扩大刀鞘强红光的辉光，目标是在可格挡攻击命中前约 0.4 秒达到最亮。按住右键可维持架势，挡下一击后收刀。[Windows 试玩包](builds/Slay-the-highway-v0.12.10-Windows.zip) · [实包检查](builds/held-guard-review/actual-v01210-native/review.json)

历史 **v0.12.9** 在刀鞘双横纹加入振刀提示。有敌人进入可斩范围时红光轻微呼吸，预计可格挡攻击即将命中时亮起强红光。[Windows 试玩包](builds/Slay-the-highway-v0.12.9-Windows.zip) · [实包检查](builds/sheath-alert-review/actual-native/review.json)

历史 **v0.12.8** 恢复 v0.12.4 的轻切、重切和振刀效果。后四系列继续使用手工重制的 Boss 互动建筑与入场。[Windows 试玩包](builds/Slay-the-highway-v0.12.8-Windows.zip) · [验证记录](builds/skill-application-review/vfx-rollback-v0128-final/application-validation.json)

历史 **v0.12.7** 重做后四系列的 Boss 互动建筑。峡谷木门、赛博检修场、风暴海闸和轨道干船坞均取材于现有关卡，建筑与所在路段共享实际材质。[四区原速对照](builds/arena-art-v0127/media/boss-architecture-before-after.mp4) · [实机画面对照](builds/arena-art-v0127/media/boss-architecture-before-after.jpg) · [当时验证记录](builds/skill-application-review/arena-art-v0127-pilot/application-validation.json)

历史 **v0.12.6** 将后四系列 Boss 场地接进实际路段。机关随路肩移动，Boss 通过门位后接回战位。[当时验证报告](builds/skill-application-review/terrain-v0126-verified/application-validation.json)

历史 **v0.12.5** 修正旋翼净空引起的单直升机跳变，恢复水墨宗师的远距跃落。后四区加入场景奇观和 Boss 入场机关，轻切、重切和振刀分别加入独立接触反馈。[当时验证报告](builds/skill-application-review/spectacle-v0125-final/application-validation.json)

历史 **v0.12.4** 重编 35 种怪物和工业运兵船的入场，接入赛博四人实际吊挂和同机回归。[逐怪需求表](docs/MONSTER_ANIMATION_REQUIREMENTS.md) · [当时验证报告](builds/skill-application-review/ink-v0124-final/animation-validation.json)

历史 **v0.12.3** 优化重型切割和场景预建，并调整水墨宗师落地后的屈膝卸力与双剑错拍开锋。固定刀路实包对照中，四重型同斩的切割帧中位从 178.5 ms 降至 162.4 ms，仍有明显长帧。隔离场景构建的 CPU 中位从 925.9 ms 降至 418.2 ms，网格与换段状态一致。[Windows 试玩包](builds/Slay-the-highway-v0.12.3-Windows.zip) · [宗师入场对照](builds/skill-motion-p2/ink-entry-before-after.gif) · [验证报告](builds/skill-application-review/integrated/application-validation.json)

历史 **v0.12.1** 以 GitHub 检查点 v0.11.7 为基础，恢复握柄跟手的自由斩切与当时的战斗表现，保留切割选格、连通判定和网格重建优化。[Windows 试玩包](builds/Slay-the-highway-v0.12.1-Windows.zip) · [自由斩切对照](builds/rollback-cut-native/free-cut-comparison.json) · [重切性能对照](builds/rollback-cut-native/fixed-cut-comparison.json)

历史 **v0.11.7** 加强水墨宗师与星际无畏舰的攻击节奏，重做四个新系列共十个 Boss 的登场。宗师增加可振刀截断的回身次斩，无畏舰改用有炮口预告的四拍炮列。四个系列分别加入入场音色，并配合落地、破浪或刹停播放冲击效果。[Windows 试玩包](builds/Slay-the-highway-v0.11.7-Windows.zip) · [实包入场检查](builds/boss-entry-review-v0117/final-native/review.json) · [战斗对照](builds/boss-pressure-review-v0117/comparison-receipt.json)

历史 **v0.11.6** 让第一系列运输船载着 Boss 从 64m 外飞近，在飞行前 0.5 秒渐显，再全显飞行 1.25 秒到达下降点。顶棚在渐显结束后打开，护卫直接飞入。实包复核了入场、提前释放以及三个出口的死亡交接。[v0.11.6 Windows 包](builds/Slay-the-highway-v0.11.6-Windows.zip) · [当时专项记录](builds/first-series-exit-review-v0116/final-native/review.json)

历史 **v0.11.5** 将第一系列 Boss 和运输船的 1 秒渐显移到开顶前。闭顶时从顶梁间可见运输船，顶梁移开后露出挂载的 Boss。实包已复核入场顺序和水墨、赛博、海洋三个出口。[v0.11.5 Windows 包](builds/Slay-the-highway-v0.11.5-Windows.zip) · [当时专项记录](builds/first-series-exit-review-v0115/final-native/review.json)

历史 **v0.11.4** 修复第一系列 Boss 死亡后天花板突然闭合。展开的天花板随工业场景退出画面。该版使用 1.5 秒同步渐显。用旧版和新版的实际 Windows 包模拟 Boss 死亡，复核了水墨、赛博、海洋三个出口。[v0.11.4 Windows 包](builds/Slay-the-highway-v0.11.4-Windows.zip) · [当时专项记录](builds/first-series-exit-review-v0114/final-native/review.json)

历史 **v0.11.3** 重做第一系列通往水墨、赛博和海洋的三条接引路。工业路面与灯色渐进接到目标区域，各自经过石门、检修廊或海锁。沿用 v0.11.2 更新的海洋浪群与海工平台、赛博检修街区、轨道泊舰与货运外坞，以及26种新怪入场和10个新 Boss 的双机组结构。[v0.11.3 Windows 包](builds/Slay-the-highway-v0.11.3-Windows.zip) · [当时发行检查](builds/release-review-v0113/release-validation.json)

F6 可在局内开关无敌，每次新开一局时默认关闭。[历史 v0.11.1](builds/Slay-the-highway-v0.11.1-Windows.zip)

**v0.11.0** 重制四个新系列的角色，并精修场景与连接桥。每局从第一系列出发，随机经过第二、第三、第四中的两个不同系列，最后迎战第五系列。第一系列保留，作为真实体素造型与战斗演出的质量基准。

本次对照[角色与场景概念](docs/concepts/v0100/README.md)，重做水墨、赛博、海洋机甲、轨道军团的真实可切模型、入场和出招。16种小怪有各自的兵器与攻击；新Boss有可斩结构捷径与独立死亡演出。场景保留四种布局，增加体素瓦层、承托、设备和浪体，沿可见实体桥进入下一地区。独立手机版和旧包保留。本轮细节与技术范围见[DESIGN 第46节](docs/DESIGN.md#46-v0110四系列角色替换与场景精修)。

[启动电脑版 v0.11.0](builds/windows-v0110-final/slay_the_highway.exe)（保留同目录PCK） · [完整 Windows 包](builds/Slay-the-highway-v0.11.0-Windows-Final.zip) · [最终包场景图](builds/scenery-review-v0110-final/) · [角色演出图](builds/visual-review-v0110-final/) · [发行核对](builds/release-review-v0110-final/release-validation.json)。使用 Godot 4.7.2，Windows 导出、29项包内资源、三预设、独立菜单120帧与六文件ZIP已核对。美术、手感与默认显示设置的持续流畅度仍待人工试玩。

最终包以正常输入、正常受伤打通 `1→4→3→5`，剩3格生命；已记录三段实战换关和本路线10个Boss的死亡阶段。[实战记录](builds/release-review-v0110-final/final-playtest-receipt.json)绑定实际PCK。锁屏期间的内部渲染临时关闭同步，仍有长帧，不能当作默认设置的帧率验收。

**历史 v0.10.0 已被否定。** [旧 Windows 包](builds/Slay-the-highway-v0.10.0-Windows.zip)及其[当时发行核对](builds/release-review-v0100/release-validation.json)只保留供回溯；旧模型、动作与关间衔接不作为本版观感完成依据。

上一电脑版试玩为 **v0.9.17：刷怪与多目标真实破坏优化（已导出，交用户试玩）**。复用只读模型与武器网格、缓存完整运输船初始化数据，减少刷怪复制和资源创建；切后只整理脏部件，减少连通遍历、碎块和粒子中的重复工作。真实格、切深、连通判死、可再切残骸与强反馈保留。本轮用户明确允许仅刷怪 / 固定刀路大物体局部耗时及材料保真对照；三对headless局部CPU样本中，四普通生成中位6.814→5.754ms，Boss切割44.475→32.223ms，人工四重型同斩128.327→97.879ms。保真通过但仍有长尖峰，不称整局不卡；未推进AI / 波次或自动通关。见DESIGN第44节。


[启动 v0.9.17](builds/windows-v0917/slay_the_highway.exe)（须保留同目录PCK） · [完整Windows包](builds/Slay-the-highway-v0.9.17-Windows.zip)。46源 / 40镜像、Check / 导出、17资源 / 三预设、菜单120帧及六文件ZIP已核对；旧新实际PCK固定材料 / 单位面83/0、新包生成隔离通过，局部性能和包身份已绑定。未跑AI / 波次 / 通关或整局回放，仍有重型切割长尖峰。

此前为 **v0.9.16：地面远处接近与渐显（已导出，交用户试玩）**。普通怪、肉盾和射手从约75m处起步，身体、武器、亮边与投影同步渐显；额外30m接近在各自刹停 / 落地前完成，之后继续原个性动作，40m外结束入场再按原移动接近32m可斩范围，保留14m跟随纵深。Compatibility使用临时不透明抖动渐显，完成后恢复原材质；飞行入场时长 / 减伤、Boss / 船全程可砍、天空与连爆保留。本轮沿既有授权完成仅三地面入场及材质原生预览，不运行战斗或性能模拟，详见DESIGN第43节。


[启动 v0.9.16](builds/windows-v0916/slay_the_highway.exe)（须保留同目录PCK） · [完整Windows包](builds/Slay-the-highway-v0.9.16-Windows.zip)。最终48张同源演出图 / 46源、Check / 导出、17资源 / 三预设、菜单120帧与六文件ZIP已核对，未运行战斗或性能模拟。

此前为 **v0.9.15：飞行入场减伤与地面远处入场（已导出，交用户试玩）**。根据试玩反馈，五类飞行怪的入场时长缩短三分之一（原时长×2/3），入场期间斩击与爆破的真实材料破坏按25%生效，结束后恢复正常；仍可真实斩断，未加入HP、随机吞刀或无敌。普通怪、肉盾和射手在40m外完成各自入场，随后按原移动接近，进入32m刀切范围后可被玩家斩击；跟随增援仍落后14m。Boss与运兵船按此前特指要求保留投放全程可砍。天空、连爆、原攻击参数与Boss死亡收尾保留，详见DESIGN第42节。本轮仅语法检查、Check / 导出、依赖 / 菜单 / ZIP核对，不运行战斗或性能模拟。

[启动 v0.9.15](builds/windows-v0915/slay_the_highway.exe)（须保留同目录PCK） · [完整Windows包](builds/Slay-the-highway-v0.9.15-Windows.zip)。46源 / 40镜像、Check / 导出、17资源 / 三预设、菜单120帧与六文件ZIP已核对；本轮没有新演出预览、战斗或性能模拟，入场安全性和减伤强度交用户自测。

此前为 **v0.9.14：第一系列 · 吊装投放与个性入场（已导出，交用户试玩）**。现有九怪（含 Boss）统一标记为第一系列。Boss 由约 17m 宽的真实可切运兵船悬吊投放，切断吊臂会提前落下；落地压身、震动、喷尘后展开武装，运输船开钳爬升撤离。五类飞行怪从相机后掠过，在前方近处侧倾转身，再退至各自战位，原四跑道与天空道共用。普通怪滑跪拔刀、肉盾跃落撑锤、射手侧滑扫枪。保留真实切割、天空驻留、弹反连爆与 Boss 死亡驻留后爆破，详见 DESIGN 第 41 节。本轮已获用户单独授权，仅核对入场与死亡演出画面，不运行战斗 / 波次 / 自动通关或性能模拟。

[启动 v0.9.14](builds/windows-v0914/slay_the_highway.exe)（须保留同目录 PCK） · [完整 Windows 包](builds/Slay-the-highway-v0.9.14-Windows.zip) · [Boss 吊装原生动画预览](builds/animation-review-v0914/boss-deployment-v0914.gif)。最终同源195张演出图 / 46源、Check / 导出、17资源依赖、独立菜单启动与六文件ZIP已核对，未运行战斗或性能模拟，观感与实际路线交用户试玩。

此前 **v0.9.13：全怪入场与 Boss 驻留爆破收尾** 的短入场方案已被用户明确否定，保留历史包与原检查范围。九种怪物按体型加入落步、重落、托枪或俯冲拉平的入场动作；五种飞行怪共用相对目标位置的轨迹，兼容原跑道与天空道。Boss 被真实击毁后保持死亡位置和真实残骸，短暂停留、局部失稳，再主爆炸散开，收尾后结算。天空道、弹反连爆、真实部件切割与原攻击参数保留。本轮遵此前约定不跑战斗模拟，Check / 导出、16 资源依赖、独立菜单启动及六文件 ZIP 核对通过，范围见 DESIGN 第 40 节。

[启动 v0.9.13](builds/windows-v0913/slay_the_highway.exe)（须保留同目录 PCK） · [完整 Windows 包](builds/Slay-the-highway-v0.9.13-Windows.zip)。历史包仅供回溯；该版短入场方案已被用户否定。

此前为 **v0.9.12：弹反撞弹与逐级连爆（已导出，交用户试玩）**。弹反弹体能撞爆未弹反的来弹，并用各弹原有爆破范围引燃附近敌弹形成连爆；被引燃弹采用友方爆破归属，能真实破坏敌人材料并清除来弹。保留三条天空道、原四跑道、原弹速与反向 ×1.4、部件切割及 Boss 规则。本轮遵此前约定不跑战斗模拟，Check / 导出、16 资源依赖、独立菜单启动与六文件 ZIP 核对通过，范围见 DESIGN 第 39 节。

[启动 v0.9.12](builds/windows-v0912/slay_the_highway.exe)（须保留同目录 PCK） · [完整 Windows 包](builds/Slay-the-highway-v0.9.12-Windows.zip)。撞弹、连爆的实际难度与视听效果交用户自测。

此前为 **v0.9.11：三条天空道与驻留敌机（已导出，交用户试玩）**。原四跑道继续生成地面怪和飞行怪；另在左 / 中 / 右前上方安排少量巡飞机、双弹舱重机，进场后与玩家保持相对位置并持续射击。首版天空最多同时一架，与普通射手合计最多两名；四横排、高级机型专场及 Boss 入场前安全撤离并清掉天空来源弹。保留 v0.9.10 截击机 / 布雷机自身参数、真实切割与反弹、3C 和 Boss 双堆 / 双护卫。本版遵此前约定不跑战斗模拟，Check / 导出、16 资源依赖、独立菜单启动及六文件 ZIP 核对通过，范围见 DESIGN 第 38 节。

[启动 v0.9.11](builds/windows-v0911/slay_the_highway.exe)（须保留同目录 PCK） · [完整 Windows 包](builds/Slay-the-highway-v0.9.11-Windows.zip)。天空干扰强度、实际画面与手感交用户自测。

此前为 **v0.9.10：恢复截击机与布雷机削弱前参数（已导出，交用户试玩）**。按用户新要求，仅还原两种机型的 v0.9.7 攻击、蓄势、冷却、逼近与三发反馈，取消其额外首次蓄势延迟；保留 v0.9.9 的低频穿插、射手预算、最多一次四横排和 Boss 清场 / 双盾。遵用户前次要求，本版不跑战斗模拟或性能测定，启动与包核对后交其亲玩，见 DESIGN 第 37 节。

[启动 v0.9.10](builds/windows-v0910/slay_the_highway.exe)（须保留同目录 PCK） · [完整 Windows 包](builds/Slay-the-highway-v0.9.10-Windows.zip)。启动和包检查通过，未跑战斗模拟。

此前为 **v0.9.9：回到 v0.9.5 普通布怪基础优化（已导出，交用户试玩）**。普通波次恢复 v0.9.5 的种类序列、跑道轮换和定时流，只在中段一个普通槽安排一次四横排，不循环、不提前塞入开场；截击机和布雷机只少量替换指定射手槽，盾机留在 Boss 段。Boss 沿用 v0.9.8 的安全清场、左右护卫和减压调校。按用户明确要求，本版没有跑战斗模拟；Check、Windows 导出、16 资源依赖、独立菜单启动与六文件包核对通过，难度和手感交用户自测，详见 DESIGN 第 36 节。v0.9.8 保留为未获认可的中间技术检查点，本轮不自动推送。

历史 [v0.9.9 EXE](builds/windows-v099/slay_the_highway.exe) 须与同目录 `.pck` 放在一起；[完整 Windows 包](builds/Slay-the-highway-v0.9.9-Windows.zip) SHA-256 为 `B70EDC8CCB4967CFFB64985AE9BAC13BFE6E9B5C14330C6A5223E9693441AFC2`。本版未做战斗回放或性能测定。

v0.9.8 中间包为 [Windows ZIP](builds/Slay-the-highway-v0.9.8-Windows.zip)，SHA-256 为 `962837017566D4DF305A8A09FD91725220ABEA9B123925AE73A82D941BBD90F3`。44 源、16 依赖、16 份执行凭据与六文件包身份核对完成；旧 `05CE…` 及其全部结果继续仅作归档，不替代 `785A…`。普通波次的否定已记录，用户体验没有验收。

此前为 **v0.9.7 双反应堆 Boss 与新空战敌人（2026-11-08，本机技术复核与试玩包核对完成，用户试玩待评）**。针对 Boss 易被秒和敌种不足的反馈，加入真实双深堆 / 厚甲 / 独立支撑，并新增盾护机、截击机和布雷机。现有九种敌人（含 Boss）、两类六形态障碍；十二式、连续窄刀路、极简 UI 和默认全屏 / 4× MSAA / VSync 保留。最终 `51D1…` 已通过镜像 Check / Windows 导出、15 依赖、原行为 126 / 0、材料 / 反弹 296 / 0、held 53 / 0、编队 80 / 0、Boss 14 / 0、UI 46 / 0 与原生 15 图 / 27 项核对。实际 20 秒 / 60 秒路线加 Boss 均通过并完成六文件包身份核对；两轮仍各有 18 帧超过 50ms，本版未重跑 180 秒，不称无卡顿或用户认可，详见 DESIGN 第 34 节。GitHub 的 `main` / `v0.9.5` 保持 `df8c420`，UI v0.9.6 本地提交为 `a09b0eb`，本轮未自动推送。

历史 v0.9.7 检查点可运行 [v0.9.7 EXE](builds/windows-v097/slay_the_highway.exe)，须与同目录 `.pck` 放在一起；[完整 Windows 包](builds/Slay-the-highway-v0.9.7-Windows.zip) SHA-256 为 `5ADF88E5857D143C4914D177688317C97DD4F20A8A393B8B9E0E85217254E0D4`。40 源、六根文件解压流、14 份执行凭据及 compiled 身份核对见 `builds/release-review-v097/release-validation.json`。

此前为 **v0.9.6 极简 UI 初版（2026-11-08，本机技术复核与试玩包核对完成，用户试玩待评）**。正式英文名为 **Slay the highway**，中文名为 **杀路**。菜单可按住左键划切选项，也可点击或用键盘；主菜单、暂停、结算、设置与操作说明采用统一极简排版。实际 PCK 的 UI / 设置、原生画面、独立启动、20 秒 / 60 秒路线加 Boss 与六文件包已核对，正常回放仍记录到 >50ms 帧；范围见 DESIGN 第 33 节，不称手感或审美已获认可。UI 初版仍在本地 `codex/slay-ui-initial`，GitHub 的 `main` / `v0.9.5` 检查点保持前版。

此前 **v0.9.5 场景与密集破坏修订（2026-11-08，本机技术复核与试玩包核对完成，用户试玩待评）**。四章工业场景、六款真实可切障碍及灯件实体连接已升级。最终 `355B…` 完成实际专项 / 保真、CPU 对照、原生画面 / 回收 / 显示 / EXE、20 秒 / 完整 180 秒路线加 Boss 和六文件包身份核对。完整路线 5 血 / 52 杀、p99 21.264ms，仍有 2 帧超过 50ms；Boss / 密集四目标 CPU 中位约下降 41.24% / 36.76% 仅指 headless 局部对照，不称整局无卡顿或用户验收。补灯前 `1385…` 单独归档，详见 DESIGN 第 32 节。

此前 **v0.9.4 Blade Flux 长斩体素特效（2026-11-08，本地发行包已核对，用户试玩待评）**。96 槽冷白 / 青白刀身体素与分层暖热命中粒子已接入，实际 PCK 的 126 / 0、313 / 0 与长斩专项 53 / 0、GPU 及 basic 20 秒 / mixed 60 秒加 Boss 已核对；姿态、刀路、锁镜头与真实伤害保留。mixed 为 5 血 / 13 杀，仍记录 12 帧超过 50ms，不能称整局无卡顿或主观效果获认可。显示 / 独立 EXE / 14 项依赖已通过，六文件 ZIP / 30 源身份已核对。Check / 导出通过范围为相同资源字节镜像；共享工作区两轮未正常退出及首轮夹具失败保留，见 DESIGN 第 31 节。

**v0.9.3 Retaliation 已保存为可试玩检查点，用户体验待评。** 完整发射速度 ×2/3、原向反射 ×1.4、所有反弹爆点的真实 AoE 及独立视听已核对；最终 PCK 126 / 0 原行为、313 / 0 专项、六组 GPU、basic 20 秒 / mixed 60 秒加 Boss、独立 EXE / 显示 / 14 依赖及六文件 ZIP / 28 源身份通过。mixed 为 5 血 / 13 杀，仍有重型破坏附近长帧，未重跑完整 180 秒，不称整局无卡顿或用户主观力度已认可。旧候选与等待拒收保留，范围见 DESIGN 第 30 节；30 段 / 32m 阴影修复继续保留。

v0.9.2 场景阴影回收修订（2026-11-08，本机局部复核完成，用户试玩待评）：旧实际 v0.9.1 PCK 已复现左下建筑地影被过早回收抽走，冻结路程、原位恢复目标段的 GPU 对照确认了这处原因。本轮将场景环由 23 段扩为 30 段、回收延至身后 32m；最终 PCK 的四章固定视角、正常 20 秒路线加 Boss、显示 / 独立 EXE / 14 项依赖、六文件 ZIP 与 27 项源快照已核对。首轮曾有约 244 / 251ms 长帧，同会话顺序复跑未再现，原因仍未确认；不称整局性能改善或稳定无卡顿。最终包与详细范围见 DESIGN 第 29 节。

v0.9.1 Art & Motion 全套造型 / 动作修订（2026-11-07～08，本机技术复核完成，用户试玩待评）：八类真实可切对象已统一重做 / 打磨；地面怪加入大腿 / 小腿 / 脚掌分段步态，射手采用真实双段支撑臂和实际相机瞄向，实体弹体使用共用分面壳体并提高相对奔跑弹速。真实腕切发现的双手材料粘连已用四格掌背倒角修正，保留断腕禁发弹规则。场景包含装配线、炉区、高架桥和核心长廊；最终实际 PCK 已通过 126 项原行为与 91 项专项、20 秒 / 完整 180 秒路线加 Boss、独立 EXE、显示及 14 项依赖核对，六文件 ZIP 与 26 文件源快照身份一致。完整路线 4 血 / 47 杀，仍采到 14 帧超过 50ms，不能称整局无卡顿；具体数据与边界见 DESIGN 第 28 节。旧候选和 v0.9.0 的计时各自保留，技术结果不代替用户评价。

继续使用 Godot 4.7.2 标准版 / GDScript / Compatibility，保留十二式轻击、刀柄跟手的连续长斩、实际窄刃线、重型逐层切割、可再切残骸及 v0.7.3 三倍热体素喷射。普通怪保留 34×56×22、0.05m、4826 格真实材料；肉盾、射手、Boss、两类飞行器及两类障碍也已制作对应装甲 / 结构轮廓。造型、持武器结构与动作均参与实际切割，最终画面与人工体验仍待评价。默认全屏、4× MSAA 与垂直同步；手机版后续已取消；正式名称已定为 Slay the highway / 杀路，剧情与额外技能仍待定。

v0.8.3 已错开刀镡共面饰片，并统一第一人称武器绘制深度，处理另行确认的近景 SSAO 灰色噪点，保留场景 SSAO / 照明。旧实际 v0.8.2 PCK 与最终 v0.8.3 的 16 × 273 红 / 绿内部采样中，钢色穿出为 1147→0；正式材质另做 16 个微动位姿对照。最终 PCK 完成挥刀 / 长斩 / 振刀固定输入画面、高速空路画面与 basic 20 秒路线加 Boss 真实时间回放，独立 EXE、显示设置和六文件 ZIP 核对通过；这些局部验证不等于完整整局或用户体验验收。

2026-11-07：用户说明上次电脑曾断电关机。重启后本轮初始采样处于约 13% 电池、Intel UHD 渲染状态，旧 v0.8.1 空景默认 VSync 帧间隔中位数约 24ms；用户确认插电后，新启动的旧包恢复使用 RTX 3050 Ti。电源和显卡状态不同的结果分开记录，不将显卡切换算作代码优化收益，也不据此断言上次访问异常或当前卡顿只有一个原因。

v0.8.2 最终源码通过 Check 与 126 项行为检查，实际发行 PCK 完成 speed 60 秒 / basic 20 秒路线加 Boss 两轮真实时间回放，独立 EXE 与实际显示读回通过。同会话旧 / 新 speed 对照中，超过 50ms 的采样帧由 13→1、p99 由 19.310→16.973ms，稳态仍约 16.67ms；截图读回开销包含在内。静态 GPU 时间未改善，不能将本轮局部 CPU 与长帧改善写成整局无卡顿、完整 180 秒负载或用户手感已通过；数据和边界见 DESIGN 第 25 节。

2026-11-06 的 v0.8.1 历史状态：Check 与最终夹具的 126 项行为检查通过，EXE 独立 headless / OpenGL 启动及无画面 `--fast` 逻辑筛查通过；**默认 VSync 的真实时间战斗回放拒收**。这些旧记录和包不改写为后来已通过，详见 DESIGN 第 24 节。

已按用户要求先把 v0.9.5 源码推至公开仓库 `main`，提交为 [df8c420](https://github.com/tsonghonglee-commits/githubgamejam/commit/df8c42099ad78f778b11ba8d8430cb1470f3a425)，[v0.9.5 标签](https://github.com/tsonghonglee-commits/githubgamejam/tree/v0.9.5) 解析到同一提交；索引见 [v0.9.5.json](docs/milestones/v0.9.5.json)。该检查点保留场景、六款障碍、破坏优化与灯件修正，v0.9.6 命名与 UI 在之后的独立分支制作。此前 v0.7.3 提交 [5189b88](https://github.com/tsonghonglee-commits/githubgamejam/commit/5189b88f2ab92b38734fd7c7debaaf97b8131107) 仍保留。

v0.7.3 已通过 Check 与 126 项行为检查；与实际旧 PCK 的同一首断相比，发射量 97→291 颗，实际剩余材料同为 1054 格。已查看首断 / 再切 GPU 画面，实际发行 PCK 完成 speed 60 秒 / basic 20 秒正常路线加 Boss，独立 EXE 启动与显示设置读回通过。量化和完整包校验范围见 DESIGN 第 22 节；粒子数值与回放不代替人工试玩的爽感评价。

v0.7.2 已通过 Check 与 126 项行为检查；96 个重型首轻击样本均真实局部受损且存活，26 例实际输入 / GPU 精度夹具覆盖小划与连续结构切断。实际发行 PCK 已完成 basic / speed 两轮正常 60 秒路线加 Boss 回放，并独立启动 EXE、读回全屏 / 抗锯齿 / 垂直同步设置，范围见 [设计草案第 21 节](docs/DESIGN.md#21-v072-armor-cut-重型逐层切割与体素火花2026-11-05)。回放不代替人工试玩，不代表最终手感或平衡已获认可。

2026-11-05 已将 v0.7.1 记录为可恢复的原型里程碑，索引见 [v0.7.1.json](docs/milestones/v0.7.1.json)，保留原始源码、试玩包与当时缺陷。概念研究与原始四类敌人提案见 [设计草案第 19 / 20 节](docs/DESIGN.md#19-v071-原型里程碑2026-11-05)；第 23 节保留 v0.8.0 Stage 1 的实现和验证，第 24 节记录用户否定后的修订，不能用概念图或旧回放代替本轮实机完成度。

- 赛事：[Game Off 2026](https://itch.io/jam/game-off-2026)
- 主题：**SHIFT**
- 源码：[tsonghonglee-commits/githubgamejam](https://github.com/tsonghonglee-commits/githubgamejam)（公开仓库）
- 游戏页面：待创建 itch.io 项目后补充
- 截止：**2026-12-01 13:37 PST = 2026-12-02 05:37 北京时间**

## 打开项目

1. 使用 Godot **4.7.2 标准版**，在项目管理器导入根目录的 `project.godot`。
2. 打开后按 **F5** 运行主场景。
3. 菜单支持按住左键划过选项，或短点并在同一按钮上松开；也可用 **Tab / 方向键**选项、**Enter** 确认、**Esc** 返回或暂停。v0.9.6 已核对这些输入流程，用户操作手感仍待试玩。

v0.9.1 菜单会先实际绘制敌人 / 弹体 / 爆炸材料并准备首次切口，准备完成后进入游戏；提前按 Enter 会排队开始。准备耗时与正式战斗采样分开记录，完整结果见 DESIGN 第 28 节。

电脑版首次默认全屏、**4× MSAA 抗锯齿**和**垂直同步**，可在设置中调整并保存。当前 [v0.9.6 EXE](builds/windows-v096/slay_the_highway.exe) / [v0.9.6 Windows 完整包](builds/Slay-the-highway-v0.9.6-Windows.zip) 已完成本机技术复核与包校验，EXE 须与同目录 `.pck` 放在一起，具体范围见 DESIGN 第 33 节。此前 [v0.9.5 EXE](builds/windows-v095/githubgamejam.exe) / [v0.9.5 Windows 完整包](builds/SHIFT-CUT-v0.9.5-Windows.zip) 已完成本机技术复核及六文件包校验；EXE 须与同目录 `.pck` 放在一起，本轮范围及残余长帧见 DESIGN 第 32 节。历史 [v0.9.4 EXE](builds/windows-v094/githubgamejam.exe) / [v0.9.4 Windows 完整包](builds/SHIFT-CUT-v0.9.4-Windows.zip) 保留，第 31 节记录其独立范围。历史 [v0.9.3 EXE](builds/windows-v093/githubgamejam.exe) / [v0.9.3 Windows 完整包](builds/SHIFT-CUT-v0.9.3-Windows.zip) 保留，最终身份、旧拒收与限制见 `builds/release-review-v093/release-validation.json` 和第 30 节。历史 [v0.9.2 EXE](builds/windows-v092/githubgamejam.exe) / [v0.9.2 Windows 完整包](builds/SHIFT-CUT-v0.9.2-Windows.zip)、[v0.9.1 EXE](builds/windows-v091/githubgamejam.exe) / [v0.9.1 Windows 完整包](builds/SHIFT-CUT-v0.9.1-Windows.zip) 及更早包亦保留，各版证据分别记录。

v0.9.6 ZIP SHA-256：`561E94A628579C5370C0687FE7A2C07F6F895B682FB3B4D788775F509B6E58CA`。本轮 PCK、36 源、12 份执行凭据、compiled remap 与六文件校验见 `builds/release-review-v096/release-validation.json`。

v0.9.5 ZIP SHA-256：`02B2DB4D74754E192C80488F5C8DF522595E1935D997EA36D72226E1046FB0F8`。完整源 / 包 / 执行凭据及 compiled remap 核对见 `builds/release-review-v095/release-validation.json`。

历史 [v0.8.2 EXE](builds/windows-v082/githubgamejam.exe) 和 [完整 Windows 包](builds/SHIFT-CUT-v0.8.2-Windows.zip) 保留。该版六个根文件的压缩流 SHA 与发行目录一致，运行资源 / 工具 17 文件快照、实际 PCK 身份及包核对见 `builds/release-review-v082/` 和 DESIGN 第 25.5 节；性能结果仍以该版当时的采样范围为准。

历史 [v0.8.1 修订快照 EXE](builds/windows-v081/githubgamejam.exe) 和 [完整快照包](builds/SHIFT-CUT-v0.8.1-Windows.zip) 保留，六个根文件及逐项 SHA 已核对；**不表示正常实时战斗已验收**。模型画面、固定帧场景记录、拒收回放与限制见 DESIGN 第 24 节，源快照和包校验见 `builds/release-review-v081/source-snapshot.json` / `release-validation.json`。

历史 [v0.8.0 Stage 1 EXE](builds/windows-v080-stage1/githubgamejam.exe) 和 [Stage 1 ZIP](builds/SHIFT-CUT-v0.8.0-Stage1-Windows.zip) 保留。该版最终源码曾通过 Check 与 126 项行为检查，实际发行 PCK 完成 speed 60 秒 / basic 20 秒路线加 Boss 两轮正常回放，独立 EXE 启动与显示读回通过，范围见 DESIGN 第 23 节；这些技术检查没有证明观感获用户认可。此前已验证的 [v0.7.3 EXE](builds/windows-v073/githubgamejam.exe) 和 [完整包](builds/SHIFT-CUT-v0.7.3-Windows.zip) 保留；EXE 与 PCK 须放在同一目录。上一版 [v0.7.2 ZIP](builds/SHIFT-CUT-v0.7.2-Windows.zip) 保留原喷射强度；更早的 [v0.7.1 ZIP](builds/SHIFT-CUT-v0.7.1-Windows.zip) 保留旧版重型贯穿与针形火花表现。

文中 `builds/` 下的试玩包、录像与验证记录属于本机产物，未提交到 GitHub；以上包链接在开发电脑上使用。克隆仓库后可用 Godot 4.7.2 运行源码，或按下文命令自行导出 Windows 包。

## 原型操作与验证目标

| 输入 | 行为 |
| --- | --- |
| 鼠标移动 | 常态小幅转头；长斩从当前实体刀姿接管，握点固定在刀柄中央；刀柄领向移动方向、刀尖拖后，实际刃腹留下一条窄切口，镜头 / FOV 和停鼠刀姿不回正 |
| 左键按下 / 连续短按 | 按下立即轻击，十二式大幅过刀、依次衔接且相邻不重复；允许刀身短暂出屏，快速连点不吞刀；不奖励速度 |
| 左键保持或按住拖动 | 进入慢动作轨迹斩击；拖动可立即进入，持续耗速；到最低速度自动收刀 |
| 右键 | 轻按或短时间内精准振刀可提速。长按可维持架势，格挡一击后收刀 |
| Shift 按住 | 提速，第四档封顶；与长斩同时使用仍然净耗速 |
| Esc | 暂停 / 继续 |

为方便单独验证原型，保留以下调试快捷键：

| 输入 | 原型调试功能 |
| --- | --- |
| F2 | 切换练习模式，生命至少保留一格；可用于连续练习切割和振刀 |
| F3 | 游戏进行中直接进入 Boss 测试 |
| F4 | 静止体素切割实验场，保留切割速度资源；再次 F4 重置目标，Enter 返回正常挑战 |
| F5 | 游戏运行中显示 / 隐藏敌人时间与文字调试提示；默认隐藏 |
| F6 | 局内开启或关闭无敌，新一局默认关闭 |

练习模式不代表正式难度。正常验证死亡与通关流程时，先确认练习模式已关闭。

玩家自动前进，不能用 A / D 换道。任意跑道漏过的敌人均会结算伤害，受击只扣生命，不降低速度。
击杀由关键体素部位被实际切断 / 破坏触发，不能用普通血量归零替代切割判定。
本轮先以五格生命、约 180 秒固定路线后接 Boss 为调试目标；这些不是最终平衡数值。
v0.2 调试速度为初始 18、最低 4、最高 60；长斩每实际秒消耗 10，同时按 Shift 时净消耗 8。初始状态可以直接长斩。
切割范围暂为 32m。正常战斗通过敌人武器动作、枪口充能、声音和刀鞘强红光预告攻击，F5 可显示目标状态和时间用于调试。敌人到接敌范围后先蓄势、再挥击并结算伤害，不在跨过距离阈值的瞬间扣血。肉盾左右手先后出招，振刀后有可见的受阻与退身；切断当前攻击所需的手臂可取消该次攻击，并不自动算击杀。
鼠标慢划与快速往返均完整生成实际刃腹接触轨迹，握点本身不充当伤害线，也不会把整根刀扫出的面积当作伤害。松开 / 振刀 / 耗速前的 1px 最后刀路也提交。命中停顿只冻结世界，握点、刀路和实际耗速仍继续更新。
关键结构断开后，大块保留体素数据并可再次切割，正常战斗中迅速掠过镜头；F4 仍保留低速反复切割。Boss 被击毁后先在死亡位置保持约 1.35 世界秒并出现局部失稳，再主爆炸散开约 1.05 世界秒后结算；慢动作、暂停和命中停顿共用世界时间，期间残敌不再攻击，真实残骸仍可切割。
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
| Windows Desktop | `builds/windows-v097/slay_the_highway.exe` 与同目录 `.pck` | v0.9.7 Check / 导出、15 依赖、实际专项 / 原生图、20 秒和 60 秒路线加 Boss、六文件 ZIP 与 compiled 身份已核对；长帧与用户试玩范围见 DESIGN 第 34 节 |
| Web | `builds/web/index.html` 与同目录文件 | 尚未安装 4.7.2 Web 模板 |
| Android | `builds/android/SHIFT-CUT-v0.4.1-Android.apk` | 保留历史 v0.4.1 触屏包与预设；手机版后续已取消，本轮未导出 / 验证 Android |

Web 使用单线程。需要时先在 Godot 的“编辑器 → 管理导出模板”安装 **4.7.2** 对应模板。
三个预设已明确列入主场景、图标及全部原型脚本，共 14 项运行资源；v0.9.1 Windows 实际 PCK 的 14 项均已核对可加载，不代表 Web / Android 已导出运行。以后添加独立资源或脚本时，在各预设的“资源”页补选，并启动导出包核对依赖完整性。
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
