"""Deterministic checklist generation (pure; no I/O, no AI).

Items come from four deterministic sources — the HomeModel itself (smoke-alarm
placement per the corpus, shutoff presence, furniture securement), the routing
engine's findings (per-peril: fire, earthquake, tornado), the S3.2 agent's
findings, and household facts (tenure, equipment, profile tags) — plus fixed
practice and readiness items. Every item id is stable for a given (home, facts,
findings) so a done-state persisted on the home document survives recomputation.

Grounded AI recommendations are appended separately (app.scoring.recommend) and
are always non-scoring: the AI advises, it never moves the number.

S6.7 NOTE: New categories (shutoffs, safe_room, mitigation, supply_kit, alerts)
are all non-scoring in this session. S6.7 owns score reweighting and will need
to decide which of these categories earn points.
"""

from __future__ import annotations

from datetime import datetime
from typing import Literal, Optional, Sequence

from pydantic import BaseModel, ConfigDict, Field

from app.models import (
    Equipment,
    HomeModel,
    ObjectCategory,
    OpeningKind,
    ProfileTag,
    RoomType,
    SafetyPointKind,
)
from app.routing.egress import EgressThresholds, check_egress
from app.routing.plan import RoutePlan, RoomRoutePlan
from app.scoring.findings import Finding

ItemCategory = Literal[
    "smoke_alarm",
    "practice",
    "routes",
    "egress",
    "agent_finding",
    "recommendation",
    # S6.4 additions:
    "shutoffs",
    "safe_room",
    "mitigation",
    "supply_kit",
    "alerts",
]

HazardTag = Literal["fire", "earthquake", "severe_weather", "general"]

#: The two scoring components whose points are earned by *checking boxes*
#: (as opposed to fixing the model). See docs/preparedness-score-weights.md.
SMOKE_ALARM_COMPONENT = "smoke_alarms"
PRACTICE_COMPONENT = "practice"

ChecklistState = dict[str, bool | str]
"""item id -> done (bool) or ISO timestamp (str) for recurring items.
Persisted on the home document by the iOS app (S2.4).

For recurring items, the value may be an ISO 8601 timestamp string recording
when the item was last completed. The done state is then computed by comparing
that timestamp against the item's recurrence_days. A plain `True` is always
treated as "done at an unknown time" — fresh for non-recurring items, stale
for recurring ones (conservative: forces re-completion).
"""


class ChecklistItem(BaseModel):
    model_config = ConfigDict(extra="forbid")

    id: str
    category: ItemCategory
    hazard: HazardTag
    title: str
    detail: str
    why: str = Field(
        default="",
        description="One-line corpus-grounded justification shown under the item.",
    )
    done: bool = False
    source_citation: Optional[str] = Field(
        default=None,
        description="Corpus source id backing this item, when it makes a safety claim.",
    )
    scoring: bool = Field(
        description="True if checking this box moves the score by points_if_done."
    )
    component: Optional[str] = Field(
        default=None, description="Score component this item contributes to, if any."
    )
    severity: Literal["info", "low", "med", "high"] = "info"
    recurrence_days: Optional[int] = Field(
        default=None,
        description=(
            "If set, the item re-opens this many days after completion. "
            "ENGINEERING CHOICE for intervals not specified by the corpus."
        ),
    )


# ---------------------------------------------------------------------------
# Recurrence helper
# ---------------------------------------------------------------------------

def _is_done(
    item_id: str,
    state: ChecklistState,
    recurrence_days: int | None,
    now: datetime | None,
) -> bool:
    """Determine whether an item is currently done, respecting recurrence."""
    raw = state.get(item_id)
    if not raw:
        return False
    if recurrence_days is None:
        # Non-recurring: any truthy value = done.
        return bool(raw)
    # Recurring item.
    if now is None:
        # No clock provided — cannot evaluate staleness. Treat any truthy
        # value as done (backward compatible with callers that don't pass now).
        return bool(raw)
    if isinstance(raw, str):
        try:
            completed_at = datetime.fromisoformat(raw)
            elapsed = (now - completed_at).days
            return elapsed < recurrence_days
        except (ValueError, TypeError):
            return False
    # bool True on a recurring item with a clock = done at unknown time → stale.
    return False


# ---------------------------------------------------------------------------
# Existing generators (extended with hazard tags)
# ---------------------------------------------------------------------------


def _bedrooms(home: HomeModel) -> list[tuple[str, str, str]]:
    """(floor_id, room_id, room_name) for every bedroom, in document order."""
    return [
        (floor.id, room.id, room.name)
        for floor in home.floors
        for room in floor.rooms
        if room.type == RoomType.bedroom
    ]


