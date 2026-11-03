# FPMCI

## Platform
Windows desktop WPF (.NET Framework 4); this is not a web UI.

## MOD purpose
First-Person Mouse Control Integration: install, launch and configure the user's Ace Combat 8 mouse-control MOD.

## Confirmed requirements
User selected FPMCI and the supplied ACE8 Mod Launcher 2.0.1 light-theme screenshot as the visual reference. Preserve existing features, next-launch configuration, Steam launch checkbox beside secondary Save, primary Start Game, no theme switch, and full numeric visibility. Frame generation stays in Common settings. Do not change game controls, files, cleanup behavior or personal preferences as a UI side effect.

## Engineering constraints
Keep WPF and external resources. Validate at boundaries, avoid redundant null checks, unnecessary single-use helpers and defensive try/catch. New work resides on E:.
