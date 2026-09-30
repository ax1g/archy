-- Cursor theme and size.
--
--   https://github.com/ful1e5/apple_cursor  (GPL-3.0)
--   installed at ~/.local/share/icons/macOS, or system-wide from the AUR
--   package of the same name.
--
-- There are two independent paths to the pointer and both have to be set, which
-- is the part that is easy to get half right:
--
--   XCURSOR_THEME / XCURSOR_SIZE are read by XWayland clients only. A native
--   Wayland app has no cursor of its own; the compositor draws it.
--
--   The compositor's cursor is drawn by hyprcursor, on by default in 0.56,
--   which takes the theme name from gsettings while
--   cursor:sync_gsettings_theme is true. autostart.lua applies that.
--
-- Setting only the env vars gives a macOS pointer inside X11 apps and the
-- default arrow everywhere else, which reads as "it half worked".
--
-- The theme is an Xcursor theme, not a hyprcursor one — cursors/ and
-- cursor.theme, with no hyprcursors/ or theme.conf. libhyprcursor falls back
-- to its Xcursor loader for exactly this case, so the name still resolves.

local CURSOR_THEME = "macOS"
local CURSOR_SIZE = 40

-- For XWayland clients.
hl.env("XCURSOR_THEME", CURSOR_THEME)
hl.env("XCURSOR_SIZE", tostring(CURSOR_SIZE))

-- For hyprcursor, i.e. the cursor the compositor itself draws. Only the size is
-- a real variable: HYPRCURSOR_THEME is not read by libhyprcursor, which takes
-- the theme from gsettings instead (see autostart.lua). Setting it here would
-- be a dead variable.
hl.env("HYPRCURSOR_SIZE", tostring(CURSOR_SIZE))

return {
  theme = CURSOR_THEME,
  size = CURSOR_SIZE,
  -- Where the theme is expected to live. Checked by install.sh so a new machine
  -- reports it rather than silently falling back to the default arrow.
  search_paths = {
    (os.getenv("HOME") or "") .. "/.local/share/icons",
    (os.getenv("HOME") or "") .. "/.icons",
    "/usr/share/icons",
  },
}
