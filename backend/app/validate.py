"""Validate HomeModel JSON documents against the contract.

Runs both halves of the contract: the JSON Schema (shape) and the pydantic
models (structural invariants). Usage, from backend/:

    python3 -m app.validate ../schema/fixtures/bungalow.json [more files...]

Exits non-zero if any file fails either validator.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from pydantic import ValidationError

from app.models import HomeModel

DEFAULT_SCHEMA_PATH = (
    Path(__file__).resolve().parents[2] / "schema" / "homemodel.schema.json"
)


def _jsonschema_errors(document: object, schema_path: Path) -> list[str]:
    try:
        import jsonschema
    except ImportError:
        return ["(jsonschema not installed — JSON Schema check skipped)"]
    schema = json.loads(schema_path.read_text())
    validator = jsonschema.Draft202012Validator(schema)
    errors = sorted(validator.iter_errors(document), key=lambda e: list(e.absolute_path))
    out = []
    for e in errors:
        where = "$" + "".join(
            f"[{p}]" if isinstance(p, int) else f".{p}" for p in e.absolute_path
        )
        out.append(f"  jsonschema at {where}: {e.message}")
    return out


def _pydantic_errors(document: object) -> list[str]:
    try:
        HomeModel.model_validate(document)
    except ValidationError as exc:
        out = []
        for err in exc.errors():
            loc = "$." + ".".join(str(p) for p in err["loc"]) if err["loc"] else "$"
            out.append(f"  pydantic at {loc}: {err['msg']}")
        return out
    return []


def validate_file(path: Path, schema_path: Path) -> list[str]:
    """Return a list of error strings; empty list means the file is valid."""
    try:
        document = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        return [f"  cannot read/parse: {exc}"]
    errors = _jsonschema_errors(document, schema_path)
    errors = [e for e in errors if not e.startswith("(")] + [
        e for e in errors if e.startswith("(")
    ]
    errors += _pydantic_errors(document)
    return [e for e in errors if not e.startswith("(")]


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        prog="python3 -m app.validate",
        description="Validate HomeModel JSON files against schema + pydantic invariants.",
    )
    parser.add_argument("files", nargs="+", type=Path, help="HomeModel JSON file(s)")
    parser.add_argument(
        "--schema", type=Path, default=DEFAULT_SCHEMA_PATH,
        help="Path to homemodel.schema.json (default: repo schema/)",
    )
    args = parser.parse_args(argv)

    failed = 0
    for path in args.files:
        errors = validate_file(path, args.schema)
        if errors:
            failed += 1
            print(f"FAIL  {path}")
            for e in errors:
                print(e)
        else:
            print(f"OK    {path}")
    if failed:
        print(f"\n{failed} of {len(args.files)} file(s) INVALID")
    else:
        print(f"\nall {len(args.files)} file(s) valid")
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
