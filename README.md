# archy

My Hyprland setup. Hyprland 0.56's native Lua config, a Waybar top bar, Wofi
for launching, and one colors file that drives everything.

I keep it here so I can rebuild a machine from this and nothing is a mystery
six months later.

## What I'm running

| | |
|---|---|
| compositor | Hyprland 0.56+, configured in Lua |
| bar | Waybar, 26px, flush to the top edge |
| launcher | Wofi (drun), also used for every menu |
| terminal | kitty, ExtraLight at 11.5 |
| shell | bash + starship |
| notifications | mako, action buttons handled by wofi |
| lock / idle | hyprlock via hypridle |
| wallpaper | swww, crossfaded |
| clipboard | wl-clipboard + cliphist |
| capture | grim + slurp, hyprpicker for the color picker |
| recording | gpu-screen-recorder |
| brightness | hyprsunset, as a gamma filter |
| files | nautilus |
| browser | zen |

A few of these are not the obvious choice, so the reasoning is here:

1. Brightness is gamma, not a backlight. This panel rejects DDC/CI writes, so
   `brightnessctl` and the kernel backlight both do nothing. hyprsunset applies
   gamma in the compositor, which every output honors. 100 is identity, lower
   is dimmer. archy-brightness stores the value and reapplies it at login,
   because gamma is compositor state and does not survive a restart.

