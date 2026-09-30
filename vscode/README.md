# archy: the VS Code theme.

# This is a local extension, not a marketplace one. VS Code picks up anything
# unpacked under ~/.vscode/extensions, so install.sh symlinks this directory
# there as `archy-theme`. There is nothing to install from a registry and
# nothing to update.
#
# The theme file is a color scheme, not code: 664 named colors and 81 token
# rules, generated from the same palette as everything else. That is why it can
# live in a repository at all.
#
# Two things about it worth knowing:
#
# It is static. It was generated once from the theme, and archy-theme does not
# rewrite it, the same as starship.toml. A theme switch changes the bar, the
# terminal, the launcher and the lock screen, and leaves the editor and the
# prompt on the old palette. Those two are the only surfaces that do, and both
# say so where they are configured.
#
# The name inside the file and in package.json have to match, and so does
# workbench.colorTheme in the user settings, or VS Code silently falls back to
# its default dark and the setting looks like it did nothing.

{
  "version": "2.0.0",
  "license": "MIT",
  "engines": { "vscode": "^1.70.0" }
}
