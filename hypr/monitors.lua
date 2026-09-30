-- Monitors.
-- Live output: hyprctl monitors all

local theme = require("hypr.theme")
local c = theme.colors

-- Scale is pinned at 1 on this 1080p panel. Logical pixels stay 1:1 with the
-- compositor's own gap and border math, so the 1680x945 cascade and the
-- half-screen Quake console both measure correctly.
local gdk_scale = 1
local monitor_scale = 1

hl.env("GDK_SCALE", tostring(gdk_scale))

-- Empty output = every connected monitor. Mode is pinned so the panel never
-- comes up at 60Hz after a hotplug.
hl.monitor({ output = "", mode = "1920x1080@144", position = "auto", scale = monitor_scale })

-- A specific monitor, if you ever need per-screen tuning:
-- hl.monitor({ output = "DP-2", mode = "2560x1440@144", position = "0x0", scale = 1 })

-- Portrait or rotated secondary:
-- hl.monitor({ output = "DP-2", mode = "preferred", position = "auto", scale = 1, transform = 1 })

-- The top bar sits in a reserved strip. Waybar reserves it via layer-shell, so
-- there is nothing to declare here; the value is only read back by qconsole.lua
-- when it measures usable height.
