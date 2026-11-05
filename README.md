当前版本：FPMCI 1.1.7。详见 [完整更新说明](RELEASE-v1.1.7.md)。

# FPMCI

**First-Person Mouse Control Integration · 第一人称鼠标操控整合**

ACE COMBAT 8 的鼠标飞控、驾驶舱平滑镜头与外置设置启动器。A mouse-flight-control, cockpit camera and settings integration for ACE COMBAT 8.

## 下载与安装 / Download & install

从 [Releases](https://github.com/TiiCiano1207/FPMCI/releases/latest) 下载 **FPMCI-1.1.7.zip** 和对应 SHA256 校验文件。GitHub 的 Source code 压缩包仅包含源码。

1. 将完整包解压到游戏目录外的新文件夹；保留 EXE 旁的全部资源。
2. 运行 **AC8Workbench.exe**（界面显示 FPMCI），选择游戏与 Steam 位置及安装方案。
3. 保存设置，按界面提示配置 Steam 启动选项，然后点击“开始游戏”。

Download the full release ZIP, extract it outside the game directory, run **AC8Workbench.exe**, select game/Steam paths and an installation mode, then save and follow the launch instructions. The EXE uses the accompanying external resources.

升级请先结束旧会话，再将完整包解压到新文件夹，重新设置路径和 Steam 启动选项。不要覆盖活动会话。新包不包含个人安装路径；导弹引导初始数值为 MOD 预设，近炸增强默认关闭。

## 功能 / Features

- 鼠标飞控、PEACE / WAR 模式与驾驶舱鼠标控制 / Mouse flight control and cockpit support.
- C 自由观察、控制圆圈平滑镜头跟随、FOV 与准星设置 / Free look, smooth camera following, FOV and reticle settings.
- DLSS 帧生成开关（默认关闭，需游戏与显卡支持）/ DLSS Frame Generation toggle (off by default; support required).
- 13 项比例引导与 11 类弹种独立近炸设置 / 13-value guidance editor and eleven per-type proximity-fuse controls.
- 外置配置，保存后下次启动生效 / External configuration applied on next launch.

## 1.1.7 更新 / Changes

接入 PropNav 2.3.9；独立近炸参数和原版伤害参考；自由观察、手动注视和镜头回正修复；等待会话整理后继续启动。

Integrate PropNav 2.3.9, per-type fuse controls and damage references; fix free-look/manual-focus/camera return and session-cleanup waiting. See [full release notes](RELEASE-v1.1.7.md).

## 1.1.2 更新 / Changes

移除诊断与分析栏目；正常及异常备份同时限制数量和容量，日志共用不超过 16 MiB／MOD 本体大小的留存预算。活动会话受到保护，结束后纳入整理。日志生成逻辑不变。

Remove Diagnostics & Analysis. Bound normal/exceptional backups and share a retained-log budget no larger than 16 MiB or the MOD payload. Active sessions are protected until completion. See [1.1.2 notes](CHANGELOG-1.1.2.md).

## 1.1.1 更新 / Changes

修复重复启动的旧会话拦截，独立退出监控并保留日志；正常备份保留最近 3 组，去除重复运行目录与录像副本，相同备份内容共享空间，异常记录保留。

Fix stale-session restart handling; detach and log the session monitor; retain 3 completed backup pairs, share identical backup contents and avoid full runtime/replay copies. Exceptional records are preserved. See [1.1.1 notes](CHANGELOG-1.1.1.md).

## 1.1.0 更新 / Changes

全新浅色航空简报界面、FPMCI 名称与数值框显示修复；加入帧生成开关、导弹引导编辑以及 Build 26002268 镜头适配，保留 Build 25201480 支持。

New aviation briefing UI and the FPMCI name; fixed clipped numeric fields; added frame generation and guidance controls plus Build 26002268 camera compatibility, retaining Build 25201480 support.

已完成离线签名、原生镜头/设置测试和界面检查；更新后游戏内实测验收仍待完成。Offline and UI checks passed; updated-game acceptance testing is pending. See [release notes](CHANGELOG-1.1.0.md).

## 源码与许可 / Source & license

`source/SettingsTool` contains the WPF launcher; `source/MouseAim` contains native flight/camera code; `source/CockpitFOV` and `source/SourceInit` contain Lua modules. Binaries and runtime resources are distributed through Releases.

基于 [FletcherMiya/AC8-Mouse-Aim](https://github.com/FletcherMiya/AC8-Mouse-Aim)，感谢原作者和上游贡献者。项目代码沿用 [MIT](LICENSE)，第三方材料见 [THIRD_PARTY_NOTICES.md](THIRD_PARTY_NOTICES.md)。This is an unofficial community project for offline single-player use.
