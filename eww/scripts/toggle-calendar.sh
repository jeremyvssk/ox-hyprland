#!/usr/bin/env bash
# The calendar is Quickshell's panel now (quickshell/CalendarPanel.qml,
# 2026-09-28): the clock grows the island's body into it. This stays
# because the retired waybar config still calls it on click, so a
# side-by-side waybar opens the same panel the island does.
exec qs ipc -p "$HOME/.config/quickshell/shell.qml" call panel toggle calendar
