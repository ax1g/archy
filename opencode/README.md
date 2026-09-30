# opencode/

My OpenCode setup: the global config, the working rules, and the custom
commands and skills. `install.sh` symlinks these into `~/.config/opencode/`.

What lives here, and why:

- `opencode.json` — client config (schema, update policy, agent defaults).
- `AGENTS.md` — global working rules plus the learned-findings log. The
  agent appends to the installed copy, which lands here through the symlink.
- `commands/` — slash commands (`/linux-audit`, `/report`).
- `skills/` — skill definitions (`linux-audit`).

Deliberately NOT here:

- `cli.json` — TUI preferences (theme, layout, animation). Personal taste,
  stays on the machine.
- `service.json` — holds an auth secret. Never vendored, never linked; the
  installer leaves it alone.
