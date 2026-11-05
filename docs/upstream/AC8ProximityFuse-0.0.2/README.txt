================================================================================
AC8ProximityFuse v0.0.2 - Player Air-to-Air Missile Proximity Fuse Mod
《皇牌空战8》全玩家对空导弹近炸引信模组
================================================================================

[ENGLISH]
1. OVERVIEW
   AC8ProximityFuse brings genuine proximity fusing (airburst detonation on miss)
   to ALL 11 player air-to-air missile types in ACE COMBAT 8 (MSL, QAAM, HVAA,
   LAAM, HCAA, HPAA, SAAM, SASM, 2AAM, 4AAM, 6AAM).
   
   Unlike naive CDO-only edits, this mod features a 4-tier data sync (CDOs, 
   DT_WeaponSettings, Player Weapon Activator configs, and live projectile instances)
   combined with an active Closest-Point-of-Approach (CPA) seeker-miss trigger.
   When your missile closes within the configurable trigger radius (default: 30m),
   it forces an instant proximity airburst that damages the enemy even on near-misses!

2. INSTALLATION
   - Prerequisite: UE4SS (v3.0.1 or compatible experimental release) installed.
   - Extract the `AC8ProximityFuse` folder into your game's UE4SS Mods directory:
     `<ACE COMBAT 8>\Game\Binaries\Win64\ue4ss\Mods\AC8ProximityFuse`
   - Ensure the mod is enabled in `<ACE COMBAT 8>\Game\Binaries\Win64\ue4ss\Mods\mods.txt`:
     AC8ProximityFuse : 1
   - (Optional) Verify that `enabled.txt` exists inside the mod folder.

3. CONFIGURATION & HOT-RELOAD (settings.ini)
   - FuseMode              : 1 = Active Mode 1 CPA Airburst (Default, recommended)
                             0 = Passive property write only
   - TriggerRadiusMeters   : Proximity detonation distance in meters (Default: 30)
   - ExplosionRadiusMeters : Blast radius in meters (Default: 50)
   - AreaDamage            : Explosion blast damage (Default: 30)
   - Weapon Toggles        : Set msl, qaam, hvaa, laam, etc. to 1 (Enabled) or 0 (Vanilla)
   - In-Game Hot-Reload    : Press [F7] at any time during gameplay to immediately
                             reload settings.ini without restarting the game!

4. LOGS & TELEMETRY
   - Check `AC8ProximityFuse.log` inside the mod folder to view real-time proximity
     trigger events and actual target HP delta (e.g., Target HP: 75.0 -> 0.0).

--------------------------------------------------------------------------------

[中文说明]
1. 模组简介
   AC8ProximityFuse 为《皇牌空战8》中玩家全部 11 种空对空导弹（MSL、QAAM、
   HVAA、LAAM、HCAA、HPAA、SAAM、SASM、2AAM、4AAM、6AAM）赋予真正的近炸引信
   （近距擦肩自爆）。
   
   本模组采用“四层属性全量同步（蓝图 CDO + DT_WeaponSettings 难度表 + 飞机挂载
   配置 + 实时发射实例）+ 模式 1 主动最近点（CPA）导引脱靶空爆机制”。
   当导弹掠过敌机进入设定感应半径（默认 30 米）内时，自动在离目标最近点凌空自爆，
   即便未直接命中机身，也能利用大范围爆炸破片击落或重创敌机！

2. 安装方法
   - 前提：已安装 UE4SS 框架。
   - 将 `AC8ProximityFuse` 文件夹解压并放置到游戏 UE4SS 模组目录下：
     `<游戏根目录>\Game\Binaries\Win64\ue4ss\Mods\AC8ProximityFuse`
   - 打开 `<游戏根目录>\Game\Binaries\Win64\ue4ss\Mods\mods.txt`，确认存在以下配置行：
     AC8ProximityFuse : 1
   - （可选）确保模组文件夹内存在 `enabled.txt`。

3. 配置与实时热重载 (settings.ini)
   - FuseMode              : 1 = 模式 1 主动近炸空爆（默认推荐）；0 = 仅静态属性写入
   - TriggerRadiusMeters   : 近炸触发距离（米，默认: 30）
   - ExplosionRadiusMeters : 爆炸杀伤半径（米，默认: 50）
   - AreaDamage            : 范围爆炸伤害（默认: 30）
   - 弹种开关              : 可对 msl、qaam、hvaa、laam 等弹种单独设为 1 (启用) 或 0 (原版)
   - 游戏内热重载          : 在游戏中随时修改 settings.ini 并按键盘 [F7] 键，即可立即
                             重新加载配置，无需重启游戏！

4. 运行日志与扣血遥测
   - 模组目录下的 `AC8ProximityFuse.log` 会实时记录每一次近炸触发事件及敌机在
     爆炸前后的真实扣血遥测数据（例如：Target HP: 75.0 -> 0.0 | Detonated=true）。
================================================================================