def smoke_alarm_items(home: HomeModel, state: ChecklistState) -> list[ChecklistItem]:
    """Alarm placement + maintenance items, exactly as corpus/smoke-alarms-usfa.md
    prescribes: one per bedroom, one outside each sleeping area, one per level,
    plus the monthly test and the 10-year replacement."""
    bedrooms = _bedrooms(home)
    floors_with_bedrooms = {floor_id for floor_id, _, _ in bedrooms}
    items: list[ChecklistItem] = []

    def add(item_id: str, title: str, detail: str) -> None:
        items.append(
            ChecklistItem(
                id=item_id,
                category="smoke_alarm",
                hazard="fire",
                title=title,
                detail=detail,
                why="Working smoke alarms cut the home-fire death rate by ~55%. [cite: nfpa-smoke-alarms-report]",
                done=state.get(item_id, False) is True,
                source_citation="usfa-smoke-alarms",
                scoring=True,
                component=SMOKE_ALARM_COMPONENT,
            )
        )

    for _, room_id, room_name in bedrooms:
        add(
            f"alarm.bedroom.{room_id}",
            f"Smoke alarm inside {room_name}",
            "A working smoke alarm belongs inside every room used for sleeping.",
        )
    for floor in home.floors:
        if floor.id in floors_with_bedrooms:
            add(
                f"alarm.sleeping_area.{floor.id}",
                f"Smoke alarm outside the sleeping area on {floor.name}",
                "An alarm goes outside each separate sleeping area — the hallway "
                "serving the bedrooms.",
            )
    for floor in home.floors:
        add(
            f"alarm.level.{floor.id}",
            f"Smoke alarm on {floor.name}",
            "Every level of the home needs at least one smoke alarm.",
        )
    add(
        "alarm.test_monthly",
        "Test every smoke alarm this month",
        "Press the test button on every alarm once a month.",
    )
    add(
        "alarm.replace_10y",
        "Confirm no alarm is over 10 years old",
        "Replace every smoke alarm 10 years from its manufacture date.",
    )
    return items


def practice_items(
    state: ChecklistState, now: datetime | None = None
) -> list[ChecklistItem]:
    """The two fixed plan-practice items, plus the rescan item. Drill mode (S4.2)
    checks `practice.drill_recent` when a drill completes."""
    drill_recurrence = 183  # ENGINEERING CHOICE: ~6 months, twice-a-year cadence
    return [
        ChecklistItem(
            id="practice.meeting_point",
            category="practice",
            hazard="general",
            title="Pick an outside meeting place",
            detail="Choose one safe spot a distance from the home — a mailbox, a "
            "tree, a neighbor's porch — where everyone gathers after escaping.",
            why="A pre-agreed meeting point prevents re-entry to search for someone already safe. [cite: nfpa-escape-planning]",
            done=state.get("practice.meeting_point", False) is True,
            source_citation="nfpa-escape-planning",
            scoring=True,
            component=PRACTICE_COMPONENT,
        ),
        ChecklistItem(
            id="practice.drill_recent",
            category="practice",
            hazard="general",
            title="Practice the plan (twice a year)",
            detail="Run the drill with everyone in the household; the Red Cross "
            "benchmark is everyone at the meeting place in under two minutes.",
            why="Only ~26% of families have practiced their escape plan. [cite: redcross-escape-fact-sheet]",
            done=_is_done("practice.drill_recent", state, drill_recurrence, now),
            source_citation="nfpa-escape-planning",
            # Bug B fix (S6.7 merge, 2026-09-07): a lapsed/never-done drill must
            # flag staleness, never lower the score — same non-punitive rule as
            # rescan.home. See docs/preparedness-score-weights.md.
            scoring=False,
            component=PRACTICE_COMPONENT,
            recurrence_days=drill_recurrence,
        ),
        ChecklistItem(
            id="rescan.home",
            category="practice",
            hazard="general",
            title="Rescan your home to keep the model current",
            detail="Furniture moves, renovations happen. Rescan every ~6 months "
            "so the routes and checklist stay accurate.",
            why="Routes are computed from the scan; an outdated model produces outdated advice.",
            done=_is_done("rescan.home", state, drill_recurrence, now),
            source_citation=None,
            scoring=False,
            recurrence_days=drill_recurrence,
        ),
    ]


def route_items(
    plan: RoutePlan, state: ChecklistState
) -> list[ChecklistItem]:
    """Items mirroring the routing engine's structured findings.

    Non-scoring: these are fixed by changing the home (adding an egress window,
    unblocking a route) and re-running the engine, which moves the routes
    components on its own. Checking the box must never double-count.
    """
    hazard = _peril_to_hazard(plan.peril)
    items: list[ChecklistItem] = []
    for room in plan.rooms:
        for finding in room.findings:
            if finding.kind == "no_secondary_egress":
                title = f"Add a second way out of {room.room_name}"
                item_id = f"routes.{finding.kind}.{room.room_id}"
                citation = "nfpa-escape-planning"
                why = "Two ways out is NFPA's core escape-planning rule. [cite: nfpa-escape-planning]"
            elif finding.kind == "blocked_opening":
                blocked = "-".join(finding.object_ids) or "obstruction"
                item_id = f"routes.{finding.kind}.{room.room_id}.{blocked}"
                if any(oid.startswith("scan_") for oid in finding.object_ids):
                    title = "Something new is in your escape path"
                else:
                    title = f"Clear the way out of {room.room_name}"
                citation = "usfa-escape-plans"
                why = "A blocked exit doubles the time to escape. [cite: usfa-escape-plans]"
            elif finding.kind == "narrows_route":
                squeezed = "-".join(finding.object_ids) or "obstruction"
                item_id = f"routes.{finding.kind}.{room.room_id}.{squeezed}"
                if any(oid.startswith("scan_") for oid in finding.object_ids):
                    title = "Something new is in your escape path"
                else:
                    title = f"Widen the way out of {room.room_name}"
                citation = "usfa-escape-plans"
                why = "A tight exit slows evacuation, especially in the dark. [cite: usfa-escape-plans]"
            else:
                title = f"{room.room_name} has no usable way out"
                item_id = f"routes.{finding.kind}.{room.room_id}"
                citation = "nfpa-escape-planning"
                why = "Every room needs a viable escape route. [cite: nfpa-escape-planning]"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="routes",
                    hazard=hazard,
                    title=title,
                    detail=finding.detail,
                    why=why,
                    done=state.get(item_id, False) is True,
                    source_citation=citation,
                    scoring=False,
                )
            )
    return items


