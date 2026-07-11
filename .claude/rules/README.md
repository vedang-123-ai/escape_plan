# rules/

Granular guidance scoped narrower than CLAUDE.md.

- `global/` — always-on baseline (`architecture.md`, `conventions.md`, `workflows.md`),
  auto-loaded via `@`-references in the root CLAUDE.md.
- `languages/` — `python.md` (backend), `swift.md` (iOS), loaded on demand via frontmatter globs.
- `paths/` — `schema.md` (the HomeModel contract), `corpus.md` (grounding + citation rules).
- `vendors/` — `anthropic.md` (Claude integration rules: grounded, cited, never routes).

Scoped rules carry frontmatter `globs` so they surface only when a matching file is in play.
Add new categories (layers/, platforms/) only when the project actually grows them.
