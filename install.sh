#!/usr/bin/env bash
# archy: install or update.
#
# Run with sudo: it installs the pacman packages, writes the keyd config and
# the system-wide cursor theme, then links the user config as the real user.
#
#   sudo ./install.sh
#   ./install.sh --check    # reports what is missing, changes nothing
#
# Idempotent: safe to re-run after every git pull.

set -uo pipefail

check_only=0
for arg in "$@"; do
  case "$arg" in
  --check) check_only=1 ;;
  *)
    echo "Unknown option: $arg" >&2
    echo "Usage: sudo ./install.sh | ./install.sh --check" >&2
    exit 1
    ;;
  esac
done

# The install path needs root (pacman, /etc/keyd, /usr/share/icons), so
# re-run under sudo rather than failing halfway through. The check path is
# read-only and runs fine as the user.
if (( ! check_only )) && (( EUID != 0 )); then
  echo "archy install needs root for pacman and the system config."
  echo "Re-running with sudo; user files still land in the real home directory."
  exec sudo --preserve-env=HYPRLAND_INSTANCE_SIGNATURE,XDG_RUNTIME_DIR,WAYLAND_DISPLAY "$0" "$@"
fi

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

# When elevated, $HOME is /root and every user path below would be wrong, so
# resolve the real user first and point HOME at them. Invoked directly as the
# user (check mode, or a root login), this is a no-op.
REAL_USER="${SUDO_USER:-$(id -un)}"
REAL_HOME="$(getent passwd "$REAL_USER" 2>/dev/null | cut -d: -f6)"
[[ -n ${REAL_HOME:-} ]] || REAL_HOME="$HOME"
if (( EUID == 0 )) && [[ -n ${SUDO_USER:-} ]]; then
  HOME="$REAL_HOME"
  export HOME
fi

ARCHY_HOME="${ARCHY_HOME:-$HOME/.config/archy}"
HYPR_HOME="${HYPR_HOME:-$HOME/.config/hypr}"
BIN_DIR="${ARCHY_BIN_DIR:-$HOME/.local/bin}"

info() { printf '  %s\n' "$*"; }
step() { printf '\n%s\n' "$*"; }
warn() { printf '  ! %s\n' "$*" >&2; }

# Ownership for anything created inside the real user's home. Running as root
# leaves root-owned symlinks behind otherwise, which the next audit flags.
ownit() {
  if (( EUID == 0 )) && [[ $REAL_USER != "root" ]]; then
    chown -h "$REAL_USER:$(id -gn "$REAL_USER")" "$1" 2>/dev/null || true
  fi
}

ensure_dir() {
  if [[ ! -d $1 ]]; then
    mkdir -p "$1"
    ownit "$1"
  fi
}

# Run a command as the real user with their HOME. Root-only steps never go
# through here; user steps (theme sync, live checks) always do.
as_user() {
  if (( EUID == 0 )) && [[ $REAL_USER != "root" ]]; then
    sudo -u "$REAL_USER" env HOME="$REAL_HOME" "$@"
  else
    "$@"
  fi
}

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

# Packages the desktop needs. The installer puts these in with pacman; the
# check below only reports, so a --check on a fresh machine reads as a list.
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
  # The shell: starship draws the prompt (and the blank line above it),
  # fzf feeds history and file search, zoxide owns cd, eza owns ls, and bat
  # owns the man pager. Without these the linked bashrc degrades to stock.
  starship
  fzf
  zoxide
  eza
  bat
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
  # The Caps Lock remap.
  keyd
  # The full Nerd Font weight set, not -basic.
  #
  # ttf-jetbrains-mono-nerd-basic carries only Regular/Bold/Italic/BoldItalic.
  # Kitty here is set to style="ExtraLight", which only exists in the full
  # package, so this is a hard requirement rather than a nicety: with -basic
  # alone, kitty falls back to another weight and stops matching the rest of
  # the desktop.
  ttf-jetbrains-mono-nerd
)

missing_packages() {
  local missing=()
  local seen=()
  local pkg
  for pkg in "${REQUIRED_PACKAGES[@]}"; do
    # Skip repeats, so a duplicate in the list above cannot show up twice in
    # the install line.
    local duplicate=0
    local s
    for s in "${seen[@]}"; do
      [[ $s == "$pkg" ]] && duplicate=1
    done
    ((duplicate)) && continue
    seen+=("$pkg")

    pacman -Qq "$pkg" >/dev/null 2>&1 || missing+=("$pkg")
  done
  printf '%s\n' "${missing[@]}"
}

