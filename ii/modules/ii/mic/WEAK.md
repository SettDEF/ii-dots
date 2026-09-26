# Mic panel — what's weak

> **Round 1 done.** Struck entries are fixed and verified; see "Round 1" at the
> bottom for what the fixing itself got wrong.

Slice looked at: `services/Mic.qml`, `modules/ii/mic/MicPanel.qml`,
`modules/ii/mic/MicToggle.qml`, the `mic` block in `modules/common/Persistent.qml`,
and the three registrations (`services/PanelStack.qml`, `GlobalStates.qml`,
`panelFamilies/IllogicalImpulseFamily.qml`). Written the same session the panel
was built, so nothing here is inherited — all of it is mine.

Passes done: **the seams** (QML ↔ shell), **use it** (opened the panel, captured
it), **the cost** (measured process spawns). Not done: multi-device edges, a real
recording test through the chain.

---

## Ranked

- `[impact: high | effort: S | risk: low]` ~~The gain slider drives the wrong sound card.~~ — FIXED
  WHERE: `services/Mic.qml` — `deviceHint`, used by `probeGain`
  EVIDENCE: `deviceHint` takes the *second* alphanumeric token of the device name.
  For `"RØDE NT1 5th Gen Mono"` the tokens are `[NT1, 5th, Gen, Mono]`, so the hint
  is `"5th"` — which matches no card id. The cards are `Generic`, `Generic_1`,
  `H630`, `Gen`; the NT1's id is literally `Gen`, i.e. the *third* token. With no
  match the probe falls back to the first capture-capable card, measured as
  `card1 (Generic_1)`, control `Capture`, range 0–63 — not the NT1 (`card3`,
  control `Mic`, 0–60).
  WHY IT MATTERS: the panel says "Hardware gain" under the NT1's name and moves a
  different device's input level. This is the same class of mistake as addressing
  `hw:5` after the card became `hw:2`, which is the bug the service was written to
  prevent. Match on the card **id** (`/proc/asound/cardN/id`) against the node's
  `api.alsa.card` property instead of guessing from the description string.

- `[impact: high | effort: S | risk: med]` ~~The probe/apply pair spins continuously.~~ — FIXED
  WHERE: `services/Mic.qml` — `probeGain.onStreamFinished` → `applyGain()` →
  `setGain.onExited` → `probeGain.running = true`
  EVIDENCE: sampled `ps` 50× over 10 s; `amixer` was running in **every** sample
  (sum 100 across 50 samples ≈ 2 processes at all times). The 4 s timer should
  make this a brief spike, not a constant.
  WHY IT MATTERS: it is a closed loop with no damping — probe sees drift, applies,
  the apply re-probes, and if the write never makes `actual == desired` (wrong
  card with a different dB mapping, a clamped range, a device that vanished) it
  never settles. Each turn spawns `bash` plus one `amixer` per sound card. On a
  machine that games, a shell spawning processes nonstop is a real cost, and it
  is invisible because the panel need not even be open. Needs a retry cap and a
  backoff, and the apply must not re-trigger the probe unconditionally.

- `[impact: high | effort: M | risk: low]` ~~Two of the four switches do nothing at all.~~ — FIXED
  WHERE: `services/Mic.qml` — `noiseSuppression`, `highPass`
  EVIDENCE: both are plain properties. `grep` shows nothing reads them; no filter
  chain is created. Only `setEchoCancel` and `setMonitoring` run a command.
  WHY IT MATTERS: the panel presents four equal-looking toggles and two are
  decorative. The noise-suppression one at least says its plugin is missing;
  **high-pass claims to cut rumble below 80 Hz and does nothing**, which is worse
  than the greyed-out one — it looks like it worked.

- `[impact: high | effort: S | risk: low]` ~~The level meter is dead, and wired to the wrong signal.~~ — FIXED
  WHERE: `modules/ii/mic/MicPanel.qml` (meter bar) + `services/AudioMeter.qml`
  EVIDENCE: `AudioMeter.active` is documented "Panels set this while a meter is on
  screen and clear it after" — `grep -rn "AudioMeter.active"` returns **no
  setters anywhere**, including my panel. Worse, `AudioMeter.monitorSource` is
  `Audio.sink.name + ".monitor"` — the **output** monitor, i.e. the speakers.
  WHY IT MATTERS: the "silent" in the screenshot was not the muted device, it was
  a meter that never ran. Even switched on it would show playback level, not mic
  level. A mic panel whose meter reflects the speakers is actively misleading —
  and the meter is the one control here you cannot replace with a number.

