# FPMCI 1.1.5 — 每弹种近炸参数

- 每个弹种开启近炸增强后，可独立修改触发距离（1–200 米）、爆炸半径（1–500 米）、范围伤害（1–500），最多三位小数。关闭后保留数值并收起编辑区，保存后下次启动生效。
- 旧版只有 11 个开关的 ProximityFuse.ini 仍可读取；缺少的数值使用原有默认 30 米／50 米／30。首次保存写入完整配置，更新安装本身保留个人配置原文。
- 根据 AC8 数据库（Steam build 26002268）补齐 11 类弹种的战役单枚基础直击伤害，在“范围伤害”后显示；未计零件和目标伤害倍率，标准导弹剧情难度另注 56。
- 页面顶部仅保留原版自带空爆的 SASM 参考：直击伤害 50／50 米爆炸半径／30 范围伤害。数据库未公布实际近炸触发距离，因此移除界面的“距离字段 1 米”；历史原始字段保留供追溯。
- QAAM 0.4、SAAM 0.1、剧情 0.2、简单 0.1 的原版比例引导参考与数据库一致。其余弹种未公开该字段，保留原有已收录基线。来源及难度/模式例外见 docs/VANILLA-FUSE-REFERENCE.json；未进行当前游戏版本的实机伤害验证。
- 保持实例级处理，不写共享难度表和导弹默认对象；不改变比例引导或飞控算法。默认数值和个人开关保留，新增参数支持现有备份、恢复与配置合并。

验证：Lua 隔离测试覆盖不同弹种参数、米/厘米与平方距离换算、边界、原版开关、恢复及旧回调；PowerShell 覆盖旧配置与新序列化；WPF 覆盖展开/收起、数值保留、非法值阻止保存、独立保存与恢复。未进行真实游戏空爆和伤害实测。

English: Add independent trigger radius, blast radius and area damage to each enabled missile type. Retain values while disabled, migrate legacy switch-only settings using the previous defaults, and apply on next launch. Complete all eleven campaign base direct-hit references from AC8 Database build 26002268; note MSL story damage 56. Retain SASM blast radius 50 m and area damage 30, add direct-hit damage 50, and remove the unverified actual-trigger implication of the historical 1 m field conversion. Keep source history and personal settings. Instance-only operation remains unchanged. Isolated Lua, PowerShell and WPF tests passed; live damage/detonation remains untested.
