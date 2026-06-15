#!/usr/bin/env python3
# KDE Connect → MPRIS bridge.
#
# Publishes a session-bus MPRIS player that mirrors the phone's media
# state (via KDE Connect's mprisremote DBus plugin). With this running,
# the phone's "now playing" appears in any MPRIS-aware UI alongside
# desktop players (Spotify, Firefox, etc.).
#
# Single-instance: exits if another bridge is already on the bus.

import os
import sys
import signal
import time
import dbus
import dbus.service
import dbus.mainloop.glib
from gi.repository import GLib

BUS_NAME = "org.mpris.MediaPlayer2.kdeconnect_phone"
OBJ_PATH = "/org/mpris/MediaPlayer2"
ROOT_IF  = "org.mpris.MediaPlayer2"
PLAYER_IF = "org.mpris.MediaPlayer2.Player"
PROPS_IF = "org.freedesktop.DBus.Properties"

KC_SVC  = "org.kde.kdeconnect"
KC_IF   = "org.kde.kdeconnect.device.mprisremote"


def _str(v): return str(v) if v is not None else ""
def _bool(v): return bool(v) if v is not None else False
def _int(v):
    try: return int(v)
    except: return 0


class Bridge(dbus.service.Object):
    def __init__(self, bus, device_id):
        super().__init__(bus, OBJ_PATH)
        self.device_id = device_id
        self.kc_path = f"/modules/kdeconnect/devices/{device_id}/mprisremote"
        self.bus = bus

        self.title = ""
        self.artist = ""
        self.album = ""
        self.player = ""
        self.is_playing = False
        self.length_us = 0
        self.volume_pct = 100   # mprisremote exposes 0–100; MPRIS uses 0.0–1.0
        # Position is anchored: stored as (value-at-anchor, monotonic-time-at-anchor)
        # so Get("Position") returns interpolated µs between polls.
        self._pos_anchor_us = 0
        self._pos_anchor_t  = time.monotonic()

        # Poll the phone every second; metadata can change (track end, skip).
        GLib.timeout_add(1000, self._tick)
        self._tick()

    @property
    def position_us(self):
        if not self.is_playing:
            return self._pos_anchor_us
        delta = (time.monotonic() - self._pos_anchor_t) * 1_000_000
        pos = self._pos_anchor_us + int(delta)
        if self.length_us > 0 and pos > self.length_us:
            pos = self.length_us
        return max(pos, 0)

    # ── DBus introspection helper ────────────────────────────────────
    def _kc_get(self, prop):
        try:
            obj = self.bus.get_object(KC_SVC, self.kc_path)
            return obj.Get(KC_IF, prop, dbus_interface=PROPS_IF)
        except Exception:
            return None

    def _kc_action(self, action):
        # mprisremote exposes a single sendAction(QString) method that
        # takes "Play" / "Pause" / "PlayPause" / "Stop" / "Next" / "Previous".
        try:
            obj = self.bus.get_object(KC_SVC, self.kc_path)
            obj.sendAction(action, dbus_interface=KC_IF)
        except Exception as e:
            print(f"kdeconnect sendAction {action} failed: {e}", file=sys.stderr)

    def _tick(self):
        new_title  = _str(self._kc_get("title"))
        new_artist = _str(self._kc_get("artist"))
        new_album  = _str(self._kc_get("album"))
        new_player = _str(self._kc_get("player"))
        new_play   = _bool(self._kc_get("isPlaying"))
        new_len    = _int(self._kc_get("length")) * 1000      # ms → µs
        new_pos    = _int(self._kc_get("position")) * 1000    # phone reports ms
        new_art    = _str(self._kc_get("localAlbumArtUrl"))
        new_vol    = self._kc_get("volume")
        new_vol    = _int(new_vol) if new_vol is not None else self.volume_pct

        changed = {}
        if new_vol != self.volume_pct:
            changed["Volume"] = float(max(0, min(100, new_vol))) / 100.0
            self.volume_pct = new_vol
        meta_changed = (new_title != self.title or new_artist != self.artist
                        or new_album != self.album or new_len != self.length_us
                        or new_art != getattr(self, "art_url", ""))
        self.art_url = new_art
        if meta_changed:
            changed["Metadata"] = self._metadata(new_title, new_artist, new_album, new_len, new_art)
        if new_play != self.is_playing:
            changed["PlaybackStatus"] = "Playing" if new_play else "Paused"
        if new_player != self.player:
            changed["Identity"] = new_player or "Phone"

        # Position anchoring: re-anchor whenever the phone's reported
        # position drifts from our interpolated estimate by > 1.5 s, when
        # the track changes, or when play/pause flips. Otherwise we trust
        # local interpolation so the slider doesn't jitter.
        prev_play = self.is_playing
        self.title, self.artist, self.album = new_title, new_artist, new_album
        self.player, self.is_playing = new_player, new_play
        self.length_us = new_len

        my_pos = self.position_us
        if (meta_changed or prev_play != new_play
                or abs(new_pos - my_pos) > 1_500_000):
            self._pos_anchor_us = new_pos
            self._pos_anchor_t  = time.monotonic()
            # MPRIS Seeked signals the new absolute position to clients.
            self.Seeked(dbus.Int64(new_pos))

        if changed:
            non_identity = {k: v for k, v in changed.items() if k != "Identity"}
            if non_identity:
                self.PropertiesChanged(PLAYER_IF, non_identity, [])
            if "Identity" in changed:
                self.PropertiesChanged(ROOT_IF, {"Identity": changed["Identity"]}, [])
        return True

    def _metadata(self, title, artist, album, length_us, art_url=""):
        m = dbus.Dictionary(signature="sv")
        m["mpris:trackid"] = dbus.ObjectPath("/org/kdeconnect/track/0")
        if length_us > 0:
            m["mpris:length"] = dbus.Int64(length_us)
        if title:   m["xesam:title"]   = title
        if artist:  m["xesam:artist"]  = dbus.Array([artist], signature="s")
        if album:   m["xesam:album"]   = album
        if art_url: m["mpris:artUrl"]  = art_url
        return m

    # ── org.freedesktop.DBus.Properties ──────────────────────────────
    @dbus.service.method(PROPS_IF, in_signature="ss", out_signature="v")
    def Get(self, interface, prop):
        return self.GetAll(interface).get(prop, "")

    @dbus.service.method(PROPS_IF, in_signature="s", out_signature="a{sv}")
    def GetAll(self, interface):
        if interface == ROOT_IF:
            return {
                "CanQuit": False,
                "CanRaise": False,
                "HasTrackList": False,
                "Identity": self.player or "Phone (KDE Connect)",
                "DesktopEntry": "kdeconnect",
                "SupportedUriSchemes": dbus.Array([], signature="s"),
                "SupportedMimeTypes": dbus.Array([], signature="s"),
            }
        if interface == PLAYER_IF:
            return {
                "PlaybackStatus": "Playing" if self.is_playing else "Paused",
                "LoopStatus": "None",
                "Rate": 1.0,
                "Shuffle": False,
                "Metadata": self._metadata(self.title, self.artist, self.album, self.length_us, getattr(self, "art_url", "")),
                "Volume": float(max(0, min(100, self.volume_pct))) / 100.0,
                "Position": dbus.Int64(self.position_us),
                "MinimumRate": 1.0,
                "MaximumRate": 1.0,
                "CanGoNext": True,
                "CanGoPrevious": True,
                "CanPlay": True,
                "CanPause": True,
                "CanSeek": True,
                "CanControl": True,
            }
        return {}

    @dbus.service.method(PROPS_IF, in_signature="ssv")
    def Set(self, interface, prop, value):
        if interface == PLAYER_IF and prop == "Volume":
            try: f = float(value)
            except Exception: return
            pct = max(0, min(100, int(round(f * 100))))
            try:
                obj = self.bus.get_object(KC_SVC, self.kc_path)
                obj.Set(KC_IF, "volume", dbus.Int32(pct),
                        dbus_interface=PROPS_IF)
            except Exception as e:
                print(f"set volume failed: {e}", file=sys.stderr)
            self.volume_pct = pct
            self.PropertiesChanged(PLAYER_IF, {"Volume": pct / 100.0}, [])
        elif interface == PLAYER_IF and prop == "Position":
            try: self._set_remote_position(max(0, int(value)))
            except Exception: pass

    @dbus.service.signal(PROPS_IF, signature="sa{sv}as")
    def PropertiesChanged(self, interface, changed, invalidated):
        pass

    # ── org.mpris.MediaPlayer2 ───────────────────────────────────────
    @dbus.service.method(ROOT_IF)
    def Raise(self): pass
    @dbus.service.method(ROOT_IF)
    def Quit(self): pass

    # ── org.mpris.MediaPlayer2.Player ────────────────────────────────
    @dbus.service.method(PLAYER_IF)
    def Next(self):     self._kc_action("Next")
    @dbus.service.method(PLAYER_IF)
    def Previous(self): self._kc_action("Previous")
    @dbus.service.method(PLAYER_IF)
    def Pause(self):    self._kc_action("Pause")
    @dbus.service.method(PLAYER_IF)
    def PlayPause(self): self._kc_action("PlayPause")
    @dbus.service.method(PLAYER_IF)
    def Stop(self):     self._kc_action("Stop")
    @dbus.service.method(PLAYER_IF)
    def Play(self):     self._kc_action("Play")
    @dbus.service.method(PLAYER_IF, in_signature="x")
    def Seek(self, offset_us):
        target = max(0, self.position_us + int(offset_us))
        self._set_remote_position(target)
    @dbus.service.method(PLAYER_IF, in_signature="ox")
    def SetPosition(self, trackid, pos_us):
        self._set_remote_position(max(0, int(pos_us)))
    @dbus.service.method(PLAYER_IF, in_signature="s")
    def OpenUri(self, uri): pass

    def _set_remote_position(self, pos_us):
        try:
            obj = self.bus.get_object(KC_SVC, self.kc_path)
            # mprisremote.position is a writable int property in ms.
            obj.Set(KC_IF, "position", dbus.Int32(pos_us // 1000),
                    dbus_interface=PROPS_IF)
        except Exception as e:
            print(f"setPosition failed: {e}", file=sys.stderr)
        # Re-anchor immediately so UI feedback is instant.
        self._pos_anchor_us = pos_us
        self._pos_anchor_t  = time.monotonic()
        self.Seeked(dbus.Int64(pos_us))

    @dbus.service.signal(PLAYER_IF, signature="x")
    def Seeked(self, position_us):
        pass


def _find_device():
    # Pick the first reachable+paired KDE Connect device.
    bus = dbus.SessionBus()
    try:
        dmgr = bus.get_object(KC_SVC, "/modules/kdeconnect")
        ids = dmgr.devices(True, True, dbus_interface="org.kde.kdeconnect.daemon")
        return list(ids)[0] if ids else None
    except Exception:
        return None


def main():
    if len(sys.argv) >= 2 and sys.argv[1]:
        device_id = sys.argv[1]
    else:
        device_id = _find_device()
    if not device_id:
        print("kdeconnect_mpris_bridge: no reachable device", file=sys.stderr)
        sys.exit(2)

    dbus.mainloop.glib.DBusGMainLoop(set_as_default=True)
    bus = dbus.SessionBus()

    # Single-instance — bail if the well-known name is already taken.
    if bus.name_has_owner(BUS_NAME):
        print("kdeconnect_mpris_bridge: already running", file=sys.stderr)
        sys.exit(0)
    name = dbus.service.BusName(BUS_NAME, bus=bus, do_not_queue=True)

    Bridge(bus, device_id)
    loop = GLib.MainLoop()
    signal.signal(signal.SIGTERM, lambda *_: loop.quit())
    signal.signal(signal.SIGINT,  lambda *_: loop.quit())
    loop.run()


if __name__ == "__main__":
    main()
