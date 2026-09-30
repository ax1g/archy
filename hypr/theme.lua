-- Theme loader. Reads colors/colors.conf and applies it to Hyprland.
--
-- One file drives every color in the setup. To retheme, edit that file and
-- reload Hyprland; run `archy-theme sync` to also refresh the generated
-- Waybar and Wofi stylesheets, then `archy-theme restart` to reload the bar.

local home = os.getenv("HOME") or "/home/archy"
local colors_file = os.getenv("ARCHY_COLORS_FILE") or (home .. "/.config/archy/colors/colors.conf")

local function parse(path)
  local handle = io.open(path, "r")
  if not handle then
    error("archy: cannot read colors file at " .. path)
  end

  local colors = {}
  for line in handle:lines() do
    local trimmed = line:match("^%s*(.-)%s*$")

    -- Whole-line comment.
    if trimmed:sub(1, 1) == "#" then
      -- skip
    else
      local key, value = trimmed:match("^([%w_]+)%s*=%s*(.*)$")
      if key and value then
        value = value:match("^%s*(.-)%s*$")

        -- A '#' only introduces a trailing comment when the value does not
        -- already start with one. Every color in the palette is a hex value, so
        -- "accent = #4a9a68" has a '#' right after the '=' and a naive
        -- whitespace-aware comment strip would empty out the entire file.
        if value:sub(1, 1) ~= "#" then
          value = value:gsub("%s+#.*$", ""):match("^%s*(.-)%s*$")
        end

        if value ~= "" then
          colors[key] = value
        end
      end
    end
  end
  handle:close()

  return colors
end

local c = parse(colors_file)

-- Hyprland wants #rrggbbaa, not a bare #rrggbb, for border colors. Extend the
-- short form so the theme file can stay in plain hex.
local function with_alpha(hex, alpha)
  hex = hex:gsub("^#", "")
  if #hex == 6 then
    return "#" .. hex .. alpha
  end
  return "#" .. hex
end

local active_border = c.active_border
local inactive_border = c.inactive_border or "rgba(595959aa)"

hl.config({
  general = {
    col = {
      active_border = active_border,
      inactive_border = inactive_border,
    },
  },

  group = {
    col = {
      border_active = active_border,
      border_inactive = inactive_border,
    },
  },
})

-- Expose the palette so other config files can read it: require("hypr.theme").colors.accent
local M = { colors = c, with_alpha = with_alpha }
return M
