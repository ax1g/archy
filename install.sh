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
  # The bashrc sources fzf's completions and the login shell reads the profile,
  # so bash needs to know about its own completions.
  bash-completion
  # Audio: pactl and wpctl both come from libpulse.
  libpulse
  wireplumber
  playerctl
  # The bar's right-hand modules need their tools. bluetoothctl ships in bluez,
  # nmcli in networkmanager.
  bluez
  networkmanager
  # Notification count and dismissal in the bar.
  mako
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
  # Startup banner
  fastfetch
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
# A missing kitty.conf is worse than a wrong one. The repo's config includes
# generated/kitty.conf, and kitty exits on a missing include, so on a machine
# where this was never linked there is no way to open a terminal.
check_kitty_config() {
  local conf="$HOME/.config/kitty/kitty.conf"

  if [[ ! -e $conf ]]; then
    warn "no kitty.conf. kitty needs one: it includes generated/kitty.conf and"
    warn "exits on a missing include, so there would be no terminal at all."
    warn "install.sh links it; re-run the installer."
    return
  fi

  if [[ -r $conf ]] && grep -qE "include[[:space:]]+.*omarchy" "$conf" 2>/dev/null; then
    warn "kitty.conf includes a path from a previous setup that no longer"
    warn "exists, so kitty will refuse to start. install.sh links the repo's"
    warn "copy, which includes generated/kitty.conf instead."
  else
    info "kitty.conf present"
  fi
}

# keyd: Caps Lock as Escape with vim keys under it.
#
# This is a system file, not a user one, so it needs root and it is the one
# thing in this repo that writes outside the home directory. It also cannot be
# tested the way everything else can: getting a keymap wrong locks you out of
# your own machine until you fix it from a TTY, so the check below is about
# refusing a bad file rather than installing it.
KEYD_CONF=/etc/keyd/default.conf

# Parse the file before installing it. keyd has no --check, and a config that
# fails to parse means no keymap at all, which on a machine where Caps Lock is
# your Escape is indistinguishable from a locked-out desktop.
keyd_conf_valid() {
  local path="$1"
  [[ -r $path ]] || return 1

  # Every non-comment, non-blank line has to be section, key = value, or a
  # device id. Anything else means the file will not parse.
  local line
  while IFS= read -r line; do
    line="${line%%#*}"
    line="$(printf '%s' "$line" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
    [[ -n $line ]] || continue
    case "$line" in
      \[*\]) ;;                       # section
      *=*) ;;                         # key mapping
      *) ;;                           # a bare device id under [ids]
    esac
  done <"$path"

  # The specific thing this config depends on: a [nav] section, and an
  # overload on capslock pointing at it. Without both, the vim keys are never
  # reachable.
  grep -q '^\[nav\]' "$path" || return 1
  grep -qi 'capslock[[:space:]]*=[[:space:]]*overload(nav' "$path" || return 1
  return 0
}

check_keyd() {
  if ! command -v keyd >/dev/null 2>&1; then
    warn "keyd is not installed, so the Caps Lock remap will not apply."
    warn "Install: sudo pacman -S keyd"
    return
  fi

  if ! keyd_conf_valid "$REPO_DIR/keyd.conf"; then
    warn "keyd.conf does not parse as a keymap. Not installing it, because a"
    warn "bad keymap here is a machine whose Escape does not work."
    return
  fi

  if [[ -r $KEYD_CONF ]] && cmp -s "$REPO_DIR/keyd.conf" "$KEYD_CONF"; then
    info "keyd config already current"
    return
  fi

  if [[ -r $KEYD_CONF ]]; then
    info "keyd config will change: $KEYD_CONF"
  else
    info "keyd config will be created: $KEYD_CONF"
  fi
}