- `[impact: high | effort: M | risk: low]` ~~No device picker; it follows whatever is default.~~ — FIXED
  WHERE: `services/Mic.qml` — `readonly property PwNode source: Pipewire.defaultAudioSource`
  EVIDENCE: the panel rendered "Ryzen HD Audio Controller Analog Stereo" while the
  NT1 was the intended target. Known before this pass; kept because it is still
  the largest usability hole.
  WHY IT MATTERS: the default source is a system-wide setting that other apps
  change. A mic panel that cannot choose its mic is a mic panel for somebody
  else's mic.

- `[impact: med | effort: S | risk: med]` ~~`pactl unload-module` by name removes every instance.~~ — FIXED
  WHERE: `services/Mic.qml` — `setEchoCancel`, `setMonitoring`
  EVIDENCE: both unload by module *name*, never tracking the id returned by
  `load-module`.
  WHY IT MATTERS: turning off "Hear myself" unloads **all** loopbacks — including
  the Bitwig→DJ-808 routing set up by hand earlier, or anything else using
  `module-loopback`. Capture the id from `load-module` and unload that.

- `[impact: med | effort: S | risk: low]` ~~The card index is stale between probe and write.~~ — FIXED
  WHERE: `services/Mic.qml` — `applyGain()` uses `root.cardIndex` captured by the
  last probe
  EVIDENCE: the NT1 was observed at `card5`, then `card2`, then `card3` within one
  session. `setGainDb` writes using whatever the last probe stored.
  WHY IT MATTERS: the whole premise of the service is "never trust a cached card
  index", and the write path does exactly that. The window is small but the
  failure is silent and writes to another device.

- `[impact: med | effort: S | risk: low]` ~~Toggling a `MicToggle` destroys its binding.~~ — FIXED
  WHERE: `modules/ii/mic/MicToggle.qml` — `StyledSwitch { checked: root.checked; onToggled: ... }`
  EVIDENCE: standard QML behaviour — a user-driven write to `checked` replaces the
  binding to `root.checked`.
  WHY IT MATTERS: after the first click the switch no longer follows the service.
  If a command fails, or the state changes elsewhere, the switch keeps showing the
  user's last click rather than reality.

- `[impact: med | effort: S | risk: low]` **Command failures never reach the screen.**
  WHERE: `services/Mic.qml` — `runShell`, `setGain`
  EVIDENCE: no `exitCode` is read anywhere; `chainCmd` has no handler.
  WHY IT MATTERS: if `pactl load-module` fails (module missing, PipeWire busy) the
  switch stays on and the panel asserts a filter that is not running. Same class
  of problem as the dead toggles, but harder to notice.

- `[impact: low | effort: S | risk: low]` **Volume clamp disagrees with the rest of the config.**
  WHERE: `services/Mic.qml` `setVolume` clamps at 1.5; `services/Audio.qml`
  declares `hardMaxValue: 2.00`
  EVIDENCE: two literals for one concept, in two services.
  WHY IT MATTERS: small, but it is a second source of truth for a limit the audio
  service already owns.

---

## Looked at and fine

- **Panel registration.** All three places are correct and consistent with the
  others: `PanelStack.order` places `mic` between `audio` and `iris`,
  `GlobalStates._stackedPanels` maps it to `micOpen`, and the property exists.
  Measured live: `quickshell:mic` at `1131,45 400x491` — right width, right slot.
- **Panel chrome and visual language.** Uses `StackedSettingsPanel`,
  `Appearance.colors.col*` roles throughout, no literal hex, the section-container
  idiom, and `MaterialSymbol` icons at 17 px. Matches the neighbours in the capture.
- **Persistence shape.** The `mic` `JsonObject` follows the existing pattern in
  `Persistent.qml`; `gainDb` round-trips.
- **Reload.** `qs-check` reports clean; the earlier cascade was a template-literal
  syntax error in `Mic.qml` and is fixed.

## Could not check