def egress_window_items(
    home: HomeModel, thresholds: EgressThresholds, state: ChecklistState
) -> list[ChecklistItem]:
    """Bedroom escape windows that fail IRC R310, checked deterministically."""
    items: list[ChecklistItem] = []
    for floor in home.floors:
        bedrooms = {r.id: r for r in floor.rooms if r.type == RoomType.bedroom}
        grade_floor = floor.level <= 0
        for opening in floor.openings:
            if opening.kind != OpeningKind.window:
                continue
            served = [rid for rid in opening.room_ids if rid in bedrooms]
            if not served:
                continue
            assessment = check_egress(opening, thresholds, grade_floor=grade_floor)
            if assessment.viable:
                continue
            room = bedrooms[served[0]]
            item_id = f"egress.window.{opening.id}"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="egress",
                    hazard="fire",
                    title=f"Escape window in {room.name} is too small to climb out of",
                    detail=(
                        "An emergency escape window in a sleeping room has to be "
                        "big enough to climb through: "
                        + "; ".join(assessment.reasons)
                        + "."
                    ),
                    why="IRC R310 requires sleeping rooms to have an emergency escape opening. [cite: irc-2021-r310]",
                    done=state.get(item_id, False) is True,
                    source_citation="irc-2021-r310",
                    scoring=False,
                )
            )
    return items


def finding_items(
    findings: Sequence[Finding], state: ChecklistState
) -> list[ChecklistItem]:
    """Items from the S3.2 agent's findings."""
    items: list[ChecklistItem] = []
    for index, finding in enumerate(findings):
        item_id = (
            f"agent_finding.{finding.id}" if finding.id else f"agent_finding.{index}"
        )
        items.append(
            ChecklistItem(
                id=item_id,
                category="agent_finding",
                hazard="general",
                title=finding.finding,
                detail=finding.recommendation,
                why=f"[cite: {finding.citation}]" if finding.citation else "",
                done=state.get(item_id, False) is True,
                source_citation=finding.citation,
                scoring=False,
                severity=finding.severity,
            )
        )
    return items


# ---------------------------------------------------------------------------
# S6.4 new generators
# ---------------------------------------------------------------------------

def _peril_to_hazard(peril: str) -> HazardTag:
    """Map a RoutePlan peril string to a HazardTag."""
    return {
        "fire": "fire",
        "tornado": "severe_weather",
        "earthquake": "earthquake",
    }.get(peril, "general")


def shutoff_items(home: HomeModel, state: ChecklistState) -> list[ChecklistItem]:
    """Items for floors missing gas shutoff or electrical panel safety points."""
    items: list[ChecklistItem] = []
    for floor in home.floors:
        sp_kinds = {sp.kind for sp in floor.safety_points}
        if SafetyPointKind.gas_shutoff not in sp_kinds:
            item_id = f"shutoffs.gas.{floor.id}"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="shutoffs",
                    hazard="earthquake",
                    title=f"Locate and tag your gas shutoff valve on {floor.name}",
                    detail=(
                        "Know where your gas shutoff is. Shut it off ONLY if you "
                        "suspect a leak — broken pipes, the smell or sound of gas, "
                        "or a meter spinning quickly. Never turn it back on "
                        "yourself: only the gas company can, after checking for "
                        "leaks."
                    ),
                    why=(
                        "Shutting the gas off is a judgement call with a named trigger; "
                        "turning it back on is never the resident's action. "
                        "[cite: shakeout-guidance-after] [cite: usgs-earthquake-donts]"
                    ),
                    done=state.get(item_id, False) is True,
                    source_citation="shakeout-guidance-after",
                    scoring=False,
                )
            )
        if SafetyPointKind.electrical_panel not in sp_kinds:
            item_id = f"shutoffs.electrical.{floor.id}"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="shutoffs",
                    hazard="general",
                    title=f"Locate and tag your electrical panel on {floor.name}",
                    detail=(
                        "Know where your electrical panel is. After shaking, shut "
                        "power off at the main breaker if there is any damage to "
                        "house wiring, and leave it off until the damage is repaired."
                    ),
                    why=(
                        "Damaged house wiring is the named trigger for killing power at "
                        "the main breaker. [cite: shakeout-guidance-after]"
                    ),
                    done=state.get(item_id, False) is True,
                    source_citation="shakeout-guidance-after",
                    scoring=False,
                )
            )
    return items


