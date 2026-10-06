#!/usr/bin/env bash
# ── ONE BLUEZ READ, SHARED BY EVERYTHING ─────────────────────────────
#
# WHY THIS FILE EXISTS.
# Five separate things polled org.bluez GetManagedObjects on their own
# schedule: the waybar module (3s), bt-notify.sh (3s), and the eww
# defpolls bt-powered / bt-devices / bt-status (3s each). Each one
# spawned its own busctl + python3, and -- the actual bug -- each one
# mapped "my read came back empty" onto "there is no adapter".
#
# That conflation is what produced the two symptoms:
#   * bt-notify.sh fired a CRITICAL red "Adapter unavailable" toast,
#     then "Bluetooth on" a few seconds later. The journal for that
#     window has no adapter removal, no rfkill event and no bluetoothd
#     message -- the adapter never went anywhere. The toast was a
#     failed read being reported as hardware loss.
#   * waybar-bluetooth.sh drew the crossed-out 󰂲 "off" glyph on the
#     same failed read, so the bar flipped to the disabled-looking icon
#     while a headset was connected and playing.
#
# So: one reader, one cache, and a HARD distinction between the three
# states a read can be in --
#
#     ok:true  adapter:on|off|none   the bus answered; this is truth
#     ok:false                        the bus did not answer; this is
#                                     NOT news, and nothing may render
#                                     or announce it as "no adapter"
#
# Consumers hold their last known-good state across an ok:false rather
# than repainting or toasting. A genuine adapter loss still surfaces,
# because a genuine loss answers the bus with adapter:none.
#
# The cache doubles as de-duplication: reads inside FRESH_MS are served
# from the file, so a burst of consumers waking on the same tick costs
# one D-Bus round trip instead of five.
#
# Output (single line):
#   {"ts":<epoch_ms>,"ok":<bool>,"adapter":"on|off|none",
#    "devices":[{"mac","name","connected","paired","trusted"}],
#    "age_ms":<int>}
#
# Usage: bt-snapshot.sh [--fresh]
#   --fresh  bypass the freshness window; use right after an action
#            that just changed state, so the UI does not show the
#            pre-action value it cached 400ms ago.

CACHE="${XDG_RUNTIME_DIR:-/tmp}/bt-snapshot.json"

# Long enough to collapse a same-tick stampede, short enough that no
# consumer ever shows data older than its own poll interval.
FRESH_MS=900

# Past this, a cached value stops being "the adapter as it was a moment
# ago" and starts being a guess. Consumers degrade instead.
STALE_MS=30000

now_ms() { date +%s%3N; }

read_cache() { [[ -r "$CACHE" ]] && cat "$CACHE" 2>/dev/null; }

