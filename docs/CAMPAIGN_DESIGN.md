# 四关随机路线与系列战斗计划

本文件描述电脑版v0.11.0的路线、编排与战斗合同。v0.10.0的表现已被用户否定，四套新角色已替换；场景保留空间框架继续修改、精修。`campaign_director/encounter_director`只准备不可变数据；`campaign_runtime`负责主场景接线，`series_combat/series_attack_contact`负责实际武器接触与动作窗口，`series_archetypes`委托四个`series_*_rebuilt`库构建真实体素，`series_scenery/effects`负责预建场景与有限演出池。旧`series_model_detail`不进入发行依赖。概念图与原生模型分开核对，技术通过不代表观感或手感验收。独立手机版不在本次改动范围。

## 路线与随机流

每局固定四关：`[1, a, b, 5]`，`a/b` 从第二、第三、第四系列无重复抽取，顺序也随机，共六种路线。开局保留完整 `seed`，同一引擎版本、种子和选项可复现完整计划。

路线和每一关各持独立 `RandomNumberGenerator`，关内角色与跑道也分流。只使用局部 RNG 的 Fisher–Yates 洗牌和抽袋，不调用全局 `seed/randi/randf` 或 `Array.shuffle()`；不会消耗武器、碎块、粒子的全局随机序列。角色袋一轮包含四种职责，下一轮边界也避开相同前导职责；跑道袋避开上一槽的主压跑道，同槽不重复跑道。第一系列稀有四排覆盖全部跑道，属于有清场条件的明确例外。

强度只由本局第几关决定。第二系列如果排在第三关，使用第三关强度；第四系列如果排在第二关，使用第二关强度。系列编号不参与强度等级计算。

| 出场序号 | 时长（Boss前） | 基础槽间隔 | 普通地面上限 | 天空上限 | 总射手上限 | 重型上限 | 威胁上限 |
| --- | --- | --- | --- | --- | --- | --- | --- |
| 1 | 75秒 | 4.3秒 | 3 | 1 | 2 | 1 | 3.6 |
| 2 | 90秒 | 4.0秒 | 3 | 1 | 2 | 1 | 4.2 |
| 3 | 90秒 | 3.7秒 | 3 | 2 | 2 | 1 | 4.8 |
| 4 | 100秒 | 3.4秒 | 3 | 2 | 2 | 1 | 5.4 |

间隔仅有小幅种子扰动。多数槽仍为单体或双体，后两关的对照段才少量尝试第三体；提高节奏与职责组合，而不让所有槽都堆满。普通重型、射手、天空怪和待激活对象共同占预算。实体弹硬上限仍为24，爆炸表现池仍为12。

## 系列职责

这些是出场职责，不是HP或不可切阶段。材料、关键部件、动作与真实刀路由生产敌人实现负责。

| 系列 | melee | heavy | ranged | flying support | Boss |
| --- | --- | --- | --- | --- | --- |
| 1 铸甲军团 | normal，贴身刀兵 | tank，厚甲重击 | ranged，枪线压力 | drone / missile_drone，空域干扰 | boss，真双堆；吊装船与护卫沿用专门流程 |
| 2 墨武宗门 | ink_swordsman，近身剑线 | ink_spear，长兵空间 | ink_talisman，符弹读招 | ink_crane，侧上方牵制 | ink_master |
| 3 霓虹特勤 | cyber_breacher，突进破门 | cyber_riot，盾阵重压 | cyber_sniper，远线预告 | cyber_drone，交叉观察 | 四人特勤组，随后直升机、坦克、炮艇 |
| 4 深海群落 | sea_skimmer，贴地掠行 | sea_crab，甲壳钳击 | sea_eel，轴线弹压 | sea_ray，上空掠袭 | sea_leviathan |
| 5 星际帝国 | empire_lancer，冲锋枪骑 | empire_walker，步行重装 | empire_sentinel，哨戒射线 | empire_fighter，空域截击 | empire_dreadnought |

