#!/usr/bin/env bash
# Battery thresholds. The reason the bar no longer carries a battery
# icon at all: an icon that reads "fine" 95% of the time is 20px spent
# on nothing. A notification is the right shape for this -- it costs
# zero pixels until the one moment it matters.
#
# Fires once per crossing, not once per poll: $LAST holds the lowest
# threshold already announced and is cleared when you plug in.

STATE="$HOME/.cache/batt-notify.state"
INTERVAL=45
THRESHOLDS=(20 10 5)

note() { timeout 2 notify-send -a Battery "$@" >/dev/null 2>&1 || true; }

read_pct()    { cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1; }
read_status() { cat /sys/class/power_supply/BAT*/status   2>/dev/null | head -1; }

prev_status=""
last_fired=101
[[ -r "$STATE" ]] && last_fired=$(< "$STATE")

while :; do
    pct=$(read_pct); status=$(read_status)
    if [[ -n "$pct" ]]; then
        if [[ "$status" == "Discharging" ]]; then
            [[ -n "$prev_status" && "$prev_status" != "Discharging" ]] \
                && note "On battery" "${pct}%"
            for t in "${THRESHOLDS[@]}"; do
                if (( pct <= t && last_fired > t )); then
                    if (( t <= 5 )); then
                        # Critical is sticky (timeout 0 in dunstrc): at 5%
                        # a toast that fades after six seconds is a toast
                        # you will miss.
                        note -u critical "Battery ${pct}%" "Plug in now"
                    elif (( t <= 10 )); then
                        note "Battery ${pct}%" "Low"
                    else
                        note "Battery ${pct}%" "Getting low"
                    fi
                    last_fired=$t; echo "$last_fired" > "$STATE"
                    break
                fi
            done
        else
            # On AC: re-arm every threshold, and say so once.
            [[ "$prev_status" == "Discharging" ]] && note "Charging" "${pct}%"
            last_fired=101; echo "$last_fired" > "$STATE"
        fi
        prev_status="$status"
    fi
    sleep "$INTERVAL"
done
