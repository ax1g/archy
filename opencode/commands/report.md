---
description: Build an interactive single-file HTML report from collected evidence using the reusable reporting engine.
agent: build
---

Reporting engine lives at `~/.local/share/opencode/reporting/` (`generate.py`, `template.html`, `schema.json`, `README.md`). Reuse it; never rebuild the template or CSS/JS unless broken.

Workflow:

1. Analyze the request, collect evidence with local scripts and small scoped batches. Never invent facts; label assumptions with severity `assumption`.
2. Write ONLY the report data as JSON matching `schema.json` to `/tmp/opencode/report-<topic>.json` (required: `title`; optional: `generated`, `summary`, `stats`, `findings`, `sections`, `recommendations`, `methodology`, `limitations`).
3. Run: `python ~/.local/share/opencode/reporting/generate.py /tmp/opencode/report-<topic>.json -o /tmp/opencode/report-<topic>.html`
4. Validate: confirm the generator printed `ok:` with expected finding/section counts; spot-check the HTML file exists.
5. Open: `xdg-open /tmp/opencode/report-<topic>.html` with the real path. If it fails, report the failure and give the file path.

Keep the final response under 100 words: file path, brief summary, limitations, browser-open status. Never print HTML or large JSON in chat. $ARGUMENTS
