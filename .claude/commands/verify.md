# /verify

Run the full green gate for the repo. Invoke the `verify-all` skill and follow it exactly:
EditorCore SwiftPM tests, the iOS app suite on the iPhone 17 Pro simulator, backend pytest
(`-m "not live"`), and `backend/corpus/validate.py`.

Report a PASS/FAIL line per surface with each summary line. If anything fails, show the specific
failing test and assertion — never weaken a test to make it pass.
