#!/usr/bin/env bash
# Watches BlueZ and toasts every connect / disconnect / power change.
#
# It owns the SUCCESS half of bluetooth notifications, so it catches the
# events no click ever sees: a headset powering itself off, a phone
# connecting from its own side, the adapter genuinely dropping.
# bluetooth-set.sh owns the FAILURE half, because only the caller knows
# why a connect attempt was refused.
#
# ── THE BUG THIS FILE HAD ────────────────────────────────────────────
# snapshot() ran its own busctl call with no timeout and printed
# "ADAPTER:none" whenever the JSON failed to parse -- which is also what
# it printed when the bus merely failed to answer. A momentary read
# failure was therefore indistinguishable from the adapter being ripped
# out, and the very next line fired a CRITICAL red toast about it.
#
# Observed: two "Bluetooth / Adapter unavailable" criticals followed by
# "Bluetooth on", with NOTHING in the journal for that window -- no
# rfkill event, no hci0 removal, no bluetoothd message. The adapter
# never moved. The toasts were a failed D-Bus read being announced as
# hardware loss, and they landed while a headset was connected and
# playing, which is what made them read as "wacky".
#
# ── WHAT REPLACES IT ─────────────────────────────────────────────────
# 1. All reads go through bt-snapshot.sh, which reports ok:false for a
#    failed read instead of inventing an absent adapter. An ok:false
#    tick is skipped entirely: not news, nothing to say.
# 2. "The adapter is gone" must be asserted by CONFIRM consecutive
#    SUCCESSFUL reads before it is announced. A real unplug says so
#    every time and still surfaces in ~9s; a one-tick blip says it once
#    and is dropped.
# 3. The first successful read after start is the BASELINE, not an
#    event -- otherwise every login toasts whatever was already true.
# 4. Nothing is announced until the adapter has been seen at least once,
#    so the boot race (this starts as a Hyprland exec-once, well before
#    bluetooth.target is guaranteed) cannot produce a startup toast.

STATE="$HOME/.cache/bt-notify.state"
INTERVAL=3

# Consecutive confirmations required before "the adapter is gone" is
# treated as true. 3 x 3s -- long enough to outlast any blip, short
# enough that pulling the dongle still tells you within ten seconds.
CONFIRM=3

note() { timeout 2 notify-send -a Bluetooth "$@" >/dev/null 2>&1 || true; }

# ADAPTER:<on|off|none> plus one DEV: line per connected device.
# Returns non-zero and prints nothing when the read failed.
snapshot() {
    "$HOME/.config/eww/scripts/bt-snapshot.sh" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(1)
# A failed read is not a state. Say nothing and let the caller skip.
if not d.get("ok"):
    sys.exit(1)
a = d.get("adapter")
if a is None:
    sys.exit(1)
print("ADAPTER:" + a)
for x in d.get("devices", []):
    if x.get("connected") == "yes":
        print("DEV:" + x["name"])
'
}

devs() { grep '^DEV:' <<< "$1" | sort; }
adap() { grep '^ADAPTER:' <<< "$1"; }

# ── Establish a baseline before saying anything ──────────────────────
# Keep trying until the bus answers. Until it does there is no "before"
# to compare against, so there is nothing that could legitimately be
# announced.
prev=""
while [[ -z "$prev" ]]; do
    prev=$(snapshot) || prev=""
    [[ -z "$prev" ]] && sleep "$INTERVAL"
done
printf '%s\n' "$prev" > "$STATE"

none_streak=0

while :; do
    sleep "$INTERVAL"

    cur=$(snapshot) || continue   # failed read: not news, skip the tick
    [[ -z "$cur" ]] && continue
    [[ "$cur" == "$prev" ]] && continue

    pa=$(adap "$prev"); ca=$(adap "$cur")

    # ── Adapter absence has to earn it ───────────────────────────────
    if [[ "$ca" == "ADAPTER:none" ]]; then
        none_streak=$((none_streak + 1))
        if (( none_streak < CONFIRM )); then
            # Unconfirmed. Do not announce, and do not advance prev --
            # if this was a blip, the next tick matches the old state
            # and no transition is ever seen.
            continue
        fi
    else
        none_streak=0
    fi

    if [[ "$pa" != "$ca" ]]; then
        case "$ca" in
            ADAPTER:on)   note "Bluetooth on" ;;
            ADAPTER:off)  note "Bluetooth off" ;;
            ADAPTER:none) note -u critical "Bluetooth" "Adapter unavailable" ;;
        esac
    fi

    # Device churn is only meaningful while the adapter was up on BOTH
    # sides. A device list that emptied because the adapter went away is
    # not a pile of disconnect toasts -- the adapter line already said it.
    if [[ "$ca" == "ADAPTER:on" && "$pa" == "ADAPTER:on" ]]; then
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            note "Connected" "${line#DEV:}"
        done < <(comm -13 <(devs "$prev") <(devs "$cur"))
        while IFS= read -r line; do
            [[ -z "$line" ]] && continue
            note "Disconnected" "${line#DEV:}"
        done < <(comm -23 <(devs "$prev") <(devs "$cur"))
    fi

    prev="$cur"
    printf '%s\n' "$prev" > "$STATE"
    pkill -SIGRTMIN+2 waybar 2>/dev/null || true
done