def safe_room_items(
    tornado_plan: RoutePlan | None,
    state: ChecklistState,
) -> list[ChecklistItem]:
    """Items derived from the tornado routing plan."""
    if tornado_plan is None:
        return []
    items: list[ChecklistItem] = []
    seen_no_viable = False
    has_shelter = False
    for room in tornado_plan.rooms:
        for finding in room.findings:
            if finding.kind == "no_viable_safe_room" and not seen_no_viable:
                seen_no_viable = True
                item_id = "safe_room.nearby_shelter"
                items.append(
                    ChecklistItem(
                        id=item_id,
                        category="safe_room",
                        hazard="severe_weather",
                        title="Identify a nearby sturdy building for tornado shelter",
                        detail=(
                            "No room in your home qualifies as a safe room. "
                            "Identify a nearby sturdy building (community shelter, "
                            "neighbor's basement) you can reach quickly, and do it "
                            "now rather than when a warning arrives."
                        ),
                        why=(
                            "Mobile, manufactured and trailer homes and RVs are not safe "
                            "in high wind events, so the plan has to be made in advance — "
                            "before a watch or warning is ever issued. "
                            "[cite: redcross-tornado] [cite: noaa-tornado-ww]"
                        ),
                        done=state.get(item_id, False) is True,
                        source_citation="redcross-tornado",
                        scoring=False,
                        severity="high",
                    )
                )
        if room.primary is not None:
            has_shelter = True

    if has_shelter and not seen_no_viable:
        item_id = "safe_room.know"
        items.append(
            ChecklistItem(
                id=item_id,
                category="safe_room",
                hazard="severe_weather",
                title="Know your tornado safe room",
                detail=(
                    "Your home's safe room has been identified by the engine. "
                    "Make sure every household member knows where to go when a "
                    "tornado warning is issued."
                ),
                why=(
                    "Go to the lowest floor, most interior room, with as many walls as "
                    "possible between you and the outside — a safe room or storm shelter "
                    "first, then a basement, then a small windowless interior room. "
                    "[cite: noaa-tornado] [cite: fema-tornado-ready]"
                ),
                done=state.get(item_id, False) is True,
                source_citation="noaa-tornado",
                # S11.2: scoring. Knowing where to go is the single completable
                # action tornado readiness turns on, and it was filed as advisory.
                scoring=True,
                severity="info",
            )
        )

        # Both of these only make sense once a safe room exists to go to.
        item_id = "safe_room.head_protection"
        items.append(
            ChecklistItem(
                id=item_id,
                category="safe_room",
                hazard="severe_weather",
                title="Keep head protection and something sturdy in your safe room",
                detail=(
                    "Put a bicycle or motorcycle helmet for each person in the safe "
                    "room, and know what you will get under — a heavy table, or a "
                    "mattress pulled over you."
                ),
                why=(
                    "Most injuries associated with high winds come from flying debris, "
                    "so protecting your head is the priority once you are sheltered. "
                    "[cite: noaa-tornado-shelter]"
                ),
                done=state.get(item_id, False) is True,
                source_citation="noaa-tornado-shelter",
                scoring=True,
                severity="info",
            )
        )

        item_id = "safe_room.practice_the_move"
        items.append(
            ChecklistItem(
                id=item_id,
                category="safe_room",
                hazard="severe_weather",
                title="Practise moving to your safe room with the whole household",
                detail=(
                    "Walk everyone through it, including anyone who needs help "
                    "getting there — the sources name a personal support team of "
                    "people you may assist and who can assist you."
                ),
                why=(
                    "Practising the move with the entire household is the sourced "
                    "instruction, and a personal support team is named alongside it. "
                    "[cite: redcross-tornado]"
                ),
                done=state.get(item_id, False) is True,
                source_citation="redcross-tornado",
                # Deliberately NOT recurring: docs/preparedness-score-weights.md
                # establishes that recurring items are non-punitive, and a scoring
                # recurring item would contradict that rule.
                scoring=True,
                severity="info",
            )
        )
    return items


from app.routing.object_hazards import ObjectHazardThresholds, analyze_object_hazards, ObjectHazard

def object_hazard_items(home: HomeModel, thresholds: ObjectHazardThresholds, state: ChecklistState) -> list[ChecklistItem]:
    hazards = analyze_object_hazards(home, thresholds)
    items: list[ChecklistItem] = []
    
    for h in hazards:
        item_id = f"hazard.{h.rule_id}.{h.object_id}"
        
        hazard_tag: HazardTag = "general"
        if h.rule_id in ("topple", "overhead", "water_heater_unsecured"):
            hazard_tag = "earthquake"
        elif h.rule_id == "heat_clearance":
            hazard_tag = "fire"
            
        done = state.get(item_id, False) is True
        
        if h.rule_id in ("topple", "water_heater_unsecured") and not done:
            generic_id = f"mitigation.secure.{h.object_id}"
            renter_id = f"{generic_id}.renter"
            if state.get(generic_id, False) is True or state.get(renter_id, False) is True:
                done = True

        title = f"Resolve hazard on {h.object_category} '{h.object_id}'"
        if h.rule_id == "topple":
            title = f"Secure {h.object_category} '{h.object_id}' to prevent toppling"
        elif h.rule_id == "overhead":
            title = f"Relocate heavy items from {h.object_category} '{h.object_id}'"
        elif h.rule_id == "heat_clearance":
            title = f"Move {h.object_category} '{h.object_id}' away from heat source"
        elif h.rule_id == "water_heater_unsecured":
            title = f"Strap water heater '{h.object_id}'"

        items.append(ChecklistItem(
            id=item_id,
            category="mitigation",
            hazard=hazard_tag,
            title=title,
            detail=h.detail,
            why=f"[cite: {h.citation}]",
            done=done,
            source_citation=h.citation,
            scoring=False,
            severity=h.severity,
        ))
    return items


