#!/usr/bin/env bash

# Get current workspace ID from the focused monitor
current=$(hyprctl monitors -j | jq -r '.[0].activeWorkspace.id')

if [ -z "$current" ] || ! [[ "$current" =~ ^[0-9]+$ ]]; then
    echo "Error: Could not get current workspace ID" >&2
    exit 1
fi

direction="$1"  # "next" or "prev"

if [ "$direction" = "next" ]; then
    next=$(( (current % 5) + 1 ))
elif [ "$direction" = "prev" ]; then
    next=$((current - 1))
    if [ $next -lt 1 ]; then
        next=5
    fi
else
    echo "Usage: $0 next|prev" >&2
    exit 1
fi

hyprctl dispatch "hl.dsp.focus({ workspace = $next })"
