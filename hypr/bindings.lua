-- Personal keybinds: the ones that actually differ from stock Hyprland.
--
-- Workspace tiling and window movement live in tiling.lua. This file is the
-- daily driver — apps, clipboard, capture, media keys, the launcher.
--
-- Inspect what is live: hyprctl binds

-- App launcher. Wofi drun over the desktop entries.
o.bind("SUPER + SPACE", "App launcher", o.script("launcher"))
o.bind("SUPER + ALT + SPACE", "Window switcher", o.script("window-switcher"))

-- Terminal. Kitty, running bash. The class is kitty's own, so windows.lua tags
-- the window "terminal" and the universal clipboard chords switch to
-- CTRL+Insert inside it rather than sending CTRL+C, which is SIGINT.
o.bind("SUPER + RETURN", "Terminal", o.launch("kitty"))

-- Power and lock.
o.bind("SUPER + CTRL + L", "Lock system", o.script("lock"))
o.bind("SUPER + ESCAPE", "Power menu", o.script("power-menu"), { locked = true })
o.bind("XF86PowerOff", "Power menu", o.script("power-menu"), { locked = true })

-- Lid and internal display, for a laptop panel. Harmless on a desktop.
o.bind("switch:on:Lid Switch", nil, "loginctl lock-session", { locked = true })
o.bind("switch:off:Lid Switch", nil, o.script("monitor-clamshell"), { locked = true })
o.bind("SUPER + CTRL + DELETE", "Toggle laptop display", o.script("monitor-internal") .. " toggle")

-- ---------------------------------------------------------------- apps

-- My app bindings.
o.bind("SUPER + B", "Browser", { launch = "zen-browser" })
o.bind("SUPER + SHIFT + B", "Browser (private)", { launch = "zen-browser --private" })
o.bind("SUPER + D", "Drawy", { launch = "drawy" })
-- Emoji picker. Searches by unicode name and types the selection with wtype.
o.bind("SUPER + PERIOD", "Emoji picker", o.script("emoji"))
o.bind("SUPER + SLASH", "Visual Studio Code", { launch = "code" })
o.bind("SUPER + E", "File manager", { launch = "nautilus" })

-- TUIs and agent sessions, opened in kitty. focus = true would reuse an
-- existing window; these are meant to open their own.
o.bind("SUPER + M", "Cliamp", { tui = "cliamp" })
o.bind("SUPER + A", "opencode", { tui = "opencode" })
o.bind("SUPER + P", "btop", { tui = "btop" })

-- Web apps in the browser.
o.bind("SUPER + SHIFT + A", "ChatGPT", { web = "https://chatgpt.com" })
o.bind("SUPER + SHIFT + G", "Gmail", { web = "https://gmail.com" })
o.bind("SUPER + SHIFT + SLASH", "Github", { web = "https://github.com/ax1g" })
o.bind("SUPER + SHIFT + M", "MonkeyType", "zen-browser --new-window https://monkeytype.com", { action = "float" })
o.bind("SUPER + SHIFT + W", "Word", "zen-browser --new-window https://word.cloud.microsoft")
o.bind("SUPER + SHIFT + E", "Excel", "zen-browser --new-window https://excel.cloud.microsoft")

-- ---------------------------------------------------------------- clipboard

-- Universal copy/paste/cut. Sends the chord to whatever is focused, except in
-- a terminal, where CTRL+C means SIGINT and INSERT is the copy key.
--
-- A virtual keyboard (wtype) will not do: the physically held SUPER merges
-- into the injected chord at the seat. The down/up split works around
-- send_key_state sometimes leaving synthetic key state stuck.
local function send_shortcut_once(mods, key)
  return function()
    hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "down" }))
    hl.timer(function()
      hl.dispatch(hl.dsp.send_key_state({ mods = mods, key = key, state = "up" }))
    end, { timeout = 50, type = "oneshot" })
  end
end

-- Lean on the terminal tag from windows.lua so there is one definition of what
-- counts as a terminal. Dynamic tags carry a trailing "*".
local function active_window_is_terminal()
  local window = hl.get_active_window()
  if not window then
    return false
  end
  for _, tag in ipairs(window.tags or {}) do
    if tag:gsub("%*$", "") == "terminal" then
      return true
    end
  end
  return false
end

local function universal_clipboard_shortcut(default_mods, default_key, terminal_mods, terminal_key)
  return function()
    if active_window_is_terminal() then
      send_shortcut_once(terminal_mods, terminal_key)()
    else
      send_shortcut_once(default_mods, default_key)()
    end
  end
end

local universal_copy = universal_clipboard_shortcut("CTRL", "C", "CTRL", "Insert")
local universal_paste = universal_clipboard_shortcut("CTRL", "V", "SHIFT", "Insert")