def mitigation_items(home: HomeModel, state: ChecklistState, hazards: list[ObjectHazard] | None = None) -> list[ChecklistItem]:
    """Earthquake mitigation items for unsecured tall/heavy objects.

    Tenure-aware, but NOT because renters get a different fastener: they get the
    subset of actions that need no attachment. S11.1 (2026-09-21) established that
    ShakeOut names flexible nylon straps for *storage racks* and putty for *small
    objects*, and presents neither as a no-drill substitute for securing tall
    furniture — see backend/corpus/earthquake-securing-home.md, "What this corpus
    does not claim". Owners get the wall-stud instruction; renters get move-it-first.
    """
    is_renter = (
        home.household is not None and home.household.tenure is not None
        and home.household.tenure.value == "rent"
    )
    heavy_categories = {"wardrobe", "storage", "appliance"}
    items: list[ChecklistItem] = []
    
    suppressed_ids = set()
    if hazards:
        for h in hazards:
            if h.rule_id in ("topple", "water_heater_unsecured"):
                suppressed_ids.add(h.object_id)
                
    for floor in home.floors:
        for obj in floor.objects:
            if obj.category.value not in heavy_categories:
                continue
            if obj.secured:
                continue
            if obj.id in suppressed_ids:
                continue
                
            if is_renter:
                item_id = f"mitigation.secure.{obj.id}.renter"
                title = f"Move {obj.category.value} '{obj.id}' away from beds and seating"
                detail = (
                    "Securing to studs needs the landlord's permission, so start with "
                    "what needs no attachment: move it away from where people sit and "
                    "sleep, put heavy objects on lower shelves, and hold small objects "
                    "down with museum putty."
                )
                why = "Moving it comes before fastening it, and needs no installation. [cite: shakeout-guidance]"
            else:
                item_id = f"mitigation.secure.{obj.id}"
                title = f"Secure {obj.category.value} '{obj.id}' to wall studs"
                detail = (
                    "Secure tall or heavy furniture to wall studs."
                )
                why = (
                    "A UCLA study of the 1994 Northridge earthquake found 55% of injuries "
                    "came from falling furniture or objects and 1% from building damage. "
                    "[cite: shakeout-guidance]"
                )
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="mitigation",
                    hazard="earthquake",
                    title=title,
                    detail=detail,
                    why=why,
                    done=state.get(item_id, False) is True,
                    source_citation="shakeout-guidance",
                    scoring=False,
                )
            )
    return items


