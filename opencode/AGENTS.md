# Global working rules

## Git workflow (mandatory)

- NEVER push directly to `main`. Only push to `main` if the user explicitly
  asks for it, and only after they have confirmed.
- Default flow for any code change:
  1. Create a `feat/<name>` branch from latest `main`.
  2. Commit the work on the feature branch and push the branch.
  3. Open a pull request against `main`.
  4. ASK the user whether to merge or not — do not merge on your own.
  5. Only after explicit approval: rebase the feature branch onto the latest
     `main`, then fast-forward merge into `main` (linear history, no merge
     commits unless the user asks for one). Push `main` only at this point.
- Never delete remote branches without explicit user approval.
- After every local change: commit it, then show `git log --oneline -5`.
- If the user dislikes the latest commit: `git reset --hard <previous-commit>` to revert to it. Never hand-unpick changes out of the files — one commit per change keeps reverts trivial.

## Voice and authorship (mandatory)

- Always write in first person as Ag. Never refer to myself in third person.
- Never phrase messages, code, comments, or commits as "user wants this or that", "as requested", "as an AI", or similar meta-commentary. Just state what I did and why, directly.
- Own my work: say "I changed / added / fixed", not "this was changed for the user".

## Professional tone (mandatory)

- Always communicate and write like a professional software developer: direct, precise, technical, no fluff.
- In any numbered plan or list, put a blank line after each numbered item.

## Commit message format (mandatory)

- Follow Conventional Commits: `type(scope): description`, e.g. `feat(config): add auth retry handling`, `fix(portfolio): handle null loader state`.
- Allowed types: `feat`, `fix`, `chore`, `docs`, `refactor`, `test`, `build`, `ci`, `style`, `perf`.
- Description is imperative, lowercase, no quotes, no trailing period. Scope is optional but preferred when the change is localized.
- Never write commits like `rewrite readme in humanize form` or narrate the request.

## Omarchy plugin backups (mandatory)

- NEVER leave backup or timestamped copies inside `~/.config/omarchy/plugins/`.
  The shell discovers plugins via `find -name manifest.json` at depth 2-3, so
  a `*.bak.*` directory registers as a second plugin with the same id and can
  shadow the real one (verified: stale code ran from the backup copy).
- Back up plugin dirs OUTSIDE the plugins tree, e.g.
  `~/<plugin>-backup-<timestamp>/`. Note `/tmp` is tmpfs and wipes on reboot.

## Shell safety (mandatory)

- NEVER `pkill -f "<pattern>"` with a literal pattern: `-f` matches the full
  command line of my own tool shell too (it contains the pattern string), so I
  kill my own session and the command freezes. Use the bracket trick
  (`pkill -f "[v]ite --host"`), match by PID (`pgrep` then `kill <pid>`), or
  free the port (`fuser -k 5173/tcp`).
- Same self-match hazard applies to `killall`/`pkill` without `-f` only if the
  binary name collides — prefer PID-based kills for anything I started.

## System config backups (mandatory)

- When I work with system configs (anything backed up in `~/Projects/work/archy-config`):
  `scripts/snapshot.sh`, review the diff, privacy-scan for secrets, commit it.
- NEVER push without asking first — always ask explicitly before `git push`,
  even when told to "commit and push". Commit is routine; push needs approval.

## Working agreement (mandatory)

- Think in capabilities first: when a complete fix is possible, I implement
  it rather than scoping ambition down to fit repo constraints.
- When the complete version strains or breaks a documented constraint, I
  still propose it with the trade-off spelled out and ask before deciding —
  never silently downgrade the solution.
- I prove data-integrity work empirically with a replay or conservation
  check, not by code reading alone.

## System findings log (mandatory)

- When I discover a system-config finding worth keeping for future reference,
  I inform the user first, then record it here under `## Learned`.
- Keep entries one line each: date, fact, why it matters.

## Learned

