# 第一人称鼠标操控整合 / First-Person Mouse Control Integration (FPMCI) 1.1.1

## 中文
- 再次启动时，先通过现有归属检查和备份流程恢复有记录的上次会话，避免旧会话直接阻挡启动；未知文件仍不自动处理。
- 会话监控改为独立隐藏进程，保存输出、错误和阶段日志。模拟终止启动父进程后，监控仍可完成；此前两次监控中断的具体触发者无法从现有日志确定。
- 正常完成的会话及恢复备份保留最近 3 组；失败、未完成及活动记录不自动删除。确认完成的旧历史备份会按规则整理。
- 相同的已完成备份二进制/存档内容使用同盘硬链接共享空间。不再复制完整运行目录，仅保留诊断数据；不再每次复制 Replay 录像存档，原始游戏存档不变。
- 修复包保留个人设置及游戏载荷，界面版本更新至 1.1.1。

验证：隔离的启动恢复、保留数量、异常与活动保护、去重及父进程终止测试通过。未进行真实游戏启动/退出实测，游戏版本兼容性原有实测限制仍保留。

## English
- Resume recorded stale sessions through existing ownership and backup checks before launching. Unknown files remain blocked.
- Run the session monitor in a separate hidden worker with persistent output, error and lifecycle logs. A simulated parent-process termination no longer stops the worker. The exact trigger of the historical monitor terminations remains unknown.
- Keep the latest 3 completed session/archive pairs. Preserve active, interrupted and failed records. Recognized completed historical backups are pruned under this policy.
- Share identical completed binary/save backup contents using same-volume hard links. Keep diagnostic inputs instead of another full runtime copy; skip per-launch Replay save snapshots. Original game saves are untouched.
- Preserve personal settings and game payload; update the displayed version to 1.1.1.

Validation: isolated recovery, retention, failure/active protection, deduplication and parent-termination tests passed. Live game launch/exit validation has not been performed; previous game-compatibility validation limits still apply.

## 下载 / Downloads
- **FPMCI-1.1.1.zip** — 完整包 / full package. Extract outside the game directory.
- **FPMCI-1.1.1-fix-update.zip** — 适用于 FPMCI 1.1.0 / patch for FPMCI 1.1.0. Close the game and launcher, run Apply-Update.cmd and choose the MOD tool folder. The patch does not execute maintenance itself; maintenance runs after subsequent session recovery/completion.
- 补丁仅替换工具文件，不执行历史备份整理；整理在后续会话恢复或完成时执行。异常备份不会被自动删除，因此并非整个目录的硬性容量上限。Hard-linked backup files share contents and should be treated as read-only recovery data.
