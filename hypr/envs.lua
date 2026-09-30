-- Environment and compositor defaults.
--
-- These are not theme values, so they live here rather than in colors.conf.
-- They are the variables a Wayland desktop is expected to set, and getting
-- them wrong is what makes a browser quietly fall back to XWayland or a Qt app
-- pick the wrong platform theme.

local theme = require("hypr.theme")
local c = theme.colors

-- Cursor. The theme sets the name in looknfeel.lua; size is an env var because
-- Hyprcursor and XWayland apps read it separately.
hl.env("HYPRCURSOR_SIZE", "40")

-- Prefer native Wayland everywhere. The x11/xcb fallbacks stay last so an app
-- that genuinely cannot do Wayland still runs instead of refusing to start.
hl.env("GDK_BACKEND", "wayland,x11,*")
hl.env("QT_QPA_PLATFORM", "wayland;xcb")
hl.env("QT_QPA_PLATFORMTHEME", "gtk3")
hl.env("SDL_AUDIODRIVER", "pipewire")
hl.env("MOZ_ENABLE_WAYLAND", "1")
hl.env("ELECTRON_OZONE_PLATFORM_HINT", "auto")
hl.env("OZONE_PLATFORM_HINT", "auto")
hl.env("XDG_SESSION_TYPE", "wayland")
hl.env("XDG_CURRENT_DESKTOP", "Hyprland")
hl.env("XDG_SESSION_DESKTOP", "hyprland")

-- Login shell, for anything that asks. Must be a real shell on this machine or
-- it is a dead value that some tool will try to exec.
hl.env("XDG_SHELL", "/usr/bin/bash")

-- Compose key.
hl.env("XCOMPOSEFILE", (os.getenv("HOME") or "") .. "/.XCompose")

-- The compositor must not scale: the monitor config pins scale 1, and letting
-- XWayland pick its own factor here is what produces mismatched window sizes
-- between native and X11 apps.
hl.config({
  xwayland = {
    force_zero_scaling = true,
  },

  ecosystem = {
    no_update_news = true,
  },
})