def earthquake_prep_items(home: HomeModel, state: ChecklistState) -> list[ChecklistItem]:
    """Whole-home earthquake preparation, from backend/corpus/earthquake-securing-home.md.

    S11.2 (2026-09-22). Until this session, `earthquake` had no `scoring: true`
    item at all: its sub-score was a constant 95 on every fixture, so the
    "weakest link" composite always resolved to fire. These are the items that
    make it move.

    They are `scoring: true` but carry NO numeric threshold — there is none to
    carry. `docs/decisions.md` 2026-09-21 records that the sources hold exactly
    two numbers and neither is app-checkable. A checkbox is a fact the resident
    asserts, not a measurement, which is why scoring these does not smuggle in
    the false precision the `guidance_based` tier exists to prevent.

    `mitigation_items` is per-object and stays per-object; these are per-home and
    fire once each. Emission conditions are facts the model actually holds — a
    kitchen room, a water heater, a tagged gas shutoff — never an inference about
    construction type.
    """
    items: list[ChecklistItem] = []

    def add(
        item_id: str,
        title: str,
        detail: str,
        why: str,
        citation: str,
    ) -> None:
        items.append(
            ChecklistItem(
                id=item_id,
                category="mitigation",
                hazard="earthquake",
                title=title,
                detail=detail,
                why=why,
                done=state.get(item_id, False) is True,
                source_citation=citation,
                scoring=True,
                severity="info",
            )
        )

    add(
        "eq.move_before_fasten",
        "Move tall furniture away from beds and seating",
        "Start by moving, not fastening. Bookcases and other tall furniture "
        "should not stand where people sit, sleep, or spend a lot of time.",
        "A UCLA study of the 1994 Northridge earthquake found 55% of injuries came "
        "from falling furniture or objects and 1% from building damage, which is why "
        "securing contents comes before structural work. [cite: shakeout-guidance]",
        "shakeout-guidance",
    )
    add(
        "eq.heavy_objects_low",
        "Move heavy and breakable objects to lower shelves",
        "Store heavy and breakable objects on low shelves rather than high ones.",
        "Both ShakeOut and Ready.gov give this instruction directly. "
        "[cite: shakeout-guidance] [cite: fema-earthquake]",
        "shakeout-guidance",
    )
    add(
        "eq.tv_computer_straps",
        "Secure televisions and computers with straps made for them",
        "Televisions and computers are secured with special straps made for that "
        "purpose, not with general-purpose furniture hardware.",
        "ShakeOut names televisions and computers as their own securing case. "
        "[cite: shakeout-guidance]",
        "shakeout-guidance",
    )

    room_types = {room.type for floor in home.floors for room in floor.rooms}
    if RoomType.kitchen in room_types:
        add(
            "eq.cabinet_latches",
            "Fit latches to your kitchen cabinet doors",
            "Latches stop cabinet doors swinging open and emptying their contents "
            "during shaking.",
            "ShakeOut names kitchen cabinet latches as a securing step. "
            "[cite: shakeout-guidance]",
            "shakeout-guidance",
        )

    object_categories = {obj.category for floor in home.floors for obj in floor.objects}
    safety_point_kinds = {
        sp.kind for floor in home.floors for sp in floor.safety_points
    }
    has_gas_appliance = (
        ObjectCategory.water_heater in object_categories
        or SafetyPointKind.gas_shutoff in safety_point_kinds
    )
    if has_gas_appliance:
        add(
            "eq.flexible_gas_connectors",
            "Put flexible connections on gas lines to appliances",
            "Water heaters, ovens and clothes dryers should connect to the gas "
            "supply with flexible connections rather than rigid pipe.",
            "ShakeOut names gas lines to appliances as a securing step in their "
            "own right. [cite: shakeout-guidance]",
            "shakeout-guidance",
        )

    # Advisory, never scoring: this is information, not a task anyone completes.
    item_id = "eq.stay_if_undamaged"
    items.append(
        ChecklistItem(
            id=item_id,
            category="mitigation",
            hazard="earthquake",
            title="Know the after-shaking default: stay put if the building is undamaged",
            detail=(
                "Outside a tsunami zone, evacuate only if the building is damaged "
                "or the area around it is unsafe. An undamaged building can be safe "
                "to remain in even with the power out."
            ),
            why=(
                "This is the opposite default from fire, where leaving immediately is "
                "always right. [cite: shakeout-guidance-after]"
            ),
            done=state.get(item_id, False) is True,
            source_citation="shakeout-guidance-after",
            scoring=False,
        )
    )
    return items


def supply_kit_items(state: ChecklistState) -> list[ChecklistItem]:
    """The single shared supply-kit item — tagged general, appears once.

    S11.2 (2026-09-22): this used to read "72-hour kit… one gallon per person per
    day for three days" cited to `fema-earthquake`. Nothing in the corpus carries
    that — `fema-earthquake` (ready.gov/earthquakes) is only ever cited for
    securing objects and for Drop, Cover, Hold On. The quantities were invented.
    The item now says only what `earthquake-after-shaking.md` sources, and the id
    is kept unchanged so persisted done-state survives.
    """
    item_id = "supply_kit.72h"
    return [
        ChecklistItem(
            id=item_id,
            category="supply_kit",
            hazard="general",
            title="Pack a grab-and-go bag and keep flashlights, not candles",
            detail=(
                "Shelters have limited space, so pack essentials only: medication, "
                "important documents, prescription eyewear. Keep flashlights, "
                "battery-powered lights or light sticks to hand — not candles or "
                "matches, which can ignite a gas leak you have not found yet."
            ),
            why=(
                "Both the bag's contents and the no-open-flame rule are what the "
                "sources actually specify. [cite: shakeout-guidance-after]"
            ),
            done=state.get(item_id, False) is True,
            source_citation="shakeout-guidance-after",
            scoring=False,
        )
    ]


