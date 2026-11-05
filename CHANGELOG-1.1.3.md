# FPMCI 1.1.3 — AC8PropNav 2.3.9

接入用户提供的上游 2.3.9 原始 DLL（新版游戏适配），保留 FPMCI 现有引导配置。11 类玩家导弹由上游核心处理；STORY/EASY 与其余完整强化字段继续由 FPMCI Lua 处理，避免两套实现重复写入玩家引导字段。未增加敌方覆盖，保留既有方案；配置下次启动应用。

仅鼠标飞控不部署该核心；旧 AVRT.dll 存在时阻止部署并保留原文件。第三方 DLL 在 AC8SourceInit 内随本包归属检查与备份恢复，日志继续纳入现有留存规则。

上游 DLL SHA256：b4207774b64ce542cb9174708e25906cbcbbb785a9d361786753d30846bda222。
上游仅提供二进制，未将它描述为 FPMCI 自行编译的源码。原始说明及入口脚本见 docs/upstream/AC8PropNav-2.3.9。

隔离验证：DLL 字节身份、PE 架构／导出、字段分工、补丁读回及幂等性、加载失败／单次启动、三种安装模式、个人配置保留与旧代理保护通过。测试未执行 DLL 原生线程，也未启动真实游戏，不能视为游戏内兼容性或实际制导效果验收。

Integrated the supplied upstream 2.3.9 binary while retaining existing FPMCI settings. The native core owns eleven player missile lead profiles; FPMCI retains difficulty and other full-enhancement fields. No enemy overrides are added. Mouse-only mode excludes the core; legacy AVRT conflicts block deployment without deletion. Isolated static and integration tests passed; the native thread and live game have not been tested.
