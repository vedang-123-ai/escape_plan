#!/usr/bin/env python3
"""Check that the deployed backend is actually demo-ready. Run this BEFORE filming.

    python3 scripts/demo-preflight.py                    # deployed backend
    python3 scripts/demo-preflight.py --base-url http://127.0.0.1:8000

Stdlib only, no server-side dependencies — it talks to the deployed service the way the
app does, so it fails for the same reasons the app would.

Every failure this catches has already happened at least once in this project and would
have gone straight into the video:

- the shared bearer token missing from `escape_plan/BackendConfig.local.json`, which the
  app surfaces as "The server didn't accept the access token"
- `ANTHROPIC_API_KEY` never set in the Render dashboard, so every AI endpoint 502s in
  production while working perfectly on localhost
- the Anthropic account running out of credit (found 2026-08-04) — the deterministic half
  keeps working, so nothing looks wrong until the assistant is on screen
- Render free-tier cold start: the first request after ~15 min idle takes ~50 s while the
  service wakes, which on camera reads as "the app is broken"

Exit codes: 0 ready to film · 1 something is not.
"""

from __future__ import annotations

import argparse
import json
import os
import ssl
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]
DEPLOYED = "https://escape-plan-backend.onrender.com"
CONFIG = REPO / "escape_plan" / "BackendConfig.local.json"
FIXTURE = REPO / "schema" / "fixtures" / "bungalow.json"
DOTENV = REPO / ".env"

# Render free tier spins the service down when idle; the wake-up is the slow part, not
# the request. Anything past this on /health means a cold start, not a broken service.
COLD_START_SECONDS = 5.0

GREEN, RED, YELLOW, DIM, RESET = "\033[32m", "\033[31m", "\033[33m", "\033[2m", "\033[0m"
if not sys.stdout.isatty():
    GREEN = RED = YELLOW = DIM = RESET = ""

failures: list[str] = []
warnings: list[str] = []


def tls_context() -> ssl.SSLContext:
    """A context that actually has root certificates.

    python.org builds on macOS ship without a usable system trust store unless
    `Install Certificates.command` has been run, so a plain
    `ssl.create_default_context()` fails CERTIFICATE_VERIFY_FAILED against a perfectly
    healthy backend — a false alarm that looks exactly like "the server is down".
    certifi is already in the environment (requests/anthropic pull it in); fall back to
    the system store when it isn't.
    """
    try:
        import certifi

        return ssl.create_default_context(cafile=certifi.where())
    except ImportError:
        return ssl.create_default_context()


CONTEXT = tls_context()


def ok(label: str, detail: str = "") -> None:
    print(f"{GREEN}  PASS{RESET}  {label}{DIM}{'  ' + detail if detail else ''}{RESET}")


def fail(label: str, detail: str, fix: str) -> None:
    print(f"{RED}  FAIL{RESET}  {label}\n        {detail}\n        {DIM}fix: {fix}{RESET}")
    failures.append(label)


def warn(label: str, detail: str) -> None:
    print(f"{YELLOW}  WARN{RESET}  {label}\n        {DIM}{detail}{RESET}")
    warnings.append(label)


def post(base: str, path: str, token: str, payload: dict, timeout: float = 120.0):
    """POST JSON. Returns (status, parsed-or-text, seconds)."""
    request = urllib.request.Request(
        f"{base}{path}",
        data=json.dumps(payload).encode(),
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"},
        method="POST",
    )
    started = time.monotonic()
    try:
        with urllib.request.urlopen(request, timeout=timeout, context=CONTEXT) as response:
            return response.status, json.loads(response.read()), time.monotonic() - started
    except urllib.error.HTTPError as exc:
        body = exc.read().decode(errors="replace")
        try:
            body = json.loads(body).get("detail", body)
        except json.JSONDecodeError:
            pass
        return exc.code, body, time.monotonic() - started
    except Exception as exc:  # noqa: BLE001 — DNS, TLS, timeout all land here
        return 0, f"{type(exc).__name__}: {exc}", time.monotonic() - started


# ---------------------------------------------------------------------------