第一系列目录另保留并预热 `barrier/beam` 的职责资源；首版随机战斗槽使用四类职责和单次高级机专场，暂不安排障碍槽。`interceptor/mine_layer` 每关仅抽一种安排一个专场，不与其他活威胁叠加；另一种也可预热，避免以后新增槽时临场建模板。盾机只进入第一系列Boss专门护卫流程，不进入普通随机槽。

飞行是独立属性。飞行支援可进入原四跑道，也可以安排天空道；非飞行单位绝不进入天空道。高级机首版仍从原道进入专场。天空不是将全部飞行怪迁走的替代层。

## 段落与压力

第一关先四个单种介绍槽，后续关先两个短介绍槽。后续关沿用本关更快间隔、威胁上限与敌人本身性能，不将基础强度退回第一关。介绍后进入轻组合，对照段增加互补职责；收尾确定以重型或射手为主并尝试一个搭档，然后预留6.5秒喘息与Boss转场窗口。

第一系列整关至多一个四横排，只有种子抽中、较后段且前导职责不会连续重复时才成立。四排全为普通刀兵，原延迟 `[0,.12,.64,.76]` 保留，地面预算只在该槽临时放宽为4；它要求清场、撤离天空来源弹并留1.2秒恢复，不能循环或补成高频满排。高级机也要求独占场面。普通跟随单位保持14米纵深与错开攻击延迟，不能把两个前导对象重叠在同一跑道。

`at_seconds` 是关内绝对计划时间。槽被预算挡住时可短等到 `latest_seconds`；过期跳过，不在后续同帧追补。Boss前空槽不会生成敌人，要求消费方安全撤离天空；进入Boss时按原生产清场流程先停旧攻击，再处理旧对象及其来源弹。计划只提供策略，不能靠把演员藏掉、改HP或删真实材料冒充击败。

## Boss阶段

`boss_stages` 的外层是顺序阶段，只有当前阶段全部成员真实结构死亡后才进下一阶段。普通怪预算与Boss专门阶段预算分开，不能将四名小型军官误判成四个重型Boss。

第三系列为：

1. `cyber_captain / cyber_flanker / cyber_suppressor / cyber_spotter` 四人同场可见，最多四单位，轮流获得一个攻击令牌及一个射手令牌；其余做掩护侧移与换位。四人均真死后才转场。
2. `cyber_helicopter` 单体。
3. `cyber_tank` 单体。
4. `cyber_gunship` 单体。

后三个大物不与其他阶段重叠。`ordered=true` 表示攻击轮转；`max_active=1` 的语义通过 `max_active_semantics="attacking"` 明示，存活上限另看 `max_units`，避免把首组实现成四场单挑。其他系列均为一个单Boss阶段。第一系列吊装船与双护卫由原Boss流程负责，目录列出资源但不当成额外通关目标。

## 数据接口

`scripts/campaign_director.gd`：

```gdscript
var run: Dictionary = CampaignDirector.build_run(seed)
# 或持有对象 prepare_run(seed)，再通过 getters 读取。
var route: Array = run.route
var level: Dictionary = run.levels[level_index]
var plans: Array = level.plans
```

`build_run(seed, options={})` 返回：

```text
{schema_version, seed, route:Array[int], levels:Array[Dictionary],
 catalog:Array[String], activation_contract:Dictionary}

level = {series_id, level_index, difficulty_tier, seed, duration,
 duration_seconds, plans, waves, catalog:Array[String], boss_stages,
 boss_stage_policies, budgets, interval_base, intro_slots, rare_four_rows}
```

`plans` 与 `waves` 是同一只读列表的别名；`duration` 与 `duration_seconds` 同值。每个计划保留旧 `id/spawns/sky_spawns/interval/minimum_distance/approach_seconds/distance_bias/hold_until_clear/recovery_seconds` 等字段，增加 `at_seconds/latest_seconds/skip_if_blocked/phase/lead_role/exclusive/retire_sky/budgets/demand`。地面spawn保留 `kind/lane/z_offset/role/fire_delay/attack_delay`；天空spawn另含 `sky_lane`，其lane可供工具读取，生产仍以 `4+sky_lane` 建实际天空索引。

