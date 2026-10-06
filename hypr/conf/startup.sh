#!/bin/bash
# Session services. The display layout is NOT here any more -- it is an
# exec-once of its own (conf/monitors.sh), because it has to win before
# anything paints.

# ——— THE TRAY WAIT IS GONE, AND ITS ABSENCE IS THE POINT ———
# There used to be a loop here that blocked for up to 10s waiting for
# waybar to claim org.kde.StatusNotifierWatcher, so that kded6 could not.
# The reasoning was sound and is worth keeping: that bus name is
# first-come-first-served; kded6 is D-Bus activatable and grabs it the
# instant any KDE app touches the session bus -- dolphin below is exactly
# such an app -- and it then holds the name WITHOUT exporting
# /StatusNotifierWatcher, which is the `GDBus.Error ... No such object
# path` in the old waybar log and the reason tray icons never appeared.
# Disabling the kded module does not help: kded loads that one on demand
# regardless of autoload.
#
# The bar is Quickshell now and it draws NO TRAY, so there is nothing to
# claim the name and the loop could only ever have waited out its full
# 10s, every login, before starting dolphin and the portals. A wait for
# something that is not coming is not caution, it is a delay.
#
# WHAT THIS COSTS: kded6 will take the name, and the next app that wants
# a tray icon will find a watcher that exports nothing. It costs nothing
# TODAY -- measured at handover, waybar's watcher held zero items -- and
# the fix is a tray in the island rather than a sleep here. Quickshell
# 0.3.1 ships Quickshell.Services.SystemTray; when the island grows a
# tray, this loop comes back with `waybar` swapped for `quickshell`.
# → open-items.md

# ——— File manager daemon ———
if ! pgrep -x dolphin > /dev/null; then
    dolphin --daemon &
fi

# ——— XDG portals ———
# Hyprland + GTK only. The KDE portal is deliberately absent: with it
# present, xdg-desktop-portal hands screencast/file-chooser requests to
# a backend that expects plasmashell, and the two portals then disagree
# about which one owns a request. `systemctl --user start
# plasma-kded.service` and `xdg-desktop-portal-kde.service` used to be
# started here and BOTH silently failed -- neither unit exists under
# those names (they are plasma-kded6 / plasma-xdg-desktop-portal-kde),
# so the lines were dead weight pretending to be setup.
killall xdg-desktop-portal-hyprland xdg-desktop-portal xdg-desktop-portal-gtk 2>/dev/null

/usr/lib/xdg-desktop-portal-hyprland &
/usr/lib/xdg-desktop-portal-gtk &
sleep 1
/usr/lib/xdg-desktop-portal &

echo "[$(date)] Hyprland portals started by startup.sh" >> "$HOME/.cache/hypr-portals.log"

# ——— eww, last ———
# eww's layer-shell popups bind to the monitor layout that exists when
# the daemon starts; starting it in parallel with the layout pass breaks
# click routing on popup buttons (see architecture.md). It
# used to wait on `pgrep -x kanshi`; kanshi is gone, so it now waits on
# the state file monitors.sh writes once the layout is settled.
(
    for _ in {1..20}; do
        [[ -s "${XDG_RUNTIME_DIR:-/tmp}/hypr-monitors.state" ]] && break
        sleep 0.5
    done
    sleep 1
    pkill -x eww 2>/dev/null
    eww --config "$HOME/.config/eww" daemon &
) &
