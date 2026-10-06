#!/usr/bin/env bash
# Volume for the bar. Icon only -- the number is gone.
#
# The percentage was removed because the glyph already carries the read:
# no waves / one wave / two waves / slashed. What the old script did NOT
# have was enough levels for that to be true -- it had three, spaced
# 0/40/70, so anything from 70 to 100 looked identical. Four levels on
# even thirds, plus two distinct silent states, is what makes the icon
# sufficient.
#
#   muted     󰝟  U+F0581  volume-mute   (deliberately muted)
#   zero      󰝞  U+F075F  volume-off    (turned all the way down)
#   low       󰕿  U+F057F  volume-low    (1-33)
#   medium    󰖀  U+F0580  volume-medium (34-66)
#   high      󰕾  U+F057E  volume-high   (67-100)
#
# Exact level is in the tooltip and in the audio panel.

# ONE read, not two. This script is re-executed by waybar on every
# SIGRTMIN+4 from audio-watch.sh -- i.e. on every volume change, which
# during a key repeat is several a second -- and `audio-get.sh state`
# answers both questions from a single wpctl round trip. Asking for
# `volume` and then `mute` was two forks of this script's own helper and
# two round trips, on the hot path of the thing that is supposed to feel
# instant.
read -r vol mute _ _ < <(~/.config/eww/scripts/audio-get.sh state 2>/dev/null)
[[ "${vol:-}" =~ ^[0-9]+$ ]] || vol=0
[[ "${mute:-}" == "true" ]] || mute=false

if [[ "$mute" == "true" ]]; then
    printf '{"text":"󰝟","tooltip":"Muted (%s%%)","class":"off"}\n' "$vol"
elif (( vol == 0 )); then
    printf '{"text":"󰝞","tooltip":"Volume 0%%","class":"off"}\n'
elif (( vol < 34 )); then
    printf '{"text":"󰕿","tooltip":"Volume %s%%"}\n' "$vol"
elif (( vol < 67 )); then
    printf '{"text":"󰖀","tooltip":"Volume %s%%"}\n' "$vol"
else
    printf '{"text":"󰕾","tooltip":"Volume %s%%"}\n' "$vol"
fi
