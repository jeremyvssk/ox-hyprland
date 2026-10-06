#!/usr/bin/env bash
# Bluetooth is Quickshell's panel now (quickshell/BluetoothPanel.qml).
# eww's own bluetooth-panel, its -kb twin, bluetooth-get.sh,
# bluetooth-set.sh, bt-watch.sh and eww's bt-agent.py were deleted on
# 2026-09-16. This stays only because the retired waybar config still
# calls it on click, so a side-by-side waybar opens the same panel the
# island does.
exec qs ipc -p "$HOME/.config/quickshell/shell.qml" call panel toggle bluetooth
