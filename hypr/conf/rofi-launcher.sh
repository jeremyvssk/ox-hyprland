#!/bin/sh
# Every app you launch from here INHERITS this environment. That is why
# XDG_CURRENT_DESKTOP matters: it used to say KDE, so anything started
# from the launcher believed it was running in Plasma and asked for the
# KDE portal, the KDE file dialog and Plasma notification hints -- while
# the same app started from a terminal or a keybind behaved like a
# Hyprland app. Two different behaviours for one program, depending on
# how you opened it, is the exact "half KDE half Hyprland" feeling.
#
# Qt apps still look right: QT_QPA_PLATFORMTHEME=qt6ct is what themes
# them, and it does not need XDG_CURRENT_DESKTOP to be KDE.
export XDG_CURRENT_DESKTOP=Hyprland
export XDG_SESSION_TYPE=wayland
export XDG_SESSION_DESKTOP=Hyprland

export XDG_DATA_HOME=$HOME/.local/share
export XDG_DATA_DIRS=$XDG_DATA_HOME/applications:/usr/share/applications:/usr/local/share/applications
export DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/$(id -u)/bus
export XDG_ICON_DIRS=/usr/share/icons:/usr/share/pixmaps:/usr/share/icons/Papirus-Dark

export QT_QPA_PLATFORMTHEME=qt6ct
export QT_QPA_PLATFORM=wayland

exec rofi -show drun -show-icons -theme ~/.config/rofi/torbik-bar.rasi
