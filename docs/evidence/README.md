# docs/evidence/ — curated acceptance evidence

`artifacts/` is wholesale gitignored (test logs, xcresult bundles, scratch screenshots), which
meant acceptance evidence never survived a clone. This directory is the fix: a **small, curated
subset** of evidence that backs specific acceptance claims, committed to the repo.

Rules:

- Screenshots only as a rule; keep each file **under 1 MB** (re-encode/scale if needed).
  No videos over ~10 MB — link a location instead if a recording matters.
- One subdirectory per session/claim (e.g. `s44-before/`, `s44-after/`), named by session id.
- Every subdirectory gets referenced from a doc (session note, pairing doc, or tracker entry)
  saying what each file demonstrates — an unexplained screenshot is not evidence.
- Raw/bulk output (full-resolution recordings, xcresult bundles, per-fixture dumps) stays in
  `artifacts/` and out of git.

Current contents:

- `s44-before/` + `s44-after/` — S4.4 polish pass before/after captures (iPhone 17 simulator,
  three seeded fixture homes, local backend). Pairing: `s44-before-after.md`.
