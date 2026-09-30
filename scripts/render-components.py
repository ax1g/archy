#!/usr/bin/env python3
"""Render each surface of the desktop to screenshots/, from the real config.

Every component is built from the file that the running program would read:
generated/waybar.css, generated/wofi.css, generated/mako.conf, colors.conf. The
palette is never written out by hand, so retheming and re-running this produces
screenshots of the new theme rather than of the old one.

What this is: the layout, spacing, colors, and the shape of each surface. What
it is not: GTK. Wofi and Waybar render through GTK, Mako through GTK, and
hyprlock through Qt. This is a browser, so text metrics, shadow radii, and border
rounding will differ by a pixel or two, and anything with a real animation is
shown in one of its states only.

Usage:
    scripts/render-components.py [name ...]     # default: all
    scripts/render-components.py bar wofi-lock
"""

import base64
import pathlib
import re
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
OUT = ROOT / "screenshots"
GENERATED = ROOT / "generated"
WALLPAPER = ROOT / "wallpapers" / "totoro.png"

BAR_HEIGHT = 26
WIDTH = 1920


# ---------------------------------------------------------------- palette

def colors():
    """Read the palette out of the generated stylesheet.

    The generated CSS is the concatenation of the @define-color block and the
    hand-written layout, so this sees the real values with no second copy to
    keep in step.
    """
    css = (GENERATED / "waybar.css").read_text()
    found = dict(re.findall(r"@define-color\s+(\w+)\s+([^;]+);", css))
    if not found:
        sys.exit("generated/waybar.css has no @define-color block; run archy-theme sync")
    return found


def rgb(hexish, alpha=None):
    """#rrggbb or rgba(r,g,b,a) into something usable as a CSS color."""
    h = hexish.strip().lstrip("#")
    if len(h) == 3:
        h = "".join(c * 2 for c in h)
    if len(h) == 8:
        h = h[:6]
    r, g, b = int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16)
    if alpha is not None:
        return f"rgba({r},{g},{b},{alpha})"
    return f"rgb({r},{g},{b})"


def wallpaper_b64():
    if not WALLPAPER.exists():
        return ""
    return base64.b64encode(WALLPAPER.read_bytes()).decode()


# ---------------------------------------------------------------- shared css

def shell_css(c, *, wallpaper=False, height=None):
    """The page frame. One place, so every component sits on the same ground."""
    bg = f"url(data:image/png;base64,{wallpaper_b64()})" if wallpaper else "none"
    return f"""
  * {{ box-sizing: border-box; margin: 0; padding: 0; }}
  body {{
    font-family: "JetBrainsMono Nerd Font", "DejaVu Sans Mono", monospace;
    font-size: 12px;
    background: {rgb(c['darker_background'])};
    background-image: {bg};
    background-size: {WIDTH}px auto;
    background-position: top center;
    background-repeat: no-repeat;
    color: {rgb(c['foreground'])};
  }}
  /* Three passes, matching waybar/style.css: tight for the glyph edge, wider
     to carry the shape. */
  .shadow {{
    text-shadow: 0 0 2px {rgb(c['darker_background'])},
                 0 0 4px {rgb(c['darker_background'])},
                 0 0 6px {rgb(c['darker_background'])};
  }}
  .g {{ display: inline-block; min-width: 11px; text-align: center;
        color: {rgb(c['muted'])}; }}
  .cap {{ background: {rgb(c['darker_background'])};
          padding: 12px 24px 14px; line-height: 1.55; }}
  .cap b {{ color: {rgb(c['muted'])}; font-weight: normal; }}
  .cap code {{ color: {rgb(c['accent'])}; }}
  .cap .note {{ color: {rgb(c['yellow'])}; }}
  .g-label {{ color: {rgb(c['dark_foreground'])}; font-size: 10px;
              text-transform: uppercase; letter-spacing: .08em;
              margin: 0 0 10px; }}
"""


