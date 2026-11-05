# FPMCI desktop interface

FPMCI means First-Person Mouse Control Integration. Native Windows WPF, .NET Framework 4. User-approved reference: ACE8 Mod Launcher 2.0.1 light theme in QQ_2026-11-03_13-23-57.png. Mode: Operate.

## Palette and geometry

Canvas #E7EFF2; rail #DCE7EC; header/footer #DDEAF0. Primary text #142F3C; secondary #496878; accent #087F9F. Dividers #BED3DD, control borders #8EB7C9, inputs #F8FBFC, errors #AF3928. Flat one-pixel boundaries, near-square corners, rounded switch tracks. Selected navigation has a slanted trailing edge.

## Typography

Big Shoulders Bold: MOD name 48 and English page headings 34 WPF units. Microsoft YaHei UI: Chinese page titles 19, labels 14, descriptions 12. Bahnschrift SemiCondensed for compact metadata. Numeric input uses centered 16-unit Consolas. Chinese retains normal proportions. Official Big Shoulders OFL license ships in ui/fpmci/fonts/.

## Composition

Fixed 228-unit rail, independently scrolling navigation, package selection/reload and version. Main area has four basic status cells: Game, Mod Mode, Profile and Version. Bilingual heading and cyan rule precede vertically scrolling setting rows. Footer remains visible: secondary Save beside Steam checkbox, primary Start Game on the right. Defaults and backup restoration remain available on configuration pages. Frame generation stays in Common settings. Single theme only.

## Interaction and numeric constraints

Text fields use cyan focus borders. Buttons use contrasting dark two-pixel keyboard-focus borders. Selected dropdown entries use white text on cyan. Switches show explicit on/off text as well as knob position. Disabled buttons fade.

Normal setting rows reserve 270 units for controls, including a 104-unit numeric input. PART_ContentHost must keep zero margin; TextBox owns its padding. This prevents duplicate padding and clipped final digits.

## Verified scope

Common settings rendered at 1160x860 and 980x720; installation, camera and guidance at 1160x860. Native tests cover all nine page layouts, numeric visibility, dropdown selection contrast, primary focus template, settings save/restore and conflict priority. No web detector applies to native WPF. Final independent visual review resolved its two interaction-state findings.

Existing game payload, configuration, launch and cleanup behavior are retained. UI verification does not establish live game compatibility; the prior runtime-validation limitation remains.

The diagnostics/analysis page was removed in 1.1.2 at the user's request. Installation and recovery pages retain their operation output and integrity checks.

1.1.4: Missile Enhancement retains the existing WPF layout and adds eleven original/enhanced fuse switches. Two installation choices replace the full-enhancement preset.

1.1.5: Source-backed vanilla fuse references sit above the per-type rows. Enabled fuse switches reveal three numeric fields; disabling retains values and collapses the panel.
