# Decisions log

Running log of deviations from playbook defaults, and why. Newest first.

| Date | Session | Decision | Why |
|------|---------|----------|-----|
| 2026-07-10 | S0.1 | Xcode project stays at repo root (`escape_plan/`, `escape_plan.xcodeproj`) instead of `ios/EscapePlan/` for now | Project was created before the monorepo layout was adopted; moving it mid-session breaks the open Xcode workspace. Revisit before Phase 1 iOS work (S0.3) — P2 can relocate it when scaffolding, or we keep root placement and document it. |
| 2026-07-10 | S0.1 | Repo/init tasks executed by P3 (Claude Code) rather than P1 | Team assigned P3's full lane to Claude Code; P1 asked for the init to be done now. |
