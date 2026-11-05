# FPMCI 1.1.7

本版汇总自公开版 1.1.2 以来的 1.1.3–1.1.7 更新。

- 接入 AC8PropNav 2.3.9 DLL，保留已有的 13 项比例引导设置。
- 导弹页面改为“导弹强化”；移除完整强化安装方案，保留“飞控 + 导弹模块”和“仅鼠标飞控”。
- 11 类弹种可分别启用近炸，并修改触发距离、爆炸半径和范围伤害。默认关闭，SASM 原版空爆保留；近炸仅修改受管理的玩家导弹实例，不写共享表或默认对象。
- 补齐经 AC8 数据库核对的战役基础直击伤害参考；SASM 参考为直击 50、爆炸半径 50 米、范围伤害 30，不把历史距离字段当作实际触发距离。
- 统一自由观察与操控圈的 FOV 输入换算；手动注视目标时保留鼠标飞控；平滑衔接镜头回正、缩放恢复及外部相机位置。
- 启动或检查时遇到前一会话恢复/整理占锁，最多等待 60 秒再继续，并重新检查会话、残留和游戏进程；超时给出明确中文提示。

下载 FPMCI-1.1.7.zip 与 SHA256 校验文件。退出旧会话并完成恢复后，解压到游戏目录之外的新文件夹，运行 AC8Workbench.exe，设置游戏/Steam 路径及安装方案，再更新 Steam 启动选项。仅用于离线单人。个人设置、存档副本、会话记录和历史归档不包含在完整包中。

验证：完整包、所有归档文件 SHA256 和 ZIP CRC 检查；WPF 设置/界面测试、10 项原生输入与相机隔离测试、Lua 近炸及注视状态测试、会话锁和 GUI 恢复场景测试通过。没有自动进行真实游戏空爆、伤害或镜头手感验收，不将隔离测试等同于游戏内验证。AC8PropNav DLL 的源码未随上游文件提供；来源、版本和哈希保留在 docs/upstream。

## English

This release includes the cumulative changes from 1.1.3 through 1.1.7 since public release 1.1.2.

- Integrate AC8PropNav 2.3.9 while retaining the existing 13 guidance settings.
- Replace the full-enhancement preset with two installation choices: flight control with missile modules, or flight control only.
- Add eleven independent proximity-fuse switches and per-type trigger distance, blast radius and area damage. Defaults remain off; stock SASM airburst is preserved. The fuse adaptation changes managed player-missile instances only, with no shared-table or default-object writes.
- Complete campaign base direct-hit damage references from AC8 Database; distinguish SASM direct-hit damage 50, blast radius 50 m and area damage 30.
- Match free-look input to the flight ring's FOV projection, retain mouse flight during manual target focus, and smooth camera/optical-zoom return.
- Wait up to 60 seconds for previous session cleanup/maintenance, then refresh session, residual and game-process state before continuing.

Download the full ZIP and its SHA256 file. Finish the old session first, extract to a new folder outside the game directory, run AC8Workbench.exe, configure game/Steam paths and update Steam launch options. Offline single-player only. The full package excludes personal settings, save backups, sessions and historical archives.

Package checks, ZIP CRC and per-file SHA256 checks passed, together with WPF settings/UI, ten native input/camera suites, Lua fuse/focus tests and isolated session-lock/GUI recovery tests. Live-game detonation, damage and camera handling remain unverified by automated testing. The upstream PropNav binary's source was not supplied; provenance is retained under docs/upstream.
