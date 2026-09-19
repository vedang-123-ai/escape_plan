---
handoff_status: active
handoff_owner: Anish Yarrakonda
handoff_opened: 2026-09-18
---

# START HERE: the S11 arc

> **The board is [`tracker/BLOCKERS.md`](tracker/BLOCKERS.md).** Status lives there. This file is the
> five-minute brief. Set `handoff_status: closed` above when S11.13 ships (the session-start banner reads it).

## What happened

A firefighter told us the app is not a tool for firefighters to use mid-fire, and that it fits **prevention
and education**, with an opt-in snapshot a family can share with its department. We reframed the product
around readiness and prevention, kept the deterministic engine and the grounded AI, deepened the two thin
perils, and turned the remaining work into 13 sessions that three people run in parallel.
Read [`playbook/01-product-spec.md`](playbook/01-product-spec.md) for the why and the scope lock.

## What to do in the next five minutes

1. `git fetch origin && git switch main && git pull`. The baseline (`s11-0-baseline`) must be on `origin/main`
   before anyone branches; if it is not, ask the owner to push it.
2. Read [`playbook/README.md`](playbook/README.md): the lanes, the dependency map, the branch protocol.
3. Pick your lane and run `/session S11.<n>`. Lane A is backend and corpus. Lane B is iOS product surfaces.
   **Lane C needs the machine with the simulator and the physical iPhone 17 Pro.**
4. Work only on your session's branch. Never commit to `main`. Merge `--no-ff` after your gate is green.

## Things that will cost you an hour if you do not know them

- The deployed backend needs `escape_plan/BackendConfig.local.json` (gitignored) or a fresh install gets 401
  on everything. Ask the owner for the token. `python3 scripts/demo-preflight.py` checks readiness.
- The Anthropic account is out of credits, so `/explain`, `/analyze`, `/chat` and `/build` return 502. That is
  billing, not code. Only S11.4 works in that layer, and it does so without a key.
- SourceKit and VS Code cannot index this project; trust `xcodebuild` and `scripts/typecheck-ios.sh`.
- A red iOS run is about one-in-three environmental flake. Re-run once before believing it. True counts come
  from `xcrun xcresulttool get test-results summary --path <bundle>`.
- Never re-enable `allowsCameraControl`; keep `CameraRigModel` free of SceneKit and UIKit.
- No new colours: `Theme.swift` is the semantic scale, and route orange is for lit routes and exits only.

## History you can recover

`archive/playbook-v1` holds the old 65-file playbook, `archive/pre-s11-main` and `archive/pre-s11-origin` the
two sides of the merge, and `archive/s8-cloud-sync` the accounts arc before it was demoted.
