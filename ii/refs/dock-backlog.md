# Dock + widget system — what's weak

> **Round 1 fixed (2026-09-25):** `dock.spacing` now honoured; `mediaStyle`
> removed; the expansion's 100ms tick gated on `showExpansion`; the Track
> panel's leaked CLI message. Struck through below.

Slice audited: `modules/ii/dock/**`, `modules/ii/dock/widgets/**`,
`services/TaskbarApps.qml`, `services/DockWidgets.qml`, the dock keys in
`modules/common/Config.qml`, and `DockTile`/`DockGauge` in common/widgets.
Passes done: use-it, seams, edges, cost, the record. 2026-09-25.

---

- [impact: high | effort: S | risk: low] **~~Four~~ TWO dock settings are controls that do nothing.** (`spacing` wired, `mediaStyle` removed; `position` + `floating`/`floatingMargin` REMAIN)
  WHERE: `Config.qml` dock block; controls at `settings/InterfaceConfig.qml:135,151,168`
  and `dock/DockEditPanel.qml:135`
  EVIDENCE: the only readers of `dock.position`, `dock.floating` and
  `dock.floatingMargin` outside Config and the settings UI are
  `startMenu/StartMenu.qml:50,54` — `Dock.qml` never reads them.
  `dock.mediaStyle` has **zero** readers anywhere. `dock.spacing` is exposed in
  two places while `Dock.qml:121` hardcodes `spacing: 3`.
  WHY IT MATTERS: a settings screen that lies is worse than a missing feature.
  Worse, the start menu positions its clearance for a floating/top dock that
  the dock itself will never honour, so those two are already inconsistent.

- [impact: high | effort: M | risk: med] **Nothing inside the dock scales with `dock.height`.**
  WHERE: `DockAppButton.qml:15` (`iconSize: 35`), `DockWidget.qml:12,17`
  (`tileSize: 35`, `implicitWidth: 50`), `DockTile.qml:14-15` (35x35)
  EVIDENCE: `dock.height` is settable 40–120 and now draggable, but is read
  only by `Dock.qml:57` (window height), the edit overlay, and clearance maths
  in StartMenu and DesktopIcons. At height 120 the icons stay 35px.
  WHY IT MATTERS: the headline setting, and the drag handle added today,
  produce a visibly broken dock at anything but the default height.

- [impact: med | effort: S | risk: low] ~~**The media expansion ticks 10x/second whenever a track exists.**~~ FIXED — gated on `showExpansion`.
  WHERE: `DockMediaExpansion.qml:66-69`, `visible:` at :47-50
  EVIDENCE: `visible` is true for ANY track while the feature is on — not only
  while expanded — and the position re-sync timer is `running: root.visible;
  interval: 100; repeat: true`.
  WHY IT MATTERS: permanent idle cost during playback that never shows up in a
  profile taken while interacting with the dock. Added 2026-09-25; should be
  gated on `media.showExpansion`, with one extra sync on open.

- [impact: med | effort: S | risk: low] **Two settings surfaces, divergent subsets.**
  WHERE: `settings/InterfaceConfig.qml` vs `dock/DockEditPanel.qml`
  EVIDENCE: the user's own complaint — "not all settings are in the context
  menu". Interface has position/floating; the edit panel has the widget list,
  which Interface lacks. Neither is a superset.
  WHY IT MATTERS: every new dock setting has to be added twice or it is
  missing from one of them. Pick one as authoritative.

- [impact: med | effort: S | risk: low] **The settings dialog would open once per monitor.**
  WHERE: `DockSettingsDialog.qml:27` — `Variants { model: Quickshell.screens }`
  EVIDENCE: read in the code; NOT observed (single screen on this machine).
  WHY IT MATTERS: N identical modal dialogs on a multi-monitor setup. The dock
  itself is correctly per-screen; a modal is not.

- [impact: med | effort: S | risk: low] **Dead file: `DockSettingsDialog.qml` is unreferenced.**
  WHERE: 8.2 KB, written 2026-09-25; `Dock.qml:194` still instantiates the old
  `DockEditPanel`
  EVIDENCE: grep for both names across the config.
  WHY IT MATTERS: two edit UIs in the tree, one of them reachable. Either wire
  it in and delete the panel, or delete the dialog.

- [impact: low | effort: S | risk: low] **A widget that fails to load leaves a silent 50px hole.**
  WHERE: `DockWidget.qml:17` — `implicitWidth: 50` unconditionally
  EVIDENCE: observed today. While `DockGauge is not a type` was breaking three
  widgets, their slots rendered as blank space with no indication of failure.
  WHY IT MATTERS: a broken widget looks like a layout bug, not a broken widget.

- [impact: low | effort: S | risk: low] **Design-system drift in the widget tiles.**
  WHERE: `ResourcesWidget.qml:21,24,30,41`; `VolumeWidget.qml:39`;
  `DockTile.qml:14-15`; `DockWidget.qml:17`
  EVIDENCE: raw literals (9, 4, 35, 50) where `Appearance.rounding.*` and
  `Appearance.sizes.*` exist and are used elsewhere in the same files.
  WHY IT MATTERS: these are exactly the values that drift when one file is
  edited and the others are not — the separators did precisely this and ended
  up with two different heights and two different centres.

- [impact: low | effort: S | risk: med] **The resize drag writes config.json on every mouse move.**
  WHERE: `DockEditOverlay.qml:50-56`
  EVIDENCE: rounded to 2px, but still one `Config.options.dock.height` write
  per step; each write persists.
  WHY IT MATTERS: a one-second drag is dozens of disk writes. Commit on
  release, preview live.

---

## Looked at and fine

- `TaskbarApps.qml` separator emission — trailing separators are dropped as of today.
- `DockWidgets.enabled` filters unknown ids, so removing a widget from the
  catalog cannot leave a hole in the dock.
- The `dock` IpcHandler sits in the `Scope`, not the per-screen window, so it
  registers once rather than once per monitor.
- `DockAppMenu`'s model gating — verified against three app shapes (running
  with 2 windows, running with 1, pinned and not running).

## Round 1 notes

The remaining high-impact item is `dock.position` / `dock.floating`: both need
real geometry changes in `Dock.qml`, the file that has broken repeatedly, so
they want the measure-with-a-red-rectangle workflow rather than reasoning.
`StartMenu.qml` already positions its clearance as if both worked, so the two
are currently inconsistent whichever way it goes.

Also added this round, outside the original slice: `TimeTrackerWidget` printed
timewarrior's "No filtered data found in the range ..." CLI message as if it
were the summary, because that message goes to stdout with exit 0 and the
widget's emptiness check was `!== ""`. It now has real empty and
missing-tool states.

## Could not check

- Dock-attributable RSS/CPU. Needs a run with the dock disabled to compare
  against; `qs` as a whole was ~1.3 GB earlier in the session.
- Multi-monitor behaviour — one screen on this machine.
- Tablet/touch mode interaction (`Appearance.touchUi` paths in the dock).
- Commit history is useless here: the repo is a single "snapshot: initial"
  plus one later commit, so "what was fixed twice" could not be mined.
