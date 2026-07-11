# agent-memory/

Persistent long-term memory per sub-agent — one subfolder per agent in `.claude/agents/`,
each with a `MEMORY.md` the agent appends to across runs. Committed on purpose (unlike the
session memory system under `~/.claude/projects/`, which is machine-local and out of scope).
