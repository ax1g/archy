#!/usr/bin/env bash
# archy: helper library. Sourced by every archy-* script.
#
# Holds the paths, the palette reader and the dispatcher shim. Not executable on
# its own.

set -o pipefail

ARCHY_HOME="${ARCHY_HOME:-$HOME/.config/archy}"
ARCHY_COLORS="$ARCHY_HOME/colors/colors.conf"
ARCHY_BIN_DIR="${ARCHY_BIN_DIR:-$HOME/.local/bin}"
ARCHY_STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/archy"
ARCHY_CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/archy"
ARCHY_GENERATED="$ARCHY_HOME/generated"
ARCHY_SHOTS_DIR="${ARCHY_SHOTS_DIR:-$HOME/Pictures/screenshots}"

mkdir -p "$ARCHY_STATE_DIR" "$ARCHY_CACHE_DIR" "$ARCHY_GENERATED" "$ARCHY_SHOTS_DIR" 2>/dev/null

# Read one key out of colors.conf. The file is key = value with '#' comments.
color() {
  local key="$1" default="${2:-}" value
  [[ -r $ARCHY_COLORS ]] || { printf '%s' "$default"; return; }
  value="$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\(.*[^[:space:]]\)[[:space:]]*$/\1/p" "$ARCHY_COLORS" | tail -n1)"
  [[ -n $value ]] && printf '%s' "$value" || printf '%s' "$default"
}

# Hyprland 0.56 takes dispatchers as Lua. Every script that dispatches goes
# through here so the quoting is identical everywhere and a value containing a
# quote cannot break out of the Lua string.
hypr_dispatch() {
  local lua="$1"
  shift
  hyprctl dispatch "$lua" >/dev/null 2>&1 || hyprctl dispatch "$@" >/dev/null 2>&1
}

# The focused window's address, as a dispatcher-safe target.
active_address() {
  local addr
  addr="$(hyprctl -j activewindow 2>/dev/null | jq -r '.address // empty')"
  [[ -n $addr ]] || return 1
  printf 'address:%s' "$addr"
}

# The terminal. Kitty, with bash as the login shell inside it.
#
# The class is left as kitty's own on purpose: windows.lua tags a window
# "terminal" by matching on class, and both the universal clipboard chords and
# the cascade's terminal exemption read that tag. Renaming the class here would
# silently stop the clipboard shortcuts from working inside the terminal.
terminal_cmd() {
  printf 'kitty'
}

# Resolve the physical audio sink. Filters and module sinks are not real
# outputs, so follow the default sink to whatever device is behind it.
audio_sink() {
  local sink
  sink="$(pactl get-default-sink 2>/dev/null)"

  # If the default is a virtual sink created by a module, walk to its source.
  local guard=0
  while [[ -n $sink ]] && ((guard < 5)); do
    local kind
    kind="$(pactl list sinks 2>/dev/null |
      awk -v want="$sink" '
        /^Sink #/ { in_sink = 0; name = "" }
        $0 ~ "^\\s*Name: " want "$" { in_sink = 1; name = want }
        in_sink && /Sample Specification/ { spec = $0 }
        in_sink && /Description:/ { desc = $0 }
        END {
          if (name == "") exit
          if (spec ~ /module/ || spec ~ /n\/a/) print "virtual"
          else print "real"
        }')"
    [[ $kind == virtual ]] || break

    local upstream
    upstream="$(pactl list sinks 2>/dev/null |
      awk -v want="$sink" '
        /^Sink #/ { in_sink = 0 }
        $0 ~ "^\\s*Name: " want "$" { in_sink = 1 }
        in_sink && /Monitor:/ { print }
      ' | head -n1 | sed -E 's/.*Monitor: //; s/\..*//')"
    [[ -n $upstream ]] || break
    sink="$upstream"
    guard=$((guard + 1))
  done

  [[ -n $sink ]] || return 1
  printf '%s' "$sink"
}

# Show a notification. Goes through notify-send, which the mako daemon started
# in autostart.lua renders.
notify() {
  local urgency="${2:-normal}"
  notify-send -u "$urgency" -a archy "$1" >/dev/null 2>&1
}

notify_percent() {
  local icon="$1" percent="$2"
  notify "$icon  ${percent}%" low
}
