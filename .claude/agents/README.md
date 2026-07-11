# agents/

Specialized sub-agents: one markdown file each (frontmatter: `name`, `description`, `tools`),
grouped by function.

- `quality/session-auditor.md` — verifies a playbook session's acceptance criteria and
  end-of-session protocol with repo evidence before it's declared DONE.

Add agents only when a recurring, delegatable job emerges (e.g., a schema-sync checker once
pydantic + Swift models both exist). See `_TEMPLATE.md`. Each agent gets a matching
`.claude/agent-memory/<name>/MEMORY.md`.
