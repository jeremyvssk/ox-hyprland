#!/usr/bin/env bash
# THE DRAWER — a continuous waybar module.
#
# ── WHY CONTINUOUS AND NOT POLLED ────────────────────────────────────
# waybar drives a custom module three ways: `interval` (re-exec on a
# timer), `signal` (re-exec on SIGRTMIN+n), or NEITHER -- in which case
# "it is assumed that the out script loops itself" and waybar just reads
# lines off the pipe. The first two both re-exec the script per update,
# and that was measured at a 35-82ms floor (9 signalled updates took
# 372ms, with 47ms of jitter between them). An animation on that budget
# drops and doubles frames visibly.
#
# Read off a pipe there is no exec at all: this script owns the clock,
# emits a line per frame at 16ms, and the whole open takes ~200ms with
# no jitter. This is the standard waybar pattern for anything that
# animates.
#
# Requires, in waybar-modules.json: NO `interval`, NO `signal` (either
# one switches waybar back to re-exec mode), and "exec-on-event": false
# so a click does not restart the daemon underneath itself.
#
# ── WHY THE WIDTH TWEEN IS MADE OF SPACES ────────────────────────────
# GTK3 CSS can animate min-width, but min-width is a FLOOR: a GtkLabel
# never renders narrower than its own text, so there is no CSS route
# from a 250px readout down to a 12px chevron. The width has to come
# from the text. The frames are the chevron plus N blank monospace
# cells; the readout only fades in once the space already exists, which
# is the same two-phase reveal a GtkRevealer would do.
#
# Verified with Pango at the module's own size (13px): the last blank
# frame -- chevron plus 28 spaces -- and EVERY possible readout measure
# 232px exactly, including `BAT 100%  CPU 99%  RAM 99%` and
# `CHG 5%  CPU 3%  RAM 7%` with its eight trailing spaces. So the
# reveal does not snap and no value can change the width. Pango counts
# trailing spaces in a label's logical extents, which is what makes the
# blank frames work at all -- and, since the readouts are padded on the
# right too, what makes them all the same width as each other.
# CELLS below is that width, and it is derived, not chosen.
#
# ── WHERE THE SLACK GOES ─────────────────────────────────────────────
# The width must not change: the drawer is the LAST module in a
# content-hugging centred island, so one extra cell of text re-centres
# the pill and slides the clock 4px sideways. Something therefore has
# to absorb the difference between `100` and `3`, and the only question
# is where it is spent.
#
# It used to be spent by RIGHT-aligning each number into a fixed-width
# field, which puts it in the worst place available -- BETWEEN A LABEL
# AND ITS NUMBER:
#
#     BAT  95%  CPU   3%  RAM  42%     three columns everywhere
#     BAT  95%  CPU  3%  RAM 42%       BAT 3 columns, CPU/RAM 2
#
# The second line is what shipped, and the gap inside a group is then
# the SAME two cells as the gap between groups: `95%` reads as though it
# belongs to `CPU`, and at `CPU   8%` the number is stranded in the
# middle of nothing with a label at either side. A label and its number
# are the one pair on this readout that has to hold together, and the
# padding was breaking exactly that pair -- while the group boundaries
# it was supposed to be subordinate to got the same two cells.
#
# So every number now sits hard against its label -- ONE space, always,
# whatever it reads -- and all the slack is spent at the END of the
# readout as trailing spaces. Pango counts trailing spaces in a label's
# logical extents; that is not a trick borrowed for this, it is the same
# property the blank animation frames below are made of. The module is
# still exactly CELLS wide on every frame and the island still never
# moves. What breathes instead is the run of nothing between `RAM 20%`
# and the pill's right edge -- background, where nothing is drawn and
# nothing moves when it changes size.
#
# CPU and RAM are still CLAMPED to 99, but the reason is no longer the
# blank leading cell (there are none now). It buys one cell of MAXIMUM
# width: a CPU that could reach 100 makes the widest readout 27 cells,
# which means CELLS 29 and a rebuilt frame table. A pegged CPU reading
# 99% is the cheaper of the two.
#
# ── THE GAP BETWEEN THE THREE GROUPS ─────────────────────────────────
# TWO spaces, not three. Three was 24px of nothing between readings
# whose own internal gap is 8px -- a 3:1 ratio, which does not read as
# "these are three separate things", it reads as three things that have
# drifted apart. At two it is 16px against 8px: still unmistakably a
# group boundary, at two thirds of the emptiness.
#
# This is not a free number either. It sets CELLS (see below), which
# sets the frame table, which has to end on exactly that value or the
# reveal snaps. Changing it means re-deriving both, and re-measuring in
# Pango that the last blank frame still equals every possible readout.
# At 2 that was measured: 232px, both.

