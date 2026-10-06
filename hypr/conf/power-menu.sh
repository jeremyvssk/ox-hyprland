#!/usr/bin/env bash
# ── SESSION MENU ─────────────────────────────────────────────────────
#
# WHY THIS SCRIPT EXISTS.
# wlogout has no layout engine: the button grid is sized purely by four
# absolute pixel margins, and it takes integers only -- no percentages.
# The bar used to call it as
#
#     wlogout -b 4 -T 642 -B 642 -L 1376 -R 1376
#
# which are numbers computed by hand for a 3440x1440 screen. The moment
# the session came up on anything else -- the 1920x1080 laptop panel, or
# the external before its mode was applied -- 1376+1376 exceeded the
# screen width, the grid collapsed, and you got the stock-looking
# unusable menu. It was never a theming regression; it was arithmetic
# done once against one resolution.
#
# So the margins are computed here, from the monitor you are actually
# looking at, every time. -n stops the surface spanning every output.

read -r MW MH SCALE < <(
    hyprctl monitors -j 2>/dev/null | jq -r '
        (map(select(.focused)) | .[0]) // .[0]
        | "\(.width) \(.height) \(.scale)"'
)
# Fall back to something sane rather than to the old broken constants.
[[ -z "$MW" || "$MW" == "null" ]] && { MW=1920; MH=1080; SCALE=1; }

# Layer-shell margins are in LOGICAL pixels, so undo the output scale.
MW=$(awk -v w="$MW" -v s="$SCALE" 'BEGIN{printf "%d", w/s}')
MH=$(awk -v h="$MH" -v s="$SCALE" 'BEGIN{printf "%d", h/s}')

# One row of four cells. The strip has to include the column spacing or
# wlogout shrinks the cells to fit and the icons drift apart from their
# labels. Measured: 150px cells 20px apart put ~108px of air between
# adjacent icon edges -- 1.7x the icon. At the 190/24 this started with
# it was 2.5x, and four icons that far apart stop reading as one row.
BTN=150
GAP=20
STRIP_W=$(( 4 * BTN + 3 * GAP ))
STRIP_H=$BTN

# ...but never wider than the screen it lands on. This is the whole
# point of the script: on the 1920 laptop panel the cells shrink, they
# do not fall off the edge.
(( STRIP_W > MW * 70 / 100 )) && STRIP_W=$(( MW * 70 / 100 ))
(( STRIP_H > MH * 24 / 100 )) && STRIP_H=$(( MH * 24 / 100 ))

LR=$(( (MW - STRIP_W) / 2 ))
TB=$(( (MH - STRIP_H) / 2 ))

# Point wlogout at this user's layout and stylesheet EXPLICITLY.
#
# Left to itself wlogout builds "$XDG_CONFIG_HOME/wlogout/layout" by
# plain string concatenation and, if that misses, silently falls back to
# /etc/wlogout -- the stock six-button grid, no error, no exit code. It
# missed for months because the session exported XDG_CONFIG_HOME as the
# literal string `~/.config` (fixed in conf/environments.conf), and a
# silent fallback is the reason that read as "the theme broke" rather
# than "the config was not found".
#
# Passing both paths removes the fallback from the picture entirely, so
# this keeps working no matter what any future session sets XDG_* to.
LAYOUT="$HOME/.config/wlogout/layout"
STYLE="$HOME/.config/wlogout/style.css"

# ...and if they are genuinely missing, say so instead of quietly
# rendering someone else's menu.
for f in "$LAYOUT" "$STYLE"; do
    if [[ ! -r "$f" ]]; then
        notify-send -u critical "Session menu" "Missing $f" 2>/dev/null
        exit 1
    fi
done

exec wlogout -n -b 4 -l "$LAYOUT" -C "$STYLE" \
    -c "$GAP" -r "$GAP" -T "$TB" -B "$TB" -L "$LR" -R "$LR"
