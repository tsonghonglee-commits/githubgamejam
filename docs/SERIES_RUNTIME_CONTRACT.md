# 多系列制作接口（电脑版 v0.11.0）

Godot 4.7.2 standard / GDScript。只改本电脑版工程；独立 mobile 工程不动。既有 v0.9.17 与被否定的v0.10.0包保留。一局路线 `[1,a,b,5]`，a/b 从2/3/4无重复抽两个。四个新系列的模型、动作由独立`series_ink/cyber/sea/empire_rebuilt`库负责，旧detail库不再参与生产。

## 所有新kind

- 2：ink_swordsman / ink_spear / ink_talisman / ink_crane；Boss ink_master。
- 3：cyber_breacher / cyber_riot / cyber_sniper / cyber_drone；Boss四人同场 cyber_captain / cyber_flanker / cyber_suppressor / cyber_spotter（一个攻击令牌），之后依次 cyber_helicopter / cyber_tank / cyber_gunship。
- 4：sea_skimmer / sea_crab / sea_eel / sea_ray；Boss sea_leviathan。
- 5：empire_walker / empire_lancer / empire_sentinel / empire_fighter；Boss empire_dreadnought。

小怪角色依序 melee/heavy/ranged/support，飞行与role独立，empire前两项为heavy/melee。S2黑白灰红水墨武侠；S3黑甲少量霓虹战术追杀；S4原创海洋机甲，巨浪跃出；S5原创轨道军团与巨大舰船。

## 模型接口

`series_archetypes.gd` static supports(kind), info(kind), dimensions(kind), build(enemy), classify_part(kind,point), sample_pose(kind,action,phase,age,lane,integrity), emitters(kind), sample_entry(kind,p,lane=0)。

info含 series:int,role:melee/heavy/ranged/support,flying,boss,armored,label,entry_duration,behavior,approach_speed,shot_kind。dimensions返回 dimensions:Vector3i/cell:float。sample_pose返回rig:Transform3D,parts:Dictionary[int,Transform3D]。action为entry/run/windup/strike/charge/fire/recover/death。

VoxelEnemy薄适配所有调用；公开 get_series_integrity_state() 返回 vulnerable,active_supports,total_supports,core_world,name,support_active,relay_intact,world_points。只在configure与真实cut commit缓存连通，逐帧只变换缓存点。PackedByte tags共8bit，特殊bits仅8/16/32/64/128；PART_COUNT10。

Boss一律真实CORE+ANCHOR断开判死，头不是假致死。普通保留HEAD/CORE/ANCHOR。仍可磨穿厚甲杀死；额外速杀靠真支撑切断后真实part开合/倾覆露核心：宗师双护腕剑匣、队长中继、直升机外露尾支旋翼、坦克双履带、炮艇双升力舱、海兽四腿、巨舰3外露电容支架。不能HP/固定刀数/自动假删甲/无敌门。

新Boss真死时可保留最大真实主体在body，其他真实分离块沿旧规则detach。支持dead set_action('death',p)只改现存rig/part，不补格或复原部件。死亡风格：墨散朱印/战术电火/失控坠机/海兽倾覆水汽/巨舰分段殉爆。

## 场景接口

新Node管理器 series_scenery.gd：configure(game,road_segments), begin_transition(series_id), force_series(id), update(sim_dt,run_distance), is_transitioning(),transition_ready(),get_current_series()。

四theme各24种10m布局，96个预建共享Mesh；战斗中不创建场景几何，DeckReceiver可换共享材质。旧工业section_roots、IndustrialBackdrop、直挂root远景MultiMesh、speed_flow_batches与forge_lights仅系列1显示，不能误隐藏camera/敌人/HUD。tile元信息scenery_series_id供main旧_set_route_section尊重。过渡经过224m实体开放连接桥，下一片区域在前方提前出现，旧区域从身后离开；空间裁剪维护桥两端，不用浓雾或整体透明度换景。准备菜单遮挡层后先提交所有布局及裁剪材质。不得改SSAO或武器深度。

## 导演与主程序

campaign_director.gd已落：static build_run(seed)->只读{seed,route,levels,catalog}; level={series_id,level_index,difficulty_tier,duration,plans,catalog,boss_stages,boss_stage_policies}。plan为兼容原Encounter格式+at_seconds/latest_seconds/demand/budgets/exclusive。admission按活体+待激活预约；一帧最多激活一个预热actor，过期槽跳过而不追补。Root负责campaign_runtime/main/series_combat/effects与打包。

用户随后明确授权可见窗口、正常受伤的战斗模拟，禁止无敌。静态材料/刀路、定点演出、资源包、完整常规输入路线分开记录。当前机器旧新实际PCK都出现VSync异常，关闭同步的临时诊断须明确标注，不持久化设置或修改发行默认值；锁屏期间只进行引擎内部验证，不声称桌面可见检查。不得把局部CPU、离线画面或诊断刷新率声称为默认实时性能验收。
