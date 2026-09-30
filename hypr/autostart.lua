-- Autostart. Everything the desktop needs running that Hyprland does not start
-- itself.
--
-- This list is the part most likely to bite when moving a session to a new
-- machine: a notification daemon, a clipboard watcher, idle handling and a polkit
-- agent are all independent programs, and if one is missing here it is simply
-- absent after a reboot with nothing in the logs to say so.

local bin = o.bin_dir
local cursor = require("hypr.cursor")

hl.on("hyprland.start", function()
  -- Make this session's environment visible to systemd user services and D-Bus
  -- activated services, so wireplumber, polkit and portal see the same variables
  -- Hyprland just set.
  hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")
  hl.exec_cmd("dbus-update-activation-environment --systemd --all")

  -- Cursor theme for the pointer the compositor draws.
  --
  -- This is the half that is easy to miss. The env vars in cursor.lua cover
  -- XWayland clients; a native Wayland app has no cursor of its own, and
  -- hyprcursor reads the theme from gsettings while
  -- cursor:sync_gsettings_theme is true. Without these two lines the on-screen
  -- pointer is the default arrow even though the env vars look correct.
  hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-theme '" .. cursor.theme .. "'")
  hl.exec_cmd("gsettings set org.gnome.desktop.interface cursor-size " .. cursor.size)

  -- Regenerate the generated stylesheets from colors/colors.conf before the bar
  -- and the launcher read them.
  hl.exec_cmd(bin .. "/archy-theme sync")

  -- Top bar. -s passes the generated stylesheet: Waybar only takes CSS on the
  -- command line, never from its JSON config, which is why the colors are a
  -- separate file rather than a block in config.jsonc.
  hl.exec_cmd("waybar -c " .. o.home .. "/.config/archy/waybar/config.jsonc -s " .. o.home .. "/.config/archy/generated/waybar.css")

  -- Notifications. mako reads its palette from a keyfile, so the generated file
  -- is passed with -c.
  hl.exec_cmd("mako -c " .. o.home .. "/.config/archy/generated/mako.conf")

  -- Clipboard history. wl-clipboard does the copy and paste; cliphist stores
  -- the list that SUPER+CTRL+V reads. Without the watcher running, every
  -- clipboard chord works but the history is permanently empty.
  hl.exec_cmd("wl-paste --watch cliphist store")

  -- Idle. hypridle calls archy-lock, which owns the lock surface.
  hl.exec_cmd("hypridle -c " .. o.home .. "/.config/archy/hypr/hypridle.conf")

  -- Screen sharing and file choosers need the Hyprland portal. The Hyprland
  -- portal has to come up before the GTK one, which handles the dialogs it
  -- asks for.
  hl.exec_cmd("/usr/lib/xdg-desktop-portal-hyprland &")
  hl.exec_cmd("/usr/lib/xdg-desktop-portal-gtk &")

  -- Polkit: the password prompt for mounting, network settings and power.
  --
  -- There is no polkit configuration to install. Every permission here is stock
  -- (packagekit for mounting, NetworkManager for connections, logind for power)
  -- and no rules.d entry is needed; this is only the agent that draws the
  -- dialog.
  --
  -- Guarded, because a missing agent is otherwise invisible: the session comes
  -- up clean and the first sign of it is that mounting a drive does nothing and
  -- never asks for a password.
  hl.exec_cmd("command -v hyprpolkitagent >/dev/null || notify-send -u critical " ..
    "'Polkit agent missing' 'install hyprpolkitagent, or nothing will ask for a password'")
  hl.exec_cmd("hyprpolkitagent 2>/dev/null")

  -- Nightlight, on the identity profile from hyprsunset.conf.
  hl.exec_cmd("hyprsunset -c " .. o.home .. "/.config/archy/hypr/hyprsunset.conf")

  -- Removable media.
  hl.exec_cmd("udiskie --automount --no-notify --no-tray")

  -- Wallpaper. Runs after the bar, because the bar has no background of its own
  -- and needs the wallpaper behind it before it can be judged.
  hl.exec_cmd("sleep 0.5 && " .. bin .. "/archy-wallpaper set")

  -- Restore the last gamma brightness, which is compositor state and does not
  -- survive a compositor restart on its own.
  hl.exec_cmd(bin .. "/archy-brightness restore")

  -- XWayland font rendering.
  hl.exec_cmd("xrdb -load ~/.Xresources")
end)
