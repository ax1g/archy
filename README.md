# archy

A standalone Hyprland desktop. No Omarchy.

Hyprland 0.56's native Lua config, a Waybar top bar, Wofi for launching, and a
single colors file that is the only thing you edit to retheme.

```
archy/
├── hypr/                  Hyprland config, loaded through hyprland.lua
│   ├── hyprland.lua       entry point and load order
│   ├── helpers.lua        the o.* layer over Hyprland's hl.* API
│   ├── theme.lua          reads colors/colors.conf
│   ├── envs.lua           environment variables
│   ├── monitors.lua       output, mode, scale
│   ├── input.lua          keyboard, mouse, touchpad
│   ├── looknfeel.lua      gaps, decoration, blur, animation
│   ├── windows.lua        window rules and tags
│   ├── tiling.lua         core bindings
│   ├── bindings.lua       personal bindings
│   ├── floatcascade.lua   new-window cascade, SUPER+T
│   ├── qconsole.lua       the Quake console
│   ├── screencopy.lua     capture permissions
│   ├── hypridle.conf      idle and lock
│   ├── hyprsunset.conf    brightness and nightlight
│   └── Xresources         XWayland text rendering
├── colors/
│   ├── colors.conf        THE theme file
│   └── themes/            alternates, picked with SUPER+SHIFT+T
├── kitty/kitty.conf       terminal, unchanged from the current setup
├── data/emoji.txt         the SUPER+. picker's list
├── waybar/                bar config and stylesheet
├── wofi/                  launcher config
├── generated/             written by archy-theme, not edited
├── wallpapers/
├── test/                  load-test harness
└── scripts/               archy-* commands, installed to ~/.local/bin
```

## What is yours, unchanged

**Kitty.** `kitty/kitty.conf` is your current config byte for byte, with one
change: the theme include pointed into the Omarchy tree
(`~/.local/state/omarchy/current/theme/kitty.conf`), which stops existing with
Omarchy. It now includes `generated/kitty.conf`, written by `archy-theme` from
`colors/colors.conf`, so the terminal keeps following the theme.

The font block is untouched and load-bearing:

```
font_family family="JetBrainsMono Nerd Font" style="ExtraLight"
font_size 11.5
```

ExtraLight only exists in `ttf-jetbrains-mono-nerd`, the full weight set. The
`-basic` package that Omarchy pulled in carries just Regular, Bold, Italic and
BoldItalic, so on a machine with only that, kitty falls back to a different
weight and the terminal quietly stops matching everything else. `install.sh`
checks for the ExtraLight face specifically, not just the family name.

**Font in the bar and lock screen.** Same family, 12px, which is what the
Omarchy bar used: it resolved `monospace` through fontconfig to
"JetBrainsMono Nerd Font" at `base-size = 12`, in a 26px strip. Waybar is
configured to 26px with a 12px family so the bar occupies exactly the same
space and the Quake console's usable-height math is unchanged.

**Shell.** Bash, with starship. `~/.config/starship.toml` is a regular file
with no Omarchy references, so it survives untouched. One consequence: its
colors were written from the theme at install time, so it will not follow a
theme change the way the terminal and bar do.

**Bash.** `~/.bashrc` is untouched, including the starship prompt hook.

## Requirements

Hyprland 0.56 or newer. The config is written against the native Lua API
(`hl.bind`, `hl.window_rule`, `hl.on`), which does not exist before 0.56.

```sh
sudo pacman -S --needed \
  waybar wofi mako hypridle hyprlock hyprpicker wtype \
  grim slurp gpu-screen-recorder wl-clipboard cliphist \
  libpulse wireplumber playerctl \
  xdg-desktop-portal xdg-desktop-portal-hyprland xdg-desktop-portal-gtk \
  hyprpolkitagent hyprsunset swww udiskie jq \
  kitty ttf-jetbrains-mono-nerd
```

`install.sh --check` reports what is missing without changing anything. Note
that `pactl` ships in `libpulse`, so the package list is not the same as the
command list.

