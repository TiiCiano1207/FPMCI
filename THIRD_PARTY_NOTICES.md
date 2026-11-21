# Attribution and licensing

## Project foundation and thanks

**AC8 Integrated Mod is developed from [FletcherMiya/AC8-Mouse-Aim](https://github.com/FletcherMiya/AC8-Mouse-Aim).** We thank FletcherMiya and the upstream contributors for developing and sharing the mouse-flight foundation used by this project. Our online learning, control-policy switching, GUI extensions and optional missile integration build on that foundation.

This repository is independently maintained. Attribution does not imply upstream endorsement of our modifications, and upstream copyright and license notices remain in place.

## Licenses

Original integration code and modifications are provided under the root MIT license. Third-party material keeps its own license and copyright notice.

| Component | Origin / license |
|---|---|
| AC8 Mouse Aim base | [FletcherMiya/AC8-Mouse-Aim](https://github.com/FletcherMiya/AC8-Mouse-Aim), inspected source snapshot `0d6e8a7`; upstream LICENSE declares CC0 1.0. Preserve `licenses/MouseAim/LICENSE.txt` |
| MouseFlight reference | [brihernandez/MouseFlight](https://github.com/brihernandez/MouseFlight), MIT, Brian Hernandez; see `licenses/MouseAim/MouseFlight-LICENSE.txt` |
| MinHook / bundled HDE | [TsudaKageyu/minhook](https://github.com/TsudaKageyu/minhook), BSD-style notices preserved in `native/src/vendor/minhook/LICENSE.txt` and `licenses/MouseAim/MinHook-LICENSE.txt` |
| RE-UE4SS | [UE4SS-RE/RE-UE4SS](https://github.com/UE4SS-RE/RE-UE4SS), MIT, Narknon and contributors; pinned runtime 3.0.1-1152-ge3ba1016. Header snapshots use explicit standard includes and a `std::format` adaptation |

The missile work originated from research around the user-provided **AC8-PropNav v1.1** release, attributed in its supplied reference to **麦糊**. This repository uses the subsequent source-initialization/verification implementation and records that provenance; it does not import the original third-party distribution wholesale or relicense content without an applicable grant.

No ACE COMBAT game executable, mesh, texture, audio, extracted asset package, decryption key, raw save or raw personal flight recording is included. Asset paths, field names, numeric settings and derived response parameters are used to reference the user's own installed game.

The root license does not replace the individual third-party licenses. Preserve this file and all applicable license files in redistributed packages. This is an unofficial community project and is not affiliated with the game publisher or the upstream projects.

## CreeperUX UI Kit native visual adaptation (local GUI preview)

Design tokens and component conventions: CreeperUX/CreeperUX-UI-Kit 2.4.0, commit 586e23784d8f51cbe8713e583bcf0d92c473f2d0. The GUI is a WPF adaptation. Provenance is in package-template/ui/creeperux/SOURCE.json.

Bundled Chakra Petch SemiBold and Share Tech Mono retain their original names and glyphs. WOFF2 sources from the Kit were decoded to TTF for native rendering. Both are distributed under SIL Open Font License 1.1; see the font-specific OFL files next to the fonts in ui/creeperux/fonts (package-template/ui/creeperux/fonts in source).


## Workbench analysis runtime

This local integrated tool includes CPython and NumPy for the original analysis scripts. Full licenses are preserved at runtime/python/LICENSE.txt and runtime/python/Lib/site-packages/numpy-2.3.5.dist-info/LICENSE.txt. See also licenses/Workbench-Python-NumPy.txt.


## Big Shoulders
Copyright 2019 The Big Shoulders Project Authors. SIL Open Font License 1.1.
Source: https://github.com/google/fonts/tree/main/ofl/bigshoulders
Static instance: weight 700 / optical size 36. License: ui/fpmci/fonts/OFL-BigShoulders.txt.

## Supplied missile modules

FPMCI 1.1.3+ bundles the supplied AC8PropNav 2.3.9 native DLL in release payloads. Its source was not supplied; upstream files, version and SHA256 are retained in docs/upstream/AC8PropNav-2.3.9. The instance-only fuse adaptation derives from the supplied AC8ProximityFuse 0.0.2 Lua files, retained in docs/upstream/AC8ProximityFuse-0.0.2. The root MIT license does not relicense third-party material.

## Extra MOD support

ExtraMods-Settings.ps1 is adapted from [CreeperUX/AC8-Integrated-Mod v2.5.2](https://github.com/CreeperUX/AC8-Integrated-Mod/tree/v2.5.2). The bundled UEHelpers Lua library is taken from the same release and accompanies the pinned UE4SS runtime. See the UE4SS license in the payload.

## AC8EnhancedHUD 0.7.3

Enhanced Cockpit HUD 0.7.3 by neuclyd. FPMCI adapts the supplied module for the workbench and third-person EEGS. Upstream: https://www.nexusmods.com/acecombat8wingsoftheve/mods/198 .

SP Weapon Customizer 2.6 by Lenkov (lenkov7410). FPMCI adaptation of the supplied 2.6 files for offline single-player use. Upstream: https://www.nexusmods.com/acecombat8wingsoftheve/mods/57 . Related reference: Hangar Weapon Model Fix by buyx1412.

## Ace Pilots 0.1.0

[Ace Pilots](https://www.nexusmods.com/acecombat8wingsoftheve/mods/40) is by Mike-0000 (michael319, Nexus upload by 0Mike), copyright 2026 Mike-0000, under the MIT license. The copyright and permission notice is included at licenses/AcePilots-MIT.txt. The bundled UE4SS runtime retains its own MIT notice. The original project credits 4598llj and *FOV Change* for the offline launch method.

## Ace Pilots Mod - Branched 1.2

The enemy AI integration also incorporates the supplied [Branched 1.2](https://www.nexusmods.com/acecombat8wingsoftheve/mods/203) files by madcow12, based on the original work by Mike-0000. Third-party components retain their respective rights and notices.
