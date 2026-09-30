# archy: the test suite.
#
# Run: scripts/test.sh
#
# Two layers, because they catch different things:
#
#   1. A load test. Hyprland's hl.* Lua API is stubbed with a surface
#      transcribed from the strings of the installed hyprland binary, so a call
#      the compositor does not have fails here instead of on a login screen.
#      This also loads every module in order and exercises the
#      hyprland.start callbacks.
#
#   2. Static checks on the shell side: syntax, the theme generator's output,
#      and that the Lua and shell palette parsers agree — if they disagree, the
#      compositor and the bar get different themes from the same file.
#
# Everything runs against a fake HOME, so nothing here touches the real
# desktop. The one exception is a read-only query to the live compositor and
# audio server (hyprctl gamma, pactl sink list), which is how the audio sink
# resolver gets verified at all.
#
# What this cannot tell you: whether the result looks right. Only running it
# does that.

set -uo pipefail

REPO_DIR="$(cd "$(dirname "$(readlink -f "$0")")/.." && pwd)"
SANDBOX="${ARCHY_TEST_SANDBOX:-/tmp/archy-test}"

info() { printf '  %s\n' "$*"; }
fail() { printf '  FAIL: %s\n' "$*" >&2; rc=1; }
rc=0

step() { printf '\n== %s\n' "$*"; }

step "syntax"
for f in "$REPO_DIR"/scripts/archy-* "$REPO_DIR"/scripts/lib.sh "$REPO_DIR"/scripts/install.sh; do
  bash -n "$f" || fail "bash -n $(basename "$f")"
done
for f in "$REPO_DIR"/hypr/*.lua; do
  luac -p "$f" || fail "luac -p $(basename "$f")"
done
((rc == 0)) && info "shell and lua parse"

step "sandbox"
rm -rf "$SANDBOX"
mkdir -p "$SANDBOX/home/.config" "$SANDBOX/home/.local/bin" \
  "$SANDBOX/home/.local/state" "$SANDBOX/home/Pictures/screenshots" "$SANDBOX/home/.cache"
cp -r "$REPO_DIR" "$SANDBOX/home/.config/archy"
rm -rf "$SANDBOX/home/.config/archy/.git"
for s in "$SANDBOX"/home/.config/archy/scripts/archy-*; do
  ln -sf "$s" "$SANDBOX/home/.local/bin/$(basename "$s")"
done
export HOME="$SANDBOX/home"
export ARCHY_BIN_DIR="$HOME/.local/bin"
info "fake HOME with $(ls "$ARCHY_BIN_DIR" | wc -l) scripts linked"

step "config load"
# Point the harness at the sandboxed copy, not the real one.
export ARCHY_ENTRY="$HOME/.config/archy/hypr/hyprland.lua"
if ! lua "$REPO_DIR/test/harness.lua"; then
  fail "the config did not load under the stubbed API"
fi

step "theme generator"
if "$ARCHY_BIN_DIR/archy-theme" sync; then
  gen="$HOME/.config/archy/generated"
  for f in waybar.css wofi.css mako.conf hyprlock.qml kitty.conf; do
    if [[ -s $gen/$f ]]; then
      info "$(printf '%-14s %5s bytes' "$f" "$(wc -c <"$gen/$f")")"
    else
      fail "generated/$f missing or empty"
    fi
  done

  # kitty's palette has to have 16 colors or the terminal renders with gaps.
  kitty_colors="$(grep -c '^color[0-9]' "$gen/kitty.conf" 2>/dev/null || echo 0)"
  if [[ $kitty_colors -eq 16 ]]; then
    info "generated/kitty.conf has all 16 palette entries"
  else
    fail "generated/kitty.conf has $kitty_colors palette entries, expected 16"
  fi

  # The bar gets one stylesheet, so the palette and the layout have to be in the
  # same file.
  if grep -q "@define-color accent" "$gen/waybar.css" && grep -q "window#waybar" "$gen/waybar.css"; then
    info "waybar.css carries both the palette and the layout"
  else
    fail "waybar.css is missing the palette or the layout"
  fi

  # A hex color must survive. The comment-stripping bug that ate every '#' in
  # the palette was invisible to luac and fatal at runtime.
  accent="$(bash -c "source '$REPO_DIR/scripts/lib.sh'; color accent")"
  if [[ $accent == \#* && ${#accent} -eq 7 ]]; then
    info "hex value survives parsing: accent=$accent"
  else
    fail "accent parsed as '$accent'"
  fi
else
  fail "archy-theme sync failed"
fi

step "palette parsers agree"
# Every key in the file, not a hand-kept list: a drifting list would report a
# disagreement that is really just an entry it forgot.
keys="$(grep -oE '^[[:space:]]*[a-z_]+[[:space:]]*=' "$REPO_DIR/colors/colors.conf" | tr -d ' =' | sort -u)"
lua_side="$(lua "$REPO_DIR/test/parse-colors.lua" "$REPO_DIR/colors/colors.conf" | sort)"
shell_side="$(
  while read -r k; do
    [[ -n $k ]] || continue
    printf '%s=%s\n' "$k" "$(bash -c "source '$REPO_DIR/scripts/lib.sh'; color $k")"
  done <<<"$keys" | sort
)"

if [[ $lua_side == "$shell_side" ]]; then
  info "$(printf '%s\n' "$lua_side" | wc -l) keys, identical in both parsers"
else
  diff <(printf '%s\n' "$lua_side") <(printf '%s\n' "$shell_side") >&2
  fail "the Lua and shell parsers disagree: the compositor and the bar would get different themes"
fi

step "live system, read-only"
# The sink resolver is the piece most likely to be subtly wrong and the only
# one that can be checked for real without mutating anything.
if command -v pactl >/dev/null 2>&1; then
  sink="$(bash -c "source '$REPO_DIR/scripts/lib.sh'; audio_sink" 2>/dev/null)"
  if [[ -n $sink ]]; then
    info "audio_sink -> $sink"
    # Read into a variable and match in bash. A pipe into `grep -q` returns 141
    # under pipefail whenever the match is early, because grep exits first and
    # SIGPIPE kills pactl.
    sinks="$(pactl list sinks 2>/dev/null)"
    [[ $sinks == *"Name: $sink"* ]] \
      || fail "audio_sink returned '$sink', which pactl does not know"
  else
    info "audio_sink returned nothing (no audio on this host)"
  fi
fi

if command -v hyprctl >/dev/null 2>&1 && hyprctl version >/dev/null 2>&1; then
  gamma="$(hyprctl hyprsunset gamma 2>/dev/null | grep -oE '[0-9]+' | head -n1)"
  [[ -n $gamma ]] && info "live compositor gamma: $gamma" || info "no gamma filter running"
fi

step "installed-path resolution"
# ~/.local/bin holds symlinks, so a script resolving lib.sh relative to $0
# without readlink works from the repo and fails once installed.
missing=0
for s in "$REPO_DIR"/scripts/archy-*; do
  grep -q 'readlink -f "$0"' "$s" || continue
  name="$(basename "$s")"
  resolved="$(dirname "$(readlink -f "$ARCHY_BIN_DIR/$name")")"
  [[ -r $resolved/lib.sh ]] || {
    fail "$name cannot reach lib.sh from its installed path"
    missing=1
  }
done
((missing == 0)) && info "every script resolves lib.sh through its symlink"

step "packages"
"$REPO_DIR/scripts/install.sh" --check 2>&1 | sed 's/^/  /'

step ""
if ((rc == 0)); then
  echo "PASS — but this does not mean it looks right. Run it."
else
  echo "FAIL"
fi
exit $rc
