#!/usr/bin/env bash
# Weekly pending-update count. Deliberately weekly, not hourly: an
# update prompt you see every day is an update prompt you stop reading.
#
# checkupdates (pacman-contrib) uses a private sync database, so it does
# NOT touch /var/lib/pacman and never needs root or a polkit prompt.
# It exits 2 when there is nothing to do.

n=$(checkupdates 2>/dev/null | wc -l)
(( n == 0 )) && exit 0

if aur=$(command -v yay); then
    a=$("$aur" -Qua 2>/dev/null | wc -l)
else
    a=0
fi

body="$n from the repos"
(( a > 0 )) && body="$body, $a from the AUR"

timeout 5 notify-send -a Updates -u low \
    "$n pending update$( ((n!=1)) && echo s )" "$body" >/dev/null 2>&1 || true