- **Whether the gain actually survives a replug.** Needs the NT1 physically
  unplugged and re-inserted while watching `actualGainDb`. Worth doing, since it
  is the entire justification for the service — and finding #1 means it is
  currently re-applying to the wrong card anyway.
- **Echo cancellation and monitoring end to end.** Both load real PipeWire
  modules; I did not toggle them, because unloading by name (#6) would have taken
  down the Bitwig→DJ-808 loopback that was set up earlier in the session.
- **CPU attribution for the spin.** The 84 processes/s figure is system-wide and
  includes Bitwig and my own commands. The `amixer`-specific sampling is solid;
  the share of total CPU is not isolated.


---

## Round 1 — what got fixed, and what the fixing got wrong

Verified by IPC (`qs -c ii ipc call mic status`) and by forcing the gain from
outside, not by reading the diff.

**Fixed and measured**

- Card resolution: `pactl list sources` → `alsa.card`, from the node NAME.
  `cardIndex: 3`, `gainControl: "Mic"`, `gainAvailable: true` — the NT1, not the
  onboard card it was driving before.
- **The watchdog works.** Forced `amixer -c 3 sset Mic 60dB` behind its back;
  8 s later it read 20 dB again. First actual evidence that the premise holds.
- Source picker added, persisted, with an explicit "not connected" line.
- Meter is the mic: `ffmpeg -i alsa_input...NT1...`, confirmed from `/proc/PID/cmdline`.
  Runs only while the panel is open.
- High-pass builds a real `module-filter-chain` with `bq_highpass`; modules are
  unloaded by the id captured from `load-module`, so the hand-made Bitwig
  loopback survives.
- `MicToggle` re-asserts its binding after every click.
- `sources` uses `Audio.devices(false)` instead of a hand-rolled filter.

**Two findings in this file were WRONG**

- *"The probe/apply pair spins continuously"* — **false**. The evidence was
  `ps -eo args | grep '[a]mixer'`, which matched the grep's own shell command
  line; both the "before" (100) and "after" (100) figures were counting my own
  processes. Measured properly with `ps -eo comm=`: **0 amixer processes across
  50 samples**. The unbounded retry path did exist in code and is now capped, but
  it was never firing. Same self-matching trap the quickshell-ui skill documents.
- *"The panel showed the wrong device"* was right, but the reason given
  (`defaultAudioSource`) was only half of it: the picker also fell back to
  `sources[0]` via `Math.max(0, findIndex(...))`, so it DISPLAYED the NT1 while
  the service used the onboard card.

**A worse bug the fixing uncovered**

- `Mic` is a Singleton, and every reference to it lived inside a lazily-loaded
  panel, an IpcHandler body or a shortcut handler. So it was never instantiated
  until you interacted: `cardIndex: -1, probeRaw: "(never ran)"` with the panel
  closed. **The gain watchdog only ran while the panel was open** — which is the
  one situation where you do not need it. Fixed by touching `Mic` from the Scope's
  `Component.onCompleted`; verified `cardIndex: 3` with the panel shut.
- Also cost four wrong diagnoses before I stopped inferring and added
  `mic status` over IPC. That handler stays.

**Still open**

- `[impact: high | effort: M | risk: low]` Noise suppression has no plugin. Either
  `noise-suppression-for-voice` from the AUR (needs your call — it is a package
  install), or the Rust denoiser in `/mnt/storage/dev/projects/denoise` as a
  LADSPA/LV2 plugin, which is Phase 2 of that project.
- `[impact: med | effort: S | risk: low]` High-pass is wired but **never switched
  on and listened to**. It builds a filter-chain that creates a virtual source;
  nothing yet points apps at it, so turning it on may do nothing visible.
- `[impact: med | effort: S | risk: low]` Echo cancellation likewise untested —
  I would not toggle it while your Bitwig routing was live.
- `[impact: med | effort: M | risk: low]` The NT1's own APHEX chain (compressor,
  gate, aural exciter) lives in mic firmware over USB-HID. No Linux support;
  would need the protocol reverse-engineered.
- `[impact: low | effort: S | risk: low]` `setVolume` clamps at `Audio.hardMaxValue`
  now, but nothing in the panel exposes input volume separately from gain.

**Angles covered:** the seams (QML ↔ shell), correctness, real-runtime cost,
first-run/lazy-instantiation. **Not covered:** failure behaviour (device removed
mid-use), repeat use over days, accessibility.

