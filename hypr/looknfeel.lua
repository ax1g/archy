-- Look and feel: geometry, decoration, animation. This is the "pixel perfect"
-- part — everything here is a deliberate value, not a default.

local theme = require("hypr.theme")
local c = theme.colors

-- The cursor lives in cursor.lua, because the theme name and size have to be
-- set in two places to actually take effect.

-- Bolder small glyphs on low-DPI 1080p. Left disabled: fonts read too heavy
-- with stem darkening off on this panel. Uncomment to try it again.
-- hl.env("FREETYPE_PROPERTIES", "cff:no-stem-darkening=0 autofitter:no-stem-darkening=0")

-- https://wiki.hypr.land/Configuring/Basics/Variables/#general
hl.config({
  general = {
    gaps_in = 4,
    gaps_out = 8,
    border_size = 0,

    -- niri-like side-scrolling layout:
    -- layout = "scrolling",
  },
})

-- https://wiki.hypr.land/Configuring/Basics/Variables/#decoration
hl.config({
  decoration = {
    rounding = 8,

    -- Fully bright. Frost comes from opacity plus blur, not from dimming.
    active_opacity = 1.0,
    inactive_opacity = 1.0,
    fullscreen_opacity = 1.0,

    dim_inactive = false,
    dim_strength = 0.0,

    shadow = {
      enabled = true,
      range = 6,
      render_power = 3,
      color = c.darker_background .. "ee",
    },

    -- Heavy frosted blur: bright and readable behind translucent areas.
    blur = {
      enabled = true,
      size = 9,
      passes = 3,
      brightness = 1.1,
      contrast = 1.0,
      vibrancy = 0.3,
      vibrancy_darkness = 0.2,
      noise = 0.01,
      new_optimizations = true,
      ignore_opacity = true,
      xray = false,
      special = true,
      popups = true,
    },
  },
})

-- Frosted look for all windows: slight transparency so blur shows through.
-- Kept high (0.93 / 0.90) so text stays readable. Fullscreen stays solid.
o.window({ tag = "default-opacity" }, { opacity = "0.93 override 0.90 override 1.0 override" })

-- Browsers opt out of default-opacity in windows.lua, so frost them
-- explicitly rather than inheriting a rule that no longer applies to them.
o.window({ tag = "firefox-based-browser" }, { opacity = "0.93 override 0.90 override 1.0 override" })
o.window({ tag = "chromium-based-browser" }, { opacity = "0.93 override 0.90 override 1.0 override" })
o.window("zen", { opacity = "0.93 override 0.90 override 1.0 override" })

-- https://wiki.hypr.land/Configuring/Basics/Variables/#animations
hl.config({ animations = { enabled = true } })

-- Fluid, decelerating curves (smooth out, no abrupt stop).
hl.curve("fluid", { type = "bezier", points = { { 0.16, 1 }, { 0.3, 1 } } })
hl.curve("fluidSnappy", { type = "bezier", points = { { 0.21, 0.9 }, { 0.35, 1 } } })
hl.curve("fluidOvershoot", { type = "bezier", points = { { 0.05, 0.9 }, { 0.1, 1.05 } } })
hl.curve("smoothFade", { type = "bezier", points = { { 0.33, 1 }, { 0.68, 1 } } })

-- Global baseline.
hl.animation({ leaf = "global", enabled = true, speed = 8, bezier = "fluid" })

-- Windows: center zoom both ways, mirrored. Open scales 15% -> 100% with a
-- slight overshoot settle; close dives 100% -> 15%. Exact opposite depths.
-- Move stays a clean slide so dragging and resizing never scale.
hl.animation({ leaf = "windows", enabled = true, speed = 4.5, bezier = "fluid", style = "popin 15%" })
hl.animation({ leaf = "windowsIn", enabled = true, speed = 4.2, bezier = "fluidOvershoot", style = "popin 15%" })
hl.animation({ leaf = "windowsOut", enabled = true, speed = 5, bezier = "fluid", style = "popin 15%" })
hl.animation({ leaf = "windowsMove", enabled = true, speed = 4.5, bezier = "fluid", style = "slide" })

-- No per-window mirrors: a window rule covers open AND close together, so
-- mirrors would force close back to the subtle 85%. Every window follows the
-- globals above instead: open 15%, close 15%, mirrored.

