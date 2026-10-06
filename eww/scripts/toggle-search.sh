#!/usr/bin/env bash
# Search is Quickshell's panel now (quickshell/SearchPanel.qml), since
# 2026-09-16. Super+S and Super+R call this, and so does the retired
# waybar, so every way in opens the same panel the island's mark does.
exec qs ipc -p "$HOME/.config/quickshell/shell.qml" call panel toggle search
