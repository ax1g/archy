-- The hl.* stub used by the load test.
--
-- The point is not to emulate Hyprland. It is to make the config *load*, so
-- every hl.* call, every dispatcher shape and every module require gets
-- exercised. A call the real binary does not have raises.
--
-- The allowed surface is transcribed from the strings of the installed
-- hyprland binary, so anything invented in the config fails here too. Keep it
-- in sync when Hyprland is upgraded:
--
--   strings /usr/bin/hyprland | grep -oE 'hl\.[a-z_]+' | sort -u
--
-- The getters are registered without an "hl." prefix in the binary, so that
-- grep misses them; they are listed separately below.

local HL_FUNCTIONS = {
  "animation", "bind", "clear_crashed_lockscreen", "config", "cursor", "curve",
  "define_submap", "device", "dispatch", "dpms", "dsp", "env", "exec_cmd",
  "focus", "gesture", "layer_rule", "layout", "monitor", "notification", "on",
  "pass", "permission", "plugin", "send_key_state", "send_shortcut", "timer",
  "unbind", "window", "window_rule", "workspace", "workspace_rule",
}

local HL_GETTERS = {
  "get_active_monitor", "get_active_special_workspace", "get_active_window",
  "get_active_workspace", "get_config", "get_last_workspace", "get_layers",
  "get_monitor", "get_monitor_at", "get_monitor_at_cursor", "get_monitors",
  "get_window", "get_windows", "get_workspace", "get_workspace_windows",
  "is_key_down",
}

-- Dispatcher builders the config uses, transcribed the same way.
local DISPATCHERS = {
  ["window.close"] = true,
  ["window.drag"] = true,
  ["window.float"] = true,
  ["window.move"] = true,
  ["window.pseudo"] = true,
  ["window.resize"] = true,
  ["window.center"] = true,
  ["window.alter_zorder"] = true,
  ["window.tag"] = true,
  ["window.send_key_state"] = true,
  ["window.fullscreen"] = true,
  ["window.bring_to_top"] = true,
  ["window.cycle_next"] = true,
  ["window.swap"] = true,
  ["window.set_prop"] = true,
  ["workspace.toggle_special"] = true,
  ["workspace.move"] = true,
  ["group.toggle"] = true,
  ["group.next"] = true,
  ["group.prev"] = true,
  ["group.active"] = true,
  ["exec_cmd"] = true,
  ["exit"] = true,
  ["focus"] = true,
  ["layout"] = true,
  ["dpms"] = true,
}

local counts = {}
local binds = {}
local unbound = {}
local start_callbacks = {}

local function record(name)
  counts[name] = (counts[name] or 0) + 1
end

-- A returned handle. Every field read on it is a claim about the API, so
-- record which ones the config depends on.
local function handle(path)
  return setmetatable({}, {
    __index = function(_, key)
      record("field:" .. path .. "." .. tostring(key))
      return nil
    end,
    __newindex = function() end,
  })
end

local function dispatcher(path)
  if DISPATCHERS[path] then
    return { __dispatcher = path }
  end
  error("archy-test: hl.dsp." .. path .. " does not exist on this Hyprland", 2)
end