-- Capture flows stay instant. The region picker must not slide or pop, both
-- so it feels immediate and so the recorder never films its own overlay
-- animating in. These come after the float popin rule above so they win.
hl.layer_rule({ match = { namespace = "selection" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { namespace = "hyprpicker" }, no_anim = true, animation = "none" })
o.window("dev.tensaku.Tensaku", { animation = "none" })
o.window({ title = "^WebcamOverlay$" }, { animation = "none" })
o.window({ class = "^WebcamOverlay-" }, { animation = "none" })

-- Borders and fades. Close-fades run at the SAME speed as windowsOut (5), so
-- a close plays popin scale and opacity fade together and the scale stays
-- visible instead of a faster fade swallowing it. Open-side fades stay snappy.
hl.animation({ leaf = "border", enabled = true, speed = 8, bezier = "fluid" })
hl.animation({ leaf = "fade", enabled = true, speed = 10, bezier = "fluid" })
hl.animation({ leaf = "fadeIn", enabled = true, speed = 10, bezier = "fluid" })
hl.animation({ leaf = "fadeOut", enabled = true, speed = 5, bezier = "fluid" })
hl.animation({ leaf = "fadeSwitch", enabled = false })
hl.animation({ leaf = "fadeShadow", enabled = true, speed = 5, bezier = "fluid" })
hl.animation({ leaf = "fadeDim", enabled = true, speed = 10, bezier = "fluid" })

-- Workspaces: pure `slide` so the old workspace exits fully with the new one.
-- slidefade leaves the old one fading underneath, which reads as a
-- millisecond ghost of the previous workspace.
hl.animation({ leaf = "workspaces", enabled = true, speed = 5, bezier = "fluid", style = "slide" })
hl.animation({ leaf = "workspacesIn", enabled = true, speed = 5, bezier = "fluid", style = "slide" })
hl.animation({ leaf = "workspacesOut", enabled = true, speed = 5, bezier = "fluid", style = "slide" })
hl.animation({ leaf = "specialWorkspace", enabled = true, speed = 5, bezier = "fluid", style = "slidevert" })
-- Note: specialWorkspaceIn/Out are owned by qconsole.lua (the Quake console
-- drops from the top and retracts upward), which loads after this file, so
-- those two intentionally win.

-- Layers: bare `slide` is dynamic, like windows. Hyprland slides each layer
-- from its nearest screen edge, so the top bar drops from the top, the bottom
-- OSD rises from the bottom, side panels come from their own side. In and out
-- are symmetric so closing reverses opening instead of just vanishing.
hl.animation({ leaf = "layers", enabled = true, speed = 4, bezier = "fluid", style = "slide fade" })
hl.animation({ leaf = "layersIn", enabled = true, speed = 3.5, bezier = "fluid", style = "slide fade" })
hl.animation({ leaf = "layersOut", enabled = true, speed = 4, bezier = "fluid", style = "slide fade" })
hl.animation({ leaf = "fadeLayersIn", enabled = true, speed = 10, bezier = "fluid" })
hl.animation({ leaf = "fadeLayersOut", enabled = true, speed = 10, bezier = "fluid" })

-- The bar itself must not animate. A layer fade composites the bar's own
-- translucent background through Hyprland's fade, which flashes dark for a
-- frame on every workspace change.
hl.layer_rule({ match = { namespace = "^waybar$" }, no_anim = true, animation = "none" })
-- Wofi and the notification daemon draw full-height surfaces; fading those
-- composites an uncommitted black buffer and flashes the same way.
hl.layer_rule({ match = { namespace = "^(wofi|mako)$" }, no_anim = true, animation = "none" })
hl.layer_rule({ match = { class = "^(wofi|mako)$" }, no_anim = true, animation = "none" })

-- Animate manual resizes and window dragging.
hl.config({
  misc = {
    animate_manual_resizes = true,
    animate_mouse_windowdragging = true,
  },
})

-- Layout tuning.
-- hl.config({
--   layout = {
--     single_window_aspect_ratio = { 1, 1 },
--   },
-- })
-- hl.config({
--   scrolling = {
--     column_width = 0.97,
--   },
-- })
