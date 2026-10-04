# S11.37 — Failure messages tell the truth

- **Who:** P1 (Claude, for Anish)
- **Date(s):** 2026-10-04
- **Status when I stopped:** done and merged; the manual simulator check and two proxy-related unknowns are in BLOCKERS

## What happened
Reworked `BackendFailure` so each real situation reads as itself: a cancelled request shows nothing, a phone timeout
says the server didn't answer in time and may be waking up, a body that will not decode says the app and server
disagree, a server 504 says the server stopped waiting, 413 says the input is too large, and a chat 422 shows the
server's own sentence. Chat now waits 120 s; the server's chat deadline moved from 50 s to 110 s with it, and a backend
test reads the Swift constant so the pair cannot drift. Both required reviewers ran. They found that the silent
cancelled kind was still being stored as a failure by five screens; fixed with a one-line guard at each, and the
duplicate cancellation helper in `ReadinessStore` now calls the shared one.

Evidence: iOS unit suite 1072 passed, 0 failed, 3 skipped (xcresulttool, `full2.xcresult`); backend 1029 passed, 1
skipped; typecheck ok. Mutation checks: eight deliberate breaks (cancellation check off, timeout branch off, 413 arm
off, 504 arm off, decode branch off, 422 detail ignored, chat timeout back to 60, banner always draws) each made the
matching tests fail, and the banner break was also run alone. Chat deadline set to 50 and to 125 made backend tests
fail. All were restored from copies, not by `git checkout`.

## Decisions / surprises
- Stale `.pyc`: changing `CHAT_DEADLINE_S` between two values of the same length ("125.0", "110.0") within a second
  made pytest import the old bytecode and report failures that were not real. Clear `__pycache__` after a mutation run.
- The Swift reviewer and the silent-failure reviewer independently found the half-wired cancellation; the fix touches
  screens outside OWNED FILES (logged in decisions.md).
- A TEST in `ConversationStoreTests` pinned the old 422 behaviour; updated, not deleted.

## Questions for teammates
- None blocking. The Render paid-tier question for filming stays with Anish (S11.13).

## Next steps
S11.45 (one conversation per home) is now unblocked on this side. S11.39 still waits on the S11.14 decision. Someone
should watch the Assistant screen against a host that never answers during the device pass.