2. The pointer is the macOS Apple cursor, and it takes two settings to make
   that happen, which is the single easiest thing to get half right here.
   `XCURSOR_THEME` and `XCURSOR_SIZE` are read by XWayland clients only — a
   native Wayland app has no cursor of its own, the compositor draws it, and
   hyprcursor takes the theme from gsettings while
   `cursor:sync_gsettings_theme` is on. Both are in `hypr/cursor.lua`, which is
   the only file to touch to change it. The theme is from
   [apple_cursor](https://github.com/ful1e5/apple_cursor) (GPL-3.0) and is not
   an official package, so `install.sh` puts it in place if it is missing:
   AUR helper first, release tarball as the fallback.

3. Wofi handles the notification actions. mako draws the notification and hands
   the buttons to wofi, so there is one overlay style instead of two.

4. No `uwsm-app`. Apps launch with plain `setsid`, so a keybind-started process
   is a child of the compositor rather than a systemd scope. If I ever want
   scoped units, it goes back in `o.launch` in `hypr/helpers.lua`.

5. The config is Lua, not hyprlang. Hyprland 0.56 takes either, and the
   cascade, the clipboard chords and the region picker's transient bindings are
   stateful enough that imperative code is clearer than the declarative form.

## Setting up a new machine

```sh
sudo pacman -S --needed \
  hyprland hyprlang hyprcursor hypridle hyprlock hyprsunset hyprpolkitagent \
  waybar wofi mako kitty wtype \
  grim slurp hyprpicker gpu-screen-recorder wl-clipboard cliphist \
  libpulse wireplumber playerctl \
  xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  swww udiskie jq \
  ttf-jetbrains-mono-nerd
```

Then:

```sh
git clone https://github.com/ax1g/archy ~/archy
cd ~/archy
./scripts/install.sh --check     # reports what is missing, changes nothing
./scripts/install.sh
```

`install.sh` symlinks the checkout to `~/.config/archy`, symlinks `hypr/` to
`~/.config/hypr`, links the scripts into `~/.local/bin`, links `Xresources` to
`~/.Xresources`, installs the cursor theme if it is missing, and generates the
stylesheets. It is idempotent, so after every `git pull`:

```sh
git -C ~/archy pull && ~/archy/scripts/install.sh
```

If `~/.config/hypr` is already a real directory the installer leaves it alone
and tells me to move it aside. That is deliberate: I want the old config
recoverable while I am still finding out whether I like the new one.

**Cursor.** The macOS Apple cursor, which is not an official package, so
nothing installs it by default. `install.sh` fetches it when it is missing —
AUR helper if there is one, otherwise the release tarball — and never fails the
install over it, because a missing cursor is cosmetic. To do it by hand:

```sh
paru -S apple_cursor
# or
curl -L https://github.com/ful1e5/apple_cursor/releases/latest/download/macOS.tar.gz \
  | tar -xz -C ~/.local/share/icons
```

`install.sh --check` looks for `index.theme` inside the theme directory, since
that is what fontconfig reads — a directory of cursor files without it does not
resolve and the pointer silently stays the default arrow.

**Fonts.** `ttf-jetbrains-mono-nerd`, the full weight set. The `-basic`
package has only Regular, Bold, Italic and BoldItalic, and kitty here is set to
`style="ExtraLight"`, so with `-basic` alone kitty silently falls back to a
different weight and stops matching the rest of the desktop. `install.sh
--check` tests for the ExtraLight face specifically, not just the family name.

**Login.** No display manager is required — Hyprland boots straight into a
session. If I want a login screen I install one separately, and it needs a
session entry for Hyprland to show up in its list.

**Cleanup after a migration.** Anything left in `~/.local/share/fonts/` that
duplicates an installed package will shadow it. Delete the local copy and run
`fc-cache -fv`.

## Layout

```
archy/
├── hypr/                  the config, loaded through hyprland.lua
│   ├── hyprland.lua       entry point and load order
│   ├── helpers.lua        the o.* layer over Hyprland's hl.* API
│   ├── theme.lua          reads colors/colors.conf
│   ├── envs.lua           environment variables
│   ├── cursor.lua         cursor theme and size
│   ├── monitors.lua       output, mode, scale
│   ├── input.lua          keyboard, mouse, touchpad
│   ├── looknfeel.lua      gaps, decoration, blur, animation
│   ├── windows.lua        window rules and tags
│   ├── tiling.lua         core bindings
│   ├── bindings.lua       my bindings
│   ├── floatcascade.lua   new-window cascade, SUPER+T
│   ├── qconsole.lua       the Quake console
│   ├── screencopy.lua     capture permissions
│   ├── hypridle.conf      idle and lock
│   ├── hyprsunset.conf    brightness and nightlight
│   └── Xresources         XWayland text rendering
├── colors/
│   ├── colors.conf        the theme file
│   └── themes/            alternates, picked with SUPER+SHIFT+T
├── kitty/kitty.conf       terminal
├── data/emoji.txt         the SUPER+. picker's list
├── waybar/                bar config and stylesheet
├── wofi/                  launcher config
├── generated/             written by archy-theme, not edited
├── wallpapers/
├── test/                  load-test harness
└── scripts/               archy-* commands, installed to ~/.local/bin
```

## Theme

`colors/colors.conf` is the only file I edit to change themes. Hyprland reads
it directly through `hypr/theme.lua`; everything else gets it from
`archy-theme`, which writes `generated/`:

| generated file | consumer |
|---|---|
| `waybar.css` | `waybar -s` |
| `wofi.css` | `wofi --style` |
| `mako.conf` | `mako -c` |
| `kitty.conf` | `include` from `kitty/kitty.conf` |
| `hyprlock.qml` | `hyprlock -q` |

```sh
archy-theme apply    # regenerate, reload Hyprland, restart the surfaces
archy-theme sync     # regenerate only
archy-theme current  # print the active theme name
```

Second themes go in `colors/themes/` as complete copies of `colors.conf`, and
`SUPER+SHIFT+T` picks one. The menu copies the chosen file over the live one
and keeps a `.bak` beside it, so a bad switch is undoable without git.

Things worth knowing about the generated files, all of which cost me a round
trip at some point:

1. Waybar and Wofi both render through GTK, and GTK's CSS parser has no support
   for CSS custom properties. The generated stylesheets use `@define-color`, not
   `--name: value`. A `--name` rule is dropped silently and the bar comes up
   colorless, with nothing in the logs.

2. Waybar takes exactly one stylesheet, so `generated/waybar.css` is the palette
   followed by the whole of `waybar/style.css`. That is what lets the
   hand-written file reference `@define-color` names instead of pasting a second
   copy of every color.

3. Wofi parses `--config` and `--style` separately, so a color declared in one
   is not visible in the other. Anything colored lives in `generated/wofi.css`;
   `wofi/config.rasi` is layout only.

4. Kitty and mako read their palettes at startup. An already-open terminal keeps
   the old colors until it is restarted, so `archy-theme apply` says so instead
   of closing my windows.

5. starship.toml is hand-maintained, so its colors are static. It does not follow
   a theme change the way the terminal and bar do.

## Keys

`SUPER+K` lists the live bindings, read out of `hyprctl` rather than parsed from
the config files, so it shows what the compositor actually has.

| key | does |
|---|---|
| `SUPER+SPACE` | launcher |
| `SUPER+ALT+SPACE` | window switcher |
| `SUPER+RETURN` | terminal |
| `SUPER+.` | emoji picker |
| `SUPER+T` | tile or float the whole workspace |
| `SUPER+S` | scratchpad |
| `` SUPER+` `` | Quake console |
| `SUPER+O` | pop a window out, pinned |
| `SUPER+C` / `V` / `X` | copy / paste / cut, everywhere |
| `SUPER+CTRL+V` | clipboard history |
| `SUPER+SHIFT+S` | screenshot region |
| `PRINT` | screenshot |
| `ALT+PRINT` | record |
| `SUPER+SHIFT+T` | theme |
| `SUPER+CTRL+SPACE` | wallpaper |
| `SUPER+SHIFT+SPACE` | toggle the bar |
| `SUPER+ESCAPE` | power |
| `SUPER+CTRL+L` | lock |

| key | opens |
|---|---|
| `SUPER+B` | zen-browser |
| `SUPER+SHIFT+B` | zen-browser, private |
| `SUPER+D` | drawy |
| `SUPER+SLASH` | code |
| `SUPER+E` | nautilus |
| `SUPER+M` | cliamp |
| `SUPER+A` | opencode |
| `SUPER+P` | btop |
| `SUPER+SHIFT+A` | ChatGPT |
| `SUPER+SHIFT+G` | Gmail |
| `SUPER+SHIFT+SLASH` | GitHub |
| `SUPER+SHIFT+M` | MonkeyType |
| `SUPER+SHIFT+W` | Word |
| `SUPER+SHIFT+E` | Excel |

`SUPER+C` sends `CTRL+Insert` instead of `CTRL+C` when a terminal is focused,
because in a terminal `CTRL+C` is SIGINT. `SUPER+V` sends `SHIFT+INSERT` for
the same reason. The detection is a tag on the window, not a class list, so it
survives a new terminal.

`ALT+TAB` and `ALT+SHIFT+TAB` are each bound twice on purpose: Hyprland runs
every binding on a key, so they cycle the window *and* lift it above whatever is
floating over it. Splitting them would make revealing a window a two-key action.

## Look

All of it is in `hypr/looknfeel.lua`, and it is tuned for a 1080p panel at
scale 1, not for a high-DPI screen.

- 4px inner and 8px outer gaps, no borders, 8px rounding.
- Frost at 0.93, blur with `ignore_opacity` so it does not stack.
- Shadows on, tinted with the theme's darkest color rather than plain black.
- Windows open with a center zoom from 15% with a slight overshoot, and close
  mirrored. Closing fades at the same speed as the scale, because a faster fade
  turns every close into a pure fade and buries the zoom.
- Workspaces are a pure `slide`. `slidefade` leaves the old one fading
  underneath, which reads as a millisecond ghost.
- The bar is 26px with a 12px monospace family, and the Quake console measures
  the work area under it. Changing the bar height means re-checking that
  console still covers half the screen.

New windows cascade: 1680x945 centered, each extra one offset 20px down-right,
wrapping at 8 steps. `SUPER+T` flips the whole workspace between tiled and
floating. Kitty is configured to match — `placement_strategy top-left` and
`scrollback_fill_enlarged_window yes`, because the window size is rarely an exact
multiple of the cell size and the leftover padding otherwise reads as a blank
first line.

## Testing

```sh
./scripts/test.sh
```

It loads the whole config against a stub of Hyprland's `hl.*` API whose surface
is transcribed from the strings of the installed hyprland binary, so a call the
compressor does not have fails in the test instead of at login. It also reports
keys bound more than once, and unbinds of keys nothing binds.

The shell side is checked separately: the theme generator's output, and that the
Lua and shell palette parsers agree — a disagreement there means the compositor
and the bar read one file and come out with different themes.

It runs against a fake `HOME`, so nothing touches the live desktop. The only
live queries are read-only, `hyprctl` for gamma and `pactl` for the sink list.
Do not add a check that passes a mutating argument: an earlier version called the
volume script with no arguments, which the usage error turned into a volume
raise, and it moved the real volume.

`luac -p` and `bash -n` are not enough on their own. They pass on a config whose
palette parses to nothing, because there is nothing syntactically wrong with an
empty string.
