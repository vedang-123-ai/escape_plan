# /handoff <session-id, e.g. S11.4>

Run the complete end-of-session protocol for `$ARGUMENTS`. Invoke the `end-of-session-handoff`
skill and follow every step — acceptance verification, `decisions.md` + `tools-used.md`, and the
MANDATORY tracker step (session note from `_TEMPLATE`, `TODO.md`), then the
handoff artifact and a commit referencing the session id.

Leave device-only acceptance boxes unchecked unless a human actually observed the behavior on
hardware. No tracker note, no DONE.
