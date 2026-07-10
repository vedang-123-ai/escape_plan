---
id: special-considerations
org: NFPA / USFA (compiled guidance)
doc_title: Escape planning for children, older adults, people with disabilities, and pets
url: https://www.usfa.fema.gov/prevention/home-fires/at-risk-audiences/people-with-disabilities/
retrieved: 2026-07-10
topics: [profiles, children, older-adults, mobility, disabilities, pets]
additional_source_ids: [usfa-disabilities, nfpa-evacuation-disabilities, nfpa-escape-planning, usfa-smoke-alarms, redcross-escape-plan]
---

# Special considerations for household members (profile-aware guidance)

This document grounds the family-profiles feature (S3.4): how routes and advice change for children, older adults, people with mobility limitations, and pets. Paraphrased from USFA fire safety for people with disabilities [cite: usfa-disabilities], NFPA's Emergency Evacuation Planning Guide for People with Disabilities [cite: nfpa-evacuation-disabilities], and NFPA escape planning guidance [cite: nfpa-escape-planning].

## People with mobility limitations (wheelchair, walker)

- **Check every exit for passability**: doorways must be wide enough for the wheelchair/walker, and a ramp may be needed for emergency exits with steps. [cite: usfa-disabilities]
- **Sleep near an accessible exit**, ideally on the ground floor, to shorten and simplify the escape route. [cite: usfa-disabilities]
- Know the safest and quickest exit based on physical capability — stairs and window egress are generally not usable routes for a wheelchair user. [cite: usfa-disabilities]
- Involve the person in planning: they know their capabilities and needs best. [cite: nfpa-evacuation-disabilities]
- Residential fire sprinklers give people with mobility limitations significantly more time to escape and are strongly recommended where feasible. [cite: nfpa-evacuation-disabilities]

**App mapping (deterministic, documented in S3.4):** `mobility_limited` → routing constraints `avoid_stairs` + `avoid_windows`. If no viable route exists under these constraints, the app surfaces a high-severity "no accessible escape route" finding rather than silently showing an unusable route.

## Children

- Children should **master the escape plan in daytime practice** before drills are run at night while they sleep. [cite: nfpa-escape-planning]
- Draw the floor-plan map with two ways out of each room together with children so they internalize it. [cite: nfpa-escape-planning]
- Plan for an adult to assist young children; children may not wake to a smoke alarm, so assign a specific adult to each young child in the plan. [cite: nfpa-escape-planning]

**App mapping:** `child` → route explanations default to accompanied-by-adult phrasing; window egress deprioritized in route weighting.

## Older adults

- Make arrangements in the escape plan matched to each person's abilities — e.g. sleeping location near an exit and assigned assistance. [cite: nfpa-escape-planning]
- Hearing considerations: for anyone deaf or hard of hearing, use smoke alarms with strobe lights and bed-shaker/vibrating accessories so alarms actually wake them. [cite: usfa-smoke-alarms]

**App mapping:** `elderly` → prefer stair-free routes where available; recommendations include alarm-audibility and assigned-helper checklist items.

## Pets

- **Never delay escape or re-enter a burning home for pets.** Tell firefighters about pets still inside. [cite: redcross-escape-plan]
- Include pets in the plan (who grabs the leash/carrier if immediately at hand on the way out) but people escape first. [cite: redcross-escape-plan]

**App mapping:** `pet` → checklist items (leash/carrier near exit, pet-alert practice) and explanation phrasing; pets never alter route computation.

## General rule for the AI layer

Advice for a specific profile must come from this document (or another corpus doc) — never improvised. If a user's situation isn't covered (e.g. medical equipment dependencies), the assistant should say the corpus doesn't cover it and recommend consulting the local fire department, which offers home safety visits. [cite: nfpa-evacuation-disabilities]
