# FPMCI 1.1.6 — 鼠标输入与相机衔接

- 自由观察采用操控圈相同的屏幕投影和 FOV 换算；保留驾驶舱相对机身转头、俯仰限位和自由观察期间的飞行目标。
- 手动注视目标只交还相机控制，保留鼠标输入、飞控指令及 HUD；强制事件镜头、过场、暂停和失去飞机控制权仍暂停。自由观察按键优先于手动注视，退出注视保持飞行目标。
- 原生相机回调继续发布注视镜头的最终位置、方向和 FOV，关闭该状态下的视角预测，防止使用旧镜头数据。
- 驾驶舱回正平滑器从上一帧姿态开始立即推进，消除退出自由观察时的首帧停顿；默认缩放键松开后平滑恢复光学视野，外部原版相机位置重新接管时平滑衔接。
- 飞控控制律和个人设置保留。UI 沿用已核对的原版导弹参考。

验证：10 项原生隔离测试、Lua 状态测试与所有 Lua 文件语法检查通过。覆盖两条输入路径、五档 FOV、自由观察/注视/强制镜头切换、目标世界方向保留、原生相机写入范围及 30/60/144 FPS 缩放恢复。未启动真实游戏；游戏内手感和实际镜头衔接待实测。

English: Match free-look input to the flight ring's FOV-aware projection; retain mouse flight during manual target focus while yielding camera ownership. Preserve forced-view suspension and free-look priority. Advance cockpit return immediately, smooth native optical zoom release and external camera-rig reacquisition. Ten isolated native tests and Lua validation passed; live-game handling remains untested.
