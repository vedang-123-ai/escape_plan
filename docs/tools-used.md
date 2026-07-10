# Tools used

Every library, framework, API, and tool used in this project — required for Congressional App Challenge originality documentation. Includes our AI-assisted development process (Claude Code is used as a pair programmer; all output is reviewed, tested, and understood by the team).

| Tool | Version | What it's used for | License |
|------|---------|--------------------|---------|
| Xcode / Swift / SwiftUI | Xcode 16+ | iOS app | Apple SDK |
| Claude Code | — | AI pair-programming assistant (P3 lane + support); all code reviewed and understood by the team | Anthropic ToS |
| git / GitHub | — | Version control, private repo `vedang-123-ai/escape_plan` | — |
| Python 3 (stdlib only, so far) | 3.11+ | `backend/corpus/validate.py` corpus validation script | PSF |

## Content sources (grounding corpus, not code dependencies)

Full index with URLs and retrieval dates: `backend/corpus/sources.json`. Orgs: NFPA (escape planning, smoke-alarm fire statistics, disability evacuation guide), USFA/FEMA (smoke alarms, escape plans, disability fire safety), American Red Cross (escape plan steps, two-minute campaign, planning fact sheet), ICC (2021 IRC §R310/§R311 egress requirements). All corpus content is paraphrased with per-claim citations.