check_packages() {
  local missing=()
  mapfile -t missing < <(missing_packages)

  if ((${#missing[@]} == 0)) || [[ -z ${missing[0]} ]]; then
    info "all required packages installed"
    return
  fi

  warn "missing packages:"
  printf '    %s\n' "${missing[@]}"
  printf '    install with: sudo ./install.sh\n' >&2
  printf '    or by hand: sudo pacman -S --needed %s\n' "${missing[*]}" >&2
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
# This is a system file, not a user one, which is half the reason the
# installer runs with sudo. It also cannot be tested the way everything else
# can: getting a keymap wrong locks you out of your own machine until you fix
# it from a TTY, so the check below is about refusing a bad file rather than
# installing it.
KEYD_CONF="${ARCHY_KEYD_CONF:-/etc/keyd/default.conf}"

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
    warn "The installer puts it in with the rest of the packages."
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
  else
    ensure_dir "$(dirname "$KEYD_CONF")"
  fi

  install -m 644 "$REPO_DIR/keyd.conf" "$KEYD_CONF" || {
    warn "could not write $KEYD_CONF"
    return 1
  }
  info "keyd config written to $KEYD_CONF"

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
    info "$ARCHY_HOME exists and is not a symlink; install moves it to a .bak"
  fi

  # Hyprland reads ~/.config/hypr; the config lives in ~/.config/archy so the
  # rest of the desktop (waybar, wofi, wallpapers) can be symlinked from the
  # same checkout.
  if [[ -e $HYPR_HOME ]] && [[ ! -L $HYPR_HOME ]]; then
    if [[ -d $HYPR_HOME ]]; then
      info "$HYPR_HOME is a real directory; install moves it to a .bak and links"
    else
      warn "$HYPR_HOME exists and is not a directory. Remove it first."
    fi
  fi
}

# The macOS Apple cursor. https://github.com/ful1e5/apple_cursor, GPL-3.0.
#
# Vendored in cursors/macOS/, so a fresh machine needs no AUR helper and no
# network fetch: the installer copies it system-wide. The theme is an Xcursor
# theme, not a hyprcursor one — cursors/ and cursor.theme, with no
# hyprcursors/ or theme.conf. libhyprcursor falls back to its Xcursor loader
# for exactly this case, so the name still resolves.
CURSOR_THEME_NAME="macOS"
CURSOR_SOURCE_DIR="$REPO_DIR/cursors/$CURSOR_THEME_NAME"
CURSOR_SYSTEM_DIR="${ARCHY_CURSOR_DIR:-/usr/share/icons/$CURSOR_THEME_NAME}"

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

  if [[ -r $CURSOR_SOURCE_DIR/index.theme ]]; then
    info "$CURSOR_THEME_NAME cursor theme will be installed from the repo copy"
    return
  fi

  warn "$CURSOR_THEME_NAME cursor theme not found and the repo copy is missing."
  warn "The pointer will be the default arrow everywhere, because a native"
  warn "Wayland app has no cursor of its own and the compositor draws it from"
  warn "gsettings."
}

# Copy it system-wide if missing. Never fatal: a missing cursor is cosmetic,
# and refusing to finish over one would be worse.
install_cursor() {
  cursor_installed && {
    info "$CURSOR_THEME_NAME cursor theme already installed"
    return 0
  }

  if [[ ! -r $CURSOR_SOURCE_DIR/index.theme ]]; then
    warn "no vendored cursor at $CURSOR_SOURCE_DIR; skipping the cursor theme"
    return 1
  fi

  rm -rf "$CURSOR_SYSTEM_DIR"
  mkdir -p "$(dirname "$CURSOR_SYSTEM_DIR")"
  if cp -a "$CURSOR_SOURCE_DIR" "$CURSOR_SYSTEM_DIR"; then
    info "$CURSOR_THEME_NAME cursor theme installed system-wide from the repo"
    return 0
  fi
  warn "could not copy the cursor theme to $CURSOR_SYSTEM_DIR"
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
    warn "The installer puts it in with the rest of the packages."
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

# OpenCode: the global config, working rules, commands and skills live in
# opencode/ in the repo and are symlinked into ~/.config/opencode/.
#
# Two files are deliberately never touched: cli.json (TUI preferences, machine
# taste) and service.json (holds an auth secret — never vendored, never
# linked, never overwritten).
check_opencode() {
  local dir="$HOME/.config/opencode"
  local missing=()
  local name
  for name in opencode.json AGENTS.md commands skills; do
    if [[ -L $dir/$name ]] &&
      [[ "$(readlink -f "$dir/$name")" == "$(readlink -f "$REPO_DIR/opencode/$name")" ]]; then
      continue
    fi
    missing+=("$name")
  done

  if ((${#missing[@]} == 0)); then
    info "opencode config linked"
  else
    info "opencode config will be linked: ${missing[*]}"
  fi

  if ! command -v opencode >/dev/null 2>&1; then
    warn "opencode is not installed (SUPER+A has nothing to launch)."
    warn "Install: curl -fsSL https://opencode.ai/install | bash"
  else
    info "opencode present"
  fi
}

check_vscode() {
  local vscode_dir="$HOME/.config/Code/User"
  if [[ -d $vscode_dir ]]; then
    info "vscode config dir present"
  else
    info "no $vscode_dir; VS Code is not set up here, its theme will be skipped"
  fi
}

if ((check_only)); then
  step "archy check — reporting only, nothing will be changed"
  check_compositor
  check_packages
  check_fonts
  check_cursor
  check_kitty_config
  check_keyd
  check_opencode
  check_vscode
  check_layout
  step ""
  echo "Nothing was changed. Run with sudo to install: sudo ./install.sh"
  exit 0
fi

# ---------------------------------------------------------------- install

step "archy install — $REAL_USER's desktop, using sudo for the system parts"
info "repo: $REPO_DIR"
info "user home: $REAL_HOME"

# Move a real directory aside with a timestamped backup, so the installer
# never asks the user to do it by hand and never destroys anything either.
move_aside() {
  local path="$1"
  if [[ -e $path && ! -L $path ]]; then
    local backup="$path.bak.$(date +%Y%m%d-%H%M%S)"
    mv "$path" "$backup"
    info "$(basename "$path"): moved the existing one to $backup"
  fi
}

compositor_up() {
  as_user hyprctl version >/dev/null 2>&1
}

step "[1/7] system packages — installing what the desktop needs from pacman"
info "missing ones go in with: pacman -S --needed; the rest are left alone"

# The desktop packages first. --needed leaves what is already there alone;
# --noconfirm keeps a fresh-machine install unattended.
mapfile -t to_install < <(missing_packages)
if ((${#to_install[@]} == 0)) || [[ -z ${to_install[0]} ]]; then
  info "every required package is already installed, nothing to do"
else
  info "installing ${#to_install[@]} package(s): ${to_install[*]}"
  pacman -S --needed --noconfirm "${to_install[@]}"
  info "packages done"
fi

step "[2/7] config links — pointing your home at this checkout"
info "the checkout stays the source of truth: a git pull plus a re-run updates"

link_or_report() {
  local target="$1" link="$2" label="$3"
  ensure_dir "$(dirname "$link")"

  if [[ -L $link ]]; then
    local current
    current="$(readlink -f "$link")"
    if [[ $current == "$(readlink -f "$target")" ]]; then
      info "$label already linked"
      return 0
    fi
    rm -f "$link"
  elif [[ -e $link ]]; then
    move_aside "$link"
  fi

  ln -s "$target" "$link"
  ownit "$link"
  info "$label linked: $link -> $target"
}

# The whole checkout, so a git pull in this directory is the update mechanism.
move_aside "$ARCHY_HOME"
link_or_report "$REPO_DIR" "$ARCHY_HOME" "archy config"

# Hyprland reads ~/.config/hypr/hyprland.lua by default — no --config flag, no
# session file. Pointing ~/.config/hypr at the repo's hypr/ is what makes this
# checkout the main config: a bare Hyprland boots straight into it.
move_aside "$HYPR_HOME"
if [[ -L $HYPR_HOME ]] && [[ "$(readlink -f "$HYPR_HOME")" == "$(readlink -f "$REPO_DIR/hypr")" ]]; then
  info "hypr config already linked: $HYPR_HOME -> $REPO_DIR/hypr"
else
  rm -f "$HYPR_HOME"
  ln -s "$REPO_DIR/hypr" "$HYPR_HOME"
  ownit "$HYPR_HOME"
  info "hypr config linked: $HYPR_HOME -> $REPO_DIR/hypr"
fi
ensure_dir "$BIN_DIR"

# Scripts. lib.sh is sourced, not executed, so it goes in without the exec bit
# being meaningful.
for script in "$REPO_DIR"/scripts/archy-*; do
  [[ -f $script ]] || continue
  name="$(basename "$script")"
  ln -sf "$script" "$BIN_DIR/$name"
  ownit "$BIN_DIR/$name"
done
chmod +x "$REPO_DIR"/scripts/archy-* 2>/dev/null
info "scripts linked into $BIN_DIR (${name:-none})"

# kitty. This one is not optional: the config starts with an include of
# generated/kitty.conf, and kitty treats a missing include as a hard error, so a
# machine with no kitty.conf at all cannot start a terminal.
link_or_report "$REPO_DIR/kitty/kitty.conf" "$HOME/.config/kitty/kitty.conf" "kitty.conf"

# X resources for XWayland clients. The file lives in the repo, and this is the
# conventional path that both `xrdb` and X apps look at, so linking it keeps one
# copy and the expected location.
link_or_report "$REPO_DIR/hypr/Xresources" "$HOME/.Xresources" "Xresources"

# The cursor, from the vendored copy. Never fatal.
step "[3/7] cursor — installing the vendored macOS theme system-wide"
info "source: $REPO_DIR/cursors/$CURSOR_THEME_NAME, target: $CURSOR_SYSTEM_DIR"
install_cursor || true

# .bashrc is linked, not merged. A user's own bashrc holds exports and aliases
# that are not in the repo, so the existing one moves to a timestamped .bak
# rather than being overwritten.
step "[4/7] shell, editor and tools — bashrc, starship, vscode, fastfetch, opencode"
if [[ -e "$HOME/.bashrc" ]] && [[ ! -L "$HOME/.bashrc" ]]; then
  move_aside "$HOME/.bashrc"
fi
if [[ -L "$HOME/.bashrc" ]] && [[ "$(readlink -f "$HOME/.bashrc")" == "$(readlink -f "$REPO_DIR/bashrc")" ]]; then
  info "bashrc already linked"
else
  rm -f "$HOME/.bashrc"
  ln -s "$REPO_DIR/bashrc" "$HOME/.bashrc"
  ownit "$HOME/.bashrc"
  info "bashrc linked: $HOME/.bashrc -> $REPO_DIR/bashrc"
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
    ensure_dir "$HOME/.vscode/extensions"
    ext_link="$HOME/.vscode/extensions/archy-theme"
    if [[ -L $ext_link ]] && [[ "$(readlink -f "$ext_link")" == "$(readlink -f "$REPO_DIR/vscode")" ]]; then
      info "vscode theme already linked"
    else
      move_aside "$ext_link"
      rm -f "$ext_link"
      ln -s "$REPO_DIR/vscode" "$ext_link"
      ownit "$ext_link"
      info "vscode theme linked: $ext_link -> $REPO_DIR/vscode"
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
  ensure_dir "$HOME/.config/fastfetch"
  logo_link="$HOME/.config/fastfetch/logo"
  if [[ -L $logo_link ]]; then
    if [[ "$(readlink -f "$logo_link")" == "$(readlink -f "$REPO_DIR/fastfetch/logo")" ]]; then
      info "fastfetch logos already linked"
    else
      rm -f "$logo_link"
      ln -s "$REPO_DIR/fastfetch/logo" "$logo_link"
      ownit "$logo_link"
      info "fastfetch logos -> $REPO_DIR/fastfetch/logo"
    fi
  elif [[ -e $logo_link ]]; then
    warn "$logo_link exists and is not a symlink; leaving it"
  else
    ln -s "$REPO_DIR/fastfetch/logo" "$logo_link"
    ownit "$logo_link"
    info "fastfetch logos -> $REPO_DIR/fastfetch/logo"
  fi
fi

# OpenCode. The config, rules, commands and skills are symlinked in; cli.json
# and service.json stay machine-local and are never touched.
if [[ -d "$REPO_DIR/opencode" ]]; then
  ensure_dir "$HOME/.config/opencode"
  link_or_report "$REPO_DIR/opencode/opencode.json" "$HOME/.config/opencode/opencode.json" "opencode config"
  link_or_report "$REPO_DIR/opencode/AGENTS.md" "$HOME/.config/opencode/AGENTS.md" "opencode rules"
  link_or_report "$REPO_DIR/opencode/commands" "$HOME/.config/opencode/commands" "opencode commands"
  link_or_report "$REPO_DIR/opencode/skills" "$HOME/.config/opencode/skills" "opencode skills"
fi

# keyd: the system keyboard remap. After this point it is live, so it is
# deliberately ordered after everything the desktop needs to come up.
step "[5/7] keyd — writing the Caps Lock remap to $KEYD_CONF and reloading it"
info "your previous keymap is kept beside it as .bak"
install_keyd || true

# Generate the stylesheets from the current colors file. This runs as the real
# user: generated/ lives in their checkout, and root-owned files there would
# break the next theme change.
step "[6/7] theme — regenerating the waybar, wofi, mako, kitty and lock styles"
if [[ -x $BIN_DIR/archy-theme ]]; then
  if as_user "$BIN_DIR/archy-theme" sync; then
    info "stylesheets regenerated from colors/colors.conf"
  else
    warn "archy-theme sync failed; the bar and menus keep their old colors"
  fi
else
  warn "archy-theme not runnable yet; generated/ will be empty."
fi

# Reload the running session so it picks up the new config now, not on the
# next login. A reload does not re-run autostart and does not activate
# permission rules (screencopy.lua) — those go live on a full restart.
step "[7/7] session — reloading Hyprland and setting the wallpaper"
if compositor_up; then
  info "telling the running compositor to reload its config"
  if as_user hyprctl reload; then
    info "compositor reloaded"
  else
    warn "hyprctl reload failed; log out and back in to pick up the config"
  fi

  # A reload never re-runs autostart, so the wallpaper would stay unset until
  # the next login. Set the default now: archy-wallpaper starts swww-daemon
  # itself when it is missing.
  if as_user "$BIN_DIR/archy-wallpaper" set; then
    info "wallpaper set"
  else
    warn "wallpaper not set — is swww installed? (step 1 should have put it in)"
  fi
else
  info "no compositor running (SSH or TTY install); skipping reload and wallpaper"
  info "both happen on their own at the next login"
fi

# The live checks need the user's session (hyprctl, fonts, home paths), so
# re-run the read-only check as them rather than as root.
step "archy checks"
if (( EUID == 0 )) && [[ $REAL_USER != "root" ]]; then
  sudo -u "$REAL_USER" env HOME="$REAL_HOME" \
    ${HYPRLAND_INSTANCE_SIGNATURE:+HYPRLAND_INSTANCE_SIGNATURE="$HYPRLAND_INSTANCE_SIGNATURE"} \
    ${XDG_RUNTIME_DIR:+XDG_RUNTIME_DIR="$XDG_RUNTIME_DIR"} \
    ${WAYLAND_DISPLAY:+WAYLAND_DISPLAY="$WAYLAND_DISPLAY"} \
    "$REPO_DIR/install.sh" --check
else
  "$REPO_DIR/install.sh" --check
fi

step ""
echo "Installed to $ARCHY_HOME"
echo ""
echo "archy is now the default Hyprland config: ~/.config/hypr points at this"
echo "checkout, so a bare Hyprland boots straight into it. If you ever need the"
echo "explicit form, --config takes the file, not the directory:"
echo "  hyprland --config $ARCHY_HOME/hypr/hyprland.lua"
echo ""
echo "Notes:"
echo "  - The running shell keeps its old config: open a new terminal (or run"
echo "    'exec bash') to get the new prompt."
echo "  - colors/colors.conf is the only file to edit to retheme."
echo "    Run 'archy-theme apply' afterward."
echo "  - Permission rules (screencopy) activate on a full compositor restart,"
echo "    never on reload. Log out and back in once after this install."
echo "  - Put wallpapers in $ARCHY_HOME/wallpapers/, then SUPER+CTRL+SPACE."
echo "  - Log in through a display manager if you want one; archy does not"
echo "    install one, and a bare Hyprland session boots straight into it."
