-- Center-float plus cascade for new windows, and the workspace-wide SUPER+T
-- toggle.
--
-- First window per workspace: 1680x945 centered. Each extra window on the same
-- workspace: same size, offset +(STEP * index) down-right, wrapping. Special
-- workspaces (scratchpad, qconsole), fullscreen windows, pinned windows and
-- dialog-tagged windows are left alone.

local M = {}

M.W = 1680
M.H = 945
M.STEP = 20
M.WRAP = 8 -- max cascade steps before wrapping (8 * 20 = 160px)
M.DEFER_MS = 60 -- let the window map before sizing

-- Classes the cascade must never touch. Empty on purpose: btop used to be here
-- while looknfeel tiled it, but it cascades with everything else now.
--
-- zen is deliberately NOT here. It owns static float/size/center rules below
-- (one configure on first commit, no frosted flash), and listing it here would
-- also hide it from SUPER+T, since is_skipped() feeds the toggle path too. The
-- auto-float hook skips zen explicitly.
M.SKIP_CLASSES = {}

-- Static float for Zen: applied by Hyprland on first commit so there is no
-- tiled-to-float resize race on a cold Gecko first paint.
o.window("zen", { float = true })
o.window("zen", { center = true })
o.window("zen", { size = { M.W, M.H } })

local function base_tag(tag)
  return (tag or ""):gsub("%*$", "")
end

-- Hyprland's window and workspace handles are userdata, not tables, so field
-- access must not be guarded with type(x) == "table". Wrap it in pcall.
local function field(obj, key)
  if obj == nil then
    return nil
  end
  local ok, value = pcall(function()
    return obj[key]
  end)
  if not ok then
    return nil
  end
  return value
end

local function has_tag(win, name)
  for _, tag in ipairs(win.tags or {}) do
    if base_tag(tag) == name then
      return true
    end
  end
  return false
end

local function workspace_name(win)
  local name = field(field(win, "workspace"), "name")
  return type(name) == "string" and name or ""
end

function M.is_special(win)
  local name = workspace_name(win)
  if name:find("^special:") then
    return true
  end
  local id = field(field(win, "workspace"), "id")
  return type(id) == "number" and id < 0
end

-- Windows the cascade must never touch. allow_special lifts only the
-- special-workspace exclusion and is used solely by the scratchpad toggle
-- path; the auto-float hook always passes false.
function M.is_skipped(win, allow_special)
  if not win or not field(win, "address") then
    return true
  end
  if field(win, "pinned") then
    return true
  end
  local fs = field(win, "fullscreen")
  if type(fs) == "number" and fs ~= 0 then
    return true
  end
  if fs == true then
    return true
  end
  if not allow_special and M.is_special(win) then
    return true
  end
  -- Dialog-tagged windows keep their own size (file pickers, portals,
  -- viewers). Exception: terminal-tagged windows are the daily driver and
  -- cascade like any main window.
  if has_tag(win, "floating-window") and not has_tag(win, "terminal") then
    return true
  end
  if has_tag(win, "pop") then
    return true
  end
  for _, class in ipairs(M.SKIP_CLASSES) do
    if win.class == class then
      return true
    end
  end
  -- XWayland drag ghosts.
  if win.xwayland and (win.class or "") == "" then
    return true
  end
  return false
end

function M.normal_windows_on(ws_id)
  local out = {}
  local ok, wins = pcall(hl.get_workspace_windows, ws_id)
  if not ok or type(wins) ~= "table" then
    return out
  end
  for _, w in ipairs(wins) do
    if not M.is_skipped(w) then
      table.insert(out, w)
    end
  end
  return out
end

local function addr_of(win)
  return "address:" .. win.address
end

function M.apply_cascade(win, index)
  local addr = addr_of(win)
  local step = (index % M.WRAP) * M.STEP
  hl.dispatch(hl.dsp.window.float({ window = addr, action = "on" }))
  hl.dispatch(hl.dsp.window.resize({ window = addr, x = M.W, y = M.H }))
  hl.dispatch(hl.dsp.window.center({ window = addr }))
  if step > 0 then
    hl.dispatch(hl.dsp.window.move({ window = addr, x = step, y = step, relative = true }))
  end
  hl.dispatch(hl.dsp.window.alter_zorder({ window = addr, mode = "top" }))
end

function M.tile(win)
  hl.dispatch(hl.dsp.window.float({ window = addr_of(win), action = "off" }))
end

local function by_age(a, b)
  return (field(a, "focusHistoryID") or 0) < (field(b, "focusHistoryID") or 0)
end

-- Pick the toggle target: the open scratchpad if it holds eligible windows,
-- else the active regular workspace. The Quake console never qualifies.
local function toggle_target()
  local ok, spec = pcall(hl.get_active_special_workspace)
  if ok and spec and field(spec, "name") == "special:scratchpad" then
    local spec_id = field(spec, "id")
    local ok2, all = pcall(hl.get_workspace_windows, spec_id)
    if ok2 and type(all) == "table" then
      local wins = {}
      for _, w in ipairs(all) do
        if field(field(w, "workspace"), "id") == spec_id and not M.is_skipped(w, true) then
          table.insert(wins, w)
        end
      end
      if #wins > 0 then
        return wins, true
      end
    end
  end
  local ws = hl.get_active_workspace()
  local ws_id = field(ws, "id")
  if ws_id == nil then
    return {}, false
  end
  return M.normal_windows_on(ws_id), false
end

-- Workspace-wide toggle: any tiled window means "go floating", and everything
-- floats cascaded instead.
function M.toggle_workspace()
  local wins, special = toggle_target()
  if #wins == 0 then
    return
  end
  table.sort(wins, by_age)

  local any_tiled = false
  for _, w in ipairs(wins) do
    if not w.floating then
      any_tiled = true
      break
    end
  end

  if any_tiled then
    for i, w in ipairs(wins) do
      local fresh = hl.get_window(addr_of(w))
      if fresh and not M.is_skipped(fresh, special) then
        M.apply_cascade(fresh, i - 1)
      end
    end
  else
    for _, w in ipairs(wins) do
      local fresh = hl.get_window(addr_of(w))
      if fresh and not M.is_skipped(fresh) then
        M.tile(fresh)
      end
    end
  end
end

-- Center-float every new window, with a cascade offset by sibling count.
hl.on("window.open", function(win)
  local addr = field(win, "address")
  local ws_id = field(field(win, "workspace"), "id")

  -- zen skips only this hook. A cold Gecko first paint is slow, and a deferred
  -- float plus resize plus center would force a second configure cycle, which
  -- shows as a blurry translucent flash under 0.93 frost with ignore_opacity
  -- blur. zen already floats at cascade size from the static rules above.
  if win and win.class == "zen" then
    return
  end
  if M.is_skipped(win) then
    return
  end
  if ws_id == nil or addr == nil then
    return
  end

  -- Count siblings, excluding the new window itself.
  local index = 0
  for _, w in ipairs(M.normal_windows_on(ws_id)) do
    if field(w, "address") ~= addr then
      index = index + 1
    end
  end

  hl.timer(function()
    local fresh = hl.get_window("address:" .. addr)
    if not fresh or M.is_skipped(fresh) then
      return
    end
    M.apply_cascade(fresh, index)
  end, { timeout = M.DEFER_MS, type = "oneshot" })
end)

return M