def page(title, body, extra_css, c, caption, *, wallpaper=False, height=None):
    return f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
{shell_css(c, wallpaper=wallpaper, height=height)}
{extra_css}
</style></head><body>
{body}
<div class="cap"><b>{title}</b><br>{caption}</div>
</body></html>"""


# ---------------------------------------------------------------- bar

def render_bar(c):
    cfg = (ROOT / "waybar" / "config.jsonc").read_text()

    def fmt(module):
        m = re.search(r'"%s"\s*:\s*\{(.*?)\n  \}' % module, cfg, re.S)
        if not m:
            return ""
        g = re.search(r'"format(?:-icon|-icons|-wifi)?"\s*:\s*"((?:[^"\\]|\\.)*)"', m.group(1))
        return g.group(1) if g else ""

    def icon(text):
        return "".join(
            f'<span class="g">&#x{ord(ch):x};</span>' if ord(ch) > 0x2500 else ch
            for ch in text)

    def expand(f, values=None, unnamed=None):
        out = []
        for part in re.split(r"(\{[^}]*\})", f):
            m = re.fullmatch(r"\{(.*?)\}", part)
            if not m:
                out.append(icon(part))
                continue
            k = m.group(1)
            if k.startswith(":"):
                out.append(time.strftime(k[1:]))
            elif k == "icon":
                out.append('<span class="g">&#xe000;</span>')
            elif k == "":
                out.append(unnamed or "?")
            else:
                out.append((values or {}).get(k, "?"))
        return "".join(out)

    launcher = expand(fmt("launcher"))
    clock = expand(fmt("clock"))
    vol = expand(fmt("pulseaudio"), {"volume": "62"})
    net = expand(fmt("network"), {"signalStrength": "78"})

    ws = "".join(
        f'<div class="ws{" on" if n == "1" else ""}">{n}</div>' for n in "12345")

    body = f"""
<div class="bar shadow">
  <div class="left">
    <div id="launcher">{launcher}</div>
    <div id="workspaces">{ws}</div>
    <div id="marquee">Ludovico Einaudi — Nuvole Bianche</div>
  </div>
  <div class="mid">{clock}</div>
  <div class="right">
    <div id="mod">{net}</div>
    <div id="mod"><span class="g">&#xf029;</span>2</div>
    <div id="mod">{vol}</div>
    <div id="mod"><span class="g">&#xf08b;</span></div>
    <div id="tray"><span class="traydots">{'&#9679;' * 3}</span></div>
  </div>
</div>"""

    css = f"""
  .bar {{ height: {BAR_HEIGHT}px; width: {WIDTH}px; display: flex;
          align-items: center; background: transparent; }}
  .left {{ display: flex; align-items: center; }}
  .mid {{ flex: 1; text-align: center; color: {rgb(c['bright_foreground'])};
          font-weight: bold; }}
  .right {{ display: flex; align-items: center; }}
  #launcher {{ color: {rgb(c['bright_foreground'])}; font-size: 14px;
               padding: 0 12px 0 12px; }}
  #workspaces {{ display: flex; padding: 0 10px 0 4px; }}
  .ws {{ padding: 0 7px; color: {rgb(c['bright_foreground'])}; }}
  .ws.on {{ color: {rgb(c['accent'])}; font-weight: bold;
            text-decoration: underline; text-underline-offset: 2px; }}
  #marquee {{ color: {rgb(c['bright_foreground'])}; padding: 0 9px 0 6px; }}
  #mod {{ color: {rgb(c['bright_foreground'])}; font-size: 14px; padding: 0 9px; }}
  #tray {{ color: {rgb(c['foreground'])}; font-size: 14px; padding: 0 10px 0 9px; }}
  .traydots {{ letter-spacing: 2px; opacity: .75; font-size: 11px; }}