`get_series_definition(id)` 返回只读职责、演员档案和Boss阶段，不预加载几何脚本。`get_route/get_level_plan/get_level_plans/get_catalog` 读取 `prepare_run` 结果。`options.durations` 可给四关时长（各限制45～180秒），`options.planned_speed` 仅写入准备参数，不改实际玩家速度。

`EncounterDirector.plan()` 保留旧版行为。新增 `build_level(series,tier,seed,options={})`；`plan_for_series(series,wave_index,progress,speed,duration=90,tier=1,seed=0)` 是兼容查询便利入口，不能在每帧调用；`progress` 不会令既定槽重抽。

`admission(plan, live_and_reserved={})` 返回 `{allowed,reason,demand}`。统计键为：

```text
ground, sky, shooters, heavy, advanced, threat,
projectiles, projectile_reservation
```

`ground/sky/...` 必须包含当前活威胁及已排入队列的预约。`projectiles` 是实际活弹，`projectile_reservation` 是未激活队列的首轮弹量预约；它只帮助准入，不代替发射时的24弹硬上限。每次先对整槽准入，再一次性预约；出队时将预约原子转换成活体，不能重复把该槽加一遍。高级机与其他活威胁互斥。普通地面上限不是仅对一槽成立的上限，消费方必须使用合计数。

## 预备、激活与性能合同

菜单阶段一次性准备所选整条路线的全部计划，结果每层Array/Dictionary都设为只读。消费方修改队列时复制spawn数据，不能回写共享计划。`run.catalog` 是整局去重预热列表，`level.catalog` 是本关列表，包含所有Boss阶段及第一系列船/护卫。

模型模板、武器primitive和必要材质在开局前预热。生产激活队列每帧最多一名演员；绝对时间过期槽不追补成同帧尖峰。模型准备与演员激活分离，并不等于模型对象已可无成本实例化；导入、首shader、节点分配、入场初始化仍需要实际测量。

不延后伤害、删格、真实连通或同次网格更新，不减材料、切深、24碎片、576/2304粒子或强反馈。DESIGN44已知多大物同步切割仍有明显局部CPU尖峰；此导演通过限制同时重型与提前准备减少可避免叠场，但不能宣称解决真实切割热点、原生帧长或整局卡顿。菜单预热也不能替代原生GPU耗时与多目标切割的后续测量。

新增精度模型的局部归因显示，受损碎片建网格是detach的一项显著成本。当前Debris源先逐字冻结，再只优化重建表示：同一字典的keys/values序列只取一次；在最多200万格的带边框临时byte表中查询六面邻接，过大稀疏边界回原字典查询；大碎块缓存面色与法线后批量提交ArrayMesh，128格以下保留SurfaceTool。原贪心遍历/合并/顶点序列、实际cells、选择bounds和同次立即mesh更新保留，临时数组提交后释放。完整part共享分支及原再切、粒子、动态规则未改。

三次固定生产cut捕获9份单part真实受损碎块，随后只以冻结cells计重建CPU：三个新进程各10次预热、60次AB/BA交替，27个case中位均下降；合并后各case中位改善4.42%～19.73%。墨刃2040格5.083→4.080ms，狙击3693格5.313→4.669ms，哨卫2387格4.261→3.807ms，哨卫盾2258格3.518→3.033ms。三组各194项保真/再切0失败，正式生产源另195项0失败及77项边界0失败；实际数组、单位面、法线、颜色、绕序、bounds、碎块姿态与后续真再切保持。代码块与实测候选逐字相同；去掉优化块和新增缓存字段后，其余整个Debris源与冻结基线逐字一致。

以上仅为单碎块网格重建，不是整个detach/cut或原生帧耗时。墨刃主体max9.806→10.865ms、哨卫主体max8.336→8.961ms、狙击第二块p95 5.206→5.559ms未改善；小型/薄片边界可多3～19μs，也不能称全尺寸都更快。期间可能有并行机器调度干扰，paired中位一致不代替整帧或用户体验验收。单纯bulk和稠密面mask候选没有稳定收益，保留原记录且未采用。汇总 `.local/debris-mesh-v0100/comparison-summary.json` 绑定22项基线/候选/输入/工具/成功产物；未运行AI、波次、通关或GPU。