def check_local_config() -> str | None:
    print("\nLocal configuration")
    token = None
    # The app can only read BackendConfig.local.json, so its absence is always a FAIL —
    # but an env token still lets the endpoint checks below run, which is what you want
    # when pointing at a local backend you started yourself.
    env_token = os.environ.get("BACKEND_BEARER_TOKEN") or None
    if not CONFIG.exists():
        fail("app bearer token", f"{CONFIG.relative_to(REPO)} does not exist",
             'create it: {"bearer_token": "<the shared token>"} — gitignored, per-machine')
    else:
        try:
            token = json.loads(CONFIG.read_text()).get("bearer_token") or None
        except json.JSONDecodeError as exc:
            fail("app bearer token", f"{CONFIG.name} is not valid JSON: {exc}", "fix the JSON")
        if token:
            ok("app bearer token", f"{CONFIG.name} ({len(token)} chars)")
        elif CONFIG.exists():
            fail("app bearer token", f"{CONFIG.name} has no non-empty `bearer_token`",
                 "add the key, or the app shows the token banner on camera")

    if token is None and env_token:
        warn("using $BACKEND_BEARER_TOKEN for the endpoint checks",
             "the app itself cannot read an env var — it still needs the JSON file above")
        token = env_token

    if DOTENV.exists() and "ANTHROPIC_API_KEY" in DOTENV.read_text():
        ok("ANTHROPIC_API_KEY in .env", "local AI + the -m live suite can run")
    else:
        warn("ANTHROPIC_API_KEY not in ./.env",
             "only affects local runs and `pytest -m live`; the deployed backend reads "
             "its own Render env var, checked below")
    return token


def check_health(base: str) -> None:
    print("\nBackend reachability")
    started = time.monotonic()
    try:
        with urllib.request.urlopen(f"{base}/health", timeout=120, context=CONTEXT) as response:
            elapsed = time.monotonic() - started
            body = json.loads(response.read())
    except Exception as exc:  # noqa: BLE001
        if "CERTIFICATE_VERIFY_FAILED" in str(exc):
            fail("/health", f"TLS trust store problem on THIS machine, not the backend: {exc}",
                 "run `pip install certifi`, or the `Install Certificates.command` in your "
                 "Python.app folder. The iPhone uses the system trust store and is unaffected.")
        else:
            fail("/health", f"{type(exc).__name__}: {exc}",
                 f"is {base} deployed and awake? check the Render dashboard")
        return
    # Deliberately NOT printing body["version"]: that is a hardcoded FastAPI `app.version`
    # ("1.0") and says nothing about what code is deployed. On 2026-09-07 it was read as
    # evidence of a stale backend and cost a wrong diagnosis. check_deployed_schema() below
    # asks a question whose answer actually moves.
    ok("/health", f"{body.get('status')} in {elapsed:.1f}s")
    if elapsed > COLD_START_SECONDS:
        warn("cold start",
             f"/health took {elapsed:.0f}s — the free-tier service was asleep. Hit the "
             "backend a few minutes before filming so the first on-camera request is warm.")


def check_deployed_schema(base: str) -> None:
    """Is the DEPLOYED code current, or is Render serving something older than this checkout?

    A stale deploy is invisible until a real client posts a document the old models reject,
    which on camera reads as "Score unavailable". /openapi.json needs no auth, so this runs
    even when the bearer token is missing.
    """
    local = "unknown"
    schema_file = REPO / "schema" / "homemodel.schema.json"
    try:
        local_doc = json.loads(schema_file.read_text())
        enum = local_doc.get("properties", {}).get("schema_version", {})
        local = enum.get("const") or (enum.get("enum") or ["unknown"])[-1]
    except Exception:  # noqa: BLE001
        pass

    try:
        with urllib.request.urlopen(f"{base}/openapi.json", timeout=60, context=CONTEXT) as resp:
            spec = json.loads(resp.read())
    except Exception as exc:  # noqa: BLE001
        warn("deployed schema", f"could not read /openapi.json: {type(exc).__name__}: {exc}")
        return

    schemas = spec.get("components", {}).get("schemas", {})
    prop = schemas.get("HomeModel", {}).get("properties", {}).get("schema_version", {})
    deployed = prop.get("const") or (prop.get("enum") or ["unknown"])[-1]
    routes = sorted(spec.get("paths", {}))

    if deployed == local:
        ok("deployed schema", f"schema_version {deployed}, {len(routes)} routes — matches this checkout")
    else:
        fail("deployed schema",
             f"deployed serves schema_version {deployed}, this checkout is {local}",
             "Render is behind. push to the branch Render builds (or redeploy from the "
             "dashboard), then re-run. A current client will 422 against the old models.")