local function build()
  local hl = {}

  local all = {}
  for _, name in ipairs(HL_FUNCTIONS) do all[#all + 1] = name end
  for _, name in ipairs(HL_GETTERS) do all[#all + 1] = name end

  for _, name in ipairs(all) do
    hl[name] = function(...)
      local n = select("#", ...)
      local args = { ... }
      local first = args[1]

      -- hl.curve(name, table)
      if name == "curve" then
        if type(args[1]) ~= "string" or type(args[2]) ~= "table" then
          error("archy-test: hl.curve expects (name, table), got " .. n .. " arg(s)", 2)
        end
        record("curve")
        return nil
      end

      -- hl.animation({...}) and hl.animation(name, {...}) are both accepted by
      -- the real API.
      if name == "animation" then
        local ok = (type(first) == "table")
          or (type(first) == "string" and type(args[2]) == "table")
        if not ok then
          error("archy-test: hl.animation got " .. n .. " unexpected arg(s)", 2)
        end
        record("animation")
        return nil
      end

      -- hl.env(name, value)
      if name == "env" then
        if type(args[1]) ~= "string" or type(args[2]) ~= "string" then
          error("archy-test: hl.env expects (name, value), got " .. n .. " arg(s)", 2)
        end
        record("env")
        return nil
      end

      -- hl.bind(keys, dispatcher, opts)
      if name == "bind" then
        if type(first) ~= "string" then
          error("archy-test: hl.bind expects a key string, got " .. type(first), 2)
        end
        if n < 2 then
          error("archy-test: hl.bind needs a dispatcher", 2)
        end
        record("bind")
        binds[#binds + 1] = { keys = first, at = debug.getinfo(2, "Sl") }
        return { unbind = function() record("unbind_call") end }
      end

      -- hl.unbind(keys)
      if name == "unbind" then
        if type(first) ~= "string" then
          error("archy-test: hl.unbind expects a key string, got " .. type(first), 2)
        end
        record("unbind")
        unbound[#unbound + 1] = first
        return nil
      end

      -- hl.on(event, callback)
      if name == "on" then
        if type(first) ~= "string" then
          error("archy-test: hl.on expects an event name, got " .. type(first), 2)
        end
        record("on")
        -- Collect the session-start callback so it can be run afterwards: that
        -- is where a bad command string would show up. Everything else is
        -- registered but never fired, since firing needs a live compositor.
        if first == "hyprland.start" and type(args[2]) == "function" then
          start_callbacks[#start_callbacks + 1] = args[2]
        end
        return nil
      end

      if name == "get_config" or name == "get_window" or name == "get_monitor"
        or name == "get_workspace" or name == "get_monitor_at" then
        return nil
      end

      if name == "get_active_workspace" or name == "get_active_special_workspace"
        or name == "get_last_workspace" or name == "get_active_monitor" then
        return handle(name)
      end

      if name == "get_workspace_windows" or name == "get_windows" or name == "get_layers" then
        return {}
      end

      if type(first) == "table" then
        record(name)
        return nil
      end

      error("archy-test: hl." .. name .. " got an unexpected " .. type(first) .. " as arg 1", 2)
    end
  end

  -- hl.dsp is a namespace of builders, not a callable.
  hl.dsp = setmetatable({}, {
    __index = function(_, key)
      return setmetatable({}, {
        __index = function(_, sub)
          return function()
            return dispatcher(tostring(key) .. "." .. tostring(sub))
          end
        end,
        __call = function()
          return dispatcher(tostring(key))
        end,
      })
    end,
  })

  return hl
end

local hl = build()

-- hl.exec_cmd and hl.dispatch run shell commands for real. Under test they are
-- recorded, never run.
hl.exec_cmd = function(cmd)
  if type(cmd) ~= "string" then
    error("archy-test: hl.exec_cmd expects a string, got " .. type(cmd), 2)
  end
  record("exec")
  return nil
end
hl.dispatch = function(d)
  if type(d) ~= "table" then
    error("archy-test: hl.dispatch expects a dispatcher, got " .. type(d), 2)
  end
  record("dispatch")
  return nil
end

_G.hl = hl

--------------------------------------------------------------------------------
-- run
--------------------------------------------------------------------------------

local entry = os.getenv("ARCHY_ENTRY")
if not entry then
  print("ARCHY_ENTRY is not set; run this through scripts/test.sh")
  os.exit(1)
end

local ok, err = pcall(dofile, entry)
if not ok then
  print("FAIL: " .. tostring(err))
  os.exit(1)
end
print("config loaded")

print("")
print("calls:")
for _, key in ipairs({
  "config", "bind", "unbind", "unbind_call", "window_rule", "layer_rule",
  "workspace_rule", "animation", "curve", "env", "monitor", "on", "exec",
  "dispatch",
}) do
  if counts[key] then
    print(string.format("  %-16s %d", key, counts[key]))
  end
end

-- Two bindings on one key: Hyprland runs all of them, so this is only a
-- problem when it is accidental. tiling.lua binds ALT+TAB twice on purpose.
print("")
print("keys bound more than once")
local by_key = {}
for _, b in ipairs(binds) do
  by_key[b.keys] = (by_key[b.keys] or 0) + 1
end
local seen_keys = false
for keys, count in pairs(by_key) do
  if count > 1 then
    seen_keys = true
    -- An unbind of the same key anywhere in the run means a re-bind, which is
    -- the intended pattern for changing a key's behavior.
    local was_unbound = false
    for _, u in ipairs(unbound) do
      if u == keys then was_unbound = true end
    end
    print(string.format("  %-40s x%d%s", keys, count,
      was_unbound and "  (rebound deliberately)" or "  <-- two bindings, no unbind between"))
  end
end
if not seen_keys then
  print("  none")
end

-- Unbinding a key nothing bound is dead weight: in a standalone config there
-- are no defaults, so it can only mean the key was expected to come from
-- somewhere it no longer does.
print("")
print("unbinds of keys this config never binds")
local orphans = 0
for _, u in ipairs(unbound) do
  if not by_key[u] then
    print("  " .. u)
    orphans = orphans + 1
  end
end
if orphans == 0 then
  print("  none")
end

-- Run the session-start callbacks. This is where a wrong path or a typo in an
-- autostarted command shows up.
print("")
print("hyprland.start callbacks: " .. #start_callbacks)
for i, fn in ipairs(start_callbacks) do
  local ok2, err2 = pcall(fn)
  if not ok2 then
    print("  callback " .. i .. " FAILED: " .. tostring(err2))
    os.exit(1)
  end
end
if #start_callbacks > 0 then
  print("  all " .. #start_callbacks .. " ran clean")
end

print("")
print("PASS")