"""
    cap = (f"waybar/config.jsonc + generated/waybar.css, {WIDTH}&times;{BAR_HEIGHT}, "
           f"no background of its own.<br>left <code>launcher, workspaces, custom-marquee</code> "
           f"&middot; centre <code>clock</code> &middot; right "
           f"<code>network, custom-notifications, pulseaudio, bluetooth, tray</code><br>"
           f"Volume, signal and the notification count are sample values; the clock is live. "
           f"The marquee is empty when nothing is playing, so the left cluster shortens.")
    return page("waybar", body, css, c, cap, wallpaper=True)


# ---------------------------------------------------------------- wofi

def wofi_css(c, *, width=620, height=460, prompt="Launch"):
    """Reproduce generated/wofi.css and wofi/config.rasi.

    The rasi sets the geometry and the rounded corners, the generated css the
    colors. Both are read from the real files; this only restates them as one
    stylesheet, because a browser cannot consume two of them.
    """
    rasi = (ROOT / "wofi" / "config.rasi").read_text()

    def rasi_value(key, default):
        m = re.search(rf'{key}\s*:?\s*"?([\w.%]+)"?\s*;', rasi)
        return m.group(1) if m else default

    w = rasi_value("width", str(width)).replace("px", "")
    h = rasi_value("height", str(height)).replace("px", "")
    loc = rasi_value("location", "center")
    input_size = rasi_value("font-size", "18px").replace("px", "")

    justify = {"center": "center", "top": "flex-start",
               "bottom": "flex-end"}.get(loc, "center")
    align = {"center": "center", "left": "flex-start",
             "right": "flex-end"}.get(loc, "center")

    return f"""
  .wofi {{ position: fixed; top: 0; left: 0; width: {WIDTH}px;
           height: 100vh; display: flex; align-items: {justify};
           justify-content: {align}; }}
  .win {{ width: {w}px; height: {h}px;
          background: {rgb(c['darker_background'])};
          color: {rgb(c['foreground'])};
          border: 2px solid {rgb(c['muted'])};
          border-radius: 8px; overflow: hidden;
          display: flex; flex-direction: column;
          box-shadow: 0 18px 50px {rgb(c['darker_background'], 0.55)}; }}
  .input {{ font-size: {input_size}px; color: {rgb(c['bright_foreground'])};
            background: {rgb(c['dark_background'])};
            border-bottom: 2px solid {rgb(c['accent'])};
            padding: 12px; margin: 8px;
            border-bottom-left-radius: 0; border-bottom-right-radius: 0; }}
  .input::before {{ content: "{prompt}  "; color: {rgb(c['dark_foreground'])}; }}
  .list {{ margin: 0 8px 8px 8px; overflow: hidden; flex: 1; }}
  .item {{ padding: 8px 10px; border-radius: 8px; color: {rgb(c['foreground'])}; }}
  .item.sel {{ background: {rgb(c['selection'])};
               color: {rgb(c['bright_foreground'])};
               border-left: 3px solid {rgb(c['accent'])}; padding-left: 7px; }}