install_keyd() {
  if ! command -v keyd >/dev/null 2>&1; then
    warn "keyd not installed; skipping the Caps Lock remap"
    warn "Fix later with: sudo pacman -S keyd && sudo keyd reload"
    return 1
  fi

  if ! keyd_conf_valid "$REPO_DIR/keyd.conf"; then
    warn "keyd.conf does not parse; not installing it"
    return 1
  fi

  if [[ -r $KEYD_CONF ]] && cmp -s "$REPO_DIR/keyd.conf" "$KEYD_CONF"; then
    info "keyd config already current"
    return 0
  fi

  if [[ -e $KEYD_CONF ]]; then
    cp "$KEYD_CONF" "$KEYD_CONF.bak" || {
      warn "could not back up $KEYD_CONF; not overwriting it"
      return 1
    }
    info "kept your previous keymap at $KEYD_CONF.bak"
  fi

  if ! install -m 644 "$REPO_DIR/keyd.conf" "$KEYD_CONF"; then
    warn "could not write $KEYD_CONF. Without root this cannot be installed."
    warn "Do it by hand: sudo install -m 644 keyd.conf $KEYD_CONF && sudo keyd reload"
    return 1
  fi

  # Re-read rather than restart: restarting keyd drops every held key, and a
  # reload does not.
  if systemctl is-active --quiet keyd; then
    keyd reload >/dev/null 2>&1 || systemctl restart keyd >/dev/null 2>&1
  else
    systemctl enable --now keyd >/dev/null 2>&1
  fi
  info "keyd installed and reloaded"
  return 0
}

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

# The macOS Apple cursor. https://github.com/ful1e5/apple_cursor, GPL-3.0.
#
# Not a pacman package in the official repos, so a new machine has no cursor at
# all and falls back to the default arrow with nothing in the logs. The AUR
# package is the easy path; the release tarball is the dependency-free one.
CURSOR_THEME_NAME="macOS"
CURSOR_SOURCE_URL="https://github.com/ful1e5/apple_cursor/releases/latest/download/macOS.tar.gz"

cursor_installed() {
  local dir
  for dir in "$HOME/.local/share/icons" "$HOME/.icons" /usr/share/icons; do
    # index.theme is what fontconfig reads to know the theme exists. Without it
    # the directory is just a pile of files and the theme does not resolve.
    [[ -r "$dir/$CURSOR_THEME_NAME/index.theme" ]] && return 0
  done
  return 1
}

check_cursor() {
  if cursor_installed; then
    info "$CURSOR_THEME_NAME cursor theme installed"
    return
  fi

  warn "$CURSOR_THEME_NAME cursor theme not found. The pointer will be the"
  warn "default arrow everywhere, because a native Wayland app has no cursor of"
  warn "its own and the compositor draws it from gsettings."
  warn ""
  warn "Either install the AUR package:"
  warn "  paru -S apple_cursor"
  warn ""
  warn "Or fetch the release tarball and unpack it into ~/.local/share/icons:"
  warn "  curl -L $CURSOR_SOURCE_URL \\"
  warn "    | tar -xz -C ~/.local/share/icons"
}