## 验证边界

`tools/campaign_director_verify.gd` 仅运行纯数据：多个seed的四关路线、六种排列、复现性、嵌套只读、绝对时间边界、职责与跑道重复、每槽预算、活体加队列准入、Boss阶段与预热目录、全局RNG隔离，以及旧plan入口的基础兼容样本。它不实例化main、敌人、网格，不推进AI、战斗、波次、通关或性能回放。

实际是否好读、压力是否合理、队列是否正确预约、四人是否正确轮攻、Boss过渡与真实材料是否一致，仍需各生产实现及相应授权范围内的后续验证。纯数据通过不作上述事项的体验或性能验收。

新增小怪特色战斗接入 `scripts/series_combat.gd`：

| 系列 | 各小怪实际策略 |
| --- | --- |
| 墨武 | 刀客先无伤晃招再反向错拍双斩；长枪先投实体墨槊再近刺；符使发一枚悬停0.65秒后按预存速度出发的实体符；纸鹤按镜面侧掠路线发斜向羽刃。 |
| 特勤 | 破门兵侧跳发三实体buckshot再短冲；盾兵按真实盾铰状态推进重砸；狙击手发实体长钉后跨道向后撤至少4米；侦察机放可切的驻留beacon，由真实存活来源炮口支持两次bolt发射。 |
| 深海 | 鳍刃先下潜再跃刺；重蟹左右螯错拍且逐侧检查真末端；海鳗蛇形侧移并由真实尾9甩出electric_wave；翼鳐发一次按预设固定目标折向的torpedo，反弹后不再折向。 |
| 帝国 | 重步机架四脚、左右真炮口轮换重炮球；枪骑跨道推进突刺，切断独立推进支撑后连续减速且保留矛的可用性；哨卫真实双瓣开盾蓄势发plasma_lance；战机低空来回横扫。 |

以上有弹的混合职责（长枪、破门兵、重步机）也占射手预算，不能因为role仍为heavy/melee而绕过总射手上限。纸鹤、beacon及战机按首轮真实弹量预约3/3/4；所有发射仍受24实体弹硬上限约束。

姿态薄元数据为 `series_attack_variant/series_feint/series_shield_open/series_burrow`，只驱动实际rig/part；`series_behavior` 用于观察。prime/beacon/bend只是实体弹有限状态配置，没有hitscan或追踪改向。buckshot同簇共享 `volley_id`，各节点仍能独立斩切/反射，玩家伤害按同簇去重一次。首次出手的wave_attack_delay在windup或charge共享消费，不能对同一演员延迟两次。

追加hybrid预算后的同一1007种子检查为87,720槽、16项0失败，结果在 `.local/campaign-review-hybrid.json/.log`。这里只运行纯计划数据。新combat已通过Godot4.7.2仅语法解析，未执行攻击、死亡或整局AI；专属策略和物理弹的实际观感、时序仍不作已验收结论。

2026-11-09纯数据记录：1007个种子（包含正负int64边界），87,717个计划槽，16项汇总检查0失败；另覆盖所有系列/出场等级的45秒与180秒时长边界。结果和日志在 `.local/campaign-review-v2.json/.log`，源SHA写入结果。早期lane bag最后一项可能重复前导道的问题已修；最初失败JSON保留在 `.local/campaign-review-first.json`，不以失败文件作通过证据。本轮未运行游戏场景、AI、波次战斗或通关。

## 独立入场姿态与衔接

`SeriesEntryMotion.sample(kind, phase, lane)` 返回 `offset/rotation/opacity/rig/parts/impact_phase`；宗师另含 `flash_step`。这是归一化真实姿态数据，不创建演员、网格、外壳或伤害。`series_combat` 把数据施加到本帧真实rig与现存部件，模型层用 `series_entry_authored` 取消旧通用入场抬臂，再保留实际支撑断裂后的开甲/失衡。小飞行怪仍由原前掠转身flyby负责，天空/原跑道共用。