# Reuse a recent successful read unless told not to.
if [[ "${1:-}" != "--fresh" ]]; then
    cached=$(read_cache)
    if [[ -n "$cached" ]]; then
        reuse=$(printf '%s' "$cached" | NOW="$(now_ms)" FRESH="$FRESH_MS" python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not d.get("ok"):
    sys.exit(1)
age = int(os.environ["NOW"]) - int(d.get("ts", 0))
if 0 <= age < int(os.environ["FRESH"]):
    d["age_ms"] = age
    print(json.dumps(d))
else:
    sys.exit(1)
' 2>/dev/null)
        if [[ -n "$reuse" ]]; then
            printf '%s\n' "$reuse"
            exit 0
        fi
    fi
fi

# ── WHY THIS READ IS PYTHON AND NOT `busctl --json` ──────────────────
# It was busctl, and busctl is why the panel and the bar kept saying
# "Adapter unavailable" with a headset connected and playing.
#
# Reproduced, not guessed: press Scan, let it find anything that
# advertises, then read the tree --
#
#   $ busctl --system --json=short call org.bluez / \
#       org.freedesktop.DBus.ObjectManager GetManagedObjects
#   Failed to dump DBus message to JSON object: Invalid argument
#
# org.bluez.Device1 carries ManufacturerData as a{qv} and ServiceData
# as a{sv}-with-byte-arrays. busctl's JSON dumper cannot represent a
# dictionary keyed by a uint16, so it fails the WHOLE reply -- not the
# one property, not the one device. One advertising device in range
# therefore took out every consumer of this file at once: the panel
# emptied, the bar drew the crossed-out rune, and bt-notify.sh had a
# "no adapter" story to tell. The adapter never moved; `bluetoothctl
# show` said Powered: yes throughout.
#
# That data is written into the tree BY a scan and ages out on its own,
# which is exactly the shape of the intermittency this file's header
# was written about -- and the reason the old comment blamed concurrent
# polling: the failures clustered after a scan, and scans came from the
# panel, which was also the thing polling.
#
# dbus-python reads the same tree with real types and never has to
# serialise it, so ManufacturerData is simply a value we do not look
# at. It is already a dependency: scripts/bt-agent.py is a bluez agent
# built on it.
out=$(timeout 3 python3 -c '
import json, sys, time

now = int(time.time() * 1000)

# An exception here is a FAILED READ, never "no adapter". BlueZ saying
# it has no adapter is a successful read that returns an object tree
# with no Adapter1 in it -- handled further down.
try:
    import dbus
    bus = dbus.SystemBus()
    om = dbus.Interface(bus.get_object("org.bluez", "/"),
                        "org.freedesktop.DBus.ObjectManager")
    objs = om.GetManagedObjects()
except Exception:
    print(json.dumps({"ts": now, "ok": False}))
    sys.exit()

adapters = [i for i in objs.values() if "org.bluez.Adapter1" in i]
if not adapters:
    # A real answer with no adapter in it: rfkill soft-block removes the
    # object entirely, as does unplugging a USB controller.
    adapter = "none"
else:
    adapter = "on" if any(
        bool(a.get("org.bluez.Adapter1", {}).get("Powered", False))
        for a in adapters) else "off"

devices = []
for ifaces in objs.values():
    dev = ifaces.get("org.bluez.Device1")
    if not dev:
        continue
    mac = str(dev.get("Address", ""))
    if not mac:
        continue
    name = str(dev.get("Alias") or dev.get("Name") or mac)
    conn = bool(dev.get("Connected", False))
    pair = bool(dev.get("Paired", False))
    # Trusted is what decides whether a paired device may reconnect on
    # its own. It is read here rather than looked up per row because it
    # is already in this object tree -- and because a headset that pairs
    # and then never comes back the next morning is untrusted, which is
    # a thing the panel now has to be able to say out loud.
    trust = bool(dev.get("Trusted", False))
    # connected -> paired -> merely discovered. A scan drops a pile of
    # one-off nearby MACs into the tree and an unsorted list buries the
    # headphones you actually use.
    devices.append((0 if conn else 1 if pair else 2, name.lower(), {
        "mac": mac,
        "name": name,
        "connected": "yes" if conn else "no",
        "paired": "yes" if pair else "no",
        "trusted": "yes" if trust else "no",
    }))
devices.sort(key=lambda t: (t[0], t[1]))

print(json.dumps({
    "ts": now, "ok": True, "adapter": adapter,
    "devices": [x[2] for x in devices], "age_ms": 0,
}))
' 2>/dev/null)

[[ -z "$out" ]] && out="{\"ts\":$(now_ms),\"ok\":false}"

# Only a SUCCESSFUL read is allowed to become the cached truth -- a
# failure must never overwrite the last good state, or "hold what you
# had" degrades into "hold the failure".
if grep -q '"ok": true' <<< "$out" || grep -q '"ok":true' <<< "$out"; then
    tmp="${CACHE}.$$"
    printf '%s\n' "$out" > "$tmp" 2>/dev/null && mv -f "$tmp" "$CACHE" 2>/dev/null
    printf '%s\n' "$out"
    exit 0
fi

# Read failed. Hand back the last good value, aged, so the caller can
# decide whether to keep showing it or degrade. STALE_MS is the cutoff.
cached=$(read_cache)
if [[ -n "$cached" ]]; then
    aged=$(printf '%s' "$cached" | NOW="$(now_ms)" STALE="$STALE_MS" python3 -c '
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
if not d.get("ok"):
    sys.exit(1)
age = int(os.environ["NOW"]) - int(d.get("ts", 0))
if age >= int(os.environ["STALE"]):
    sys.exit(1)
# ok:false says "this read failed"; the adapter/devices fields are the
# last known good ones and age_ms says how old. Consumers render these
# and stay quiet.
d["ok"] = False
d["age_ms"] = age
print(json.dumps(d))
' 2>/dev/null)
    if [[ -n "$aged" ]]; then
        printf '%s\n' "$aged"
        exit 0
    fi
fi

printf '%s\n' "$out"
