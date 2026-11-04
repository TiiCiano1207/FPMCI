# FPMCI 1.1.2

## 中文
- 移除“诊断与分析”栏目，保留安装校验、操作输出与会话恢复。日志生成逻辑不变。
- 正常记录最多 3 组／1 GiB；失败、未完成和无配对记录合计最多 3 组／512 MiB。活动会话及待恢复所需备份受到保护。
- 已结束会话、清理备份与 diagnostics 共用日志预算：16 MiB 与 MOD 载荷大小取较小值，其中预留 1 MiB 给最近 20 条整理摘要。按逻辑大小计算，硬链接不会放大额度。活动日志不截断，结束后才纳入上限，因此运行期间不是绝对磁盘配额。
- 启动、环境检查、恢复和退出时维护备份，不依赖正常退出；可选诊断失败不再跳过整理。更新备份最多 3 组／256 MiB，设置备份 3 组／16 MiB，资源索引备份 3 组／64 MiB，诊断记录最多 20 组。
- 已结束备份的重复内容使用只读硬链接。仍跳过 Replay 存档快照，不复制完整 runtime-copy；原始存档和未知 MOD 不纳入整理。
- 直接启动也显示实时日志窗口；关闭前台窗口后独立后台监控继续运行。有记录的旧会话通过归属验证和备份恢复后可再次启动。

验证范围：Windows PowerShell 5.1 隔离保留／容量／异常／活动保护、硬链接、监控脱离前台、诊断失败、GUI 恢复、WPF 编译和界面检查；补丁在隔离副本应用。未进行真实游戏启动／退出实测，历史监控中断原因仍未确定。

## English
- Remove the Diagnostics & Analysis page; keep installation checks, operation output and recovery. Log producers are unchanged.
- Keep up to 3 normal groups / 1 GiB and 3 failed, unfinished or orphan groups / 512 MiB. Protect active sessions and pending recovery backups.
- Share one retained-log budget across sessions, cleanup archives and diagnostics: the smaller of 16 MiB and the MOD payload size, reserving 1 MiB for 20 bounded removal summaries. Count logical bytes conservatively. Active logs are exempt until completion; this is retention at maintenance checkpoints, not a live disk quota.
- Maintain on launch, environment checks, recovery and exit, independently of optional analysis. Bound update backups to 3 / 256 MiB, settings to 3 / 16 MiB, resource indexes to 3 / 64 MiB, and diagnostic records to 20 groups.
- Deduplicate inactive backup content using read-only hard links. Keep diagnostic runtime-copy inputs only and skip Replay snapshots. Original saves and unknown MOD files are excluded.
- Show live logs for direct launch. The detached monitor survives closing its frontend. Recorded stale sessions resume through ownership and recovery checks.

Validation: isolated PowerShell 5.1 retention, capacities, failure/active protection, hard links, detached monitoring, optional-analysis failure, GUI recovery, WPF build/UI checks and patch application. Live game launch/exit has not been tested; the cause of historical monitor termination remains unknown.

## 下载 / Downloads
- FPMCI-1.1.2.zip: 完整包 / full package. Extract outside the game directory.
- FPMCI-1.1.2-fix-update.zip: FPMCI 1.1.0 / 1.1.1 补丁 / patch. Close the game and launcher, run Apply-Update.cmd, select the MOD folder.
- 补丁只更新已识别的工具文件，保留个人设置、载荷及旧会话；安装时不执行备份整理，下次启动／检查时执行上述规则。The patch preserves settings, payload and stale session state. Installation performs no retention; subsequent launch/check applies the policy.