hl.unbind("SUPER + C")
hl.unbind("SUPER + V")
hl.unbind("SUPER + X")
hl.unbind("SUPER + SHIFT + C")
hl.unbind("SUPER + SHIFT + X")
hl.unbind("SUPER + CTRL + V")

o.bind("SUPER + C", "Universal copy", universal_copy)
o.bind("SUPER + SHIFT + C", "Universal copy", universal_copy)
o.bind("SUPER + V", "Universal paste", universal_paste)
o.bind("SUPER + X", "Universal cut", send_shortcut_once("CTRL", "X"))
o.bind("SUPER + SHIFT + X", "Universal cut", send_shortcut_once("CTRL", "X"))

-- Clipboard history in wofi. cliphist has to be running (autostart.lua).
o.bind("SUPER + CTRL + V", "Clipboard history", o.script("clipboard-history"))

-- ---------------------------------------------------------------- capture

o.bind("PRINT", "Screenshot", o.script("screenshot") .. " fullscreen")
o.bind("SUPER + SHIFT + S", "Screenshot region", o.script("screenshot") .. " region")
o.bind("SUPER + PRINT", "Color picker", "pkill hyprpicker || hyprpicker -a")
o.bind("ALT + PRINT", "Screen recording", o.script("screenrecord") .. " toggle")

-- Keybindings for the slurp region picker. These live exactly as long as a
-- selection layer is on screen, so they cannot leak or get stuck, and they are
-- removed individually so unbinding by key cannot take a user binding with it.
local selection_layers = 0
local selection_binds = {}

hl.on("layer.opened", function(layer)
  if layer.namespace == "selection" then
    selection_layers = selection_layers + 1
    if selection_layers == 1 then
      local script = o.script("screenshot")
      selection_binds = {
        hl.bind("RETURN", hl.dsp.exec_cmd(script .. " region --window"), { description = "Capture highlighted window" }),
        hl.bind("CTRL + RETURN", hl.dsp.exec_cmd(script .. " region --screen"), { description = "Capture entire screen" }),
        hl.bind("TAB", hl.dsp.exec_cmd(script .. " region --cycle next"), { description = "Select next window to capture" }),
        hl.bind("CTRL + TAB", hl.dsp.exec_cmd(script .. " region --cycle prev"), { description = "Select previous window to capture" }),
      }
      for _, direction in ipairs({ "left", "right", "up", "down" }) do
        table.insert(
          selection_binds,
          hl.bind(direction:upper(), hl.dsp.exec_cmd(script .. " region --cycle " .. direction), { description = "Select window to capture" })
        )
      end
    end
  end
end)

hl.on("layer.closed", function(layer)
  if layer.namespace == "selection" and selection_layers > 0 then
    selection_layers = selection_layers - 1
    if selection_layers == 0 then
      for _, keybind in ipairs(selection_binds) do
        keybind:unbind()
      end
      selection_binds = {}
    end
  end
end)

-- ---------------------------------------------------------------- window behavior

-- Workspace-wide tile/float toggle. New windows auto-float centered via
-- floatcascade.lua (1680x945, +20px cascade); this tiles every normal window on
-- the workspace, or re-floats them all cascaded.
hl.unbind("SUPER + T")
o.bind("SUPER + T", "Toggle workspace tiling/floating", function()
  require("hypr.floatcascade").toggle_workspace()
end)

-- Scratchpad.
hl.unbind("SUPER + S")
o.bind("SUPER + S", "Toggle scratchpad", hl.dsp.workspace.toggle_special("scratchpad"))