---

## Round 2 — the audio panel and the mic's place in it

Slice looked at: `modules/ii/audio/AudioSettings.qml`, the new
`services/AudioProfiles.qml`, `services/AudioLayout.qml`, and every bar/HUD
surface that reports mic mute. Prompted by the HDB 630 sounding bad and by two
crossed-out mic icons appearing in the bar at once.

**Fixed and verified this round** (screenshots taken, not inferred):

- Device rows were untracked, so `node.properties` was empty and every row but
  the active one fell to a default glyph with no subtitle — a data problem, not
  a styling one. Added a `PwObjectTracker` scoped to the list being open.
- Rows now group by how the device is ATTACHED (bus), because `kindOf()` ends in
  `return "laptop"` as a catch-all and had filed a USB DJ controller under
  "This computer" and drawn it with the tablet glyph.
- Added the mic-profile card: turning a card's microphone off removes the
  capture endpoint, so no app can open it — not a mute. Round-tripped against
  `wpctl` (profile 1 → source appears, profile 2 → gone).
- Removed the duplicate bar mic indicator (`Audio.source.muted` Revealer).

**Still open, ranked**

- `[impact: high | effort: S | risk: low]` Four different answers to "is the mic
  muted?". WHERE: `modules/common/models/quickToggles/MicToggle.qml:13`
  (`Audio.source`), `modules/ii/bar/UtilButtons.qml:113`
  (`Pipewire.defaultAudioSource`), `modules/ii/bar/BarContent.qml` and
  `MicPanel.qml` (`Mic.muted`), `modules/ii/hud/EssentialsContent.qml:155`
  (its own `micMuted`). EVIDENCE: grep, this session. WHY: `Mic` resolves an
  *effective* source through the filter chains; the others read the raw default,
  so they can disagree. The duplicate icon was the visible symptom; the cause is
  still here. Unify on the `Mic` service.

- `[impact: high | effort: S | risk: low]` `AudioProfiles` never re-reads on
  device changes. WHERE: `services/AudioProfiles.qml` — `refresh()` is called
  from the panel's `Component.onCompleted` and after its own profile switch,
  nothing else. WHY: plug a headset in while the panel is open, or change a
  profile from a terminal, and the panel is confidently stale. Hook it to
  `Pipewire.nodes` changing.

- `[impact: med | effort: S | risk: low]` The list churns for ~600 ms on open.
  EVIDENCE: photographed twice and nearly misreported as a layout bug. Before
  the first `pw-dump` lands, `isHardware()` is false for everything, so all
  devices group under "Software" with the waveform icon and then re-sort. FIX:
  while profiles are loading, treat "has `device.bus`/`device.api`" as hardware
  so the first paint is already right.

- `[impact: med | effort: S | risk: low]` `CustomIcon` requests an empty path.
  EVIDENCE: `Cannot open: file://…/assets/icons/` repeats through every reload,
  because the widget builds `basedir + ""` when the icon name is empty. Noise,
  but in the one place you look for real errors.

- `[impact: med | effort: M | risk: low]` The mic toggle only reaches the
  DEFAULT output. WHERE: `micCard` binds `Audio.sink`. WHY: if the headset is
  not the current output you cannot turn its mic off, even though the row above
  says "Mic on". It belongs on the row.

- `[impact: med | effort: M | risk: med]` Nothing restores the default sink
  after a profile switch. EVIDENCE: switching the HDB 630's profile moved output
  to the DJ-808; the panel caused it and said nothing. Restore it, or say what
  moved.

- `[impact: med | effort: M | risk: low | needs your call]` The dock drops
  silently. EVIDENCE: two mass disconnects in one day — `thunderbolt 1-2/0-2:
  device disconnected` at 20:58 took the HDB 630, DJ-808, NT1 and the USB
  ethernet with it. From the desktop's side devices just vanish. A notification
  when a whole hub goes away would have saved both investigations. Closer to a
  feature than a fix.

**Angles covered:** the seams (service ↔ panel), use it (opened and captured at
every step), correctness of what the UI ASSERTS about hardware. **Not covered:**
repeat use across dock reconnects, the vertical bar (still has only the old mic
indicator, deliberately), accessibility.