FIFO="$HOME/.cache/sysinfo.fifo"
# CELLS is the width of the full readout in monospace cells, and it is
# NOT a free number: the last blank frame has to measure the same width
# as the readout that replaces it, or the reveal snaps. Count it from
# the format below and nowhere else --
#   2 (the gap after the chevron)
#   + 8  "BAT 100%"   (3 label + 1 gap + up to 3 digits + 1 percent)
#   + 2  gap
#   + 7  "CPU 99%"    (3 label + 1 gap + up to 2 digits + 1 percent)
#   + 2  gap
#   + 7  "RAM 99%"
#   = 28
# Since the numbers are no longer padded individually this is a MAXIMUM
# rather than a constant, and sample() pads the readout out to it on the
# right. BODY below is the same number without the chevron gap.
CELLS=28                       # visible cells of the full readout
BODY=26                        # ... of which the readout itself
FRAME=0.016                    # 60fps while animating
IDLE=2                         # readout refresh when open

# ── THE TWEEN, AND WHY IT WAS JANKY ──────────────────────────────────
# The width of this module can only change in whole monospace cells --
# 8px at a time -- because the width comes from the text (see above).
# So the frame table is not sampling a curve, it IS the animation, and
# what the eye reads as smooth is the SPACING BETWEEN ITS STEPS, not
# the shape of the curve behind them.
#
# The old table was an ease-out quad over 12 frames: 4 8 12 16 19 22 24
# 26 28 29 31 32. Two faults, both visible:
#   * it opened with three consecutive 4-cell steps -- 32px per frame,
#     and the island re-centres by half of that, so the whole bar
#     lurched sideways twice before the drawer had drawn anything;
#   * it ended 28 29 31 32, alternating 1 and 2 cell steps, which reads
#     as a stutter right where the motion should be settling.
#
# This table is built the other way round: pick the STEPS first, ease
# them in and back out, and never let one exceed 3 cells.
#   steps  2 2 3 3 3 3 3 2 2 2 1 1 1
#   cum    2 4 7 10 13 16 19 21 23 25 26 27 28
# 13 frames at 16ms = 208ms, no step larger than 24px, no step in the
# tail bigger than the one before it, and no repeated frame. The curve
# it traces is a soft ease-in-out rather than an ease-out, which is the
# right shape for something that is unrolling rather than falling.
#
# (The previous table ended on 30 and read `2 4 7 10 13 16 19 22 24 26
# 28 29 30`. It changed only because CELLS did -- the group gap went
# from three spaces to two. The shape is the same.)
#
# IF YOU CHANGE CELLS: rebuild this table to end exactly on the new
# value under the same rules. A table that ends anywhere else makes the
# last blank frame a different width from the readout, and the reveal
# snaps by the difference.
FRAMES=(2 4 7 10 13 16 19 21 23 25 26 27 28)

DIM="#637875"    # --dim : the label, which you do not read twice
INK="#E6EFEC"    # --ink : the number, which is the point

CHEV_OPEN=$'\U000F0141'   # chevron-left  : click to close
CHEV_SHUT=$'\U000F0142'   # chevron-right : click to open, grows right

[[ -p "$FIFO" ]] || { rm -f "$FIFO"; mkfifo "$FIFO"; }
# Held read-write so the fifo always has a reader: a toggle written when
# nobody is listening would otherwise block the clicking process.
exec 3<>"$FIFO"

prev_busy=0; prev_total=0; body=""; last_sample=0

