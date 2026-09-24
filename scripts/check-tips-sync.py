#!/usr/bin/env python3
"""Check the bundled prevention tips copy against the corpus original (S11.5 acceptance check).

Stdlib-only on purpose: this must run with a bare `python3`, no venv, on a machine that has
never set up the backend environment — same constraint as backend/corpus/validate.py.

Why this exists: `backend/corpus/prevention_tips.json` is the ONLY source the AI layer and the
corpus validator ever check citations against (.claude/rules/paths/corpus.md). The iOS app
cannot read that file at runtime — it bundles a copy at
escape_plan/Resources/prevention_tips.json instead. If the two ever drift, the app could show a
tip, a citation, or a peril label the corpus no longer says, with nothing catching it. This
script is that catch: it fails loudly the moment the bundled copy stops being byte-identical to
the original.

Usage:   python3 scripts/check-tips-sync.py
Exit 0 = the two files are byte-identical. Exit 1 = they differ (or one is missing), with a
diff-style report on stderr.
"""
from __future__ import annotations

import sys
from pathlib import Path

REPO_ROOT = Path(__file__).parent.parent
ORIGINAL = REPO_ROOT / "backend" / "corpus" / "prevention_tips.json"
BUNDLED = REPO_ROOT / "escape_plan" / "Resources" / "prevention_tips.json"


def main() -> int:
    errors: list[str] = []

    if not ORIGINAL.exists():
        errors.append(f"missing corpus original: {ORIGINAL}")
    if not BUNDLED.exists():
        errors.append(f"missing bundled copy: {BUNDLED}")

    if errors:
        for e in errors:
            print(f"ERROR: {e}", file=sys.stderr)
        return 1

    original_bytes = ORIGINAL.read_bytes()
    bundled_bytes = BUNDLED.read_bytes()

    if original_bytes != bundled_bytes:
        print("ERROR: escape_plan/Resources/prevention_tips.json has drifted from "
              "backend/corpus/prevention_tips.json — they must be byte-identical.",
              file=sys.stderr)
        print(f"  original: {ORIGINAL} ({len(original_bytes)} bytes)", file=sys.stderr)
        print(f"  bundled:  {BUNDLED} ({len(bundled_bytes)} bytes)", file=sys.stderr)
        original_lines = original_bytes.decode("utf-8", errors="replace").splitlines()
        bundled_lines = bundled_bytes.decode("utf-8", errors="replace").splitlines()
        for i, (a, b) in enumerate(zip(original_lines, bundled_lines)):
            if a != b:
                print(f"  first differing line ({i + 1}):", file=sys.stderr)
                print(f"    corpus : {a}", file=sys.stderr)
                print(f"    bundled: {b}", file=sys.stderr)
                break
        else:
            print("  one file is a prefix of the other (length differs).", file=sys.stderr)
        print("\nFix: cp backend/corpus/prevention_tips.json "
              "escape_plan/Resources/prevention_tips.json", file=sys.stderr)
        return 1

    print(f"Tips in sync: {BUNDLED} matches {ORIGINAL} byte-for-byte "
          f"({len(original_bytes)} bytes).")
    return 0


if __name__ == "__main__":
    sys.exit(main())
