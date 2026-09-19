# /verify

Run the full green gate. Invoke the `verify-all` skill and follow it exactly.

Five surfaces. Four run anywhere — EditorCore (`swift test --package-path tools/editorcore`),
backend pytest, corpus validation, and `scripts/typecheck-ios.sh`. The fifth, the iOS suite on a
simulator, **cannot run on the owner's machine**; where it can, read the count from the
`.xcresult` bundle with `xcrun xcresulttool`, never from the console (which undercounts because
the unit target runs under Swift Testing).

Use `backend/.venv/bin/python`, not `python3` — the system interpreter is 3.9, has no pytest, and
has no working TLS trust store.

Report PASS / FAIL / **NOT RUN** per surface with each summary line. A surface you did not run is
NOT RUN, never a pass. If something fails, show the failing test and assertion — never weaken a
test to make it pass.
