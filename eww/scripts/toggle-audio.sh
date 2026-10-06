#!/usr/bin/env bash
# Sound is Quickshell's panel now (quickshell/SoundPanel.qml). eww's own
# audio-panel, mic-meter.sh and audio-watch.sh were deleted on 2026-09-16
# (copies in backup/eww-audio-20260916/). This stays only because the
# retired waybar config still calls it on click, so a side-by-side waybar
# opens the same panel the island does.
exec qs ipc -p "$HOME/.config/quickshell/shell.qml" call panel toggle sound
