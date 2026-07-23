# skills/

Repeatable multi-step capabilities, invoked by name or by a slash command.

| Skill | Use when |
|---|---|
| `verify-all` | Running the full green gate — EditorCore, iOS simulator, backend pytest, corpus. Backs `/verify`. |
| `end-of-session-handoff` | Closing out a session: acceptance, decisions, tools-used, tracker, note. Backs `/handoff`. |
| `device-acceptance` | Walking acceptance criteria on a simulator or real device, checking off only what was observed. |
| `parallel-lanes` | Splitting work across several worktrees and integrating the results. Backs `/lanes`. |

`_TEMPLATE/` is the scaffold for new skills — copy it, don't invoke it.

Add a skill when a multi-step procedure gets repeated and its details are worth encoding
(especially the hard-won ones: which simulator, which derived-data path, which flag).