def check_deterministic(base: str, token: str) -> dict | None:
    print("\nDeterministic half (must work with or without AI)")
    home = json.loads(FIXTURE.read_text())
    status, body, elapsed = post(base, "/routes", token, {"home": home})
    if status == 401 or status == 403:
        fail("/routes", f"HTTP {status}: {body}",
             "the token in BackendConfig.local.json does not match BACKEND_BEARER_TOKEN "
             "on the server")
        return None
    if status != 200:
        fail("/routes", f"HTTP {status}: {body}", "the routing engine is broken — this is the "
                                                  "one thing that cannot be cut")
        return None
    rooms = body.get("rooms", [])
    routed = sum(1 for r in rooms if r.get("primary"))
    secondary = sum(1 for r in rooms if r.get("secondary"))
    ok("/routes", f"{routed}/{len(rooms)} rooms with a primary route "
                  f"({secondary} with a backup) in {elapsed:.1f}s")
    if routed < len(rooms):
        warn("unrouted rooms",
             f"{len(rooms) - routed} room(s) have no primary route. Legitimate on a fixture "
             "seeded with a plantable hazard, alarming on the home you plan to film.")

    status, score, elapsed = post(base, "/score", token, {"home": home})
    if status == 200:
        ok("/score", f"score {score.get('score', '?')} in {elapsed:.1f}s")
    else:
        warn("/score", f"HTTP {status}: {score}")
    return body


def check_ai(base: str, token: str, home: dict, plan: dict) -> None:
    print("\nAI half (the part that has been dead since 2026-08-04)")
    status, body, elapsed = post(base, "/explain", token, {"home": home, "route_plan": plan})
    if status == 200:
        text = json.dumps(body)
        ok("/explain", f"200 in {elapsed:.0f}s, {len(text)} chars")
        if elapsed > 6:
            warn("/explain latency",
                 f"{elapsed:.0f}s — the <6s target is formally unmet and deferred "
                 "(decisions.md 2026-07-23). Fine for an edited video, not for live judging.")
        return
    if status == 502:
        fail("/explain", f"HTTP 502: {body}",
             "502 means an operator must act — almost always no Anthropic credit, or "
             "ANTHROPIC_API_KEY missing from the Render dashboard. Top up at "
             "console.anthropic.com, then Render → escape-plan-backend → Environment.")
    elif status == 503:
        fail("/explain", f"HTTP 503: {body}",
             "503 is retryable (rate limit / overload). Wait and re-run this script.")
    else:
        fail("/explain", f"HTTP {status}: {body}", "unexpected — check the Render logs")


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--base-url", default=DEPLOYED)
    parser.add_argument("--skip-ai", action="store_true",
                        help="skip /explain (it costs tokens and takes ~30s)")
    args = parser.parse_args()
    base = args.base_url.rstrip("/")

    print(f"Demo preflight against {base}")
    token = check_local_config()
    check_health(base)
    check_deployed_schema(base)

    if token:
        plan = check_deterministic(base, token)
        if plan and not args.skip_ai:
            check_ai(base, token, json.loads(FIXTURE.read_text()), plan)
        elif plan:
            warn("AI check skipped", "--skip-ai was passed; the assistant is unverified")
    else:
        warn("endpoint checks skipped", "no bearer token to authenticate with")

    print("\n" + "=" * 62)
    if failures:
        print(f"{RED}NOT READY TO FILM{RESET} — {len(failures)} failing: "
              f"{', '.join(failures)}")
        return 1
    if warnings:
        print(f"{YELLOW}Ready, with {len(warnings)} warning(s) worth reading.{RESET}")
    else:
        print(f"{GREEN}Ready to film.{RESET}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
