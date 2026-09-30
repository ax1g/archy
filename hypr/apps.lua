-- App classes that more than one file needs to agree on.
--
-- Kept in its own module because the answer has to be the same everywhere, and
-- the files that need it load in a fixed order. A shared constant that one file
-- reaches with require("hypr.other") works, but only because require caches and
-- loads on first use, which pulls the other file in earlier than the load order
-- says it should be.

local M = {}

-- The browser in daily use.
--
-- floatcascade.lua gives it static float/size/center rules because a browser is
-- slow to first paint, and resizing it from tiled to float afterwards forces a
-- second configure cycle, which shows as a blurry translucent flash under the
-- frost. looknfeel.lua gives it an explicit opacity for the same reason: a
-- frosted page body over a blurred desktop makes text edges muddy.
--
-- Change this when changing browsers.
M.BROWSER_CLASS = "zen"

-- The terminal, used for the "terminal" tag that the universal clipboard chords
-- and the cascade's terminal exemption both read. Matched as a regex, so TUI.*
-- covers a terminal window running a TUI, which is still a terminal.
M.TERMINAL_CLASS = "(kitty|TUI\\..*)"

return M
