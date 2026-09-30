#!/usr/bin/env python3
"""Render the Waybar layout described by waybar/config.jsonc and the generated
stylesheet, as a PNG.

This is not Waybar. It is a preview built from the same two files Waybar reads,
so the geometry, the spacing, the module order and the colors are the real ones.
What it cannot show is anything Waybar computes at runtime: the actual volume
number, real CPU and memory figures, the real window title, the tray contents,
and how GTK renders the font in practice.

Usage:
    scripts/render-waybar.py [output.png] [--modules "1 2 3 4 5 6 7 8 9 10"]
"""

import argparse
import json
import pathlib
import re
import shutil
import subprocess
import sys
import time

ROOT = pathlib.Path(__file__).resolve().parent.parent
CONFIG = ROOT / "waybar" / "config.jsonc"
STYLE = ROOT / "generated" / "waybar.css"

# Sample values for the modules Waybar fills in at runtime. The keys have to
# match the placeholders in each module's format string, not the module's name.
SAMPLE = {
    "marquee": "Ludovico Einaudi — Nuvole Bianche",
    "volume": "62",
    "signalStrength": "78",
}

# Workspaces, 1-based, for the preview.
DEFAULT_WORKSPACES = "1 2 3 4 5 6 7 8 9 10"
DEFAULT_ACTIVE = "2"


def read_config():
    text = CONFIG.read_text()
    text = re.sub(r"//.*", "", text)
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    text = re.sub(r",(\s*[}\]])", r"\1", text)
    return json.loads(text)


def read_colors():
    """Palette from the generated stylesheet, so it cannot drift from the theme."""
    colors = dict(re.findall(r"@define-color\s+(\w+)\s+([^;]+);", STYLE.read_text()))
    missing = {"darker_background", "foreground", "accent", "dark_foreground",
               "bright_foreground", "selection", "muted"} - colors.keys()
    if missing:
        sys.exit(f"generated/waybar.css is missing {sorted(missing)}; run archy-theme sync")
    return colors


