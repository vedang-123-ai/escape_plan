"""S8.2 authentication: password hashing, JWT issue/verify, and the
`get_current_user` dependency.

Split from `app/main.py` so the primitives are testable without HTTP, and kept
out of `app/routing/` and `app/scoring/`, which are pure deterministic modules
with no I/O and no secrets.
"""