def alert_items(home: HomeModel, state: ChecklistState) -> list[ChecklistItem]:
    """Weather alert items + hearing-impaired strobe/bed-shaker items.

    hearing_impaired produces checklist items AND ZERO routing constraints.
    This is asserted by test.
    """
    items: list[ChecklistItem] = []

    # Universal weather alert item
    item_id = "alerts.weather_radio"
    items.append(
        ChecklistItem(
            id=item_id,
            category="alerts",
            hazard="severe_weather",
            title="Set up at least two independent ways to get a tornado warning",
            detail=(
                "Sign up for your community's alerts, and add NOAA Weather Radio or "
                "the Emergency Alert System as a second channel that does not depend "
                "on the first. Keep a way to charge a phone and a battery-powered "
                "radio for a power outage. Know the difference: a Watch is when "
                "you check that your plan still works; a Warning is when you "
                "execute it."
            ),
            why=(
                "You may not always receive a warning, which is why the sources name "
                "more than one channel rather than one. "
                "[cite: fema-tornado-ready] [cite: redcross-tornado] [cite: noaa-tornado-ww]"
            ),
            done=state.get(item_id, False) is True,
            source_citation="fema-tornado-ready",
            # S11.2: scoring. Setting up alert channels is a concrete completable
            # action that was filed as advisory.
            scoring=True,
            severity="info",
        )
    )

    # hearing_impaired profiles -> strobe/bed-shaker.
    #
    # Both items below are deliberately `scoring: False`. The actions are real and
    # sourced, but a household's score must not fall because it includes a deaf or
    # hard-of-hearing member. See docs/preparedness-score-weights.md.
    for profile in home.profiles:
        if ProfileTag.hearing_impaired in profile.tags:
            item_id = f"alerts.same_receiver.{profile.id}"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="alerts",
                    hazard="severe_weather",
                    title=f"Set up a SAME-programmed weather radio alert for {profile.name}",
                    detail=(
                        "Outdoor sirens are an audible warning and are not an "
                        "accessible indoor alert. A NOAA Weather Radio receiver with "
                        "Specific Area Message Encoding can be programmed for specific "
                        "events and counties, and drives connected strobe lights, bed "
                        "shakers and pillow vibrators when a warning arrives."
                    ),
                    why=(
                        "NOAA Weather Radio carries non-verbal information specifically "
                        "to warn people who are deaf or hard of hearing. "
                        "[cite: noaa-nwr-accessibility]"
                    ),
                    done=state.get(item_id, False) is True,
                    source_citation="noaa-nwr-accessibility",
                    scoring=False,
                )
            )
            item_id = f"alerts.strobe.{profile.id}"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="alerts",
                    hazard="general",
                    title=f"Install a bed-shaker or strobe-light alarm for {profile.name}",
                    detail=(
                        "Smoke alarms with strobe lights and bed-shaker/vibrating "
                        "accessories ensure alarms actually wake someone who is deaf "
                        "or hard of hearing. Also ensure weather alerts use visual "
                        "or vibrating notifications."
                    ),
                    why="Standard audible alarms may not wake a person who is deaf or hard of hearing. [cite: usfa-smoke-alarms]",
                    done=state.get(item_id, False) is True,
                    source_citation="usfa-smoke-alarms",
                    scoring=False,
                )
            )
    return items


def household_items(
    home: HomeModel,
    state: ChecklistState,
    fire_plan: RoutePlan | None = None,
    tornado_plan: RoutePlan | None = None,
) -> list[ChecklistItem]:
    """Items driven by household facts and profile tags.

    - mobility_limited + no_viable_route/no_viable_safe_room -> high-severity item
    - child -> accompanied-adult pairing
    - pet -> leash/carrier near exit (routing no-op, asserted by test)
    """
    items: list[ChecklistItem] = []

    # Collect rooms with no-viable findings across plans
    no_viable_rooms: set[str] = set()
    for plan in (fire_plan, tornado_plan):
        if plan is None:
            continue
        for room in plan.rooms:
            for finding in room.findings:
                if finding.kind in ("no_viable_route", "no_viable_safe_room"):
                    no_viable_rooms.add(room.room_id)

    for profile in home.profiles:
        # mobility_limited -> sleep near accessible exit
        if ProfileTag.mobility_limited in profile.tags:
            item_id = f"household.sleep_near_exit.{profile.id}"
            sev: Literal["info", "high"] = "info"
            if profile.bedroom_room_id in no_viable_rooms:
                sev = "high"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="routes",
                    hazard="general",
                    title=f"{profile.name} should sleep near an accessible exit, ideally on the ground floor",
                    detail=(
                        "A person with mobility limitations should sleep near an "
                        "accessible exit to shorten and simplify the escape route."
                    ),
                    why="Stairs and window egress are generally not usable for a wheelchair user. [cite: usfa-disabilities]",
                    done=state.get(item_id, False) is True,
                    source_citation="usfa-disabilities",
                    scoring=False,
                    severity=sev,
                )
            )

        # child -> assign an adult
        if ProfileTag.child in profile.tags:
            item_id = f"household.child_assist.{profile.id}"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="practice",
                    hazard="general",
                    title=f"Assign an adult to assist {profile.name} during evacuation",
                    detail=(
                        "Children may not wake to a smoke alarm. Assign a specific "
                        "adult to each young child in the plan."
                    ),
                    why="Children may not wake independently; an assigned adult ensures they escape. [cite: nfpa-escape-planning]",
                    done=state.get(item_id, False) is True,
                    source_citation="nfpa-escape-planning",
                    scoring=False,
                )
            )

        # pet -> leash/carrier
        if ProfileTag.pet in profile.tags:
            item_id = f"household.pet_evac.{profile.id}"
            items.append(
                ChecklistItem(
                    id=item_id,
                    category="practice",
                    hazard="general",
                    title=f"Keep a leash/carrier near the exit for {profile.name}",
                    detail=(
                        "Include pets in the plan — who grabs the leash/carrier if "
                        "immediately at hand on the way out — but people escape first. "
                        "Never delay escape or re-enter for pets."
                    ),
                    why="People escape first; pets drive phrasing, never route computation. [cite: redcross-escape-plan]",
                    done=state.get(item_id, False) is True,
                    source_citation="redcross-escape-plan",
                    scoring=False,
                )
            )

    return items