def escape_html(text):
    return (str(text).replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;"))


def read_module(key):
    """One module block out of the raw config, which keeps the glyphs."""
    text = CONFIG.read_text()
    match = re.search(r'"%s"\s*:\s*\{(.*?)\n  \}' % re.escape(key), text, re.S)
    if not match:
        return {}
    block = match.group(1)
    fmt = re.search(r'"format"\s*:\s*"((?:[^"\\]|\\.)*)"', block)
    return {"format": fmt.group(1) if fmt else ""}


def glyphs(fmt):
    """Render one Nerd Font codepoint as a box of roughly the right width.

    A browser without a Nerd Font renders these as nothing at all, which hides
    the width they occupy and makes the bar look tighter than it is.
    """
    return "".join(
        f'<span class="g">&#x{ord(ch):x};</span>' if ord(ch) > 0x2500 else ch
        for ch in fmt
    )


def render(fmt, values, unnamed=None):
    """Expand a waybar format string the way waybar would.

    The placeholders are replaced by their sample values and the literal text
    around them is kept exactly once. Appending the value to the stripped
    format instead would double any literal suffix, so "{icon} {volume}%"
    came out as "%62%".

    `unnamed` is the value for a bare {}: waybar substitutes whatever the
    module's exec command printed, and custom-brightness uses exactly that.
    """
    out = []
    for part in re.split(r"(\{[^}]*\})", fmt):
        # A waybar placeholder is {name} or, for the clock, {:strftime}. The
        # colon is not a word character, so match the inner text loosely and
        # dispatch on its first character.
        match = re.fullmatch(r"\{(.*?)\}", part)
        if not match:
            out.append(glyphs(part))
            continue
        key = match.group(1)
        if key.startswith(":"):
            out.append(escape_html(time.strftime(key[1:])))
        elif key == "icon":
            # {icon} expands to the module's icon, set separately via
            # format-icons. All of those live in the private use area, so any
            # of them renders as a box of the right width.
            out.append('<span class="g">&#xe000;</span>')
        elif key == "":
            out.append(escape_html(unnamed if unnamed is not None else "?"))
        else:
            out.append(escape_html(values.get(key, "?")))
    return "".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("output", nargs="?", default="waybar-preview.png")
    ap.add_argument("--modules", default=DEFAULT_WORKSPACES)
    ap.add_argument("--active", default=DEFAULT_ACTIVE)
    ap.add_argument("--width", type=int, default=1920)
    args = ap.parse_args()

    cfg = read_config()
    colors = read_colors()
    height = int(cfg["height"])
    width = args.width

    ws_nums = args.modules.split()
    active = args.active

    launcher = render(read_module("launcher").get("format", ""), SAMPLE)
    marquee = escape_html(SAMPLE["marquee"])
    clock = render(read_module("clock").get("format", ""), SAMPLE)
    network = render(read_module("network").get("format-wifi", ""), SAMPLE)
    notifs = '<span class="g">&#xf029;</span>2'
    vol = render(read_module("pulseaudio").get("format", ""), SAMPLE)
    bluetooth = '<span class="g">&#xf08b;</span>'

    # The bar has no background of its own, so the preview needs the wallpaper
    # behind it. Without it the text shadows and the contrast over a photo
    # cannot be judged at all, which is the whole point of a transparent bar.
    wallpaper_b64 = ""
    wallpaper_path = ROOT / "wallpapers" / "totoro.png"
    if wallpaper_path.exists():
        import base64
        wallpaper_b64 = base64.b64encode(wallpaper_path.read_bytes()).decode()

    # Padding comes from the stylesheet.
    pad = 9
    pad_launcher_l = 12
    pad_clock_r = 10
    ws_gap = 7   # #workspaces button padding

    html = f"""<!DOCTYPE html>
<html><head><meta charset="utf-8"><style>
  @font-face {{ font-family: NerdMono; src: local("JetBrainsMono Nerd Font"),
                local("JetBrainsMono Nerd"), local("DejaVu Sans Mono"); }}
  * {{ box-sizing: border-box; }}
  body {{ margin: 0; background: {colors['dark_background']};
         font-family: NerdMono, "DejaVu Sans Mono", monospace;
         font-size: 12px; -webkit-font-smoothing: antialiased; }}
  /* A glyph the browser has no font for would silently collapse to nothing and
     make every module look tighter than it is. Draw a box instead, at roughly
     the width of the real icon, so the spacing can be judged. */
  .g {{ display: inline-block; min-width: 11px; text-align: center;
        color: {colors['muted']}; }}
  /* Three passes, matching the stylesheet: a tight one for the glyph edge and
     a wider one to carry the shape. One pass alone leaves the thin strokes of
     the network and bluetooth icons unreadable over a light sky. */
  .bar, .bar * {{
    text-shadow: 0 0 2px {colors['darker_background']},
                 0 0 4px {colors['darker_background']},
                 0 0 6px {colors['darker_background']};
  }}
  .desk {{ padding: 40px 0 0; background: {colors['dark_background']};
           background-image: url(data:image/png;base64,{wallpaper_b64});
           background-size: {width}px auto; background-position: top center;
           background-repeat: no-repeat; }}
  /* No background-color: the real bar has none either, which is why every glyph
     carries a text shadow. */
  .bar {{ height: {height}px; width: {width}px; background: transparent;
          color: {colors['foreground']}; display: flex; align-items: center;
          font-size: 12px; }}
  .left, .right {{ display: flex; align-items: center; height: {height}px; }}
  .left {{ padding-left: {pad_launcher_l}px; }}
  .right {{ padding-right: {pad_clock_r}px; margin-left: auto; }}
  .center {{ flex: 1; text-align: center; color: {colors['light_foreground']};
             overflow: hidden; white-space: nowrap; padding: 0 16px; }}
  .m {{ padding: 0 {pad}px; display: flex; align-items: center; gap: 6px;
        white-space: nowrap; }}
  #launcher {{ color: {colors['bright_foreground']}; font-size: 14px;
               padding-left: 12px; padding-right: 10px; }}
  #workspaces {{ padding-left: 4px; padding-right: 10px; display: flex; }}
  .ws {{ padding: 0 7px; text-align: center; color: {colors['bright_foreground']};
         height: {height}px; display: flex; align-items: center;
         justify-content: center; }}
  .ws.on {{ color: {colors['accent']}; font-weight: bold;
            text-decoration: underline; text-underline-offset: 2px; }}
  #custom-marquee {{ color: {colors['bright_foreground']}; padding-left: 6px; }}
  #tray, #network, #custom-notifications, #pulseaudio, #bluetooth {{
    font-size: 14px; color: {colors['bright_foreground']}; }}
  #clock {{ color: {colors['bright_foreground']}; font-weight: bold; }}
  .traydots {{ letter-spacing: 2px; opacity: .75; font-size: 11px; }}
  /* The caption is the preview's own annotation, not part of the bar. It sits
     over the wallpaper too, so it gets an opaque strip of its own rather than
     relying on the bar's shadow, which is sized for 12px glyphs. */
  .caption {{ color: {colors['light_foreground']}; font-size: 11px;
              background: {colors['darker_background']};
              padding: 12px 40px 16px; line-height: 1.6; }}
  .caption b {{ color: {colors['muted']}; font-weight: normal; }}
  code {{ color: {colors['accent']}; }}
  .nofont {{ color: {colors['yellow']}; }}
</style></head><body>
<div class="desk">
  <div class="bar">
    <div class="left">
      <div class="m" id="launcher">{launcher}</div>
      <div id="workspaces">{''.join(
        f'<div class="ws{" on" if n == active else ""}">{n}</div>' for n in ws_nums)}</div>
      <div class="m" id="custom-marquee">{marquee}</div>
    </div>
    <div class="center">{clock}</div>
    <div class="right">
      <div class="m" id="network">{network}</div>
      <div class="m" id="custom-notifications">{notifs}</div>
      <div class="m" id="pulseaudio">{vol}</div>
      <div class="m" id="bluetooth">{bluetooth}</div>
      <div class="m" id="tray"><span class="traydots">{'&#9679;' * 3}</span></div>
    </div>
  </div>
  <div class="caption">
    <b>waybar/config.jsonc + generated/waybar.css</b> &mdash; {width}&times;{height},
    {len(ws_nums)} workspaces, workspace {active} active.<br>
    left <code>launcher, workspaces, custom-marquee</code>
    &middot; centre <code>clock</code>
    &middot; right <code>network, custom-notifications, pulseaudio, bluetooth, tray</code><br>
    No background of its own: the strip sits on the wallpaper, which is why the
    text carries a shadow. Marquee, volume and signal are sample values; the
    clock is live.<br>
    <span class="nofont">Boxes</span> are Nerd Font glyphs this browser has no font
    for; they are drawn at the icon's width so the spacing is real, but Waybar
    will draw the actual icons.
  </div>
</div>
</body></html>"""

    html_path = pathlib.Path(args.output).with_suffix(".html")
    html_path.write_text(html)

    # Render via a headless browser if one is available, else leave the HTML.
    for browser in ("chromium", "chromium-browser", "google-chrome", "google-chrome-stable"):
        path = shutil.which(browser)
        if not path:
            continue
        png = subprocess.run(
            [path, "--headless", "--disable-gpu", "--no-sandbox",
             f"--screenshot={args.output}", f"--window-size={width},{height + 300}",
             "--hide-scrollbars", html_path.as_uri()],
            capture_output=True)
        if png.returncode == 0 and pathlib.Path(args.output).exists():
            print(f"wrote {args.output} and {html_path}")
            return
        print(f"{browser} failed: {png.stderr.decode()[:200]}", file=sys.stderr)
        break

    print(f"no headless browser available; wrote {html_path}")
    print("open it in a browser to see the preview")


if __name__ == "__main__":
    main()