## Install

```sh
git clone https://github.com/ax1g/archy
cd archy
./scripts/install.sh --check    # see what would happen
./scripts/install.sh            # do it
```

The installer symlinks the checkout into `~/.config/archy`, symlinks `hypr/`
into `~/.config/hypr`, links the scripts into `~/.local/bin`, and generates
the stylesheets. It is idempotent, so re-run it after every `git pull`.

If `~/.config/hypr` is a real directory, the installer leaves it alone and tells
you to move it aside. Do that rather than deleting it — it is your current
working config, and it is the thing you come back to if this does not work out.

### Login

archy does not install a display manager, and none is required: Hyprland boots
straight into a session. If you want a login screen, install one separately.
Note that most display managers need a session entry for Hyprland to appear in
their list.

## Theming

`colors/colors.conf` is the only file to change. Hyprland reads it through
`theme.lua`, and everything else reads it through `archy-theme`, which writes
`generated/`:

| generated file  | consumer                                |
|-----------------|-----------------------------------------|
| `waybar.css`    | `waybar -s`                             |
| `wofi.css`      | `wofi --style`                          |
| `mako.conf`     | `mako -c`                               |
| `kitty.conf`    | `include` from `kitty/kitty.conf`       |
| `hyprlock.qml`  | `hyprlock -q`                           |

```sh
archy-theme apply    # regenerate, reload Hyprland, restart the surfaces
archy-theme sync     # regenerate only
archy-theme current  # print the active theme name
```

Both Waybar and Wofi render through GTK, and GTK's CSS parser has no support
for CSS custom properties — so the generated stylesheets use `@define-color`
rather than `--name: value`. A `--name` rule would be dropped silently and the
bar would come up colorless.

Waybar takes exactly one stylesheet, so `generated/waybar.css` is the palette
followed by the whole of `waybar/style.css`. That is what lets the
hand-written file reference `@define-color` names instead of pasting a second
copy of every color.

Wofi is different: it parses `--config` and `--style` separately, so a color
declared in one is not visible in the other. Anything colored lives in
`generated/wofi.css`; `wofi/config.rasi` is layout only.

Kitty and the notification daemon read their palettes at startup, so an
already-open terminal keeps the old colors until it is restarted.
`archy-theme apply` says so rather than closing your windows for you.

### Themes

Drop a second `colors.conf` in `colors/themes/` and pick it with `SUPER+SHIFT+T`.
The menu copies the chosen file over the live one and keeps a `.bak` beside it,
so switching is reversible without git.

A theme is a color file and nothing else. GTK and Qt widget themes, icon
themes and cursor themes are named packages, not color values, and a colors
file cannot change them. The cursor here is set separately in `looknfeel.lua`
and is already decoupled.

## Keys

`SUPER+K` lists the live bindings, read out of `hyprctl` rather than parsed from
the config files, so it shows what the compositor actually has.

The ones worth knowing:

| key                | does                                  |
|--------------------|---------------------------------------|
| `SUPER+SPACE`      | launcher                              |
| `SUPER+ALT+SPACE`  | window switcher                       |
| `SUPER+RETURN`     | terminal (kitty)                      |
| `SUPER+.`          | emoji picker                          |
| `SUPER+T`          | tile or float the whole workspace     |
| `SUPER+S`          | scratchpad                            |
| `` SUPER+` ``      | Quake console                         |
| `SUPER+C`/`V`/`X`  | copy / paste / cut, everywhere        |
| `SUPER+CTRL+V`     | clipboard history                     |
| `PRINT`            | screenshot                            |
| `SUPER+SHIFT+S`    | screenshot region                     |
| `ALT+PRINT`        | record                                |
| `SUPER+SHIFT+T`    | theme                                 |
| `SUPER+CTRL+SPACE` | wallpaper                             |
| `SUPER+ESCAPE`     | power                                 |
| `SUPER+CTRL+L`     | lock                                  |

`SUPER+C` sends `CTRL+Insert` instead of `CTRL+C` when a terminal is focused,
because in a terminal `CTRL+C` is SIGINT. `SUPER+V` sends `SHIFT+INSERT` for
the same reason.

Every app binding in `hypr/bindings.lua` is one that was already bound in the
current setup, carried over unchanged:

| key                 | opens                        |
|---------------------|------------------------------|
| `SUPER+B`           | zen-browser                  |
| `SUPER+SHIFT+B`     | zen-browser (private)        |
| `SUPER+D`           | drawy                        |
| `SUPER+SLASH`       | code                         |
| `SUPER+E`           | nautilus                     |
| `SUPER+M`           | cliamp (TUI)                 |
| `SUPER+A`           | opencode (TUI)               |
| `SUPER+P`           | btop (TUI)                   |
| `SUPER+SHIFT+A`     | ChatGPT                      |
| `SUPER+SHIFT+G`     | Gmail                        |
| `SUPER+SHIFT+SLASH` | GitHub                       |
| `SUPER+SHIFT+M`     | MonkeyType                   |
| `SUPER+SHIFT+W`     | Word                         |
| `SUPER+SHIFT+E`     | Excel                        |

Omawrite is not bound: it ships from the Omarchy repository. Drawy does too, if
you want that gone as well — say so and it comes out.

Two keys are deliberately bound twice: `ALT+TAB` and `ALT+SHIFT+TAB` each run
both cycle-window and reveal-on-top, which is how the current setup behaves.

## Notes on two decisions

**Lua, not hyprlang.** Hyprland 0.56 can be configured in either. Lua was
already in use here, and the cascade, the clipboard chords and the region
picker's transient bindings are all stateful enough that imperative code is
clearer than the declarative form. The config that ships as
`~/.config/hypr` is a symlink into this repo, so `git pull` is the update.

**No launcher wrapper.** Applications are launched with `setsid` and nothing
else. There is no `uwsm-app` in the path, so a process started from a keybind
is a child of the compositor rather than a systemd scope — if you want scoped
units, add `systemd-run --user --scope` back in `o.launch` in `helpers.lua`.

## What this drops

Coming from Omarchy, these had no standalone equivalent and are gone rather
than reimplemented:

- The Quickshell bar and every panel that hung off it (audio, bluetooth,
  network, power, clipboard, screenshots, monitor, calendar, and the
  per-workspace layout switcher).
- `omarchy-menu` and its whole tree of submenus.
- Theme hooks. Anything Omarchy used to regenerate per theme — fastfetch, the
  terminal palette, browser themes, editor themes — is now either static
  (`starship.toml`) or generated by `archy-theme` (the terminal, bar, launcher,
  notifications and lock screen).
- The audio output switcher and the equalizer.
- The screen-time tracker and the workspace HUD.
- Omarchy's screenshot, recording and webcam tooling, replaced by grim, slurp,
  hyprpicker and gpu-screen-recorder.
- `uwsm-app`. Applications launch with `setsid`, so a keybind-started process is
  a child of the compositor rather than a systemd scope. If you want scoped
  units back, add `systemd-run --user --scope` in `o.launch` in `helpers.lua`.

## Testing

```sh
./scripts/test.sh
```

Two layers. The first loads the whole config against a stub of Hyprland's
`hl.*` API whose surface is transcribed from the strings of the installed
hyprland binary, so a call the compositor does not have fails in the test rather
than on a login screen. It also reports keys bound more than once and unbinds
of keys nothing binds. The second checks the theme generator's output and that
the Lua and shell palette parsers agree, since a disagreement there means the
compositor and the bar read one file and come out with different themes.

It runs against a fake `HOME`, so nothing touches your desktop. The only live
queries are read-only: `hyprctl` for the gamma value, `pactl` for the sink
list. Do not add checks that pass mutating arguments — an earlier version of
this suite called the volume script with no arguments, which the usage error
turned into a volume raise, and it moved the real volume.