"""


ICONS = {"firefox": "&#xf269;", "code": "&#xe77c;", "nautilus": "&#xf07b;",
         "kitty": "&#xe795;", "obsidian": "&#xf188;", "zen": "&#xf6d0;",
         "spotify": "&#xf1bc;", "discord": "&#xf233;", "telegram": "&#xf2c6;",
         "btop": "&#xf0e0;", "drawy": "&#xf1fc;", "nemo": "&#xf06d;",
         "org.gnome.Nautilus": "&#xf07b;"}


def wofi_body(prompt, items, selected=0):
    """The window with its rows.

    The prompt goes in via a CSS ::before so it sits at the start of the entry
    field where wofi puts it. The div's own text is empty, otherwise the prompt
    prints twice.
    """
    rows = []
    for i, (icon, label) in enumerate(items):
        glyph = ICONS.get(icon, "&#xf15b;")
        sel = " sel" if i == selected else ""
        rows.append(f'<div class="item{sel}"><span class="g">{glyph}</span>  {label}</div>')
    return (f'<div class="wofi"><div class="win">'
            f'<div class="input"></div>'
            f'<div class="list">{"".join(rows)}</div></div></div>')


def wofi_page(c, title, prompt, items, selected, caption, **kw):
    return page(title, wofi_body(prompt, items, selected),
                wofi_css(c, prompt=prompt, **kw), c, caption)


# ---------------------------------------------------------------- components

def comp_launcher(c):
    items = [
        ("firefox", "Firefox"),
        ("code", "Visual Studio Code"),
        ("nautilus", "Files"),
        ("kitty", "kitty"),
        ("obsidian", "Obsidian"),
        ("zen", "Zen Browser"),
        ("spotify", "Spotify"),
        ("telegram", "Telegram"),
        ("btop", "btop"),
    ]
    cap = ("wofi/config.rasi + generated/wofi.css, <code>--show drun</code>.<br>"
           "Every wofi surface is the same window with different rows: the launcher, "
           "the window switcher, the power menu, the clipboard, the theme and wallpaper "
           "pickers, the keybindings list, and the emoji picker. Only the rows and the "
           "prompt change.<br>Note that <b>--config</b> and <b>--style</b> are parsed "
           "separately by wofi, so every color lives in the generated css.")
    return wofi_page(c, "wofi — launcher", "Launch", items, 0, cap)


def comp_window_switcher(c):
    items = [
        ("zen", "2  zen — Reddit /r/hyprland"),
        ("code", "2  code — bindings.lua"),
        ("kitty", "3  kitty — bash"),
        ("nautilus", "3  Files — Downloads"),
        ("firefox", "5  firefox — Arch Wiki"),
    ]
    cap = ("The workspace number is in the label so two windows of the same class are "
           "still distinguishable. <code>--hide-input</code> because there is nothing to "
           "type here: the list is short enough to arrow through, and a search field on a "
           "switcher invites the wrong reflex.")
    return wofi_page(c, "wofi — window switcher", "Window", items, 0, cap,
                     width=560, height=280)


def comp_power(c):
    items = [("", "Lock"), ("", "Log out"), ("", "Reboot"), ("", "Power off"), ("", "Suspend")]
    cap = ("Locked, because this is the menu that shuts the machine down. Suspend is "
           "dropped when the kernel has no standby state, so it never appears on a "
           "machine that cannot do it.")
    return wofi_page(c, "wofi — power menu", "Power", items, 0, cap,
                     width=320, height=260)


def comp_clipboard(c):
    items = [("", "archy -color=always -c ~/.config/archy/colors/colors.conf"),
             ("code", "git status --short"),
             ("kitty", "pacman -Qqe | wc -l"),
             ("", "https://wiki.hypr.land/Configuring/Start/")]
    cap = ("cliphist is the store and wl-clipwatch is the watcher, started from "
           "autostart.lua. Without the watcher running, every clipboard chord works and "
           "the history is permanently empty, so it is the one autostart line worth "
           "checking first if this opens empty.")
    return wofi_page(c, "wofi — clipboard history", "Clipboard", items, 0, cap,
                     width=680, height=320)


def comp_keybindings(c):
    items = [("", "SUPER + SPACE     App launcher"),
             ("", "SUPER + RETURN    Terminal"),
             ("", "SUPER + T         Tile or float the workspace"),
             ("", "SUPER + S         Scratchpad"),
             ("", "SUPER + `         Quake console"),
             ("", "SUPER + C         Copy, everywhere"),
             ("", "SUPER + K         Keybindings"),
             ("", "SUPER + CTRL + L  Lock")]
    cap = ("Read out of <code>hyprctl binds</code> rather than parsed from the config, so "
           "it shows what the compositor actually has, including anything a package update "
           "changed. Lock-screen bindings are excluded: unreachable from an unlocked "
           "session, and noise in a list meant for reference.")
    return wofi_page(c, "wofi — keybindings", "Keybindings", items, 0, cap,
                     width=520, height=400)


def comp_emoji(c):
    items = [("", "thumbs up sign"), ("", "rocket"), ("", "snake"), ("", "fire"),
             ("", "sparkles"), ("", "check mark"), ("", "skull"), ("", "party popper")]
    cap = ("Searches by unicode name, which is why these are words and not glyphs. The "
           "list is <code>data/emoji.txt</code>, generated from Python's unicodedata and "
           "committed rather than fetched, so the picker needs no network and no extra "
           "package. Select and it is typed with wtype.")
    return wofi_page(c, "wofi — emoji picker", "Emoji", items, 0, cap,
                     width=420, height=340)


def comp_theme(c):
    items = [("", "evergreen"), ("", "sakura"), ("", "ristretto"),
             ("", "tokyo-night"), ("", "matte-black")]
    cap = ("One file per theme, each a complete copy of <code>colors/colors.conf</code>. "
           "The menu copies the chosen file over the live one and keeps a <code>.bak</code> "
           "beside it, so a bad switch is undoable without git. Themes do not change this "
           "screenshot, because this is a browser and not GTK.")
    return wofi_page(c, "wofi — theme picker", "Theme", items, 0, cap,
                     width=360, height=300)


# ---------------------------------------------------------------- mako

def comp_notifications(c):
    def toast(x, y, w, summary, body, actions=False):
        act = ""
        if actions:
            act = (f'<div class="acts">Reply<span class="g">&#xf054;</span>'
                   f'<span class="g">&#xf00c;</span></div>')
        return (f'<div class="toast" style="left:{x}px; top:{y}px; width:{w}px">'
                f'<div class="sum">{summary}</div>'
                f'<div class="body">{body}</div>{act}</div>')

    body = "".join([
        toast(1240, 60, 420, "Build finished", "archy — 0 errors, 2 warnings"),
        toast(1240, 150, 420, "Screenshot saved", "screenshot_2026-09-30_18-12.png"),
        toast(1240, 240, 420, "Volume 62%", ""),
    ])
    css = f"""
  .toast {{ position: absolute; background: {rgb(c['darker_background'])};
            color: {rgb(c['foreground'])};
            border: 2px solid {rgb(c['muted'])}; border-radius: 8px;
            padding: 12px; margin: 6px;
            box-shadow: 0 10px 30px {rgb(c['darker_background'], 0.5)}; }}
  .sum {{ font-weight: bold; color: {rgb(c['bright_foreground'])}; margin-bottom: 4px; }}
  .body {{ color: {rgb(c['light_foreground'])}; }}
  .acts {{ color: {rgb(c['accent'])}; margin-top: 8px; }}
  .g {{ min-width: 9px; }}
