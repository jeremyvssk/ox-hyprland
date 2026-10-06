#!/usr/bin/env bash
# One byte down the fifo. sysinfo.sh owns the animation clock.
# timeout guards the case where the daemon is not running: a write to a
# fifo with no reader blocks forever, and that would hang the click.
FIFO="$HOME/.cache/sysinfo.fifo"
[[ -p "$FIFO" ]] || exit 0
timeout 0.4 bash -c "echo t > '$FIFO'" 2>/dev/null
