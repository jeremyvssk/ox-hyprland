#!/usr/bin/env bash
# Wi-Fi is Quickshell's panel now (quickshell/WifiPanel.qml). eww's own
# network-panel, its -kb twin, network-get.sh and network-set.sh were
# deleted on 2026-09-13. This stays only because the retired waybar
# config still calls it on click, so a side-by-side waybar opens the
# same panel the island does.
exec qs ipc -p "$HOME/.config/quickshell/shell.qml" call panel toggle wifi
