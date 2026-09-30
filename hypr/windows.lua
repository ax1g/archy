-- Window rules: which windows float, which get tags, and the compositor
-- defaults that decide how windows behave at all.

local apps = require("hypr.apps")

-- Ignore client maximize requests; the compositor owns the state.
o.window(".*", { suppress_event = "maximize" })

-- Tag everything for the frost treatment. Individual apps opt out below.
o.window(".*", { tag = "+default-opacity" })

-- Untagged XWayland windows are almost always drag ghosts or unmapped
-- leftovers. Float and unfocus them so they never steal a keystroke.
o.window(
  {
    class = "^$",
    title = "^$",
    xwayland = true,
    float = true,
    fullscreen = false,
    pin = false,
  },
  { no_focus = true }
)

-- Terminals are tagged so clipboard chords and the cascade can recognize them
-- without hardcoding class names in two places. The class list is in apps.lua.
o.window(apps.TERMINAL_CLASS, { tag = "+terminal" })

-- Browsers. Firefox-family windows drop the frost tag because a frosted page
-- body over a blurred desktop makes text edges muddy; the looknfeel file
-- re-applies a gentler opacity explicitly.
o.window("((google-)?[cC]hrom(e|ium)|[bB]rave-browser|[mM]icrosoft-edge|Vivaldi-stable|helium)", { tag = "+chromium-based-browser" })
o.window("([fF]irefox|zen|librewolf)", { tag = "+firefox-based-browser" })
o.window({ tag = "chromium-based-browser" }, { tag = "-default-opacity", tile = true, opacity = "1.0 0.985" })
o.window({ tag = "firefox-based-browser" }, { tag = "-default-opacity", opacity = "1.0 0.985" })

-- Video and conferencing windows that are not really browsing.
o.window("(^.+-youtube\\.com__.*$|^.+-app\\.zoom\\.us__wc_home.*$)", { tag = "-chromium-based-browser" })
o.window("(^.+-youtube\\.com__.*$|^.+-app\\.zoom\\.us__wc_home.*$)", { tag = "-default-opacity" })
o.window("qemu", { tag = "-default-opacity", opacity = "1 1" })
o.window("steam.*", { tag = "-default-opacity", opacity = "1 1" })

-- Floating windows: dialogs, pickers, small tools. Centered at one size.
o.window({ tag = "floating-window" }, { float = true })
o.window({ tag = "floating-window" }, { center = true })
o.window({ tag = "floating-window" }, { size = { 875, 600 } })

o.window(
  "(org\\.gnome\\.NautilusPreviewer|org\\.gnome\\.Evince|imv|mpv|omacalc|dev\\.tensaku\\.Tensaku)",
  { tag = "+floating-window" }
)

-- btop is the exception: it gets +floating-window so it is exempt from the
-- cascade's skip list, then loses it again so nothing resizes it to 875x600.
-- It therefore cascades with every other window at 1680x945.
o.window("btop", { tag = "+floating-window" })
o.window("btop", { tag = "-floating-window" })

-- Portals only ever show dialogs: file pickers, screen shares, permission
-- prompts. Whatever asked for the portal, the answer floats.
o.window("xdg-desktop-portal-gtk", { tag = "+floating-window" })
o.window({
  class = "(sublime_text|DesktopEditors|org.gnome.Nautilus)",
  title = "^(Open.*Files?|Open [F|f]older.*|Save.*Files?|Save.*As|Save|All Files|.*wants to [open|save].*|[C|c]hoose.*)",
}, { tag = "+floating-window" })

-- Popped windows keep the same rounding as everything else, so a pop never
-- looks like a different kind of window.
o.window({ tag = "pop" }, { rounding = 8 })

-- Never idle while one of these is open.
o.window({ tag = "noidle" }, { idle_inhibit = "always" })

-- Screen-share notification windows have no business on screen.
o.window({ title = ".*is sharing.*" }, { workspace = "special silent" })
