#!/usr/bin/env bash
# Bluetooth status for the bar. return-type json.
#
# States, distinguished by GLYPH not by brightness -- see the colour law
# at the top of torbik/waybar/style.css. A connected radio and an idle
# one are both --mid and differ by rune; only "asleep" dims.
#
#   unavailable  󰂲  .off        adapter genuinely gone / rfkill
#   off          󰂲  .off        adapter present, Powered = false
#   on, idle     󰂯  (no class)  resting icon colour
#   connected    󰂱  (no class)  resting icon colour, different rune
#
# FAULT 1 (fixed earlier): the failure path emitted text:"" and waybar
# renders an empty label as NOTHING, so the icon and its click target
# both vanished. Every path below emits a glyph.
#
# FAULT 4 (fixed here): the failure path emitted the crossed-out .off
# glyph -- so a momentary D-Bus read failure repainted the bar as
# "bluetooth asleep" while a headset was connected and playing. That is
# the icon flipping to the old disabled-looking rune for no reason.
# A failed read is NOT a state change: bt-snapshot.sh hands back the
# last known-good adapter and device list with ok:false, and this now
# renders THAT. The bar only goes dim when BlueZ actually answers and
# says the adapter is gone.
#
# FAULT 5 (fixed here): "old icon, then new icon, then old again".
# The bar sampled BlueZ on its own 3s timer, independently of the four
# other things that did the same, and shared a 900ms cache with them --
# so during the ~3s a headset takes to come up it could easily read the
# cache written just BEFORE the connect landed, draw the idle rune, and
# only pick up the connected one a tick later. Two fixes, both needed:
#
#   1. bt-watch.sh now drives this module from BlueZ signals, coalesced,
#      so the intermediate states of a connect are never drawn at all.
#      The interval in waybar-modules.json is only a safety net now.
#   2. The hold below. Connected -> not-connected is the transition that
#      was flickering, and it is also the one that costs nothing to
#      delay: a drop must be seen for HOLD_MS before the bar acts on it.
#      A real disconnect still lands within about a second (bt-watch.sh
#      fires a confirmation read a second after every change); a
#      one-sample blip never reaches the screen.
#
# All reads go through bt-snapshot.sh so the bar and the eww panel share
# one D-Bus round trip and one definition of the truth.

"$HOME/.config/eww/scripts/bt-snapshot.sh" | \
HOLD_FILE="${XDG_RUNTIME_DIR:-/tmp}/bt-bar-hold" python3 -c '
import json, os, sys, time

OFF  = "\U000F00B2"
IDLE = "\U000F00AF"
CONN = "\U000F00B1"

# How long a "no longer connected" reading must persist before the bar
# believes it. Long enough to outlast the churn of a connect handshake,
# short enough that switching a headset off still registers immediately
# to a human.
HOLD_MS = 900

HOLD_FILE = os.environ.get("HOLD_FILE", "")

def hold_state():
    try:
        with open(HOLD_FILE) as f:
            return json.load(f)
    except Exception:
        return {}

def save_hold(d):
    if not HOLD_FILE:
        return
    try:
        tmp = HOLD_FILE + ".tmp"
        with open(tmp, "w") as f:
            json.dump(d, f)
        os.replace(tmp, HOLD_FILE)
    except Exception:
        pass

def emit(text, tooltip="", cls=None):
    o = {"text": text, "tooltip": tooltip}
    if cls:
        o["class"] = cls
    # ensure_ascii=False: the glyphs are non-BMP and the escaped
    # surrogate-pair form does not survive the waybar JSON parser.
    print(json.dumps(o, ensure_ascii=False))

try:
    d = json.load(sys.stdin)
except Exception:
    d = {}

adapter = d.get("adapter")

# No adapter field at all means we have neither a live read nor a usable
# cached one -- bluetoothd down since boot, or the cache aged out. This
# is the only path that may claim unavailability, and it stays clickable.
if adapter is None:
    emit(OFF, "Bluetooth unavailable — click to retry", "off")
    sys.exit()

stale = "" if d.get("ok") else "  (last known)"

if adapter == "none":
    emit(OFF, "No Bluetooth adapter" + stale, "off"); sys.exit()
if adapter == "off":
    emit(OFF, "Bluetooth off" + stale, "off"); sys.exit()

names = [x["name"] for x in d.get("devices", []) if x.get("connected") == "yes"]
now = int(time.time() * 1000)
h = hold_state()

if names:
    # Connected is never held back -- only the drop is.
    save_hold({"names": names, "since": None})
    emit(CONN, ", ".join(names) + stale)
    sys.exit()

held = h.get("names") or []
if held:
    since = h.get("since") or now
    if now - since < HOLD_MS:
        # Not believed yet. Keep drawing the connected rune and the
        # device it belongs to; a blip ends here and never shows.
        save_hold({"names": held, "since": since})
        emit(CONN, ", ".join(held) + stale)
        sys.exit()

save_hold({"names": [], "since": None})
emit(IDLE, "Bluetooth on \u2014 no device connected" + stale)
'