sample() {
    local u n s i w irq sirq steal busy total db dt cpu mem pct st lbl
    read -r _ u n s i w irq sirq steal _ < /proc/stat
    busy=$((u+n+s+irq+sirq+steal)); total=$((busy+i+w))
    db=$((busy-prev_busy)); dt=$((total-prev_total))
    # /proc/stat deltas, not `top -bn1`: top cost ~1s per call and
    # reported one instantaneous sample instead of the interval.
    if (( prev_total > 0 && dt > 0 )); then cpu=$(( (db*100 + dt/2) / dt )); else cpu=0; fi
    prev_busy=$busy; prev_total=$total
    (( cpu < 0 )) && cpu=0; (( cpu > 100 )) && cpu=100

    mem=$(awk '/^MemTotal:/{t=$2} /^MemAvailable:/{a=$2} END{printf "%d",(t-a)/t*100}' /proc/meminfo)
    # Two columns, so 100 has to become 99. See the header: the drawer
    # is the last module in a centred island and one extra cell moves
    # the whole bar.
    (( cpu > 99 )) && cpu=99
    (( mem > 99 )) && mem=99
    pct=$(cat /sys/class/power_supply/BAT*/capacity 2>/dev/null | head -1)
    st=$(cat /sys/class/power_supply/BAT*/status 2>/dev/null | head -1)
    [[ -z "$pct" ]] && pct="--"
    lbl=BAT; [[ "$st" == "Charging" ]] && lbl=CHG

    # Pango attribute values use SINGLE quotes: this string is about to
    # be embedded in a JSON object and a double quote would terminate
    # the "text" field. One GTK label cannot hold two colours any other
    # way, and the dim label / bright number split is the whole point.
    # No field width -- the number goes one space after its label and
    # stays there. See "WHERE THE SLACK GOES" in the header.
    row() { printf "<span foreground='%s'>%s</span> <span foreground='%s'>%s%%</span>" \
            "$DIM" "$1" "$INK" "$2"; }
    body="$(row "$lbl" "$pct")  $(row CPU "$cpu")  $(row RAM "$mem")"

    # The slack, all of it, at the end. Counted on the VISIBLE text --
    # body is full of Pango markup, so ${#body} is not a cell count.
    # Per group: 3 label + 1 gap + 1 percent = 5, plus its digits;
    # three groups and two 2-cell gaps is 19 + digits, and 26 when every
    # reading is at its widest.
    printf -v tail '%*s' "$(( BODY - 19 - ${#pct} - ${#cpu} - ${#mem} ))" ''
    body="${body}${tail}"
}

emit_shut()  { printf '{"text":"%s","tooltip":"Battery, CPU and memory","class":"collapsed"}\n' "$CHEV_SHUT"; }
emit_frame() { printf -v pad '%*s' "$1" ''
               printf '{"text":"%s%s","tooltip":"","class":"%s"}\n' "$CHEV_OPEN" "$pad" "$2"; }
emit_full()  { printf '{"text":"%s  %s","tooltip":"","class":"%s"}\n' "$CHEV_OPEN" "$body" "$1"; }

state=shut
emit_shut

while :; do
    case "$state" in
        shut|open) wait_for=$IDLE ;;
        *)         wait_for=$FRAME ;;
    esac

    if read -r -t "$wait_for" -u 3 _msg; then
        case "$state" in
            shut|closing) state=opening; idx=0 ;;
            *)            state=closing; idx=$(( ${#FRAMES[@]} - 1 )) ;;
        esac
        continue
    fi

    case "$state" in
        opening)
            if (( idx < ${#FRAMES[@]} )); then
                emit_frame "${FRAMES[idx]}" opening; (( idx++ ))
            else
                sample; last_sample=$SECONDS
                emit_full reveal      # opacity 0 ...
                sleep 0.016
                emit_full expanded    # ... so .expanded fades it up
                state=open
            fi
            ;;
        closing)
            if (( idx >= 0 )); then
                emit_frame "${FRAMES[idx]}" closing; (( idx-- ))
            else
                emit_shut; state=shut
            fi
            ;;
        open)
            (( SECONDS - last_sample >= IDLE )) && { sample; last_sample=$SECONDS; }
            emit_full expanded
            ;;
        shut)
            emit_shut
            ;;
    esac
done
