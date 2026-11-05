================================================================================
AC8ProximityFuse v0.0.2 - 《皇牌空战8》玩家对空导弹近炸引信模组
================================================================================

【版本说明 v0.0.2】
1. 四层属性全量同步：
   - 第1层：30 个玩家对空导弹蓝图类 CDO（BP_plwp_*_C）+ 导弹基类 BP_wp_msl_BaseClass_C
   - 第2层：玩家武器难度配置表（/Game/Datatables/Player/DT_WeaponSettings）全难度行
   - 第3层：玩家飞机挂载槽位配置（PlayerWeaponActivator.EquippedWeapons.Configs）
   - 第4层：发射/对象池化时的导弹实时 Actor 实例（OnInitialized / OnCreateWeapon_BP / SpawnedWeapons / ActiveWeapons）
2. 模式1 主动近炸空爆机制（FuseMode = 1）：
   - 监听 BP_wp_msl_BaseClass_C:OnTargetWithinProximity 与在飞玩家导弹实例距离。
   - 当导弹进入 TriggerRadiusMeters（默认 30 米）内时，自动将实例导引角归零强制触发引擎原生脱靶自爆（bShouldDetonateOnMiss），并在日志中输出目标战机爆炸前后血量变化（Target HP: before -> after）。
   - 挂钩 OnWeaponDestroyed 在对象池导弹销毁前自动还原原始导引角与寿命，杜绝污染对象池复用。
3. 修复与增强：
   - 修复 v0.0.1 中 GC 防回收判断假阳性的 Bug，改为按索引写入 ReferencedObjects 并做读回校验。
   - 移除“只升不降”限制，调高或调低参数均可正常写入；将某弹种设为 0 时支持恢复原版值。
   - 真正实装 [F7] 热键：在游戏内按 F7 即可实时重新读取 settings.ini 并立即应用，无需重启游戏。

【配置文件说明 (settings.ini)】
- FuseMode              : 1 = 主动近炸空爆模式（默认推荐）；0 = 仅静态写入属性
- TriggerRadiusMeters   : 近炸触发距离（米，默认 30）
- ExplosionRadiusMeters : 爆炸杀伤半径（米，默认 50）
- AreaDamage            : 范围爆炸伤害（默认 30；若想一发近炸重创敌机可调至 60~100）
- 各弹种开关 (msl/qaam/hvaa/laam/hcaa/hpaa/saam/sasm/2aam/4aam/6aam) : 1=启用，0=原版
================================================================================