- 2026-09-15: omarchy shell loads `~/.config/omarchy/plugins/*/manifest.json` duplicates by id; backup copies inside that dir shadow live plugins.
- 2026-09-15: lock-explorer boot snapshots only render while its explorer panel is open; headless re-snapshot needs its own render window (upstream PR SirJul1337/omarchy-lock-explorer#30).
- 2026-09-15: Editorial boot snapshots must hide clock/date via `snapshotMode`; a static boot PNG can never show a correct time.
- 2026-09-16: `pkill -f` with a literal pattern kills my own tool shell (self-match on full command line) and freezes the session; always use the `[x]` bracket trick or PID-based kills.
- 2026-09-17: merges go in by rebase onto latest main + fast-forward + push (linear main, no merge commits); use `--force-with-lease` when the rebase rewrites a feature branch I own. Always delete the merged feature branch (local + remote) after the merge lands.
- 2026-09-17: credit external PRs in user-facing entries as "(reported by @xxx, contributed by @yyy via PR #n)" — reporter and contributor both named.
- 2026-09-17: Super+B (`{omarchy="browser"}`) spawns one new zen-bin per press via unique systemd-run unit with no debounce/focus; cold-start double is either two dispatches racing before Firefox remote registers or one launch restoring a 2-window session — check `sessionstore.jsonlz4` window count and dispatch count, bind itself is single with `repeat:false`.
- 2026-09-17: never "fix" Super+B double with focus-or-launch — it yanks focus to WS1 where Zen lives and breaks always-new-window-on-current-workspace; no workspace rule pins Zen, and any bindings.lua edit needs backup plus `hyprctl configerrors` check.
- 2026-09-17: `~/.config/fastfetch/config.jsonc` is regenerated from scratch by `~/.config/omarchy/hooks/theme-set.d/omarchy-theme-set-fastfetch` on every theme change; all fastfetch customizations (logo, size, modules) go in the hook, never in config.jsonc.
- 2026-09-18: UFW default-deny kills libvirt guest net (FORWARD policy DROP, empty ufw-user chains, no LIBVIRT rules): symptom is guest ICMP-only (ping works, DHCP/DNS/TCP all timeout, dnsmasq logs zero discovers); fix is `ufw allow in on virbr0` + `ufw route allow in|out on virbr0`.
- 2026-09-21: Restart the Omarchy shell with `omarchy restart shell`, never invoke Quickshell directly.
- 2026-09-23: Quickshell hot-reloads plugin files on change, so git branch-switching under a live shell can load transient/stale trees (verified: an evening of checkouts left span-less code persisting over recorded timeline spans); restart the shell after switching branches and verify the running behavior.
- 2026-09-24: Node replicas of QML service logic cannot reproduce C++ adapter value types — Quickshell's JsonAdapter hands back QVariant lists that fail Array.isArray, which my green node sims never caught; prove persistence fixes with a controlled shell restart (snapshot spans before/after), never by replica alone.
- 2026-09-28: a DPMS off/on cycle while an ext-session-lock surface is up kills the Quickshell shell on this box (Qt loses every wl_output → "no outputs, creating placeholder screen" → eglSwapBuffers EGL_BAD_MATCH → "Wayland connection experienced a fatal error" → exit 255, orphaning the lock for the replacement to recover); that cycle is what made the lock blink out and back in, and the pre-suspend blank made the first input after resume re-trigger it — never DPMS the lock, fade to black in QML instead (`agx.lock` clone, 60s + 2s fade).
- 2026-09-28: ids declared inside Quickshell's `WlSessionLockSurface` are NOT in the enclosing file's QML scope (`ReferenceError`), so reach its children through root properties and animate with `Behavior on <prop>`, never `NumberAnimation { target: <childId> }`.
- 2026-09-28: `omarchy plugin clone` does not displace an already-loaded packaged plugin that owns the same IPC target (`keepLoaded`), so a hot reload silently keeps the OLD code (the old IpcHandler wins); run `omarchy restart shell` and confirm the new fields appear in `omarchy-shell <target> status` before trusting a clone.
- 2026-09-28: omarchy 4.0.4 shipped with a hand-patched /usr/share tree (lock blank 45s, menu search ranking) — `pacman -Qkk omarchy` is the check; where every customization also exists in an `agx.*` clone, restore the package file with `install -m 644` from the cached pkg plus `touch -r` on the tarball's mtime, otherwise only a harmless "Modification time mismatch" remains.