11种地面小怪分别采用滑跪拔刀、撑杆越步、展符架、侧滑肩压、落盾稳步、跪滑托枪、破水跃刺、侧步双螯落撑、落锁四足、斜推进急刹及落盾展开。前半段额外30米与原5米接近在角色的phase0.30/0.34/0.38结束，渐显到0.42完成；终锚仍为40米，跟随纵深仍为原值。大幅侧向接近也在落撑前结束，既定武器动作继续在原地完成，不以短距离走近替代所有入场。

Boss分别使用宗师双墨步抽剑、四军官不同落姿、直升机倾转稳平、坦克侧身制动、炮艇双舱横滚、海兽破水四足落撑和巨舰下降抬艏。真实root保持直立以兼容碎块地面与根运动补偿，位移/倾转由真实rig和part完成；不改变其入场可砍例外。结束后捕获最后的实体姿态，用0.18世界秒交接收势，避免切换到通用姿态时瞬跳。海兽按原四脚底角补偿最低脚底，属于整体落撑近似，不是多关节脚步IK。

`tools/series_entry_motion_verify.gd` 的最终归一化姿态检查为164项0失败，报告 `.local/series-entry-motion-final.json/.log` 绑定motion、combat和工具SHA。覆盖26kind、七lane、phase0..1的有限刚性变换、渐显单调、合法part编号、终端归零、地面根位置/植足阶段停止、普通fly原分支所有权、各角色采样姿态差异、宗师两次跨道及海兽解析脚底。combat另仅语法解析通过。这里没有实例化敌人、实际网格、GPU、攻击AI、波次或通关；根距离检查也不是实际网格32米净空证明。原生同源入场帧仍需独立核对动作、遮挡、地面接触与可读性，不能将这些数学项称为3A或用户验收。

随后按额外固定姿态范围，用真实26kind体素模型逐格计算世界cube边界：两个镜向、phase0/0.20/0.38/0.58/0.72/0.92/1共364入场姿态，再采676收势交接姿态及52个recover1稳态。实际检查修正了重步机误用外侧足趾导致的10.4cm穿地、侧击军官落地后俯身导致的13.7cm穿地，以及长枪腾跃时靴未随腿转动导致的脚踝脱接。海兽脚底改按0.10m网格真实cube角补偿，runtime摆放高度从−0.4改为−0.055，消除原静止位置34.5cm穿地。独立复核又发现坦克履带悬浮30cm，以及鳍刃/重蟹各悬浮7cm；生产新增纯函数 `_ground_root_y`，对应根高为−0.355/−0.125/−0.125，Boss从runtime读取实际摆位。坦克制动和鳍刃落地俯身另按真实履带/滑鳍底补rig升降，保留空中位移与真实部件动作，避免以原悬浮抵消俯身穿地。

最终52组0阈值报警、exit0且日志干净，报告 `.local/series-entry-geometry-final-post-perf.json/.log` 与 `.local/series-entry-geometry-receipt.json` 绑定7源、工具、逐字提取的生产Main动作/flyby/地面根高函数及runtime摆位函数，并补绑当前Debris依赖；这是DDA/碎块优化后的重新执行，源前后及当前一致，全部占用字节保持。此前 `series-entry-geometry-final` 是成功执行 `series-entry-geometry-grounding-first` 的逐字节相同别名，仅作历史记录，不计作另一次执行或当前源的最终凭据。11地面小怪采样前沿最近−38.62144m；entry1与recover1另设甲板上下6cm判据，所有非飞行稳态最低均为−0.055m（浮点差<5nm）。落撑动画最低为重蟹−0.07926m，比甲板低2.43cm，小于一格，仍需原生帧判断是否可见。长枪原脚踝邻接格心距回到0.05m。末端0.999→1最大格心位移2.577mm来自原飞行路径，收势首帧最大1.97μm，地面收势逐帧最大77.94mm。脚踝邻接中心距只用于查大脱接，不能代替全部动态关节的视觉验证。首轮遇到并行场景编辑的缺helper编译日志、采用统一Boss根高度的中间记录、实际生产高度失败及工具提取代码匹配失败均保留，不作最终证据；没有推进AI、攻击、波次、通关或GPU。

## 官方动作参考与原创改编

