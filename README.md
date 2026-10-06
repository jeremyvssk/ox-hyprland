# Ox Hyprland

A minimal Linux desktop for developers, built on Hyprland and Quickshell.

One small bar sits at the top of the screen. Wi-Fi, Bluetooth, sound, app
search and your calendar all open out of that bar. The bar itself grows into
the panel, so there are no separate pop-up windows.

> **Status: preview.** It works, and it is my daily desktop. It is not ready
> for you to install yet.
>
> **Full launch: 1 November 2026 (01.11.2026)**, with a settings menu and an
> install guide.

<!-- DEMO VIDEO: drop the video file here in GitHub's editor -->

## What's ready

- **The bar.** One glass bar, centred at the top, 38 px tall. It shows your
  workspaces, the clock, and icons for Wi-Fi, Bluetooth and sound. It has three
  sizes: compact, normal and full. **Super+Alt+B** switches between them.
  Full also shows CPU, RAM and battery.
- **Wi-Fi.** Known networks and the ones nearby. Join a network by typing the
  password right in the list. Disconnect and forget.
- **Bluetooth.** Your devices and their battery level. Connect, disconnect,
  scan for new devices and pair them.
- **Sound.** Output and input volume. Switch between speakers and headphones.
  Each app that is playing gets its own volume slider.
- **Search.** Press **Super+Shift+S** (or Super+S), type a few letters, press
  Enter to start the app.
- **Calendar and notes.** Click the clock, or press **Super+Shift+C**. A month view, a page for each day,
  and notes with a time. Notes can repeat (on chosen days, or every few days,
  with an end date). A reminder shows up as a notification.
- **Hyprland config in Lua** (Hyprland 0.56): keybinds, window rules,
  animations, and a monitor script that turns the laptop screen off while an
  external monitor is plugged in.
- **Notifications** (dunst), low-battery warnings, and a power menu (wlogout).

## What's coming

**1.0 launches on 1 November 2026** with the settings menu and an install
guide. The rest of the list is planned, not dated.

| Feature | What it is | Status |
|---|---|---|
| **Settings menu** | Customise the desktop from a menu instead of editing config files. | In progress, for 1.0 |
| **Install guide** | Step-by-step setup on a fresh system. | In progress, for 1.0 |
| **Full-width bar** | In its full size, the bar stretches across the whole top edge of the screen, with CPU, RAM and battery. | Planned |
| **Power menu in Quickshell** | Lock, log out, restart and shut down, rebuilt to match the bar. Replaces wlogout. | Planned |
| **Workspace rework** | A new workspace indicator. | Maybe |

## Keys

Every menu opens from the keyboard. Press the same keys again to close it.
Wi-Fi, Bluetooth, Sound, the calendar and the power menu also open with a
click on their icon (or the clock) in the bar.

| Keys | Opens |
|---|---|
| Super + Shift + S (or Super + S) | Search |
| Super + Shift + W | Wi-Fi |
| Super + Shift + B | Bluetooth |
| Super + Shift + A | Sound (audio) |
| Super + Shift + C | Calendar |
| Super + Shift + P | Power menu |

| Keys | Does |
|---|---|
| Super + Alt + B | Bar size: compact → normal → full |
| Super + 1 … 5 | Go to workspace 1 to 5 |
| Super + Shift + 1 … 5 | Move the window to workspace 1 to 5 |
| Super + T | Terminal (kitty) |
| Super + Q | Close the window |
| Super + F | Fullscreen |
| Super + Space | Float the window |
| Super + Alt + L | Lock the screen |

## What's in this repo

| Folder | What it is |
|---|---|
| `quickshell/` | The bar and every panel. Start with `shell.qml`. |
| `hypr/` | Hyprland config, written in Lua. |
| `eww/` | Scripts the bar still uses: the app list behind Search (`scripts/apps.py`) and low-battery warnings. The old eww pop-ups are gone; the folder keeps its old name for now. |
| `dunst/`, `wlogout/`, `rofi/` | Notifications, the power menu, the old launcher. |

The wallpaper is not included. Point `hypr/hyprpaper.conf` at your own.

## Requirements

Hyprland 0.56 or newer (Lua config), Quickshell 0.3.1, eww 0.5.0, dunst,
wlogout, rofi, hyprpaper, hyprlock, kitty, NetworkManager, BlueZ and PipeWire.

### Fonts

Two fonts are required and are **not bundled**. Install them from your
distribution. Without them Qt silently substitutes another face: the bar and the
panels still work, but they will not look like the demo.

| Font | Used for | Arch package |
|---|---|---|
| **Adwaita Sans** | Names, titles, tracked capitals (`Theme.fontSans`, `Theme.fontCaps`) | `adwaita-fonts` |
| **JetBrainsMono Nerd Font**, v3 or later | Numbers, buttons, and every icon glyph (`Theme.fontMono`) | `ttf-jetbrains-mono-nerd` |

Nerd Fonts **v3** is required, not v2. v3 moved the Material Design icons to
new code points, so on v2 about half the bar's icons are blank boxes.

Check both:

    fc-list "Adwaita Sans" | head -1
    fc-list "JetBrainsMono Nerd Font" | head -1
    fc-list ':charset=f0450' family | grep -q 'JetBrainsMono Nerd Font' && echo "Nerd Fonts v3"

### The Search panel

Super+S opens the bar's Search panel (`quickshell/SearchPanel.qml`). It reads its
app index from `eww/scripts/apps.py` and launches through it, so it needs:

| Needs | Why | Arch package |
|---|---|---|
| `python3` | builds the index, records what you open, launches | `python` |
| `gio` | starts the app from its `.desktop` file (field codes, `Terminal=true`) | `glib2` |
| `setpriv` | the panel's helper dies with the bar | `util-linux` |
| **Papirus** icon theme, optional | app icons; without it hicolor icons are used, and an app with none gets a letter tile | `papirus-icon-theme` |

Super+S is a Hyprland global shortcut (`hl.dsp.global("quickshell:search")` in
`hypr/conf/keybinds.lua`), not a script, so the panel has the keyboard before your first
letter lands. Check it is registered:

    hyprctl globalshortcuts | grep quickshell:search

## Credits

The power menu icons (lock, log out, restart, shut down) are from
[Font Awesome Free](https://fontawesome.com), licensed
[CC BY 4.0](https://creativecommons.org/licenses/by/4.0/), recoloured to match
the bar.
