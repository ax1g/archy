-- Screencopy permissions.
--
-- Hyprland 0.56 answers capture requests through its permission manager, not
-- a config key: the old screencopy:allow_token_by_default does not exist and
-- the compositor rejects it as unknown. Each capture tool is allowed here so
-- a screenshot key, the color picker and the recording pipeline never block
-- on an interactive auth prompt nobody is there to answer.

hl.permission("/usr/(bin|local/bin)/grim", "screencopy", "allow")
hl.permission("/usr/(bin|local/bin)/hyprpicker", "screencopy", "allow")
hl.permission("/usr/(bin|local/bin)/gpu-screen-recorder", "screencopy", "allow")
hl.permission("/usr/(lib|libexec|lib64)/xdg-desktop-portal-hyprland", "screencopy", "allow")