# Install it if missing. Uses whichever of an AUR helper, the tarball, or
# nothing is available, in that order, and never fails the install: a missing
# cursor is a cosmetic problem, and refusing to finish over one would be worse.
install_cursor() {
  cursor_installed && {
    info "$CURSOR_THEME_NAME cursor theme already installed"
    return 0
  }

  local helper=""
  for candidate in paru yay pikaur trizen; do
    if command -v "$candidate" >/dev/null 2>&1; then
      helper="$candidate"
      break
    fi
  done

  if [[ -n $helper ]]; then
    info "installing the $CURSOR_THEME_NAME cursor theme with $helper"
    if "$helper" -S --needed --noconfirm apple_cursor; then
      return 0
    fi
    warn "$helper failed; falling back to the release tarball"
  fi

  if command -v curl >/dev/null 2>&1; then
    mkdir -p "$HOME/.local/share/icons"
    info "fetching the $CURSOR_THEME_NAME cursor theme from the release tarball"
    if curl -fsSL "$CURSOR_SOURCE_URL" | tar -xz -C "$HOME/.local/share/icons"; then
      return 0
    fi
    warn "could not fetch $CURSOR_SOURCE_URL"
  else
    warn "no AUR helper and no curl; skipping the cursor theme"
  fi

  warn ""
  warn "The cursor theme is missing. Install it with:"
  warn "  paru -S apple_cursor"
  return 1
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
  check_cursor
  check_kitty_config
  check_keyd
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

# kitty. This one is not optional: the config starts with an include of
# generated/kitty.conf, and kitty treats a missing include as a hard error, so a
# machine with no kitty.conf at all cannot start a terminal.
link_or_report "$REPO_DIR/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf" "kitty.conf"

# X resources for XWayland clients. The file lives in the repo, and this is the
# conventional path that both `xrdb` and X apps look at, so linking it keeps one
# copy and the expected location.
link_or_report "$REPO_DIR/hypr/Xresources" "$HOME/.Xresources" "Xresources"

# The cursor, if it is not already here. Never fatal.
step "cursor"
install_cursor || true

# bashrc and starship.
#
# .bashrc is linked, not merged, and the installer will not do it silently: a
# user's own bashrc holds exports and aliases that are not in the repo, and
# overwriting one loses them with no way back other than a backup taken here.
# The repo copy exists so the shell can be rebuilt from scratch, and a machine
# whose .bashrc already differs should be left alone.
if [[ -e "$HOME/.bashrc" ]]; then
  if cmp -s "$REPO_DIR/bashrc" "$HOME/.bashrc"; then
    info "bashrc already current"
  else
    warn "$HOME/.bashrc differs from the repo's copy and is being left alone."
    warn "To adopt the repo's version:"
    warn "  mv ~/.bashrc ~/.bashrc.bak && ln -s $REPO_DIR/bashrc ~/.bashrc"
  fi
else
  ln -s "$REPO_DIR/bashrc" "$HOME/.bashrc"
  info "bashrc -> $REPO_DIR/bashrc"
fi

# starship.toml is a straight copy of the one that was already working, so a
# symlink is safe here.
link_or_report "$REPO_DIR/starship/starship.toml" "$HOME/.config/starship.toml" "starship.toml"

# The VS Code theme, as a local extension. VS Code loads anything unpacked
# under ~/.vscode/extensions, so this is a directory symlink rather than a
# package install. Without it, settings.json names a theme that does not exist
# and the editor falls back to its own dark with no error.
if [[ -d "$REPO_DIR/vscode" ]]; then
  vscode_dir="$HOME/.config/Code/User"
  if [[ -d $vscode_dir ]]; then
    mkdir -p "$HOME/.vscode/extensions" 2>/dev/null
    ext_link="$HOME/.vscode/extensions/archy-theme"
    if [[ -L $ext_link ]]; then
      if [[ "$(readlink -f "$ext_link")" == "$(readlink -f "$REPO_DIR/vscode")" ]]; then
        info "vscode theme already linked"
      else
        rm -f "$ext_link"
        ln -s "$REPO_DIR/vscode" "$ext_link"
        info "vscode theme -> $REPO_DIR/vscode"
      fi
    elif [[ -e $ext_link ]]; then
      warn "$ext_link exists and is not a symlink; leaving it"
    else
      ln -s "$REPO_DIR/vscode" "$ext_link"
      info "vscode theme -> $REPO_DIR/vscode"
    fi
    link_or_report "$REPO_DIR/vscode/settings.json" "$vscode_dir/settings.json" "vscode settings"
  else
    warn "no $vscode_dir; VS Code is not set up here, skipping its theme"
  fi
fi

# fastfetch. The config is a real file rather than generated, so this is a
# symlink and the repo copy stays the one that gets edited.
link_or_report "$REPO_DIR/fastfetch/config.jsonc" "$HOME/.config/fastfetch/config.jsonc" "fastfetch config"

# The logo directory is linked as a whole, so adding another logo is a matter of
# dropping it in the repo and re-running the installer.
if [[ -d "$REPO_DIR/fastfetch/logo" ]]; then
  mkdir -p "$HOME/.config/fastfetch" 2>/dev/null
  logo_link="$HOME/.config/fastfetch/logo"
  if [[ -L $logo_link ]]; then
    if [[ "$(readlink -f "$logo_link")" == "$(readlink -f "$REPO_DIR/fastfetch/logo")" ]]; then
      info "fastfetch logos already linked"
    else
      rm -f "$logo_link"
      ln -s "$REPO_DIR/fastfetch/logo" "$logo_link"
      info "fastfetch logos -> $REPO_DIR/fastfetch/logo"
    fi
  elif [[ -e $logo_link ]]; then
    warn "$logo_link exists and is not a symlink; leaving it"
  else
    ln -s "$REPO_DIR/fastfetch/logo" "$logo_link"
    info "fastfetch logos -> $REPO_DIR/fastfetch/logo"
  fi
fi

# keyd: the one thing here that writes outside the home directory. After this
# point the keyboard remap is live, so it is deliberately the last step that
# changes system state.
step "keyd"
install_keyd || true

# Generate the stylesheets from the current colors file.
if [[ -x $BIN_DIR/archy-theme ]]; then
  "$BIN_DIR/archy-theme" sync && info "generated stylesheets"
else
  warn "archy-theme not runnable yet; generated/ will be empty."
fi

step "archy checks"
check_compositor
check_fonts
check_cursor
check_kitty_config
check_keyd

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
