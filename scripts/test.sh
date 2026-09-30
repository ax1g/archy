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

step "apps.txt"
# apps.txt is the list for rebuilding without the old setup, so the one thing
# that must never appear in it is a package from that repository: a list that
# cannot be installed is worse than no list. This failed the first time it was
# written, so it is checked rather than trusted.
apps_file="$REPO_DIR/apps.txt"
if [[ ! -f $apps_file ]]; then
  fail "apps.txt is missing"
else
  # Package entries only. The sections from "Decisions" down are prose whose
  # headings start with words like "browser" and "ytkew", which are not
  # packages, and a leak check that reads those is checking nothing.
  #
  # Only lines starting in column 1 are entries; wrapped descriptions are
  # indented, so the second line of a long entry does not register as a name.
  entries="$(awk '/^## Install by hand/{exit} /^[a-z0-9]/ {print}' "$apps_file")"

  leaked=()
  while read -r pkg; do
    [[ -n $pkg ]] || continue
    repo="$(pacman -Si "$pkg" 2>/dev/null | awk -F': *' '/^Repository/{print $2}')"
    [[ $repo == "omarchy" ]] && leaked+=("$pkg")
  done < <(printf '%s\n' "$entries" | grep -vE '^\s*(#|$)' | awk 'NF{print $1}' | tr ',' '\n' | tr -d ' ' | sort -u)

  if ((${#leaked[@]} > 0)); then
    fail "apps.txt lists packages from the omarchy repo: ${leaked[*]}"
    info "those are not installable once that repo is gone"
  else
    info "no packages from the omarchy repo"
  fi

  # A name listed twice is a maintenance trap: it looks deliberate and nobody
  # checks which of the two wins.
  #
  # Scoped to the installable sections only. Everything from "Decisions" down is
  # prose whose headings start with words that happen to be package names, like
  # "neovim config", and counting those is noise rather than duplication. Only
  # lines starting in column 1 are entries; wrapped descriptions are indented.
  entries="$(awk '/^## Install by hand/{exit} /^[a-z0-9]/ {print}' "$apps_file")"
  dupes=""
  while read -r pkg; do
    [[ -n $pkg ]] || continue
    pacman -Si "$pkg" >/dev/null 2>&1 || continue
    dupes+="$pkg "
  done < <(printf '%s\n' "$entries" | grep -vE '^\s*(#|$)' | awk 'NF{print $1}' | tr ',' '\n' | tr -d ' ' | sort | uniq -d)

  if [[ -n $dupes ]]; then
    fail "apps.txt lists these more than once: $dupes"
  else
    info "no duplicated packages"
  fi

  # Every name that is meant to be installable has to exist, or the one-liner in
  # the header fails on a typo. Two are expected to fail: they are documented as
  # manual installs in their own section.
  manual="apple_cursor"
  unexpected=()
  total=0
  while read -r pkg; do
    [[ -n $pkg ]] || continue
    total=$((total + 1))
    pacman -Si "$pkg" >/dev/null 2>&1 && continue
    case " $manual " in
      *" $pkg "*) continue ;;
    esac
    unexpected+=("$pkg")
  done < <(printf '%s\n' "$entries" | grep -vE '^\s*(#|$)' | awk 'NF{print $1}' | tr ',' '\n' | tr -d ' ' | sort -u)

  if ((${#unexpected[@]} > 0)); then
    fail "apps.txt names these but pacman does not: ${unexpected[*]}"
    info "either a typo, or it needs to move to the manual-install section"
  else
    info "all $total names resolve to a real package"
  fi
fi

step "bar scripts resolve"
# The bar's modules call these by bare name, resolved through PATH. If one is
# not installed the module silently renders nothing, so the name is checked here
# rather than discovered as a gap in the bar.
for name in archy-marquee archy-notifications archy-network-menu archy-bluetooth-menu archy-volume archy-launcher archy-wallpaper; do
  if [[ ! -x $ARCHY_BIN_DIR/$name ]]; then
    fail "the bar calls $name but it is not linked into $ARCHY_BIN_DIR"
  fi
done
info "all $(ls "$ARCHY_BIN_DIR" | grep -c '^archy-') archy scripts linked"

# The bar config must not name a script that does not exist, which is the same
# failure one level further out.
missing_refs=""
for ref in $(grep -oE '"(on-click|on-scroll-up|on-scroll-down|exec)":\s*"archy-[a-z-]+' \
  "$REPO_DIR/waybar/config.jsonc" | grep -oE 'archy-[a-z-]+' | sort -u); do
  [[ -x $ARCHY_BIN_DIR/$ref ]] || missing_refs+="$ref "
done
if [[ -n $missing_refs ]]; then
  fail "waybar/config.jsonc calls scripts that do not exist: $missing_refs"
else
  info "every archy-* script the bar calls exists"
fi

# The bar must reference colors only through the generated stylesheet. A literal
# color here would survive a theme change and then be wrong.
if grep -nE '#[0-9a-fA-F]{6}\b' "$REPO_DIR/waybar/config.jsonc" >/dev/null; then
  fail "waybar/config.jsonc has a literal color; colors belong in colors.conf"
else
  info "no literal colors in the bar config"
fi

step "wallpaper"
default_wall="$REPO_DIR/wallpapers/totoro.png"
if [[ -r $default_wall ]]; then
  size="$(python3 - "$default_wall" <<'PY'
import struct, sys
data = open(sys.argv[1], 'rb').read(33)
w, h = struct.unpack('>II', data[16:24])
print(f"{w}x{h}")
PY
)"
  # The panel is 1920x1080 at scale 1, so the default wallpaper should match it
  # exactly. swww crops anything that does not, so a mismatch is not fatal, but
  # it means the image is being resampled every login and losing detail.
  if [[ $size == "1920x1080" ]]; then
    info "default wallpaper is $size, matching the panel"
  else
    warn "default wallpaper is $size, panel is 1920x1080"
    warn "swww will crop it, which is fine but resamples the image every login"
  fi
else
  fail "the default wallpaper wallpapers/totoro.png is missing"
fi

step "jsonc"
# Both of these are JSONC, and a naive `sed 's|//.*||'` check is wrong: it eats
# the // in the $schema https:// URL and reports a parse error on a good file.
# check-jsonc.py strips comments while tracking string state.
if ! jsonc_out="$(python3 "$REPO_DIR/scripts/check-jsonc.py" \
  "$REPO_DIR/fastfetch/config.jsonc" \
  "$REPO_DIR/waybar/config.jsonc" 2>&1)"; then
  printf '%s\n' "$jsonc_out" | sed 's/^/  /'
  fail "a JSONC file does not parse"
else
  printf '%s\n' "$jsonc_out" | sed 's/^/  /'
fi

# fastfetch reads a command per row, and a row that shells out to something
# absent prints an error every time fastfetch runs. Nothing in this config may
# reference the old setup.
if grep -qE '"text":[^"]*omarchy' "$REPO_DIR/fastfetch/config.jsonc"; then
  fail "fastfetch has a row that runs an omarchy command"
else
  info "no fastfetch row depends on the old setup"
fi

# The logo is referenced by path. If it is missing, fastfetch falls back to
# nothing and prints the modules with no logo at all, with no error.
#
# The path in the config is the installed one (~/.config/archy/...), because that
# is what fastfetch reads at runtime, not the checkout path. Resolving it here
# checks the repo copy at the same relative name.
logo_src="$(grep -oE '"source":[[:space:]]*"~/[^"]*"' "$REPO_DIR/fastfetch/config.jsonc" |
  head -n1 | grep -oE '~/[^"]*')"
if [[ -n $logo_src ]]; then
  # install.sh symlinks the checkout to ~/.config/archy, so that prefix in the
  # config resolves to the repo copy. Map it back rather than assuming.
  logo_path="$logo_src"
  case "$logo_src" in
    "~/.config/archy/"*) logo_path="$REPO_DIR/${logo_src#"~/.config/archy/"}" ;;
    "~/"*) logo_path="$REPO_DIR/${logo_src#\~/}" ;;
  esac
  if [[ ! -r $logo_path ]]; then
    fail "fastfetch logo missing: $logo_src -> $logo_path"
  else
    info "fastfetch logo present ($(basename "$logo_path"))"
  fi
else
  info "fastfetch uses no logo"
fi

step "keyd"
# A keymap that fails to parse means no remap at all, which on this machine is
# indistinguishable from having no Escape key. The installer refuses to write an
# unparseable one; this makes sure the file in the repo is itself valid.
if ! command -v keyd >/dev/null 2>&1; then
  info "keyd not installed, skipping the keymap check"
else
  conf="$REPO_DIR/keyd.conf"
  problems=""
  grep -q '^\[ids\]' "$conf" || problems+=" no [ids] section;"
  grep -q '^\[main\]' "$conf" || problems+=" no [main] section;"
  grep -q '^\[nav\]' "$conf" || problems+=" no [nav] section;"
  # The specific pairing this config exists for: Caps Lock overloaded onto nav,
  # where the vim keys live. Without both halves neither is reachable.
  grep -qi 'capslock[[:space:]]*=[[:space:]]*overload(nav' "$conf" ||
    problems+=" capslock is not overloaded onto nav;"
  for key in h j k l; do
    grep -qE "^${key}[[:space:]]*=" "$conf" || problems+=" no ${key} binding;"
  done

  if [[ -n $problems ]]; then
    fail "keyd.conf is incomplete:$problems"
  else
    info "keyd.conf has the [nav] map and capslock overload"
  fi
fi

step "screenshots"
# The renderers read the generated files, so a component that silently renders in
# the wrong theme is the failure worth catching: a missing @define-color block or
# a generated file that was never written still produces a screenshot, just an
# ugly one. This checks the inputs are present, not that the images look right.
if [[ ! -x "$REPO_DIR/scripts/render-components.py" ]]; then
  fail "scripts/render-components.py is missing or not executable"
else
  for f in waybar.css wofi.css mako.conf kitty.conf hyprlock.qml; do
    [[ -s "$REPO_DIR/generated/$f" ]] ||
      fail "generated/$f is missing; the component renderers would draw nothing"
  done
  if compgen -G "$REPO_DIR/screenshots/*.png" >/dev/null; then
    info "$(ls "$REPO_DIR"/screenshots/*.png | wc -l) screenshots rendered"
  else
    info "no screenshots yet; run scripts/render-components.py"
  fi
fi

step "shell"
# A .bashrc that does not load is the most visible failure in this repo, and the
# one it replaced sourced a defaults file for aliases and completions. So this
# checks the replacement is self-contained and actually loads.
if grep -qE 'OMARCHY_PATH|omarchy/default' "$REPO_DIR/bashrc"; then
  fail "bashrc still sources the old setup"
else
  info "bashrc sources nothing outside the repo"
fi

# The early return for non-interactive shells has to come after the PATH and
# locale blocks, or a script run over SSH gets neither.
rc_line="$(grep -n 'return' "$REPO_DIR/bashrc" | head -n1 | cut -d: -f1)"
path_line="$(grep -n 'local/bin' "$REPO_DIR/bashrc" | head -n1 | cut -d: -f1)"
if [[ -n $rc_line && -n $path_line ]] && ((rc_line < path_line)); then
  fail "bashrc returns before the PATH setup; scripts get no .local/bin"
else
  info "PATH is set before the interactive check"
fi

# Load it for real, in a stripped environment, and see whether the prompt hooks
# and the aliases survive. A clean env matters: it is what a fresh session or an
# SSH command actually looks like.
if bash -c 'set -e; source "$1"' _ "$REPO_DIR/bashrc" 2>/dev/null; then
  info "bashrc loads non-interactively without error"
else
  fail "bashrc errors when sourced"
fi

if out="$(env -i HOME="$HOME" TERM=dumb PATH="/usr/bin:/bin" \
  bash --rcfile "$REPO_DIR/bashrc" -i -c 'echo ok' 2>&1)"; then
  if [[ $out == *ok* ]]; then
    info "bashrc loads interactively and returns to the prompt"
  else
    fail "interactive load did not reach the prompt: $out"
  fi
else
  fail "interactive load failed: $out"
fi

# starship: it is a straight copy, so the only thing worth checking is that it
# parses and that nothing in it reaches for a path that will not exist.
if python3 -c "
import sys, tomllib
tomllib.load(open(sys.argv[1], 'rb'))
" "$REPO_DIR/starship/starship.toml" 2>/dev/null; then
  info "starship.toml parses"
else
  fail "starship.toml is not valid TOML"
fi

if grep -qiE 'omarchy|local/state' "$REPO_DIR/starship/starship.toml"; then
  fail "starship.toml references the old setup"
else
  info "starship.toml is self-contained"
fi

step "desktop only"
# This is a desktop: one HDMI output, no eDP internal panel, no battery, no lid
# switch. Anything that only works on a laptop is dead weight here, and a script
# that silently exits 0 is worse than one that was never written, because it
# looks like it is doing something.
desktop_only=0

if [[ -n $(ls /sys/class/power_supply/ 2>/dev/null) ]]; then
  info "a battery is present, so battery-aware config would be reasonable"
else
  if compgen -G "$REPO_DIR/scripts/*battery*" >/dev/null; then
    fail "a battery script exists but there is no battery"
    desktop_only=1
  fi
  if grep -qiE '"type":[[:space:]]*"battery"' "$REPO_DIR/waybar/config.jsonc"; then
    fail "waybar has a battery module but there is no battery"
    desktop_only=1
  fi
  if grep -q "power-profiles-daemon" "$REPO_DIR/scripts/install.sh" "$REPO_DIR/apps.txt" 2>/dev/null; then
    fail "power-profiles-daemon is listed but there is no battery to switch away from"
    desktop_only=1
  fi
fi

if ls /sys/class/power_supply/ 2>/dev/null | grep -q . || \
   [[ -n $(hyprctl -j monitors 2>/dev/null | jq -r '.[].name | select(startswith("eDP-"))' 2>/dev/null) ]]; then
  info "an internal panel is present, so clamshell handling would be reasonable"
else
  for gone in monitor-clamshell monitor-internal; do
    if compgen -G "$REPO_DIR/scripts/archy-$gone" >/dev/null; then
      fail "archy-$gone exists but there is no internal panel to switch"
      desktop_only=1
    fi
  done
  if grep -q "Lid Switch" "$REPO_DIR/hypr/bindings.lua"; then
    fail "lid switch bindings exist but there is no lid switch"
    desktop_only=1
  fi
fi

((desktop_only == 0)) && info "no laptop-only config for a machine with no lid, panel or battery"

step "vscode theme"
# The theme name has to agree in three places: the label the extension
# contributes, the name inside the theme file, and workbench.colorTheme in the
# user settings. If they disagree VS Code falls back to its default dark and the
# setting looks like it did nothing, so this is worth asserting rather than
# eyeballing.
if [[ ! -d "$REPO_DIR/vscode" ]]; then
  fail "vscode/ is missing; settings.json would name a theme that is not there"
else
  # The heredoc terminator has to sit at column 0. Indented, bash treats it as
  # more script, the if never closes, and the next check runs as a false branch
  # and reports a failure that has nothing to do with the theme.
  if python3 - "$REPO_DIR" <<'PY'
import json, pathlib, sys
root = pathlib.Path(sys.argv[1])
pkg = json.loads((root / "vscode/package.json").read_text())
# The contributed path is relative to the extension root and starts with "./".
# Removed as a prefix, not as a character set: stripping characters would turn
# "./themes/x.json" into "themes/x.json" by luck, and "/themes/x.json" by
# accident on a leading-dot path.
raw = pkg["contributes"]["themes"][0]["path"]
theme_rel = raw[2:] if raw.startswith("./") else raw.lstrip("/")
theme = json.loads((root / "vscode" / theme_rel).read_text())
settings = json.loads((root / "vscode/settings.json").read_text())
label = pkg["contributes"]["themes"][0]["label"]
want = settings["workbench.colorTheme"]
if label != theme["name"]:
    sys.exit(f"package.json label {label!r} != theme name {theme['name']!r}")
if want != theme["name"]:
    sys.exit(f"colorTheme {want!r} != theme name {theme['name']!r}")
print(f"  ok   {theme['name']}: {len(theme['colors'])} colors, "
      f"{len(theme.get('tokenColors', []))} token rules, label and colorTheme agree")
PY
  then
    :
  else
    fail "the vscode theme names do not agree"
  fi

  # The extension is loaded from ~/.vscode/extensions by name, so the directory
  # it is linked as has to match the publisher and name in package.json.
  pub="$(python3 -c "import json;print(json.load(open('$REPO_DIR/vscode/package.json'))['publisher'])")"
  name="$(python3 -c "import json;print(json.load(open('$REPO_DIR/vscode/package.json'))['name'])")"
  info "installs as $pub.$name -> ~/.vscode/extensions/archy-theme"
fi

step "packages"
"$REPO_DIR/scripts/install.sh" --check 2>&1 | sed 's/^/  /'

step ""
if ((rc == 0)); then
  echo "PASS — but this does not mean it looks right. Run it."
else
  echo "FAIL"
fi
exit $rc
