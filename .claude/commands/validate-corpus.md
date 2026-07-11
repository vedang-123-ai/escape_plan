# /validate-corpus

Validate the grounding corpus.

Run `python3 backend/corpus/validate.py` and report the result. If it fails, fix the corpus
files (per `.claude/rules/paths/corpus.md`) and re-run until green — never weaken the
validator to make it pass.
