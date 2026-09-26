# not-finished backlog — dock + wallpaper

Updated 2026-09-26. Angles covered so far: **correctness**, **rendered pixels**,
**prior art**. Open: real-runtime cost, failure behaviour, first-run/empty states,
scale, repeat use, accessibility.

## Done this round
- [x] Dock edit panel rebuilt Latte/Plasma-shaped (tabs + action bar). Verified by capture.
- [x] Card clipped its last row (hand-counted chrome), then collapsed entirely
      (circular fillHeight). Both fixed; verified by capture.
- [x] Widget windows pinned to 160px forever — implicitHeight measured a
      Loader-hidden child that reports 0 at map time. Now declared per widget.
- [x] Sizes moved to `Appearance.sizes.dockWidgetWindow` + `font.pixelSize.display`.
- [x] Wallpaper transition had no path for Image.Error / empty source / stalled
      load; workSafety's blanked source left the hidden wallpaper pinned in the
      prev layer. Now resolves every outcome + 8s watchdog.
- [x] Media hover-expansion suppressed during dock edit mode.

## Next, ranked
- [impact: med | effort: S | risk: low] `DockEditPanel.dockTop` reads `_tick` and
  `hostHeight` but returns a constant; a 100ms timer runs for nothing while the
  panel is open. Looks like an unfinished port of DockMediaExpansion's
  mapFromItem re-sync. Verify the popup still repositions when the dock height
  is dragged BEFORE removing the timer.
- [impact: high | effort: M | risk: med] `dock.position` is declared, exposed in
  settings, and read only by StartMenu — it does nothing. Either implement
  (flip bottom anchoring, reveal-slide direction, asymmetric insets) or remove.
- [impact: med | effort: M | risk: low] Nothing scales with `dock.height`:
  icons/tiles fixed at 35, widget slots 50, while height is draggable 40-120.
- [impact: med | effort: M | risk: low] Prior art — live mini-preview diagram per
  settings group (Plasma draws a little screen+panel that reflects the current
  choice). Biggest visual upgrade for the least risk.
- [impact: med | effort: S | risk: low] Prior art — pin/sticky toggle so the edit
  card survives outside clicks while testing hover behaviour (Latte has one).
- [impact: med | effort: M | risk: med] Prior art — screen-edge arrow picker
  overlaid on the real screen instead of a position dropdown (Plasma).
- [impact: low | effort: S | risk: low] `WidgetRow` soft-duplicates
  `modules/ii/bar/StyledPopupValueRow.qml`; consider merging.
- [unverified] Wallpaper fixes are read-in-the-source, not reproduced at runtime:
  qml6 silently no-ops headlessly here, and triggering workSafety needs config
  changes. Worth a real repro before trusting the workSafety path.

## Prior art notes
Cloned to `~/.cache/prior-art/`: `KDE/latte-dock`, `KDE/plasma-desktop` (both
GPL-2.0-or-later — technique only, no code copied). Confirmed: both apply every
setting live with no Cancel, only Close. Validates the Done-button model.

## Performance — measured 2026-09-26, shell idle, all panels closed

    RSS          ~1.13 GB, oscillating 1121-1176 MB
    idle CPU     ~34% of one core over 30s with nothing happening
    uptime       4h17m at time of measurement

The RSS oscillation is GC sawtooth, **not** a leak — it reclaims each cycle.
An earlier "59 MB drift" reading was one half of that sawtooth, not growth.

Open, ranked:
- [impact: high | effort: L | risk: med] 34% of a core at idle is the headline.
  Not caused by timers: only 4 always-on repeating timers under 2s exist and
  the background effect is off (`"effect": ""`). Next step is a real QML
  profile, or bisecting by disabling panel families, not more code reading.
- [impact: med | effort: S | risk: low] Two `nmcli monitor` children are
  spawned where one would do. Find the second spawner.
- [impact: med | effort: S | risk: low] `DockEditPanel`'s 100ms `_tick` timer
  feeds a `dockTop` binding that returns a constant. Verify the popup still
  repositions when the dock height is dragged, then delete the timer.
- [impact: med | effort: M | risk: low] 1.13 GB baseline. Worth finding what
  holds it — likely cached images/shaders. Compare RSS with the dock, HUD and
  wallpaper widgets disabled one at a time.

## Performance pass — 2026-09-26, second round