以下只研究四个官方主来源，核对日期2026-11-09。左侧是来源能够支持的事实；右侧是本项目的设计推导，尚不等于生产实现或已验收行为。不引入来源游戏的人物、品牌标志、模型、动作捕获、音效、贴图或界面资产。

| 主来源与已核实事实 | 对本项目可迁移的机制 | 本项目应原创的落点与边界 |
| --- | --- | --- |
| S-GAME创始人在PlayStation官方博客说明，甄子丹担任《影之刃零》创意顾问，并参与角色面部及动作捕捉，目标包含功夫电影的表现。[S-GAME开发者文章，2026-08-17](https://blog.playstation.com/2026/08/17/phantom-blade-zero-state-of-play-dives-deep-into-combat-and-the-wulin-world/) | 从完整招式的蓄势、接触、借力、收势关系做动作；武器、身体重心和后续攻防应互相解释，而非只加拖影或加快摆动。此处为设计推导，官方文章不提供其引擎实现。 | 墨武系列分别原创剑的短促折返、长兵伸收、符术准备与鹤形转翼的轮廓和节拍。身体、刀与真实命中几何同相位；成功格挡后从实体当前姿态接收势，不能播放一条与伤害无关的假刀路。仅借鉴动作设计方法，不复刻其角色或招式序列。 |
| AC6官方入门指南强调观察敌人、三维战场、装备部件职责，以及冲击累积造成踉跄后制造进攻机会。[Bandai Namco官方指南，2023-08-23](https://armoredcore6.bn-ent.net/en/information/?p=22) | 敌人外形先交代武器与承重职责，玩家据此选择先处理发射部件或暴露结构；大物需要可辨认的进攻窗口。官方指南没有说明本项目这种真实体素肢解，不能将它当作肢解功能的依据。 | 帝国与机械系列用真实可切武器架、关节支撑和核心连接体现职责；切断实际端口才禁对应射击，承重真断才改变状态。窗口可由动作自然暴露或部件脱落产生，不引入冲击条、HP扣除或“规定刀数后才可伤”的替代门槛。 |
| 《只狼》发行商官方机制页说明，攻击与临命中格挡共同破坏姿态，部分交锋需要连续格挡；成功格挡可带来反斩机会。[Activision官方机制说明，2019-03-22](https://support.activision.com/fi/sekiro/articles/sekiro-shadows-die-twice-game-mechanics) | 攻防节拍有可学习的承诺：识别蓄势、回应一段明确连招，再抓取收势窗口。与永远等冷却的循环相比，玩家正确回应应及时改变下一拍。 | 墨武Boss用少量清楚的连击段与呼吸间隔支持本项目已有振刀/真实回击；切断武器后当前及后续相关攻击都必须失效。这里不移植姿态条、忍杀标记或锁定相机，也不把成功振刀改成自动扣血；伤害继续来自实际刀路与材料连通。 |
| Cyberpunk2077的2.0官方说明介绍随通缉等级变化的追击单位与行为、路障、AV投放重装特勤，以及车辆战斗和可破坏轮胎。[CDPR官方更新说明，2023-09-21](https://www.cyberpunk.net/en/news/49060/update-2-0) | 追杀段落通过出动方式与威胁职责升级，而非把所有最强单位同帧堆出；投放、掩护、追击和大型载具可以组成不同节拍。 | 霓虹特勤四名原创军官同场迂回、共享一个进攻令牌，四人均真死后才依次进入原创直升机、坦克、炮艇段。四人职责和这套阶段顺序是用户需求与本项目设计，不是官方资料所述固定编队。轮胎/动力/武器架应由真实材料与连通变化反馈，不能仅换一张受损贴图。 |

优先落地检查点是“能读招且真响应”：各角色至少一个稳定蓄势轮廓、清楚接触点、有限收势窗口；断武器/端口后所有发射与近战伤害分支都读真实存活状态；四人令牌在蓄势、出手、弹体到达和收势间移交，不能只让开始蓄势错开却令弹体同刻叠伤。其次才增加招式数量与演出层。以上是静态设计要求，不能用目录/计划的纯数据通过替代相应动作与材料验证。