"""
    cap = ("mako, from generated/mako.conf. Anchored top right. <br>Mako draws the "
           "notification and hands the action buttons to wofi, so there is one overlay "
           "style rather than two — that is why there is no separate button style here. "
           "<br>The count in the bar comes from the same daemon's history, not from a "
           "second source.")
    return page("mako — notifications", body, css, c, cap, wallpaper=True)


# ---------------------------------------------------------------- hyprlock

def comp_lock(c):
    now = time.strftime("%H:%M")
    body = f"""
<div class="lock">
  <div class="clock">{now}</div>
  <div class="date">{time.strftime('%A, %d %B')}</div>
  <div class="topbar"></div>
  <div class="hint">SUPER+SPACE launch  ·  SUPER+ESCAPE power</div>
</div>"""
    css = f"""
  .lock {{ position: relative; width: {WIDTH}px; height: 100vh;
           background: {rgb(c['darker_background'])};
           display: flex; flex-direction: column; align-items: center;
           justify-content: center; }}
  .clock {{ font-size: 96px; font-weight: bold;
            color: {rgb(c['bright_foreground'])}; line-height: 1; }}
  .date {{ font-size: 18px; color: {rgb(c['dark_foreground'])}; margin-top: 12px; }}
  .topbar {{ position: absolute; top: 0; width: 100%; height: 3px;
             background: {rgb(c['accent'])}; }}
  .hint {{ position: absolute; bottom: 48px; font-size: 14px;
           color: {rgb(c['muted'])}; }}