**Measurement was unreliable and I said so too late.** Four `rustc` processes
(wgpu/naga) were saturating the CPU at 0.1% idle, load average 16-18, while I
was sampling quickshell's CPU share. The "33% -> 14.8%" figure from that window
is NOT trustworthy, and neither is the 33.7% that followed it. **Re-measure CPU
only on a quiet machine.** RAM readings are unaffected by CPU contention and
stay usable.

### Fixed — real waste, justified without the numbers
- `DockMediaExpansion` LIVE pulse was `running: true`, ungated: an infinite
  opacity animation repainting the popup every frame for the whole length of a
  live stream, open or not. Now gated on `showExpansion`.
- `OnScreenTouchpad` flush timer ran at 16ms (60Hz) permanently. `PanelLoader`
  defaults to `active: true`, so that panel is built whether or not it is ever
  shown — 60 wakeups a second to hit an early return. Now gated on pending motion.
- `HudClockOrbit` and `HudDashboard` infinite animations were ungated; now bound
  to `visible`.
- `wallpaperPrev` held a second full-resolution wallpaper texture (~16 MB here,
  3072x1920 source) for the life of the shell, for a fade lasting 700ms. Released
  1.2s after the crossfade ends. RSS 913 -> 872 MB across the reload, though the
  reload confounds the attribution.

### Checked and NOT the problem — don't re-investigate
- **Eager panels.** Most already gate their heavy content internally
  (`RegionSelector` has `active: GlobalStates.regionSelectorOpen` etc.). This is
  why the earlier lazy-panel attempt added nothing and broke keybinds: every
  heavy panel registers its own `GlobalShortcut` **inside itself**, so making the
  panel lazy unregisters the shortcut. Any future attempt must split the Scope —
  shortcut eager, window lazy — and verify with `hyprctl globalshortcuts`
  (83 registered; that count is the regression test).
- **Wallpaper `sourceSize`.** The `* monitor.scale` is a correct logical->physical
  conversion, not double-counting: layer surfaces use logical coords (the dock
  layer is 1536 wide on a 2560px panel at scale 1.67).
- **Short always-on timers.** Only 4 exist under 2s; the HUD's 40ms one
  self-terminates after 3 ticks.

### Next, ranked
- [impact: high | effort: M | risk: low] Re-measure idle CPU on a quiet machine.
  Everything above is mechanism-justified but the size of the win is unknown.
- [impact: med | effort: M | risk: low] 58 `layer.enabled: true` sites, including
  `RippleButton` — which is instantiated everywhere. Each forces an offscreen
  render target. Worth checking whether RippleButton needs it at rest.
- [impact: med | effort: L | risk: med] ~870 MB RSS is still unexplained. Needs a
  real profiler or bisecting by panel family, not more code reading.
- [impact: high | effort: L | risk: med] Multi-dock (Latte-style, unlimited docks).
  Do it AFTER the perf pass: N docks multiply whatever per-dock cost exists.
  Today the dock is one PanelLoader against one config object; it needs a docks
  array, per-dock config, and per-screen placement.

## Dock edit panel — 2026-09-26, later
- [x] Widgets tab rebuilt as per-widget cards: each enabled widget gets a
      colLayer1 surface with a hairline between it and its own settings, so
      sub-rows read as belonging to a widget rather than as more widgets. A
      disabled widget stays a bare row. Verified by capture.
- [x] The panel remembers its last tab (`Persistent.states.dock.editTab`).
      Set once in `Component.onCompleted`, NOT bound: a TabBar assigns
      `currentIndex` during construction, which destroys a binding on it —
      that is why the first attempt silently did nothing.
- [x] Duplicate `skip_next` removed from the media seek row; the card below
      already carries it.
- [x] Transport button sizes unified behind `DockMedia.transportSize`. They
      were 26/26/28/26 hardcoded across two files.

### Dock: looked at, deliberately NOT changed
The dock hides by animating `dockMouseArea.anchors.topMargin` so its content
slides below the surface — the subtree stays instantiated and the layer stays
mapped (1536x87 at y=873 even when hidden). Gating the subtree on `reveal`
would cut scene-graph work, but it risks the reveal animation, which the user
has already objected to twice. Needs a measurable win before it is worth the
risk, and the win cannot be measured without disrupting their desktop.
