#!/usr/bin/env python3
"""Validate the fire-safety grounding corpus (S0.4 acceptance check).

Stdlib-only on purpose: the backend Python environment is not scaffolded
until S1.6, so this must run with a bare `python3`.

Checks:
  1. sources.json parses; every source has the required fields.
  2. Every corpus_files entry points to an existing .md file, and every
     .md file in this directory is indexed.
  3. Every .md front-matter has the required keys and its source ids
     (id / additional_source_ids) resolve to sources.json (compilation
     docs' own ids must match their corpus_files primary_id).
  4. Every inline [cite: X] in every .md resolves to a source id.
  5. egress_thresholds.json parses; every threshold value is a positive
     number, every source_doc_id resolves, and imperial/metric pairs
     agree within 1% after unit conversion.
  6. object_hazard_thresholds.json cited values resolve and convert;
     engineering constants each carry a written basis.
  7. prevention_tips.json parses; ids are unique; peril is one of the
     three in scope; text is non-empty; every cite resolves.

What this script deliberately does NOT check: whether a claim is
actually present on the page its citation points at. That needs the
network; `check_urls.py` covers the machine-checkable part of it.

Exit 0 = corpus valid. Exit 1 = problems, listed on stderr.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

CORPUS_DIR = Path(__file__).parent
REQUIRED_SOURCE_FIELDS = {"id", "org", "doc_title", "url", "retrieved", "topics"}
REQUIRED_FRONT_MATTER = {"id", "org", "doc_title", "url", "retrieved", "topics"}
CITE_RE = re.compile(r"\[cite:\s*([a-z0-9-]+)\]")
REQUIRED_TIP_FIELDS = {"id", "peril", "topic", "text", "cite", "audience"}
PERILS = {"fire", "earthquake", "tornado"}

SQFT_TO_M2 = 0.09290304
IN_TO_M = 0.0254
FT_TO_M = 0.3048

errors: list[str] = []


def err(msg: str) -> None:
    errors.append(msg)


def parse_front_matter(text: str, fname: str) -> dict[str, object]:
    """Minimal YAML front-matter parser: scalar values and flow-style lists."""
    m = re.match(r"^---\n(.*?)\n---\n", text, re.DOTALL)
    if not m:
        err(f"{fname}: missing YAML front-matter block")
        return {}
    fm: dict[str, object] = {}
    for line in m.group(1).splitlines():
        if ":" not in line:
            continue
        key, _, val = line.partition(":")
        val = val.strip()
        if val.startswith("[") and val.endswith("]"):
            fm[key.strip()] = [v.strip() for v in val[1:-1].split(",") if v.strip()]
        else:
            fm[key.strip()] = val
    return fm


def main() -> int:
    # 1. sources.json
    try:
        index = json.loads((CORPUS_DIR / "sources.json").read_text())
    except (OSError, json.JSONDecodeError) as e:
        print(f"FATAL: cannot load sources.json: {e}", file=sys.stderr)
        return 1

    source_ids: set[str] = set()
    for src in index.get("sources", []):
        missing = REQUIRED_SOURCE_FIELDS - src.keys()
        if missing:
            err(f"sources.json: source {src.get('id', '?')} missing fields {sorted(missing)}")
        if src.get("id") in source_ids:
            err(f"sources.json: duplicate source id {src['id']}")
        source_ids.add(src.get("id", "?"))

    # 2. corpus_files index vs directory contents
    indexed = {cf["file"]: cf for cf in index.get("corpus_files", [])}
    on_disk = {p.name for p in CORPUS_DIR.glob("*.md")}
    for f in indexed.keys() - on_disk:
        err(f"sources.json: indexed file {f} does not exist")
    for f in on_disk - indexed.keys():
        err(f"{f}: exists on disk but is not indexed in sources.json corpus_files")

    # 3 + 4. per-file front-matter and inline citations
    for fname, entry in indexed.items():
        path = CORPUS_DIR / fname
        if not path.exists():
            continue
        text = path.read_text()
        fm = parse_front_matter(text, fname)
        missing = REQUIRED_FRONT_MATTER - fm.keys()
        if missing:
            err(f"{fname}: front-matter missing keys {sorted(missing)}")
        if fm.get("id") != entry["primary_id"]:
            err(f"{fname}: front-matter id {fm.get('id')!r} != corpus_files primary_id {entry['primary_id']!r}")
        declared = set(fm.get("additional_source_ids", []) or [])
        if fm.get("id") in source_ids:
            declared.add(str(fm["id"]))
        for sid in declared - source_ids:
            err(f"{fname}: front-matter references unknown source id {sid!r}")
        cited = set(CITE_RE.findall(text))
        for sid in cited - source_ids:
            err(f"{fname}: inline citation [cite: {sid}] does not resolve to a source in sources.json")
        for sid in cited - declared:
            err(f"{fname}: cites {sid!r} but does not declare it in front-matter (id/additional_source_ids)")

    # 5. egress_thresholds.json
    try:
        thresholds = json.loads((CORPUS_DIR / "egress_thresholds.json").read_text())
    except (OSError, json.JSONDecodeError) as e:
        print(f"FATAL: cannot load egress_thresholds.json: {e}", file=sys.stderr)
        return 1

    def check_threshold(name: str, t: dict) -> None:
        if t.get("source_doc_id") not in source_ids:
            err(f"egress_thresholds.json: {name}: source_doc_id {t.get('source_doc_id')!r} not in sources.json")
        numeric = {k: v for k, v in t.items() if k.startswith("value_")}
        if not numeric:
            err(f"egress_thresholds.json: {name}: no value_* fields")
        for k, v in numeric.items():
            if not isinstance(v, (int, float)) or v <= 0:
                err(f"egress_thresholds.json: {name}.{k}: expected positive number, got {v!r}")
        pairs = [("value_sqft", "value_m2", SQFT_TO_M2), ("value_in", "value_m", IN_TO_M)]
        for imp, met, factor in pairs:
            if imp in numeric and met in numeric:
                expected = numeric[imp] * factor
                if abs(expected - numeric[met]) / expected > 0.01:
                    err(
                        f"egress_thresholds.json: {name}: {imp}={numeric[imp]} converts to "
                        f"{expected:.4f}, but {met}={numeric[met]} (>1% off)"
                    )

    for section, body in thresholds.items():
        if not isinstance(body, dict):
            continue
        if "source_doc_id" in body:  # leaf section like rooms_requiring_escape_opening
            if body["source_doc_id"] not in source_ids:
                err(f"egress_thresholds.json: {section}: source_doc_id {body['source_doc_id']!r} not in sources.json")
            continue
        for name, t in body.items():
            if isinstance(t, dict):
                check_threshold(f"{section}.{name}", t)

    # 6. object_hazard_thresholds.json
    oht_path = CORPUS_DIR / "object_hazard_thresholds.json"
    if oht_path.exists():
        try:
            oht = json.loads(oht_path.read_text())
        except (OSError, json.JSONDecodeError) as e:
            print(f"FATAL: cannot load object_hazard_thresholds.json: {e}", file=sys.stderr)
            return 1

        # 6a. cited thresholds: source_doc_id must resolve, imperial↔metric consistency
        for name, entry in oht.get("cited", {}).items():
            if not isinstance(entry, dict):
                continue
            sid = entry.get("source_doc_id")
            if sid not in source_ids:
                err(f"object_hazard_thresholds.json: cited.{name}: source_doc_id {sid!r} not in sources.json")
            # imperial↔metric consistency checks
            pairs = [("value_ft", "value_m", FT_TO_M), ("value_in", "value_m", IN_TO_M)]
            for imp, met, factor in pairs:
                if imp in entry and met in entry:
                    expected = entry[imp] * factor
                    actual = entry[met]
                    if abs(expected - actual) / expected > 0.01:
                        err(
                            f"object_hazard_thresholds.json: cited.{name}: {imp}={entry[imp]} converts to "
                            f"{expected:.4f}, but {met}={actual} (>1% off)"
                        )

        # 6b. engineering_constants: each must have a non-empty 'basis' string
        for name, entry in oht.get("engineering_constants", {}).items():
            if not isinstance(entry, dict):
                continue
            basis = entry.get("basis")
            if not basis or not isinstance(basis, str) or not basis.strip():
                err(f"object_hazard_thresholds.json: engineering_constants.{name}: missing or empty 'basis' string")
            val = entry.get("value")
            if val is None or not isinstance(val, (int, float)):
                err(f"object_hazard_thresholds.json: engineering_constants.{name}: missing or non-numeric 'value'")

    # 7. prevention_tips.json
    tips_path = CORPUS_DIR / "prevention_tips.json"
    n_tips = 0
    if tips_path.exists():
        try:
            tips_doc = json.loads(tips_path.read_text())
        except (OSError, json.JSONDecodeError) as e:
            print(f"FATAL: cannot load prevention_tips.json: {e}", file=sys.stderr)
            return 1

        tips = tips_doc.get("tips")
        if not isinstance(tips, list):
            err("prevention_tips.json: 'tips' must be a list")
            tips = []
        n_tips = len(tips)

        seen_ids: set[str] = set()
        for i, tip in enumerate(tips):
            where = f"prevention_tips.json: tips[{i}]"
            if not isinstance(tip, dict):
                err(f"{where}: expected an object, got {type(tip).__name__}")
                continue
            where = f"prevention_tips.json: {tip.get('id', f'tips[{i}]')}"

            missing = REQUIRED_TIP_FIELDS - tip.keys()
            if missing:
                err(f"{where}: missing fields {sorted(missing)}")

            tid = tip.get("id")
            if tid in seen_ids:
                err(f"{where}: duplicate tip id {tid!r}")
            elif isinstance(tid, str):
                seen_ids.add(tid)

            if tip.get("peril") not in PERILS:
                err(f"{where}: peril {tip.get('peril')!r} not one of {sorted(PERILS)}")

            text = tip.get("text")
            if not isinstance(text, str) or not text.strip():
                err(f"{where}: 'text' must be a non-empty string")

            cite = tip.get("cite")
            if cite not in source_ids:
                err(f"{where}: cite {cite!r} does not resolve to a source in sources.json")

    if errors:
        print(f"CORPUS INVALID — {len(errors)} problem(s):", file=sys.stderr)
        for e in errors:
            print(f"  - {e}", file=sys.stderr)
        return 1
    n_md = len(on_disk)
    n_threshold_files = sum(1 for f in ["egress_thresholds.json", "object_hazard_thresholds.json"]
                            if (CORPUS_DIR / f).exists())
    print(f"Corpus valid: {len(source_ids)} sources, {n_md} corpus files, "
          f"{n_threshold_files} threshold file(s) consistent, {n_tips} prevention tips.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
