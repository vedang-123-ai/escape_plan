#!/usr/bin/env python3
"""Re-fetch every source URL in sources.json and check it still says what we cite it for.

**This is NOT part of the gate.** `validate.py` stays offline, fast and stdlib-only so it
can run anywhere; this script talks to the network and is run by hand when adding or
re-verifying a source. Never wire it into validate.py.

Why it exists (S11.1): `validate.py` checks that a `[cite: id]` *resolves* to an entry in
sources.json. It cannot check that the claim is actually *on* the cited page. Four
earthquake/tornado claims were found in 2026-09-21 attributed to pages that never carried
them. This script closes the machine-checkable half of that gap: the URL still resolves,
and the words we rely on are still in the text.

Per-source `verify_keywords` in sources.json drive the content check. A source with no
keywords is fetched and status-checked only, and is reported as UNVERIFIED.

Usage:
    python3 backend/corpus/check_urls.py                 # all sources
    python3 backend/corpus/check_urls.py --id noaa-tornado --id fema-tornado
    python3 backend/corpus/check_urls.py --json          # machine-readable
    python3 backend/corpus/check_urls.py --stale-days 90 # flag old retrieved dates

Exit 0 = every requested source returned 200 and matched its keywords.
Exit 1 = at least one fetch failed or lost a keyword.
"""
from __future__ import annotations

import argparse
import datetime as dt
import html
import json
import re
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

CORPUS_DIR = Path(__file__).parent
SOURCES = CORPUS_DIR / "sources.json"

# redcross.org 403s a plain urllib request but serves curl with a browser UA fine.
BROWSER_UA = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 "
    "(KHTML, like Gecko) Chrome/130.0 Safari/537.36"
)
TIMEOUT = 30


def to_text(raw: bytes) -> str:
    """Bytes -> searchable text. PDFs are returned empty: we can check they serve, not what they say."""
    if raw[:5] == b"%PDF-":
        return ""
    decoded = raw.decode("utf-8", "replace")
    text = re.sub(r"(?is)<(script|style|noscript|svg)\b.*?</\1>", " ", decoded)
    text = re.sub(r"(?s)<[^>]+>", " ", text)
    text = html.unescape(text)
    return re.sub(r"\s+", " ", text).strip()


def fetch(url: str) -> tuple[int, str, str]:
    """Return (status, text, how). Tries urllib, falls back to curl for 403/blocked hosts."""
    req = urllib.request.Request(url, headers={"User-Agent": BROWSER_UA})
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return resp.status, to_text(resp.read()), "urllib"
    except urllib.error.HTTPError as e:
        status = e.code
    except Exception:  # noqa: BLE001 - network is allowed to fail in any shape here
        status = 0

    # Fallback: curl with a browser UA, following redirects. Binary capture on purpose --
    # PDFs and mis-declared charsets are not valid UTF-8 and must not crash the run.
    try:
        proc = subprocess.run(
            ["curl", "-sS", "-L", "-A", BROWSER_UA, "--max-time", str(TIMEOUT),
             "-w", "\n__HTTP_STATUS__%{http_code}", url],
            capture_output=True, timeout=TIMEOUT + 10,
        )
    except (subprocess.SubprocessError, OSError) as e:
        return status, "", f"curl failed: {e}"

    out = proc.stdout
    m = re.search(rb"\n__HTTP_STATUS__(\d+)$", out)
    if not m:
        return status, "", "curl (no status)"
    return int(m.group(1)), to_text(out[: m.start()]), "curl"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--id", action="append", dest="ids", help="check only these source ids (repeatable)")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--stale-days", type=int, default=0, help="warn when retrieved is older than N days")
    args = ap.parse_args()

    index = json.loads(SOURCES.read_text())
    sources = index.get("sources", [])
    if args.ids:
        wanted = set(args.ids)
        unknown = wanted - {s.get("id") for s in sources}
        if unknown:
            print(f"unknown source id(s): {sorted(unknown)}", file=sys.stderr)
            return 1
        sources = [s for s in sources if s.get("id") in wanted]

    today = dt.date.today()
    results: list[dict[str, object]] = []
    failures = 0

    for src in sources:
        sid, url = src.get("id", "?"), src.get("url", "")
        keywords = src.get("verify_keywords") or []
        status, text, how = fetch(url)
        lowered = text.lower()
        missing = [k for k in keywords if k.lower() not in lowered]

        ok = status == 200 and not missing
        if not ok:
            failures += 1

        stale = None
        if args.stale_days:
            try:
                age = (today - dt.date.fromisoformat(str(src.get("retrieved")))).days
                if age > args.stale_days:
                    stale = age
            except (TypeError, ValueError):
                stale = -1  # unparseable retrieved date

        results.append({
            "id": sid, "url": url, "status": status, "via": how,
            "chars": len(text), "keywords": len(keywords),
            "missing_keywords": missing,
            "verified": bool(keywords) and ok,
            "stale_days": stale,
        })

        if not args.json:
            if status != 200:
                mark, detail = "FAIL", f"HTTP {status} via {how}"
            elif not text:
                mark, detail = "NO-TEXT", "200 but no extractable text (PDF or JS-rendered)"
            elif missing:
                mark, detail = "DRIFT", f"200 but missing {missing}"
            elif not keywords:
                mark, detail = "UNVERIFIED", f"200, {len(text)} chars, no verify_keywords set"
            else:
                mark, detail = "ok", f"200, {len(keywords)} keyword(s) present"
            if stale:
                detail += f" · retrieved {stale} days ago" if stale > 0 else " · unparseable retrieved date"
            print(f"  [{mark:10}] {sid:34} {detail}")

    if args.json:
        print(json.dumps({"checked": len(results), "failures": failures, "results": results}, indent=2))
    else:
        verified = sum(1 for r in results if r["verified"])
        print(f"\n{len(results)} source(s) checked · {verified} content-verified · {failures} problem(s)")

    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