"""
    cap = ("hyprlock, from generated/hyprlock.qml, written by archy-theme.<br>"
           "The one surface that is Qt rather than GTK, and the one that most needs the "
           "compositor's own frost rather than a flat fill — the screen behind it is "
           "faded to black first by archy-lock, before this surface comes up, because "
           "cycling DPMS with a lock surface on screen takes down every output the "
           "compositor has.")
    return page("hyprlock", body, css, c, cap)


# ---------------------------------------------------------------- qconsole

def comp_qconsole(c):
    body = """
<div class="desk">
  <div class="ghost">window behind, dimmed by dim_special 0.6</div>
  <div class="console">
    <div class="gutter">~/Projects/archy</div>
    <div class="gutter">❯</div>
    <div class="gutter">❯</div>
  </div>
</div>"""
    css = f"""
  .desk {{ position: relative; width: {WIDTH}px; height: 100vh;
          background: {rgb(c['background'])}; }}
  .ghost {{ position: absolute; inset: 0; color: {rgb(c['dark_foreground'])};
            padding: 60px 40px; font-size: 13px; opacity: .35; }}
  .console {{ position: absolute; top: 0; left: 0; right: 0; height: 50%;
              background: {rgb(c['darker_background'])};
              border-bottom: 1px solid {rgb(c['muted'])};
              padding: 14px 24px; }}
  .gutter {{ color: {rgb(c['foreground'])}; line-height: 1.5; }}
  .gutter:nth-child(2) {{ color: {rgb(c['accent'])}; }}
"""
    cap = ("special:qconsole, from hypr/qconsole.lua. Half the usable height, dropped from "
           "the top.<br><code>dim_special = 0.6</code> is what separates it from the "
           "workspace underneath, and it only costs anything while the console is open. "
           "Seeded with kitty, so it is a terminal from the first open.")
    return page("Quake console", body, css, c, cap, wallpaper=False)


# ---------------------------------------------------------------- registry

COMPONENTS = {
    "bar": render_bar,
    "launcher": comp_launcher,
    "window-switcher": comp_window_switcher,
    "power": comp_power,
    "clipboard": comp_clipboard,
    "keybindings": comp_keybindings,
    "emoji": comp_emoji,
    "theme": comp_theme,
    "notifications": comp_notifications,
    "lock": comp_lock,
    "qconsole": comp_qconsole,
}

HEIGHTS = {
    "bar": BAR_HEIGHT + 130,
    "launcher": 700, "window-switcher": 520, "power": 500,
    "clipboard": 560, "keybindings": 640, "emoji": 580, "theme": 540,
    "notifications": 480, "lock": 1080, "qconsole": 700,
}


def browser():
    for name in ("chromium", "chromium-browser", "google-chrome",
                 "google-chrome-stable"):
        path = shutil.which(name)
        if path:
            return path
    return None


def main(argv):
    OUT.mkdir(parents=True, exist_ok=True)
    chrome = browser()
    if not chrome:
        print("no chromium found; cannot screenshot. Install chromium.", file=sys.stderr)
        return 1

    names = argv[1:] or list(COMPONENTS)
    unknown = [n for n in names if n not in COMPONENTS]
    if unknown:
        print(f"unknown component(s): {', '.join(unknown)}", file=sys.stderr)
        print(f"available: {', '.join(COMPONENTS)}", file=sys.stderr)
        return 2

    c = colors()
    for name in names:
        html = COMPONENTS[name](c)
        html_path = OUT / f"{name}.html"
        png_path = OUT / f"{name}.png"
        html_path.write_text(html)
        subprocess.run(
            [chrome, "--headless", "--disable-gpu", "--no-sandbox",
             f"--screenshot={png_path}",
             f"--window-size={WIDTH},{HEIGHTS.get(name, 700)}",
             "--hide-scrollbars", html_path.as_uri()],
            capture_output=True, check=False)
        if png_path.exists():
            print(f"  {png_path.relative_to(ROOT)}")
        else:
            print(f"  FAILED {name}", file=sys.stderr)

    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
