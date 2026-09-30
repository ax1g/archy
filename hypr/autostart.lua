-- Autostart. Everything the desktop needs running that Hyprland does not
-- start itself.
--
-- This list is the part of the migration most likely to bite: Omarchy's shell
-- started the notification daemon, clipboard watcher, idle handling and the
-- polkit agent on its own, and nothing in a plain hyprland.conf starts them.
-- If something is missing after the switch, it is almost certainly here.

local bin = o.bin_dir

hl.on("hyprland.start", function()
  -- Make this session's environment visible to systemd user services and D-Bus
  -- activated services, so wireplumber, polkit and portal see the same variables
  -- Hyprland just set.
  hl.exec_cmd("systemctl --user import-environment $(env | cut -d'=' -f 1)")
  hl.exec_cmd("dbus-update-activation-environment --systemd --all")

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
  hl.exec_cmd("hyprpolkitagent")

  -- Nightlight, on the identity profile from hyprsunset.conf.
  hl.exec_cmd("hyprsunset -c " .. o.home .. "/.config/archy/hypr/hyprsunset.conf")

  -- Removable media.
  hl.exec_cmd("udiskie --automount --no-notify --no-tray")

  -- Restore the last gamma brightness, which is compositor state and does not
  -- survive a compositor restart on its own.
  hl.exec_cmd(bin .. "/archy-brightness restore")

  -- XWayland font rendering.
  hl.exec_cmd("xrdb -load ~/.Xresources")
end)
