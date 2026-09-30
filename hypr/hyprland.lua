-- archy: my Hyprland desktop.
--
-- Hyprland 0.56's native Lua config. A Waybar top bar, Wofi for launching, and
-- colors/colors.conf as the single source of truth for the theme.
--
-- Layout of this directory:
--   hyprland.lua    this file: module path and load order
--   helpers.lua     the o.* layer over Hyprland's hl.* API
--   theme.lua       reads colors/colors.conf
--   monitors.lua    output and scale
--   input.lua       keyboard, mouse, touchpad
--   looknfeel.lua   gaps, decoration, blur, animation
--   windows.lua     window rules and tags
--   apps.lua        app classes shared across files
--   tiling.lua      core Hyprland bindings
--   bindings.lua    my bindings
--   floatcascade.lua  new-window cascade and SUPER+T
--   qconsole.lua    the Quake console
--   screencopy.lua  capture permissions
--   autostart.lua   everything started at session start

local home = os.getenv("HOME") or "/home/agx"

-- module path so require("hypr.looknfeel") resolves. Loaded before the helper
-- layer, because every config file below assumes o.* exists.
package.path = home
  .. "/.config/archy/?.lua;"
  .. home
  .. "/.config/archy/?/init.lua;"
  .. package.path

-- Drop our own modules from the cache so a reload picks up edits instead of
-- replaying the previous run's state.
for module in pairs(package.loaded) do
  if module:sub(1, 4) == "hypr." then
    package.loaded[module] = nil
  end
end

require("hypr.helpers")

-- Environment and compositor defaults, before anything reads them.
require("hypr.envs")

-- Theme first: later files read colors from it.
require("hypr.theme")

-- App classes, shared so a window rule and a layout rule cannot disagree.
require("hypr.apps")

require("hypr.monitors")
require("hypr.input")
require("hypr.looknfeel")
require("hypr.windows")

-- Bindings after the window rules, so a bind can unbind a key a rule or an
-- earlier bind already claimed.
require("hypr.tiling")
require("hypr.bindings")

-- Cursor, after the bindings that read it (SUPER+CTRL+Z zoom).
require("hypr.cursor")

-- Loaded last of the interactive pieces: the cascade owns the new-window hook
-- and the console owns the specialWorkspaceIn/Out animations, both of which
-- have to win over looknfeel.
require("hypr.floatcascade")
require("hypr.qconsole")

require("hypr.screencopy")
require("hypr.autostart")

-- Layout and misc defaults that the compositor needs set regardless of theme.
-- Split out so the values are visible in one place rather than scattered
-- through looknfeel.
hl.config({
  dwindle = {
    preserve_split = true,
    force_split = 2,
  },

  scrolling = {
    column_width = 0.49,
  },

  master = {
    new_status = "master",
  },

  misc = {
    disable_hyprland_logo = true,
    disable_splash_rendering = true,
    disable_scale_notification = true,
    focus_on_activate = true,
    anr_missed_pings = 3,
    on_focus_under_fullscreen = 1,
    initial_workspace_tracking = 0,
    allow_session_lock_restore = true,
    force_default_wallpaper = 0,
  },

  cursor = {
    hide_on_key_press = true,
    warp_on_change_workspace = 1,
  },

  binds = {
    hide_special_on_workspace_change = true,
  },
})
