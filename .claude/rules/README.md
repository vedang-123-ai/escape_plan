# rules/

Granular guidance scoped narrower than CLAUDE.md. **Nothing here auto-loads.**

- `languages/` — `python.md` (backend), `swift.md` (iOS).
- `paths/` — `schema.md` (the HomeModel contract), `corpus.md` (grounding + citation rules).
- `vendors/` — `anthropic.md` (Claude integration rules: grounded, cited, never routes).

Scoped rules carry frontmatter `globs` so they surface only when a matching file is in play, and
the root `CLAUDE.md` has a table saying which one to open for which territory.

**`global/` was removed 2026-09-08.** Its three files (`architecture.md`, `conventions.md`,
`workflows.md`) were `@`-referenced from the root `CLAUDE.md`, so they loaded into every session
whether or not they were relevant — about 5 KB of mostly-duplicated text on top of a CLAUDE.md
that already said the same things. Duplication is also how this repo's docs drifted into
contradicting each other, so the content was folded into `CLAUDE.md` as the single copy rather
than kept in two places. See `docs/decisions.md`, 2026-09-08.

Add new categories (`layers/`, `platforms/`) only when the project actually grows them — and keep
them on-demand. A rule that loads when it isn't needed is a tax on every session.
