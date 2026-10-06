#!/usr/bin/env bash
# Wi-Fi state for the bar. return-type json.
#
# ICONS — Material Design Icons only (U+F0xxx), stroke-drawn.
# The old set used mdi wifi-strength-4 (U+F0928), a SOLID filled wedge:
# next to the hairline-thin bluetooth rune it read as a blob. mdi-wifi
# (U+F05A9) is the same arc-fan drawn as strokes, so the two radios now
# carry the same optical weight.
#
#   connected   󰖩  U+F05A9  wifi
#   off         󰖪  U+F05AA  wifi-off
#   fault       󰖩  U+F05A9  (dim, tooltip says why)
#
# Signal strength is NOT encoded in the glyph any more. Four near-
# identical fans are unreadable at 15px, and strength lives in the
# tooltip and in the network panel where there is room for a number.

state=$(nmcli -t -f STATE general status 2>/dev/null || echo "unknown")

emit() { printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$1" "$2" "$3"; }

if [[ "$state" == "connected" ]]; then
    ssid=$(nmcli -t -f active,ssid dev wifi 2>/dev/null \
        | awk -F: '$1=="yes"{print $2; exit}')
    if [[ -n "$ssid" ]]; then
        sig=$(nmcli -t -f active,signal dev wifi 2>/dev/null \
            | awk -F: '$1=="yes"{print $2+0; exit}')
        emit "󰖩" "$ssid — ${sig}%" "connected"
    else
        emit "󰈁" "Ethernet" "connected"
    fi
elif [[ "$state" == "disconnected" ]]; then
    emit "󰖪" "Wi-Fi off" "off"
else
    # NEVER emit empty text: waybar draws an empty label as nothing, and
    # the click target vanishes with it -- see waybar-bluetooth.sh.
    emit "󰖪" "No network" "off"
fi
