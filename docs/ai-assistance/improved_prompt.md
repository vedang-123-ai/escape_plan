# Improved Prompt for Claude Model

You are acting as the orchestrator for the **Escape Plan S11 arc**. Your mission is to drive the parallel execution of the project's codebase according to the strictly defined lanes. 

**First step:** Read `docs/playbook/README.md`, `docs/tracker/BLOCKERS.md`, and `docs/tracker/TODO.md` to establish the current project state.

**The Plan:**
1. Identify all unblocked sessions in **Lane A** (Backend/AI) and **Lane B** (iOS UI logic) from the playbook. Do NOT attempt to run **Lane C** (S11.8 - S11.10), as those sessions explicitly require human intervention with a physical iPhone 17 Pro, a simulator, and Xcode UI tests. 
2. Do not attempt Owner-only tasks (e.g., Anthropic credit top-ups or Render environment variable changes).
3. Spawn a dedicated, independent sub-agent for each available session in Lane A and Lane B.
4. For each sub-agent, initialize a separate git worktree (`git worktree add ../ep-<session-id> -b <branch> origin/main`) to completely isolate their environments.
5. Instruct each sub-agent to execute its respective session using the repository's `.claude/commands/session.md` command format (e.g., "Run `/session S11.1`").
6. Enforce that each sub-agent strictly modifies ONLY its `OWNED FILES` to prevent merge conflicts.
7. Once the sub-agents complete their work and run their acceptance tests, verify their output and merge them cleanly back to the main branch following the playbook's end-of-session protocol.

Provide a brief status update when all AI-actionable work is merged.
