# FPMCI 1.1.7 installation

[简体中文](../INSTALL.md) | [Home](../../README.md)

Use the [FPMCI releases](https://github.com/TiiCiano1207/FPMCI/releases). Supported Steam builds: 25201480 and 26002268. Offline single-player only.

1. Exit the previous game session and wait for cleanup to finish.
2. Extract the full ZIP to a new folder outside the game directory. Keep the external resources beside AC8Workbench.exe.
3. Run AC8Workbench.exe, select the game and steam.exe paths, choose an installation mode and save.
4. Copy the generated launch option into Steam game properties. Update it whenever the MOD folder moves.
5. Start through the tool or Steam, select Expert controls, and allow the session monitor to restore the game files after exit.

The two modes are **飞控 + 导弹模块** (flight control plus missile modules, saved as guidance) and **仅鼠标飞控** (flight control only, saved as none). The old full preset is retired and migrates to guidance. The missile page **导弹强化** provides 13 guidance values and eleven per-type fuse switches. Enabled fuse types expose trigger distance, blast radius and area damage. Fuse enhancement defaults off, retaining stock SASM airburst. Save for next launch. Direct-hit references are campaign base values, before parts and target-type damage rates.

The GUI is Chinese with English page headings. F4 toggles PEACE/WAR, F8 toggles mouse flight, F9 recenters, F3 switches camera mode, and the free-look/zoom keys are configurable. Personal settings can be edited while the game is closed.

On start/check, the tool waits up to 60 seconds for a previous session's cleanup/maintenance and then refreshes its state. Do not run multiple packages concurrently. Use the management page to recover an interrupted recorded session; unknown loaders require ownership checks. To return to the stock game, finish cleanup and remove this package's Steam launch option.

See [release notes](../../RELEASE-v1.1.7.md) for changes and validation limits. sessions may contain personal save backups; share the original release ZIP rather than your installed folder.
