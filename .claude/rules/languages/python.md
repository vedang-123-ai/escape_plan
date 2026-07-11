---
description: Python conventions for the backend
globs: ["backend/**/*.py"]
alwaysApply: false
---

# Python rules

- 3.11+, fully typed (mypy-clean intent even before tooling lands), pydantic v2 for all
  request/response and domain models.
- Routing (`app/routing/`) and conversion (`app/convert/`) are pure-function modules: no I/O,
  no globals, deterministic (same input → same output). FastAPI endpoints are thin wrappers.
- pytest for everything; fixtures come from `schema/fixtures/` — don't invent parallel test
  homes.
- `backend/corpus/validate.py` stays stdlib-only (it must run before the backend env exists).
