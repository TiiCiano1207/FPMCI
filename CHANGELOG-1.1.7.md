# FPMCI 1.1.7 — 会话整理期间再次启动

- 启动或检查遇到前一会话恢复/整理占锁时，最多等待 60 秒，释放后继续执行。
- 等待后重新读取活动会话、加载器残留和游戏进程状态，避免使用等待前的旧记录，也避免重复启动。
- 会话忙碌的提示改为中文并说明稍候重试，不再显示无关的路径/权限排查提示。其他调用默认仍立即拒绝锁冲突。
- 八种 GUI 隔离场景及跨进程锁竞争、限时等待、释放后继续测试通过；未启动真实游戏，未清理真实游戏文件。

English: Wait up to 60 seconds for previous session cleanup/maintenance before GUI start/check, then refresh session, residual and game-process state. Keep fail-fast defaults for other operations and provide a specific busy hint. Isolated GUI and cross-process lock tests passed; no live game was started.