def engine_finding_items(
    plans: Sequence[RoutePlan],
    state: ChecklistState,
) -> list[ChecklistItem]:
    """Checklist items derived from engine findings across all peril plans.

    Deduplicates: the same room with the same finding kind across plans
    produces one item, not N.
    """
    items: list[ChecklistItem] = []
    seen: set[str] = set()

    for plan in plans:
        hazard = _peril_to_hazard(plan.peril)
        for room in plan.rooms:
            for finding in room.findings:
                if finding.kind == "no_viable_safe_room":
                    # Handled by safe_room_items; skip duplication.
                    continue
                if finding.kind == "no_cover_in_room":
                    item_id = f"engine.no_cover.{room.room_id}"
                    if item_id in seen:
                        continue
                    seen.add(item_id)
                    items.append(
                        ChecklistItem(
                            id=item_id,
                            category="mitigation",
                            hazard="earthquake",
                            title=f"No earthquake cover in {room.room_name}",
                            detail=(
                                "Practice Drop, Cover, Hold On with arms protecting "
                                "your head and neck. Consider adding a sturdy table."
                            ),
                            why="Getting under a sturdy table is the safest position during shaking. [cite: shakeout-guidance]",
                            done=state.get(item_id, False) is True,
                            source_citation="shakeout-guidance",
                            scoring=False,
                        )
                    )
                if finding.kind == "no_viable_route":
                    item_id = f"engine.no_viable_route.{room.room_id}"
                    if item_id in seen:
                        continue
                    seen.add(item_id)
                    items.append(
                        ChecklistItem(
                            id=item_id,
                            category="routes",
                            hazard=hazard,
                            title=f"{room.room_name} has no escape route under current constraints",
                            detail=finding.detail,
                            why="A room with no viable route is a trap. [cite: nfpa-escape-planning]",
                            done=state.get(item_id, False) is True,
                            source_citation="nfpa-escape-planning",
                            scoring=False,
                            severity="high",
                        )
                    )
    return items


# ---------------------------------------------------------------------------
# Equipment pre-satisfaction
# ---------------------------------------------------------------------------

def _apply_equipment_presatisfaction(
    items: list[ChecklistItem],
    home: HomeModel,
) -> list[ChecklistItem]:
    """Mark items as done when the household declares existing equipment.

    The item STILL appears (so the user sees it was considered), but pre-set
    to done. This is the "derive first, store only when you must" principle:
    the spatial artefact (equipment exists) determines the state.
    """
    if home.household is None:
        return items
    equipment = set(home.household.existing_equipment)
    if Equipment.smoke_alarm in equipment:
        for item in items:
            if item.category == "smoke_alarm" and (
                item.id.startswith("alarm.bedroom.")
                or item.id.startswith("alarm.sleeping_area.")
                or item.id.startswith("alarm.level.")
            ):
                item.done = True
    return items


# ---------------------------------------------------------------------------
# build_checklist (the public entry point)
# ---------------------------------------------------------------------------


def build_checklist(
    home: HomeModel,
    plan: RoutePlan,
    findings: Sequence[Finding],
    state: ChecklistState,
    thresholds: Optional[EgressThresholds] = None,
    *,
    tornado_plan: Optional[RoutePlan] = None,
    earthquake_plan: Optional[RoutePlan] = None,
    now: Optional[datetime] = None,
    object_hazard_thresholds: Optional[ObjectHazardThresholds] = None,
) -> list[ChecklistItem]:
    """The full deterministic checklist, ordered scoring-items-first.

    `thresholds` is optional only for backward compatibility with callers
    predating the egress items — pass it. Without it, undersized bedroom escape
    windows are only reported when /analyze has been run.

    `tornado_plan` / `earthquake_plan` enable the S6.4 multi-peril items.
    Omitting them produces exactly the pre-S6.4 checklist (backward compat).

    `now` is the current time for evaluating recurrence. If None, recurring
    items with timestamp state are treated as stale. The generator itself
    remains pure — `now` is an explicit input, not a clock read.
    """
    all_plans: list[RoutePlan] = [plan]
    if tornado_plan is not None:
        all_plans.append(tornado_plan)
    if earthquake_plan is not None:
        all_plans.append(earthquake_plan)

    hazards = []
    if object_hazard_thresholds:
        hazards = analyze_object_hazards(home, object_hazard_thresholds)

    items = [
        *smoke_alarm_items(home, state),
        *practice_items(state, now),
        *route_items(plan, state),
        *(egress_window_items(home, thresholds, state) if thresholds else []),
        *finding_items(findings, state),
        # S6.4 additions:
        *shutoff_items(home, state),
        *safe_room_items(tornado_plan, state),
        *(object_hazard_items(home, object_hazard_thresholds, state) if object_hazard_thresholds else []),
        *mitigation_items(home, state, hazards=hazards),
        *earthquake_prep_items(home, state),
        *supply_kit_items(state),
        *alert_items(home, state),
        *household_items(home, state, plan, tornado_plan),
        *engine_finding_items(all_plans, state),
    ]

    items = _apply_equipment_presatisfaction(items, home)
    return items
