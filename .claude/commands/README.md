# commands/

Custom slash commands. Each `.md` file is a command body; `$ARGUMENTS` receives what the user
typed after the command name.

- `/session <id>` — run a playbook session end-to-end with the handoff protocol (prereq check,
  plan, execute, acceptance verification, decisions/tools-used updates, handoff artifact).
- `/validate-corpus` — run the corpus validator and fix failures.

Scripts backing a command (if any) live in `bash/`, `node/`, or `python/` subfolders. See
`_TEMPLATE.md` for the shape.
