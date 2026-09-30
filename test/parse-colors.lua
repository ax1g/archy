-- Standalone copy of the palette parser from hypr/theme.lua, so the test can
-- compare it against the shell parser in scripts/lib.sh without loading the
-- whole config.
--
-- The two must agree exactly. If they disagree, the compositor and the bar read
-- the same file and come out with different themes, which is the exact failure
-- this duplication is a hazard for.
--
-- Usage: lua test/parse-colors.lua <path-to-colors.conf>

local path = arg[1] or (os.getenv("HOME") .. "/.config/archy/colors/colors.conf")

local handle = assert(io.open(path, "r"), "cannot read " .. path)

for line in handle:lines() do
  local trimmed = line:match("^%s*(.-)%s*$")

  if trimmed:sub(1, 1) == "#" then
    -- whole-line comment
  else
    local key, value = trimmed:match("^([%w_]+)%s*=%s*(.*)$")
    if key and value then
      value = value:match("^%s*(.-)%s*$")

      -- A '#' only introduces a trailing comment when the value does not
      -- already start with one. Every color in the palette is hex, so
      -- "accent = #4a9a68" must not be truncated.
      if value:sub(1, 1) ~= "#" then
        value = value:gsub("%s+#.*$", ""):match("^%s*(.-)%s*$")
      end

      if value ~= "" then
        print(key .. "=" .. value)
      end
    end
  end
end