-- Quake console on SUPER+`. Half-height dropdown, distinct from the
-- full-size scratchpad on SUPER+S. Workspace rules live in qconsole.lua.
o.bind("SUPER + GRAVE", "Toggle Quake console", hl.dsp.workspace.toggle_special("qconsole"))
o.bind("SUPER + SHIFT + GRAVE", "Move window to Quake console", hl.dsp.window.move({ workspace = "special:qconsole", follow = false }))

-- Nothing to unbind here, and that is deliberate. There are no default bindings
-- in this config, so an unbind can only ever remove something bound in this same
-- directory. If a key seems to do the wrong thing, it is bound twice — check
-- with `hyprctl binds` rather than looking for a missing unbind. The test suite
-- reports both cases.

-- ---------------------------------------------------------------- media keys

-- Volume and brightness. These shell out to archy-volume and archy-brightness,
-- which use pactl and hyprsunset directly.
hl.unbind("XF86AudioRaiseVolume")
o.bind("XF86AudioRaiseVolume", "Volume up", o.script("volume") .. " raise", { locked = true, repeating = true })
hl.unbind("XF86AudioLowerVolume")
o.bind("XF86AudioLowerVolume", "Volume down", o.script("volume") .. " lower", { locked = true, repeating = true })
hl.unbind("XF86AudioMute")
o.bind("XF86AudioMute", "Mute", o.script("volume") .. " mute-toggle", { locked = true })
hl.unbind("XF86AudioMicMute")
o.bind("XF86AudioMicMute", "Mute microphone", o.script("volume") .. " mic-mute-toggle", { locked = true })
hl.unbind("XF86AudioPlay")
hl.unbind("XF86AudioPause")
hl.unbind("XF86AudioNext")
hl.unbind("XF86AudioPrev")
o.bind("XF86AudioPlay", "Play/pause", o.script("media") .. " play-pause", { locked = true })
o.bind("XF86AudioPause", "Play/pause", o.script("media") .. " play-pause", { locked = true })
o.bind("XF86AudioNext", "Next track", o.script("media") .. " next", { locked = true })
o.bind("XF86AudioPrev", "Previous track", o.script("media") .. " previous", { locked = true })

-- Precise steps, one percent at a time.
hl.unbind("ALT + XF86AudioRaiseVolume")
o.bind("ALT + XF86AudioRaiseVolume", "Volume up precise", o.script("volume") .. " +1", { locked = true, repeating = true })
hl.unbind("ALT + XF86AudioLowerVolume")
o.bind("ALT + XF86AudioLowerVolume", "Volume down precise", o.script("volume") .. " -1", { locked = true, repeating = true })

-- Brightness. This monitor rejects DDC/CI writes, so brightness is applied as a
-- compositor-level gamma filter through hyprsunset rather than to the panel.
hl.unbind("XF86MonBrightnessUp")
o.bind("XF86MonBrightnessUp", "Brightness up", o.script("brightness") .. " +5%", { locked = true, repeating = true })
hl.unbind("XF86MonBrightnessDown")
o.bind("XF86MonBrightnessDown", "Brightness down", o.script("brightness") .. " 5%-", { locked = true, repeating = true })
hl.unbind("SHIFT + XF86MonBrightnessUp")
o.bind("SHIFT + XF86MonBrightnessUp", "Brightness maximum", o.script("brightness") .. " 100%", { locked = true, repeating = true })
hl.unbind("SHIFT + XF86MonBrightnessDown")
o.bind("SHIFT + XF86MonBrightnessDown", "Brightness minimum", o.script("brightness") .. " 15%", { locked = true, repeating = true })
hl.unbind("ALT + XF86MonBrightnessUp")
o.bind("ALT + XF86MonBrightnessUp", "Brightness up precise", o.script("brightness") .. " +1%", { locked = true, repeating = true })
hl.unbind("ALT + XF86MonBrightnessDown")
o.bind("ALT + XF86MonBrightnessDown", "Brightness down precise", o.script("brightness") .. " 1%-", { locked = true, repeating = true })

-- Manual gamma on function keys. F11/F12 also reach apps, so a fullscreen
-- browser never sees them.
o.bind("F11", "Brightness down", o.script("brightness") .. " 5%-", { repeating = true })
o.bind("F12", "Brightness up", o.script("brightness") .. " +5%", { repeating = true })

-- Nightlight, on the hyprsunset schedule.
hl.unbind("SUPER + CTRL + N")
o.bind("SUPER + CTRL + N", "Toggle nightlight", o.script("nightlight-toggle"), { locked = true })

-- ---------------------------------------------------------------- shell

o.bind("SUPER + K", "Keybindings", o.script("keybindings-menu"))

hl.unbind("SUPER + SHIFT + T")
o.bind("SUPER + SHIFT + T", "Theme", o.script("theme-menu"))

hl.unbind("SUPER + SHIFT + SPACE")
o.bind("SUPER + SHIFT + SPACE", "Toggle bar", o.script("toggle") .. " bar", { locked = true })

hl.unbind("SUPER + CTRL + SPACE")
o.bind("SUPER + CTRL + SPACE", "Wallpaper", o.script("wallpaper-menu"))

-- Cursor zoom.
hl.unbind("SUPER + CTRL + Z")
o.bind("SUPER + CTRL + Z", "Zoom in", function()
  local zoom = hl.get_config("cursor.zoom_factor") or 1
  hl.config({ cursor = { zoom_factor = zoom + 1 } })
end)
hl.unbind("SUPER + CTRL + ALT + Z")
o.bind("SUPER + CTRL + ALT + Z", "Reset zoom", function()
  hl.config({ cursor = { zoom_factor = 1 } })
end)

-- Toggles for gaps, transparency and single-window aspect, the three things
-- worth being able to A/B while tuning the look.
hl.unbind("SUPER + BACKSPACE")
o.bind("SUPER + BACKSPACE", "Toggle window transparency", o.script("toggle") .. " transparency")
hl.unbind("SUPER + SHIFT + BACKSPACE")
o.bind("SUPER + SHIFT + BACKSPACE", "Toggle window gaps", o.script("toggle") .. " gaps")
hl.unbind("SUPER + CTRL + BACKSPACE")
o.bind("SUPER + CTRL + BACKSPACE", "Toggle single-window square aspect", o.script("toggle") .. " single-square")
