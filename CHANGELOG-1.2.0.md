# FPMCI 1.2.0

本版汇总公开版 1.1.7 以来的更新。[查看当前项目首页的版本摘要](https://github.com/TiiCiano1207/FPMCI#120-更新--changes)。

## 敌方 AI 增强

- 合并 Ace Pilots (complete) 与 Ace Pilots Branched，在工作台左侧「敌方AI增强」专页管理启停、预设和自定义选项。游戏内快捷键已关闭，设置在下次启动游戏时生效。
- 「关闭」「全员 5 级」「强化 2」「强化 3」「强化 4」「极限」一次应用一组参数，之后可以逐项调整飞行员等级、机动权重、机体性能、攻击与防御、作用范围和 AI 行为脚本。悬停可查看中文说明，包括高等级和低等级飞行员常选的机动。
- 打开「允许使用热焰弹」后，输入每架飞机由 MOD 主动触发的累计释放上限。默认 9 次，输入 0 表示不限。

## 增强 HUD

- 「常用设置」提供增强 HUD 总开关和一个「第三人称 HUD」子开关。开启第三人称 HUD 后，追尾视角会显示俯仰刻度、航向带和自动 EEGS。默认触发距离为 1800 米，选中的空中目标进入该范围时，弧圈和弹道线会替换原机炮瞄准圈。

## 工作台

- 「模组管理」内的「附加 MOD」可以导入 ZIP 或文件夹、切换启停和移到备份。可拖动 MOD 行，也可用「上移」「下移」按钮排序。再次启动时，已启用的 MOD 按列表从上到下加载，MOD 自带的 Pak 和 IoStore 资源随会话部署。
- 「保存设置」后保留当前滚动位置，便于继续调整本页的其他选项。「安装说明」入口位于「开始游戏」旁边。
- 「保存飞行记录」默认关闭，开启后于下次启动保存 FE 和 Shadow 的 CSV 数据。启动日志与会话恢复所需的存档备份仍会保留。

## 安装

结束旧会话并等工作台恢复文件后，将完整包解压到游戏目录外的新文件夹。运行 AC8Workbench.exe，重新选择游戏位置、Steam 程序和安装方案，保存后按提示设置 Steam 启动选项。完整包适用于工作台管理的离线单人会话。

## English

This release covers the changes since public version 1.1.7.

- The workbench merges Ace Pilots (complete) and Ace Pilots Branched into the Enemy AI Enhancement sidebar page. Enable or configure it before launching. Its in-game hotkeys are disabled, and settings apply on the next launch.
- Six presets apply a set of values at once. Pilot rank, maneuver weights, aircraft performance, combat behavior, scope and AI scripts can then be adjusted individually. Hover over a control for its Chinese description.
- Enabling flares reveals the cumulative limit per aircraft for releases triggered by the mod. The default is 9. Enter 0 for unlimited releases.
- Common Settings provides the Enhanced HUD master switch and a Third-Person HUD toggle. The chase view gains a pitch ladder, a heading tape and automatic EEGS. When the selected airborne target enters the default 1,800 m range, EEGS replaces the stock gun reticle with an arc and ballistic guide lines.
- Additional Mods can import ZIP files or folders, toggle mods and move them to backup. Drag rows or use Move Up and Move Down. On the next launch, enabled mods load from top to bottom and their bundled Pak and IoStore files deploy with the session.
- Saving keeps the current scroll position. The installation guide sits next to Start Game. Save Flight Records is off by default and saves FE and Shadow flight data as CSV files on the next launch when enabled. Launch logs and saves needed for session recovery are still retained.

Finish the previous session and let the workbench restore its files. Extract the full ZIP to a new folder outside the game directory, run AC8Workbench.exe, select the game and Steam paths and installation mode, then follow the Steam launch instructions. Use the full package for workbench-managed offline single-player sessions.

第三方作者、上游项目和许可见 [Third-party notices](https://github.com/TiiCiano1207/FPMCI/blob/main/THIRD_PARTY_NOTICES.md)。
