#!/usr/bin/env bash
# archy: install or update.
#
# Symlinks this checkout into ~/.config/archy, links the entry point into
# ~/.config/hypr, installs the scripts into ~/.local/bin, generates the
# stylesheets, and reports anything the desktop needs that is not installed.
#
# Idempotent: safe to re-run after every git pull.
#
# Usage: install.sh [--check] [--force]
#
#   --check   report what is missing and where things would go, change nothing
#   --force   overwrite a symlink that points somewhere unexpected

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
ARCHY_HOME="${ARCHY_HOME:-$HOME/.config/archy}"
HYPR_HOME="${HYPR_HOME:-$HOME/.config/hypr}"
BIN_DIR="${ARCHY_BIN_DIR:-$HOME/.local/bin}"

check_only=0
force=0
for arg in "$@"; do
  case "$arg" in
  --check) check_only=1 ;;
  --force) force=1 ;;
  *)
    echo "Unknown option: $arg" >&2
    echo "Usage: install.sh [--check] [--force]" >&2
    exit 1
    ;;
  esac
done

info() { printf '  %s\n' "$*"; }
step() { printf '\n%s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }

# ---------------------------------------------------------------- checks

# Hyprland 0.56 is the floor: the native Lua config API this setup is written
# against (hl.bind, hl.window_rule, hl.on) does not exist before it.
check_compositor() {
  local version
  version="$(hyprctl version 2>/dev/null | grep -oP 'Hyprland \K[0-9.]+' | head -n1)"
  if [[ -z $version ]]; then
    warn "hyprctl not found or not running. Is the compositor up?"
    return
  fi
  local major minor
  major="${version%%.*}"
  minor="$(cut -d. -f2 <<<"$version")"
  if ((major < 0 || (major == 0 && minor < 56))); then
    warn "Hyprland $version is too old. This config needs 0.56+ for its Lua API."
  else
    info "hyprland $version"
  fi
}

# Packages the desktop needs. Anything already installed is left alone; nothing
# here is installed automatically, because which of these you actually want is
# a choice, not a side effect of running a script.
#
# These are package names, not binary names. pactl in particular ships in
# libpulse, so listing "pactl" here would report a missing package on a machine
# where the command works fine.
REQUIRED_PACKAGES=(
  # Bar and launcher
  waybar
  wofi
  # Notifications
  mako
  # Idle and lock
  hypridle
  hyprlock
  # Screen capture and recording
  grim
  slurp
  hyprpicker
  gpu-screen-recorder
  # Clipboard
  wl-clipboard
  cliphist
  # Terminal and the emoji picker's typing helper
  kitty
  wtype
  # Audio: pactl and wpctl both come from libpulse.
  libpulse
  wireplumber
  playerctl
  # Session plumbing
  xdg-desktop-portal
  xdg-desktop-portal-hyprland
  xdg-desktop-portal-gtk
  hyprpolkitagent
  # Brightness and nightlight
  hyprsunset
  # Compositor support libraries
  hyprlang
  hyprcursor
  # Screenshot and monitor scripts parse hyprctl's JSON output.
  jq
  # Animated wallpaper
  swww
  # Removable media
  udiskie
  # The full Nerd Font weight set, not -basic.
  #
  # ttf-jetbrains-mono-nerd-basic carries only Regular/Bold/Italic/BoldItalic.
  # Kitty here is set to style="ExtraLight", which only exists in the full
  # package, so this is a hard requirement rather than a nicety: with -basic
  # alone, kitty falls back to another weight and stops matching the rest of
  # the desktop.
  ttf-jetbrains-mono-nerd
)

check_packages() {
  local missing=()
  local seen=()
  local pkg
  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    # Skip repeats, so a duplicate in the list above cannot show up twice in
    # the suggested install line.
    local duplicate=0
    local s
    for s in "${seen[@]}"; do
      [[ $s == "$pkg" ]] && duplicate=1
    done
    ((duplicate)) && continue
    seen+=("$pkg")

    pacman -Qq "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done

  if ((${#missing[@]} == 0)); then
    info "all required packages installed"
    return
  fi

  warn "missing packages:"
  printf '    %s\n' "${missing[@]}"
  printf '    install with: sudo pacman -S --needed %s\n' "${missing[*]}" >&2
}

# Where each piece is going, and whether something is already there.
check_layout() {
  if [[ -e $ARCHY_HOME ]] && [[ ! -L $ARCHY_HOME ]]; then
    warn "$ARCHY_HOME exists and is not a symlink. Move it aside first:"
    warn "  mv $ARCHY_HOME $ARCHY_HOME.bak"
  fi

  # Hyprland reads ~/.config/hypr; the config lives in ~/.config/archy so the
  # rest of the desktop (waybar, wofi, wallpapers) can be symlinked from the
  # same checkout.
  if [[ -e $HYPR_HOME ]] && [[ ! -L $HYPR_HOME ]]; then
    if [[ -d $HYPR_HOME ]]; then
      warn "$HYPR_HOME is a real directory. This will replace it with a symlink:"
      warn "  mv $HYPR_HOME $HYPR_HOME.bak"
    else
      warn "$HYPR_HOME exists and is not a directory. Remove it first."
    fi
  fi
}

check_fonts() {
  # Matched with bash's own pattern matching rather than a pipe into grep -q.
  #
  # `printf '%s' "$x" | grep -q needle` returns 141 under `set -o pipefail`:
  # grep exits at the first match, printf is killed with SIGPIPE, and pipefail
  # reports the whole pipeline as failed. That reported this font missing on a
  # machine that had it. No subprocess, no pipe, no ambiguity.
  local fonts
  fonts="$(fc-list 2>/dev/null)"

  if [[ $fonts != *"JetBrainsMono Nerd Font"* ]]; then
    # The bar, the lock screen and the terminal all reference this family, and
    # without it the Nerd Font glyphs render as tofu boxes rather than icons.
    warn "JetBrainsMono Nerd Font not found. Icons will show as empty boxes."
    warn "Install: sudo pacman -S ttf-jetbrains-mono-nerd"
    return
  fi
  info "jetbrains-mono-nerd present"

  # Kitty is configured for ExtraLight, a thin stroke chosen for legibility on a
  # low-DPI 1080p panel. Only the four basic weights ship in
  # ttf-jetbrains-mono-nerd-basic, so with only that installed kitty silently
  # falls back to another weight and stops matching the rest of the desktop.
  if [[ $fonts != *ExtraLight* ]]; then
    warn "Only the basic weight set is installed: no ExtraLight face."
    warn "kitty is set to style=\"ExtraLight\" at size 11.5 and will fall back."
    warn "Fix: sudo pacman -S ttf-jetbrains-mono-nerd"
  else
    info "ExtraLight present, so kitty's configured weight resolves"
  fi
}

if ((check_only)); then
  step "archy check"
  check_compositor
  check_packages
  check_fonts
  check_layout
  step ""
  echo "Nothing was changed. Run without --check to install."
  exit 0
fi

# ---------------------------------------------------------------- install

step "archy install"

mkdir -p "$HYPR_HOME" "$BIN_DIR" 2>/dev/null

link_or_report() {
  local target="$1" link="$2" label="$3"
  mkdir -p "$(dirname "$link")" 2>/dev/null

  if [[ -L $link ]]; then
    local current
    current="$(readlink -f "$link")"
    if [[ $current == "$(readlink -f "$target")" ]]; then
      info "$label already linked"
      return 0
    fi
    rm -f "$link"
  elif [[ -e $link ]]; then
    if ((force)); then
      rm -f "$link"
    else
      warn "$link exists and is not a symlink. Not touching it (use --force)."
      return 1
    fi
  fi

  ln -s "$target" "$link"
  info "$label -> $target"
}

# The whole checkout, so a git pull in this directory is the update mechanism.
link_or_report "$REPO_DIR" "$ARCHY_HOME" "archy config"

# Hyprland reads ~/.config/hypr/hyprland.lua. The config itself lives in
# ~/.config/archy/hypr; this is the one file that has to appear where the
# compositor looks.
if [[ -d $HYPR_HOME && ! -L $HYPR_HOME ]]; then
  warn "$HYPR_HOME is a real directory, leaving it alone."
  warn "To use this config: mv $HYPR_HOME $HYPR_HOME.bak && ln -s"
  warn "  $REPO_DIR/hypr $HYPR_HOME"
else
  rm -rf "$HYPR_HOME"
  ln -s "$REPO_DIR/hypr" "$HYPR_HOME"
  info "hypr -> $REPO_DIR/hypr"
fi

# Scripts. lib.sh is sourced, not executed, so it goes in without the exec bit
# being meaningful.
for script in "$REPO_DIR"/scripts/archy-*; do
  [[ -f $script ]] || continue
  name="$(basename "$script")"
  ln -sf "$script" "$BIN_DIR/$name"
done
chmod +x "$REPO_DIR"/scripts/archy-* 2>/dev/null
info "scripts -> $BIN_DIR (${name:-none})"

# Generate the stylesheets from the current colors file.
if [[ -x $BIN_DIR/archy-theme ]]; then
  "$BIN_DIR/archy-theme" sync && info "generated stylesheets"
else
  warn "archy-theme not runnable yet; generated/ will be empty."
fi

step "archy checks"
check_compositor
check_fonts

step ""
echo "Installed to $ARCHY_HOME"
echo "Start it with: Hyprland (the session), or hyprland --config $ARCHY_HOME/hypr"
echo ""
echo "Notes:"
echo "  - colors/colors.conf is the only file to edit to retheme."
echo "    Run 'archy-theme apply' afterward."
echo "  - Put wallpapers in $ARCHY_HOME/wallpapers/, then SUPER+CTRL+SPACE."
echo "  - Log in through a display manager if you want one; archy does not"
echo "    install one, and a bare Hyprland session boots straight into it."
