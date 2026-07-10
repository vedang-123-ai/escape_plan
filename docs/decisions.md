# Decisions log

Running log of deviations from playbook defaults, and why. Newest first.

| Date | Session | Decision | Why |
|------|---------|----------|-----|
| 2026-07-10 | S0.4 | Corpus is ~8 dense pages, under the playbook's 15–25 page target | Dense structured guidance beats padded prose for prompt grounding; every planned topic is covered. Expand in S3.1 if explanation quality demands it. |
| 2026-07-10 | S0.4 | Added `validate.py` (stdlib-only) in `backend/corpus/` | "Thresholds file validates" acceptance needs a checkable definition; stdlib-only because the Python env isn't scaffolded until S1.6. Checks source resolution, front-matter, inline `[cite:]` tags, and imperial↔metric consistency (1% tolerance). |
| 2026-07-10 | S0.4 | Citation convention: inline `[cite: source-id]` tags; compilation docs (`fire-facts-stats`, `special-considerations`) have non-source primary ids | Gives S3.1's citation validator an exact, greppable format; compilation docs only ever cite underlying external sources. |
| 2026-07-10 | S0.4 | Thresholds carry both imperial (as codified) and metric values; metric is authoritative for computation | HomeModel schema is in meters; imperial preserved so citations match the code text judges can check. |
| 2026-07-10 | S0.1 | Xcode project stays at repo root (`escape_plan/`, `escape_plan.xcodeproj`) instead of `ios/EscapePlan/` for now | Project was created before the monorepo layout was adopted; moving it mid-session breaks the open Xcode workspace. Revisit before Phase 1 iOS work (S0.3) — P2 can relocate it when scaffolding, or we keep root placement and document it. |
| 2026-07-10 | S0.1 | Repo/init tasks executed by P3 (Claude Code) rather than P1 | Team assigned P3's full lane to Claude Code; P1 asked for the init to be done now. |
