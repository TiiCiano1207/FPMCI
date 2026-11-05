# FPMCI 1.1.4 — 导弹强化

- “导弹引导”更名为“导弹强化”，11 类导弹分别添加近炸增强开关，默认关闭（原版）。SASM 原有空爆能力保留；保存后下次启动生效。
- 安装方案只保留“飞控 + 导弹模块”“仅鼠标飞控”；旧 full 方案按 guidance 读取并迁移，不再加载旧性能、射程、伤害和外观强化。
- 基于用户提供的 AC8ProximityFuse 0.0.2 主动空爆机制适配。近炸模块不访问共享难度表、不写导弹 CDO，只处理本地玩家武器组件登记的已启用实例。参数固定为 30 米触发、50 米爆炸半径、30 范围伤害。
- 临时导引角及寿命在销毁前恢复；爆炸参数保留到销毁/伤害调用结束后再恢复，避免提前取消伤害。初始化前再次处理遗留状态，使用记录隔离旧延迟回调。仍有已启用在飞导弹时继续监测，集合为空停止；取消 F7 热重载。
- 比例引导继续使用 AC8PropNav 2.3.9；原有 13 项引导数值、飞控配置与已有备份保留。原始游戏存档不参与更新。

验证：隔离 Lua 覆盖弹种隔离、原版 SASM、距离边界、本地归属、超过 300 帧飞行、触发后恢复、对象地址复用、延迟回调、地图切换及部分写入回滚；PowerShell 覆盖两种模式与旧 full 迁移；WPF 覆盖 11 个开关保存/恢复、旧配置缺项、非法值、页面更名及两项安装选项。

未启动真实游戏，未确认实际空爆、伤害与所有难度的最终效果。若引擎伤害仍读取共享表，该问题需要实际游戏验证和进一步适配，不能以隔离测试代替验收。

English: Rename the page to Missile Enhancement, add eleven independent next-launch proximity switches defaulting to original behavior, and retire the full-enhancement preset. The adapted fuse changes only locally owned enabled missile instances, never shared DataTables or CDOs. Preserve native PropNav settings; restore pooled instances and invalidate old callbacks. Isolated integration and WPF tests passed. Live detonation and damage acceptance remains pending.
